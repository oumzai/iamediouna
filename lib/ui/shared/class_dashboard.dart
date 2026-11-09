import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/theme.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/results_repo.dart';
import '../../services/ranking_service.dart';
import '../widgets/common.dart';

/// لوحة القسم: المؤشرات، أفضل القراء، تتبع إنجاز كل قصة.
class ClassDashboard extends StatefulWidget {
  final SchoolClass cls;
  const ClassDashboard({super.key, required this.cls});

  @override
  State<ClassDashboard> createState() => _ClassDashboardState();
}

class _ClassDashboardState extends State<ClassDashboard> {
  bool loading = true;
  late Period period;
  ClassStats? st;
  RankingOutcome? ranking;
  List<SeriesPoint> weekly = [];
  List<StoryInfo> stories = [];
  List<Student> students = [];
  int? storyId;
  Map<int, double> progress = {};
  int pending = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    period = Period.month(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final c = widget.cls;
    final s = await ResultsRepo.classStats(c.id, period.start, period.end);
    final r = await RankingService.compute(c, period);
    final w = await ResultsRepo.weekly(classId: c.id);
    final st = await LibraryRepo.stories(classId: c.id, onlyAssigned: true);
    final studs = await PeopleRepo.students(c.id);
    final pend = await ResultsRepo.pendingReviewCount(c.id);
    final sid = storyId ?? (st.isNotEmpty ? st.first.story.id : null);
    final prog = sid == null ? <int, double>{} : await ResultsRepo.storyProgress(c.id, sid);
    if (!mounted) return;
    setState(() {
      this.st = s;
      ranking = r;
      weekly = w;
      stories = st;
      students = studs;
      storyId = sid;
      progress = prog;
      pending = pend;
      loading = false;
    });
  }

  Future<void> _selectStory(int? id) async {
    if (id == null) return;
    final prog = await ResultsRepo.storyProgress(widget.cls.id, id);
    if (mounted) {
      setState(() {
        storyId = id;
        progress = prog;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final s = st!;
    final r = ranking!;
    final done = students.where((x) => progress.containsKey(x.id)).toList();
    final notDone = students.where((x) => !progress.containsKey(x.id)).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Text('${widget.cls.code} — ${period.label}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        Wrap(children: [
          StatCard(title: 'تلميذ(ة)', value: '${s.students}', icon: Icons.people),
          StatCard(title: 'قصة مسندة', value: '${s.storiesAssigned}', icon: Icons.menu_book, color: AppColors.student),
          StatCard(title: 'مشارك هذا الشهر', value: '${s.participants}', icon: Icons.how_to_reg, color: AppColors.ok),
          StatCard(title: 'نسبة المشاركة', value: Ar.percent(s.participation), icon: Icons.pie_chart, color: AppColors.admin),
          StatCard(title: 'اختبار منجز', value: '${s.attempts}', icon: Icons.quiz, color: AppColors.primaryDark),
          StatCard(title: 'متوسط الفهم', value: s.attempts == 0 ? '—' : Ar.percent(s.avgPercent), icon: Icons.psychology,
              color: AppColors.accent),
          if (pending > 0)
            StatCard(title: 'جواب ينتظر التصحيح', value: '$pending', icon: Icons.rate_review, color: AppColors.danger),
        ]),
        const SectionTitle('أفضل القراء هذا الشهر'),
        Card(
          child: r.top3.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('لا يوجد بعد تلميذ مؤهل للترتيب هذا الشهر حسب المعايير المعتمدة.'))
              : Column(children: [
                  for (final row in r.top3)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: [AppColors.accent, Colors.blueGrey, Colors.brown][(row.rank ?? 1) - 1 > 2 ? 2 : (row.rank ?? 1) - 1],
                        child: Text('${row.rank}', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(r.students[row.studentId]?.fullName ?? ''),
                      subtitle: Text('قصص منجزة: ${row.passedStories} — متوسط الفهم: ${Ar.percent(row.avgPercent)}'),
                    ),
                ]),
        ),
        const SectionTitle('عدد الاختبارات أسبوعيًا'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SimpleBars(labels: [for (final w in weekly) w.label], values: [for (final w in weekly) w.attempts.toDouble()]),
          ),
        ),
        SectionTitle(
          'تتبع إنجاز القصص',
          trailing: stories.isEmpty
              ? null
              : DropdownButton<int>(
                  value: storyId,
                  items: [for (final x in stories) DropdownMenuItem(value: x.story.id, child: Text(x.story.title))],
                  onChanged: _selectStory,
                ),
        ),
        if (stories.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('لم تُسند أي قصة لهذا القسم بعد.')))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('أنجزوا الاختبار (${done.length})', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ok)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final x in done) Chip(label: Text('${x.fullName} — ${Ar.percent(progress[x.id])}')),
                ]),
                const SizedBox(height: 10),
                Text('لم ينجزوه بعد (${notDone.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.student)),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final x in notDone) Chip(label: Text(x.fullName))]),
                const SizedBox(height: 6),
                const Text('تذكير: عدم إنجاز الاختبار لا يعني بالضرورة عدم قراءة القصة.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ),
      ]),
    );
  }
}
