import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/results_repo.dart';
import '../../data/school_repo.dart';
import '../../services/ranking_service.dart';
import '../../services/reports.dart';
import '../widgets/common.dart';

/// لائحة تلاميذ قسم (للمدير ولأستاذ القسم فقط).
class StudentsScreen extends StatefulWidget {
  final SchoolClass cls;
  const StudentsScreen({super.key, required this.cls});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Student>? students;
  Map<int, int> passed = {};
  bool showArchived = false;
  String search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PeopleRepo.students(widget.cls.id, includeArchived: showArchived);
    final crit = await ResultsRepo.effectiveCriteria(widget.cls.id);
    final p = await ResultsRepo.passedCounts(widget.cls.id, crit.config.passPercent);
    if (mounted) {
      setState(() {
        students = s;
        passed = p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = students;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final q = Ar.normalize(search);
    final filtered = q.isEmpty
        ? list
        : list.where((s) => Ar.normalize('${s.fullName} ${s.massarCode}').contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو رمز مسار'),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('المؤرشفون'),
            selected: showArchived,
            onSelected: (v) {
              showArchived = v;
              _load();
            },
          ),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? const EmptyState(icon: Icons.person_off, text: 'لا يوجد تلاميذ')
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (c, i) {
                  final s = filtered[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: s.archived ? AppColors.muted : AppColors.primary,
                        child: Text(s.firstName.isEmpty ? '؟' : s.firstName.substring(0, 1),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        s.massarCode,
                        Ar.readingLevelName(s.readingLevel),
                        'قصص منجزة: ${passed[s.id] ?? 0}',
                        if (Session.I.isAdmin) s.hasPin ? 'كلمة السر: محددة' : 'بدون كلمة سر',
                        if (s.archived) 'مؤرشف',
                      ].join(' • ')),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => StudentDetailScreen(student: s, cls: widget.cls)),
                      ).then((_) => _load()),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class StudentDetailScreen extends StatefulWidget {
  final Student student;
  final SchoolClass cls;
  const StudentDetailScreen({super.key, required this.student, required this.cls});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late Student s;
  List<Map<String, Object?>> history = [];
  List<Map<String, Object?>> certs = [];
  int suggested = -1;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    s = widget.student;
    _load();
  }

  Future<void> _load() async {
    final fresh = await PeopleRepo.studentById(s.id);
    final h = await ResultsRepo.studentHistory(s.id);
    final c = await ResultsRepo.certificatesForStudent(s.id);
    final sug = await RankingService.suggestedLevel(s.id);
    if (!mounted) return;
    setState(() {
      if (fresh != null) s = fresh;
      history = h;
      certs = c;
      suggested = sug;
      loading = false;
    });
  }

  Future<void> _setLevel(int level, String source) async {
    await PeopleRepo.setReadingLevel(s.id, level, source: source);
    await SchoolRepo.audit(Session.I.actor, 'تحديث وصف القارئ', '${s.massarCode} ← ${Ar.readingLevelName(level)}');
    _load();
  }

  Future<void> _resetPin() async {
    final ok = await confirm(context, 'كلمة سر جديدة', 'سيتم توليد كلمة سر جديدة للتلميذ(ة) ${s.fullName} وطباعة بطاقته.');
    if (!ok || !mounted) return;
    final digits = await SchoolRepo.getInt(SchoolRepo.kPinDigits, 4);
    final pins = await PeopleRepo.generatePins(widget.cls.id, studentIds: [s.id], digits: digits);
    await SchoolRepo.audit(Session.I.actor, 'إعادة تعيين كلمة سر تلميذ', s.massarCode);
    if (!mounted || pins.isEmpty) return;
    await info(context, 'كلمة السر الجديدة',
        SelectableText(pins.values.first, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)));
    final bytes = await Reports.pinCards(widget.cls, pins);
    await Reports.printOrShare(bytes, 'بطاقة_${s.massarCode}');
    _load();
  }

  Future<void> _certificate(String kind) async {
    final now = DateTime.now();
    final year = await SchoolRepo.currentYear();
    if (!mounted) return;
    final p = await showDialog<Period>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('الفترة'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, Period.month(now.year, now.month)),
              child: Text(Period.month(now.year, now.month).label)),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, Period.year(year)), child: Text(Period.year(year).label)),
        ],
      ),
    );
    if (p == null || !mounted) return;
    final bytes = await withProgress(
        context, 'إعداد الشهادة...', () => Reports.singleCertificate(s, widget.cls, kind, p, Session.I.actor));
    if (bytes != null) await Reports.printOrShare(bytes, 'شهادة_${s.massarCode}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = Session.I.isAdmin;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: admin ? AppColors.admin : AppColors.teacher,
        title: Text(s.fullName),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('رمز مسار: ${s.massarCode}'),
                    Text('القسم: ${widget.cls.code}'),
                    if (s.gender.isNotEmpty) Text('النوع: ${s.gender}'),
                    Text('الاختبارات المنجزة: ${history.length}'),
                    if (s.archived) const Text('مؤرشف', style: TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (admin)
                        OutlinedButton.icon(onPressed: _resetPin, icon: const Icon(Icons.key), label: const Text('كلمة سر جديدة')),
                      if (admin)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await PeopleRepo.setArchived(s.id, !s.archived);
                            await SchoolRepo.audit(Session.I.actor, s.archived ? 'إلغاء أرشفة تلميذ' : 'أرشفة تلميذ', s.massarCode);
                            _load();
                          },
                          icon: Icon(s.archived ? Icons.unarchive : Icons.archive),
                          label: Text(s.archived ? 'إلغاء الأرشفة' : 'أرشفة'),
                        ),
                      OutlinedButton.icon(
                          onPressed: () => _certificate('improvement'),
                          icon: const Icon(Icons.trending_up),
                          label: const Text('شهادة تحسّن')),
                      OutlinedButton.icon(
                          onPressed: () => _certificate('regularity'),
                          icon: const Icon(Icons.event_available),
                          label: const Text('شهادة مواظبة')),
                    ]),
                  ]),
                ),
              ),
              const SectionTitle('وصف القارئ (تربوي وقابل للمراجعة)'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('الوصف الحالي: ${Ar.readingLevelName(s.readingLevel)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (suggested == -1)
                      const Text('اقتراح النظام: يلزم 3 اختبارات على الأقل قبل اقتراح وصف.',
                          style: TextStyle(color: AppColors.muted))
                    else if (suggested != s.readingLevel)
                      Row(children: [
                        Expanded(child: Text('اقتراح النظام حسب آخر النتائج: ${Ar.readingLevelName(suggested)}')),
                        TextButton(onPressed: () => _setLevel(suggested, 'suggestion'), child: const Text('اعتماد')),
                      ])
                    else
                      const Text('الوصف الحالي يوافق آخر النتائج.', style: TextStyle(color: AppColors.ok)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var l = 1; l < Ar.readingLevels.length; l++)
                        ChoiceChip(
                          label: Text(Ar.readingLevelName(l)),
                          selected: s.readingLevel == l,
                          onSelected: (_) => _setLevel(l, 'teacher'),
                        ),
                    ]),
                  ]),
                ),
              ),
              const SectionTitle('سجل الاختبارات'),
              if (history.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('لم ينجز أي اختبار بعد.'))
              else
                for (final h in history)
                  Card(
                    child: ListTile(
                      title: Text(h['story_title'] as String? ?? ''),
                      subtitle: Text('${(h['finished_at'] as String? ?? '').substring(0, 10)} — المحاولة ${h['attempt_no']}'
                          '${(h['needs_review'] as int? ?? 0) == 1 ? ' — جواب ينتظر التصحيح' : ''}'),
                      leading: CircleAvatar(
                        backgroundColor: ((h['percent'] as num?) ?? 0) >= 50 ? AppColors.ok : AppColors.student,
                        child: Text('${((h['percent'] as num?) ?? 0).round()}',
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await confirm(context, 'محاولة جديدة',
                              'السماح للتلميذ(ة) بإعادة اختبار هذه القصة؟ تُحتسب أفضل نتيجة.');
                          if (!ok) return;
                          await ResultsRepo.grantRetake(s.id, h['quiz_id'] as int, Session.I.actor);
                          if (context.mounted) toast(context, 'تم السماح بمحاولة جديدة');
                        },
                        child: const Text('محاولة جديدة'),
                      ),
                    ),
                  ),
              const SectionTitle('الشهادات'),
              if (certs.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد شهادات بعد.'))
              else
                for (final c in certs)
                  ListTile(
                    leading: const Icon(Icons.workspace_premium, color: AppColors.accent),
                    title: Text(_certTitle(c)),
                    subtitle: Text('رقم: ${c['serial']} — ${(c['issued_at'] as String).substring(0, 10)}'),
                  ),
            ]),
    );
  }

  static String _certTitle(Map<String, Object?> c) {
    final kind = c['kind'];
    final rank = c['rank'] as int?;
    final period = c['period'] as String;
    final k = kind == 'improvement'
        ? 'شهادة تحسّن'
        : kind == 'regularity'
            ? 'شهادة مواظبة'
            : 'شهادة تفوق — المرتبة ${RankingService.rankWord(rank)}';
    return '$k ($period)';
  }
}
