import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/results_repo.dart';
import '../../data/school_repo.dart';
import '../shared/class_dashboard.dart';
import '../shared/criteria_screen.dart';
import '../shared/results_screen.dart';
import '../shared/stories_screen.dart';
import '../shared/students_screen.dart';
import '../student/kiosk_screen.dart';
import '../widgets/common.dart';

/// فضاء القسم (الأستاذ = القسم).
class ClassHome extends StatefulWidget {
  final SchoolClass cls;
  const ClassHome({super.key, required this.cls});

  @override
  State<ClassHome> createState() => _ClassHomeState();
}

class _ClassHomeState extends State<ClassHome> {
  int pending = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await ResultsRepo.pendingReviewCount(widget.cls.id);
    if (mounted) setState(() => pending = n);
  }

  Future<void> _openKiosk() async {
    await SchoolRepo.audit(Session.I.actor, 'فتح فضاء التلاميذ');
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => KioskScreen(cls: widget.cls)));
    Session.I.loginTeacher(widget.cls);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cls;
    return NavShell(
      title: 'القسم ${c.code}',
      color: AppColors.teacher,
      header: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Text(c.code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.teacher)),
          Text(c.levelName.isNotEmpty ? c.levelName : Ar.levelName(c.level), style: const TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.student, minimumSize: const Size(80, 40)),
            onPressed: _openKiosk,
            icon: const Icon(Icons.child_care),
            label: const Text('فتح فضاء التلاميذ'),
          ),
        ),
        IconButton(tooltip: 'خروج', icon: const Icon(Icons.logout), onPressed: () => Navigator.pop(context)),
      ],
      items: [
        NavItem(Icons.dashboard, 'لوحة القسم', (_) => ClassDashboard(cls: c)),
        NavItem(Icons.people, 'التلاميذ', (_) => StudentsScreen(cls: c)),
        NavItem(Icons.menu_book, 'القصص', (_) => StoriesScreen(cls: c)),
        NavItem(Icons.rate_review, 'تصحيح الأجوبة', (_) => ReviewScreen(cls: c, onChanged: _refresh), badge: pending),
        NavItem(Icons.emoji_events, 'النتائج والشهادات', (_) => ResultsScreen(cls: c)),
        NavItem(Icons.tune, 'معايير الترتيب', (_) => CriteriaScreen(cls: c)),
      ],
    );
  }
}

/// مراجعة الأجوبة القصيرة التي لم تتطابق مع الكلمات المفتاحية.
class ReviewScreen extends StatefulWidget {
  final SchoolClass cls;
  final VoidCallback? onChanged;
  const ReviewScreen({super.key, required this.cls, this.onChanged});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<Map<String, Object?>>? items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ResultsRepo.pendingReviews(widget.cls.id);
    if (mounted) setState(() => items = r);
  }

  Future<void> _decide(int answerId, bool correct) async {
    await ResultsRepo.setReview(answerId, correct, Session.I.actor);
    widget.onChanged?.call();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return const EmptyState(icon: Icons.task_alt, text: 'لا توجد أجوبة تنتظر التصحيح.');
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('هذه أجوبة قصيرة لم تتطابق مع الكلمات المفتاحية. قرر هل هي صحيحة؛ تُحدَّث النتيجة تلقائيًا.',
          style: TextStyle(color: AppColors.muted)),
      for (final m in list)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['first_name']} ${m['last_name']} — ${m['story_title']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('السؤال: ${m['prompt']}'),
              if ((m['keywords'] as String? ?? '').isNotEmpty)
                Text('الكلمات المفتاحية: ${m['keywords']}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF2F6F5), borderRadius: BorderRadius.circular(10)),
                child: Text(_answerText(m['answer'] as String?), style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.ok),
                  onPressed: () => _decide(m['answer_id'] as int, true),
                  icon: const Icon(Icons.check),
                  label: const Text('صحيح'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _decide(m['answer_id'] as int, false),
                  icon: const Icon(Icons.close, color: AppColors.danger),
                  label: const Text('غير صحيح'),
                ),
              ]),
            ]),
          ),
        ),
    ]);
  }

  static String _answerText(String? json) {
    final a = StudentAnswer.fromJson(json);
    return a.text.isEmpty ? '(بدون جواب)' : a.text;
  }
}
