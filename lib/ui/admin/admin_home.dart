import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/results_repo.dart';
import '../../data/school_repo.dart';
import '../../services/ranking_service.dart';
import '../../services/reports.dart';
import '../shared/class_dashboard.dart';
import '../shared/criteria_screen.dart';
import '../shared/results_screen.dart';
import '../shared/stories_screen.dart';
import '../widgets/common.dart';
import 'classes_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

/// فضاء المدير.
class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return NavShell(
      title: 'الإدارة',
      color: AppColors.admin,
      actions: [
        IconButton(
          tooltip: 'خروج',
          icon: const Icon(Icons.logout),
          onPressed: () => Navigator.pop(context),
        ),
      ],
      items: [
        NavItem(Icons.dashboard, 'لوحة القيادة', (_) => const AdminDashboard()),
        NavItem(Icons.groups, 'الأقسام والتلاميذ', (_) => const ClassesScreen()),
        NavItem(Icons.upload_file, 'استيراد مسار', (_) => const ImportScreen()),
        NavItem(Icons.menu_book, 'القصص', (_) => const StoriesScreen(cls: null)),
        NavItem(Icons.emoji_events, 'النتائج والشهادات', (_) => const AdminResultsPicker()),
        NavItem(Icons.tune, 'معايير الترتيب', (_) => const CriteriaScreen(cls: null)),
        NavItem(Icons.settings, 'الإعدادات', (_) => const SettingsScreen()),
      ],
    );
  }
}

class _ClassRow {
  final SchoolClass c;
  final ClassStats st;
  final String best;
  _ClassRow(this.c, this.st, this.best);
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Period period;
  List<Period> months = [];
  bool loading = true;
  int students = 0, stories = 0, attempts = 0, participants = 0, levels = 0;
  double avg = 0;
  List<_ClassRow> rows = [];
  List<SeriesPoint> weekly = [], monthly = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    period = Period.month(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final year = await SchoolRepo.currentYear();
    months = Period.monthsOf(year);
    if (!months.any((m) => m.key == period.key)) months.add(period);
    final classes = await PeopleRepo.classes();
    final list = <_ClassRow>[];
    var tPart = 0, tAtt = 0;
    double sum = 0;
    for (final c in classes) {
      final st = await ResultsRepo.classStats(c.id, period.start, period.end);
      final o = await RankingService.compute(c, period);
      final best = o.ranked.isEmpty ? '—' : (o.students[o.ranked.first.studentId]?.fullName ?? '—');
      list.add(_ClassRow(c, st, best));
      tPart += st.participants;
      tAtt += st.attempts;
      sum += st.avgPercent * st.attempts;
    }
    students = await PeopleRepo.totalStudents();
    stories = await LibraryRepo.storyCount();
    weekly = await ResultsRepo.weekly();
    monthly = await ResultsRepo.monthly(year);
    if (!mounted) return;
    setState(() {
      rows = list;
      participants = tPart;
      attempts = tAtt;
      avg = tAtt == 0 ? 0.0 : sum / tAtt;
      levels = classes.map((c) => c.level).toSet().length;
      loading = false;
    });
  }

  String _status(ClassStats st) {
    if (st.students == 0) return '—';
    if (st.participation >= 50 && (st.attempts == 0 || st.avgPercent >= 50)) return 'نشيط';
    if (st.participation < 25 || (st.attempts > 0 && st.avgPercent < 50)) return 'يحتاج إلى دعم';
    return 'متوسط';
  }

  Color _statusColor(String s) =>
      s == 'نشيط' ? AppColors.ok : (s == 'يحتاج إلى دعم' ? AppColors.danger : AppColors.accent);

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final participation = students == 0 ? 0.0 : participants * 100 / students;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          const Text('الفترة: ', style: TextStyle(fontSize: 16)),
          DropdownButton<String>(
            value: period.key,
            items: [for (final m in months) DropdownMenuItem(value: m.key, child: Text(m.label))],
            onChanged: (k) {
              final m = months.firstWhere((x) => x.key == k);
              period = m;
              _load();
            },
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () async {
              final bytes = await withProgress(context, 'إعداد تقرير المؤسسة...', () => Reports.schoolReport(period));
              if (bytes != null) await Reports.printOrShare(bytes, 'تقرير_المؤسسة_${period.key}');
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('تقرير المؤسسة PDF'),
          ),
        ]),
        Wrap(children: [
          StatCard(title: 'تلميذ(ة) بالمؤسسة', value: '$students', icon: Icons.people),
          StatCard(title: 'قسم / $levels مستويات', value: '${rows.length}', icon: Icons.class_, color: AppColors.admin),
          StatCard(title: 'قصة مسجلة', value: '$stories', icon: Icons.menu_book, color: AppColors.student),
          StatCard(title: 'اختبار منجز (الفترة)', value: '$attempts', icon: Icons.quiz, color: AppColors.primaryDark),
          StatCard(title: 'تلميذ مشارك', value: '$participants', icon: Icons.how_to_reg, color: AppColors.ok),
          StatCard(title: 'نسبة المشاركة', value: Ar.percent(participation), icon: Icons.pie_chart, color: AppColors.admin),
          StatCard(title: 'متوسط الفهم القرائي', value: attempts == 0 ? '—' : Ar.percent(avg), icon: Icons.psychology,
              color: AppColors.accent),
        ]),
        const SectionTitle('النتائج حسب القسم'),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('القسم')),
                DataColumn(label: Text('التلاميذ'), numeric: true),
                DataColumn(label: Text('المشاركون'), numeric: true),
                DataColumn(label: Text('المشاركة'), numeric: true),
                DataColumn(label: Text('الاختبارات'), numeric: true),
                DataColumn(label: Text('الفهم'), numeric: true),
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('أفضل قارئ')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    onSelectChanged: (_) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(backgroundColor: AppColors.admin, title: Text('القسم ${r.c.code}')),
                          body: ClassDashboard(cls: r.c),
                        ),
                      ),
                    ),
                    cells: [
                      DataCell(Text(r.c.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text('${r.st.students}')),
                      DataCell(Text('${r.st.participants}')),
                      DataCell(Text(Ar.percent(r.st.participation))),
                      DataCell(Text('${r.st.attempts}')),
                      DataCell(Text(r.st.attempts == 0 ? '—' : Ar.percent(r.st.avgPercent))),
                      DataCell(Chip(
                        label: Text(_status(r.st), style: const TextStyle(color: Colors.white)),
                        backgroundColor: _statusColor(_status(r.st)),
                      )),
                      DataCell(Text(r.best)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SectionTitle('تطور القراءة أسبوعيًا (عدد الاختبارات)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SimpleBars(labels: [for (final w in weekly) w.label], values: [for (final w in weekly) w.attempts.toDouble()]),
          ),
        ),
        const SectionTitle('متوسط الفهم شهريًا'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SimpleBars(
              labels: [for (final m in monthly) m.label],
              values: [for (final m in monthly) m.avg],
              maxValue: 100,
              color: AppColors.accent,
              valueText: (v) => v == 0 ? '—' : '${v.round()}%',
            ),
          ),
        ),
      ]),
    );
  }
}

/// اختيار قسم لعرض نتائجه وطباعة التقارير والشهادات.
class AdminResultsPicker extends StatefulWidget {
  const AdminResultsPicker({super.key});

  @override
  State<AdminResultsPicker> createState() => _AdminResultsPickerState();
}

class _AdminResultsPickerState extends State<AdminResultsPicker> {
  List<SchoolClass>? classes;

  @override
  void initState() {
    super.initState();
    PeopleRepo.classes().then((c) {
      if (mounted) setState(() => classes = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = classes;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return const EmptyState(icon: Icons.class_outlined, text: 'لا توجد أقسام بعد.');
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('اختر قسمًا لعرض الترتيب الشهري والسنوي، واعتماد النتائج، وطباعة التقارير والشواهد التقديرية.',
          style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 8),
      for (final c in list)
        Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.admin, child: Text(Ar.levelShort(c.level),
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${c.studentCount} تلميذ(ة) ${c.teacherName.isNotEmpty ? '— ${c.teacherName}' : ''}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(backgroundColor: AppColors.admin, title: Text('نتائج القسم ${c.code}')),
                  body: ResultsScreen(cls: c),
                ),
              ),
            ),
          ),
        ),
      if (Session.I.isAdmin) const SizedBox(height: 12),
    ]);
  }
}
