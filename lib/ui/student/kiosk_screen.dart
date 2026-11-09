import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/results_repo.dart';
import '../../data/school_repo.dart';
import '../../services/kiosk.dart';
import '../../services/scoring.dart';
import '../widgets/common.dart';
import 'quiz_player.dart';

/// فضاء التلاميذ على التابلت المشترك.
///
/// السيناريو: يفتح الأستاذ الفضاء ← يختار التلميذ اسمه (أو يكتب رمز مسار) ويدخل كلمة سره ←
/// ينجز الاختبار (يُحفظ كل جواب فورًا) ← «إنهاء وتسليم التابلت» ← تُغلق الجلسة وتُخفى معلوماته.
/// تُغلق الجلسة تلقائيًا بعد مدة من عدم النشاط، ولا يمكن الرجوع إلى جلسة التلميذ السابق.
class KioskScreen extends StatefulWidget {
  final SchoolClass cls;
  const KioskScreen({super.key, required this.cls});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  List<Student> students = [];
  Student? current;
  String search = '';
  Timer? idle;
  int idleMinutes = 3;
  int pinDigits = 4;
  int sessionKey = 0;

  @override
  void initState() {
    super.initState();
    Kiosk.start();
    _load();
  }

  Future<void> _load() async {
    final s = await PeopleRepo.students(widget.cls.id);
    idleMinutes = await SchoolRepo.getInt(SchoolRepo.kIdleMinutes, 3);
    pinDigits = await SchoolRepo.getInt(SchoolRepo.kPinDigits, 4);
    if (mounted) setState(() => students = s);
  }

  @override
  void dispose() {
    idle?.cancel();
    Kiosk.stop();
    super.dispose();
  }

  void _touch() {
    idle?.cancel();
    if (current == null) return;
    idle = Timer(Duration(minutes: idleMinutes), () {
      if (!mounted || current == null) return;
      _endSession(timeout: true);
    });
  }

  void _endSession({bool timeout = false}) {
    idle?.cancel();
    Session.I.logoutStudent();
    setState(() {
      current = null;
      search = '';
      sessionKey++;
    });
    if (timeout) toast(context, 'أُغلقت الجلسة بسبب عدم النشاط. أجوبتك محفوظة.');
  }

  Future<void> _login(Student s) async {
    if (!s.hasPin) {
      toast(context, 'لم تُحدَّد لك كلمة سر بعد. اطلب من الإدارة بطاقة الدخول.', error: true);
      return;
    }
    final locked = Session.I.checkLocked();
    if (locked != null) {
      toast(context, locked, error: true);
      return;
    }
    final pinKey = GlobalKey<PinPadState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('مرحبًا ${s.firstName}! اكتب كلمة السر', textAlign: TextAlign.center),
        content: PinPad(
          key: pinKey,
          length: pinDigits,
          onDone: (pin) async {
            final valid = await PeopleRepo.verifyStudentPin(s.id, pin);
            if (valid) {
              if (c.mounted) Navigator.pop(c, true);
            } else {
              Session.I.registerFailure();
              pinKey.currentState?.clear();
              if (c.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة السر غير صحيحة، حاول مرة أخرى')));
              }
              final l = Session.I.checkLocked();
              if (l != null && c.mounted) Navigator.pop(c, false);
            }
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع'))],
      ),
    );
    if (ok != true || !mounted) return;
    Session.I.registerSuccess();
    Session.I.loginStudent(s);
    setState(() {
      current = s;
      sessionKey++;
    });
    _touch();
  }

  Future<void> _loginByCode() async {
    final code = await askText(context, 'اكتب رمز مسار', label: 'مثال: F123456789');
    if (code == null || !mounted) return;
    final c = code.trim().toUpperCase();
    final s = students.where((x) => x.massarCode == c).toList();
    if (s.isEmpty) {
      toast(context, 'هذا الرمز غير موجود في هذا القسم', error: true);
      return;
    }
    _login(s.first);
  }

  Future<void> _exit() async {
    final pw = await askPassword(context, 'إغلاق فضاء التلاميذ', label: 'كلمة سر القسم');
    if (pw == null || !mounted) return;
    if (await PeopleRepo.verifyClass(widget.cls.id, pw)) {
      if (mounted) Navigator.pop(context);
    } else if (mounted) {
      toast(context, 'كلمة السر غير صحيحة', error: true);
    }
  }

  Widget _picker() {
    final q = Ar.normalize(search);
    final list = q.isEmpty ? students : students.where((s) => Ar.normalize(s.fullName).contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(
            child: Text('اضغط على اسمك', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.student)),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن اسمك'),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _loginByCode, icon: const Icon(Icons.badge), label: const Text('رمز مسار')),
        ]),
      ),
      Expanded(
        child: GridView.extent(
          padding: const EdgeInsets.all(12),
          maxCrossAxisExtent: 210,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [
            for (final s in list)
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                elevation: 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _login(s),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.student,
                      child: Text(s.firstName.isEmpty ? '؟' : s.firstName.substring(0, 1),
                          style: const TextStyle(color: Colors.white, fontSize: 24)),
                    ),
                    const SizedBox(height: 6),
                    Text(s.firstName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Text(s.lastName, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = current;
    return PopScope(
      canPop: false,
      child: Listener(
        onPointerDown: (_) => _touch(),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.student,
            automaticallyImplyLeading: false,
            title: Text(s == null ? 'فضاء التلاميذ — القسم ${widget.cls.code}' : 'مرحبًا ${s.firstName}'),
            actions: [
              if (s == null) IconButton(tooltip: 'إغلاق (للأستاذ)', icon: const Icon(Icons.lock), onPressed: _exit),
            ],
          ),
          body: s == null
              ? _picker()
              : Navigator(
                  key: ValueKey('student-$sessionKey'),
                  onGenerateRoute: (_) => MaterialPageRoute(
                    builder: (_) => StudentHome(student: s, cls: widget.cls, onHandOver: () => _endSession()),
                  ),
                ),
        ),
      ),
    );
  }
}

/// الصفحة الرئيسية للتلميذ: ثلاثة اختيارات كبيرة.
class StudentHome extends StatelessWidget {
  final Student student;
  final SchoolClass cls;
  final VoidCallback onHandOver;
  const StudentHome({super.key, required this.student, required this.cls, required this.onHandOver});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    final tiles = [
      BigTile(
        icon: Icons.auto_stories,
        label: 'قصصي',
        color: AppColors.primary,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyStoriesScreen(student: student, cls: cls, onHandOver: onHandOver))),
      ),
      BigTile(
        icon: Icons.quiz,
        label: 'اختباراتي',
        color: AppColors.student,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyStoriesScreen(student: student, cls: cls, onHandOver: onHandOver, onlyPending: true))),
      ),
      BigTile(
        icon: Icons.emoji_events,
        label: 'إنجازاتي',
        color: AppColors.accent,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AchievementsScreen(student: student))),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(children: [
                Text('مرحبًا ${student.firstName} 👋', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                if (wide)
                  Row(children: [for (final t in tiles) Expanded(child: Padding(padding: const EdgeInsets.all(10), child: t))])
                else
                  Column(children: [for (final t in tiles) Padding(padding: const EdgeInsets.all(8), child: t)]),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(260, 64)),
                  onPressed: () async {
                    final token = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
                    if (token == null || !context.mounted) return;
                    final story = await LibraryRepo.storyByToken(token);
                    if (!context.mounted) return;
                    if (story == null) {
                      toast(context, 'لم نتعرف على هذه القصة', error: true);
                      return;
                    }
                    await startQuizFlow(context, student, cls, story, onHandOver);
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 32),
                  label: const Text('امسح رمز القصة', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(320, 70)),
                  onPressed: onHandOver,
                  icon: const Icon(Icons.tablet_android, size: 30),
                  label: const Text('إنهاء وتسليم التابلت', style: TextStyle(fontSize: 22)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// بدء أو استئناف اختبار قصة (مع كل التحققات: الإسناد، توفر الاختبار، عدد المحاولات).
Future<void> startQuizFlow(BuildContext context, Student student, SchoolClass cls, Story story, VoidCallback onHandOver) async {
  final assigned = (await LibraryRepo.stories(classId: cls.id, onlyAssigned: true)).any((e) => e.story.id == story.id);
  if (!context.mounted) return;
  if (!assigned) {
    toast(context, 'هذه القصة غير مسندة لقسمك.', error: true);
    return;
  }
  final quiz = await LibraryRepo.quizForStudent(story.id, cls.level, student.readingLevel);
  if (!context.mounted) return;
  if (quiz == null) {
    toast(context, 'لا يوجد اختبار لهذه القصة بعد. أخبر أستاذك.', error: true);
    return;
  }
  final block = await ResultsRepo.canStart(student.id, quiz.id);
  if (!context.mounted) return;
  if (block != null) {
    toast(context, block);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        StoryCover(coverPath: story.coverPath, title: story.title, width: 150, height: 200),
        const SizedBox(height: 12),
        Text('هل قرأت قصة «${story.title}» الورقية؟', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
      ]),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('ليس بعد', style: TextStyle(fontSize: 20))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.ok),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('نعم، أبدأ الأسئلة', style: TextStyle(fontSize: 20)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final attempt = await ResultsRepo.startOrResume(student, quiz, cls.id);
  final answers = await ResultsRepo.answersFor(attempt.id);
  final questions = await LibraryRepo.loadQuestions(quiz.id);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => QuizPlayerScreen(
        story: story,
        quiz: quiz,
        questions: questions,
        attempt: attempt,
        initialAnswers: answers,
        onHandOver: onHandOver,
      ),
    ),
  );
}

/// «قصصي» و«اختباراتي»: أغلفة القصص المسندة للقسم.
class MyStoriesScreen extends StatefulWidget {
  final Student student;
  final SchoolClass cls;
  final VoidCallback onHandOver;
  final bool onlyPending;
  const MyStoriesScreen({super.key, required this.student, required this.cls, required this.onHandOver, this.onlyPending = false});

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  List<(StoryInfo, double?)>? items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await LibraryRepo.stories(classId: widget.cls.id, onlyAssigned: true);
    final out = <(StoryInfo, double?)>[];
    for (final s in list) {
      if (s.publishedCount == 0 && widget.onlyPending) continue;
      final best = await ResultsRepo.bestForStory(widget.student.id, s.story.id);
      if (widget.onlyPending && best != null) continue;
      out.add((s, best));
    }
    if (mounted) setState(() => items = out);
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.onlyPending ? AppColors.student : AppColors.primary,
        title: Text(widget.onlyPending ? 'اختباراتي' : 'قصصي'),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? EmptyState(
                  icon: widget.onlyPending ? Icons.celebration : Icons.menu_book,
                  text: widget.onlyPending ? 'أحسنت! لا توجد اختبارات تنتظرك الآن.' : 'لا توجد قصص في مكتبة قسمك بعد.',
                )
              : GridView.extent(
                  padding: const EdgeInsets.all(14),
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.62,
                  children: [
                    for (final (info, best) in list)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await startQuizFlow(context, widget.student, widget.cls, info.story, widget.onHandOver);
                          _load();
                        },
                        child: Column(children: [
                          Expanded(
                            child: Stack(fit: StackFit.expand, children: [
                              StoryCover(coverPath: info.story.coverPath, title: info.story.title, width: 220, height: 300),
                              if (best != null)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: AppColors.ok, borderRadius: BorderRadius.circular(20)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      for (var i = 0; i < Grader.stars(best); i++)
                                        const Icon(Icons.star, color: AppColors.accent, size: 20),
                                      if (Grader.stars(best) == 0) const Icon(Icons.check, color: Colors.white, size: 20),
                                    ]),
                                  ),
                                ),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Text(info.story.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  ],
                ),
    );
  }
}

/// «إنجازاتي»: إنجازات التلميذ الشخصية فقط (لا يرى نتائج الآخرين ولا ترتيب القسم).
class AchievementsScreen extends StatefulWidget {
  final Student student;
  const AchievementsScreen({super.key, required this.student});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  List<Map<String, Object?>>? history;
  List<Map<String, Object?>> certs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await ResultsRepo.studentHistory(widget.student.id);
    final c = await ResultsRepo.certificatesForStudent(widget.student.id);
    if (mounted) {
      setState(() {
        history = h;
        certs = c;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = history;
    if (h == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final bestByStory = <int, double>{};
    final titles = <int, String>{};
    for (final m in h) {
      final sid = m['story_id'] as int;
      final p = (m['percent'] as num).toDouble();
      titles[sid] = m['story_title'] as String? ?? '';
      if (p > (bestByStory[sid] ?? -1)) bestByStory[sid] = p;
    }
    final stars = bestByStory.values.fold<int>(0, (s, p) => s + Grader.stars(p));
    final now = DateTime.now();
    final months = <String>[];
    final counts = <double>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final e = DateTime(d.year, d.month + 1, 1);
      months.add(Ar.monthName(d.month));
      counts.add(h.where((m) {
        final f = DateTime.tryParse(m['finished_at'] as String? ?? '');
        return f != null && !f.isBefore(d) && f.isBefore(e);
      }).length.toDouble());
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.accent, title: const Text('إنجازاتي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(alignment: WrapAlignment.center, children: [
          StatCard(title: 'قصة أجبت عن أسئلتها', value: '${bestByStory.length}', icon: Icons.menu_book),
          StatCard(title: 'نجمة جمعتها', value: '$stars', icon: Icons.star, color: AppColors.accent),
          StatCard(title: 'شهادة', value: '${certs.length}', icon: Icons.workspace_premium, color: AppColors.student),
        ]),
        const SectionTitle('قراءاتي خلال الأشهر الأخيرة'),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: SimpleBars(labels: months, values: counts, color: AppColors.student))),
        const SectionTitle('القصص التي أنجزتها'),
        if (bestByStory.isEmpty) const Text('لم تُجب عن أي قصة بعد. اقرأ قصة من مكتبة قسمك وابدأ!'),
        for (final e in bestByStory.entries)
          ListTile(
            leading: const Icon(Icons.auto_stories, color: AppColors.primary),
            title: Text(titles[e.key] ?? '', style: const TextStyle(fontSize: 18)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Icon(i < Grader.stars(e.value) ? Icons.star : Icons.star_border, color: AppColors.accent),
            ]),
          ),
        if (certs.isNotEmpty) ...[
          const SectionTitle('شهاداتي'),
          for (final c in certs)
            ListTile(
              leading: const Icon(Icons.workspace_premium, color: AppColors.accent, size: 36),
              title: Text(c['kind'] == 'top'
                  ? 'شهادة تفوق في القراءة${c['rank'] != null ? ' — المرتبة ${c['rank']}' : ''}'
                  : (c['kind'] == 'improvement' ? 'شهادة التحسن في القراءة' : 'شهادة المواظبة على القراءة')),
              subtitle: Text('${c['period']}'),
            ),
        ],
      ]),
    );
  }
}

/// مسح رمز QR الملصق على القصة الورقية. الرمز يعرّف القصة فقط.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final controller = MobileScannerController();
  bool done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.student, title: const Text('امسح الرمز الملصق على القصة')),
      body: Stack(children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            if (done) return;
            for (final b in capture.barcodes) {
              final token = Story.tokenFromQr(b.rawValue ?? '');
              if (token != null) {
                done = true;
                Navigator.pop(context, token);
                return;
              }
            }
          },
          errorBuilder: (c, e) => const EmptyState(
            icon: Icons.no_photography,
            text: 'تعذر تشغيل الكاميرا. يمكنك اختيار القصة من «قصصي» مباشرة.',
          ),
        ),
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('رجوع واختيار القصة يدويًا'),
            ),
          ),
        ),
      ]),
    );
  }
}
