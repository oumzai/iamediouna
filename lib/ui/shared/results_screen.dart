import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/school_repo.dart';
import '../../services/ranking_service.dart';
import '../../services/reports.dart';
import '../widgets/common.dart';

/// الترتيب الشهري والسنوي، اعتماد النتائج، التقارير والشواهد التقديرية.
class ResultsScreen extends StatefulWidget {
  final SchoolClass cls;
  const ResultsScreen({super.key, required this.cls});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<Period> periods = [];
  Period? period;
  RankingOutcome? outcome;
  bool live = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final y = await SchoolRepo.currentYear();
    final months = Period.monthsOf(y);
    periods = [...months.reversed, Period.year(y)];
    period = months.last;
    await _load();
  }

  Future<void> _load() async {
    final p = period;
    if (p == null) return;
    setState(() => loading = true);
    final o = await RankingService.compute(widget.cls, p, live: live);
    if (!mounted) return;
    setState(() {
      outcome = o;
      loading = false;
    });
  }

  Future<void> _approve() async {
    final p = period!;
    final already = outcome?.fromSnapshot == true;
    final ok = await confirm(
      context,
      already ? 'إعادة اعتماد النتائج' : 'اعتماد النتائج',
      already
          ? 'سيُعاد حساب ترتيب ${p.label} بالمعايير الحالية ويُستبدل الترتيب المعتمد سابقًا (يُسجل ذلك في سجل العمليات).'
          : 'سيُحفظ ترتيب ${p.label} نهائيًا مع نسخة من المعايير المستعملة، حتى لا يتغير لاحقًا.',
      ok: 'اعتماد',
    );
    if (!ok || !mounted) return;
    await withProgress(context, 'اعتماد النتائج...', () => RankingService.approve(widget.cls, p, Session.I.actor));
    live = false;
    _load();
  }

  Future<void> _report() async {
    final p = period!;
    final bytes = await withProgress(context, 'إعداد التقرير...', () => Reports.classReport(widget.cls, p));
    if (bytes != null) await Reports.printOrShare(bytes, 'تقرير_${widget.cls.code}_${p.key.replaceAll('/', '-')}');
  }

  Future<void> _certificates() async {
    final p = period!;
    if (outcome?.fromSnapshot != true) {
      final ok = await confirm(context, 'النتائج غير معتمدة',
          'يُستحسن اعتماد النتائج قبل طباعة الشهادات حتى لا يتغير الترتيب لاحقًا. هل تريد الاعتماد الآن؟',
          ok: 'اعتماد ثم طباعة');
      if (!ok || !mounted) return;
      await RankingService.approve(widget.cls, p, Session.I.actor);
      live = false;
      await _load();
      if (!mounted) return;
    }
    final bytes = await withProgress(context, 'إعداد الشواهد التقديرية...',
        () => Reports.topCertificates(widget.cls, p, Session.I.actor));
    if (!mounted) return;
    if (bytes == null) {
      toast(context, 'لا يوجد تلاميذ مؤهلون للشهادات في هذه الفترة.', error: true);
      return;
    }
    await Reports.printOrShare(bytes, 'شهادات_${widget.cls.code}_${p.key.replaceAll('/', '-')}');
  }

  @override
  Widget build(BuildContext context) {
    final p = period;
    final o = outcome;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (p != null)
            DropdownButton<String>(
              value: p.key,
              items: [for (final x in periods) DropdownMenuItem(value: x.key, child: Text(x.label))],
              onChanged: (k) {
                period = periods.firstWhere((x) => x.key == k);
                live = false;
                _load();
              },
            ),
          if (o != null && o.fromSnapshot)
            Chip(
              avatar: const Icon(Icons.verified, color: Colors.white, size: 18),
              label: Text('معتمدة ${o.snapshotDate?.substring(0, 10) ?? ''}', style: const TextStyle(color: Colors.white)),
              backgroundColor: AppColors.ok,
            )
          else if (o != null)
            const Chip(label: Text('غير معتمدة (تتغير مع النتائج الجديدة)')),
          if (o != null && o.fromSnapshot)
            TextButton(
              onPressed: () {
                live = true;
                _load();
              },
              child: const Text('عرض بالمعايير الحالية'),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          ElevatedButton.icon(onPressed: _approve, icon: const Icon(Icons.verified), label: const Text('اعتماد النتائج')),
          OutlinedButton.icon(onPressed: _report, icon: const Icon(Icons.picture_as_pdf), label: const Text('التقرير PDF')),
          OutlinedButton.icon(
              onPressed: _certificates,
              icon: const Icon(Icons.workspace_premium),
              label: const Text('شواهد الثلاثة الأوائل')),
        ]),
      ),
      if (o != null)
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(o.criteria.config.describe(annual: p?.annual ?? false),
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
      Expanded(
        child: loading || o == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('المرتبة')),
                      DataColumn(label: Text('التلميذ(ة)')),
                      DataColumn(label: Text('قصص منجزة'), numeric: true),
                      DataColumn(label: Text('قصص مقيَّمة'), numeric: true),
                      DataColumn(label: Text('متوسط الفهم'), numeric: true),
                      DataColumn(label: Text('الانتظام'), numeric: true),
                      DataColumn(label: Text('النقطة'), numeric: true),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: [
                      for (final r in o.rows)
                        DataRow(
                          color: WidgetStatePropertyAll(
                            (r.rank ?? 99) <= 3 ? AppColors.accent.withValues(alpha: 0.15) : null,
                          ),
                          cells: [
                            DataCell(Text(r.rank == null ? '—' : '${r.rank}',
                                style: const TextStyle(fontWeight: FontWeight.w700))),
                            DataCell(Text(o.students[r.studentId]?.fullName ?? 'تلميذ #${r.studentId}')),
                            DataCell(Text('${r.passedStories}')),
                            DataCell(Text('${r.attemptedStories}')),
                            DataCell(Text(r.attemptedStories == 0 ? '—' : Ar.percent(r.avgPercent))),
                            DataCell(Text(Ar.percent(r.regularity * 100))),
                            DataCell(Text(r.score.toStringAsFixed(1))),
                            DataCell(Text(r.qualified ? 'مؤهل' : (r.attemptedStories == 0 ? 'لم يُقيَّم بعد' : 'غير مؤهل بعد'))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }
}
