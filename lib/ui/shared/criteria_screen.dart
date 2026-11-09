import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/results_repo.dart';
import '../../services/ai_client.dart';
import '../../services/ranking.dart';
import '../widgets/common.dart';

/// معايير الترتيب القابلة للتعديل، مع حفظ سجل لكل إصدار.
class CriteriaScreen extends StatefulWidget {
  final SchoolClass? cls; // null = معايير المؤسسة (المدير)
  const CriteriaScreen({super.key, required this.cls});

  @override
  State<CriteriaScreen> createState() => _CriteriaScreenState();
}

class _CriteriaScreenState extends State<CriteriaScreen> {
  RankingConfig cfg = RankingConfig();
  bool override = false;
  List<CriteriaVersion> history = [];
  final note = TextEditingController();
  bool loading = true;
  String? aiRationale;

  String get scope => widget.cls == null ? ResultsRepo.schoolScope : ResultsRepo.classScope(widget.cls!.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final eff = await ResultsRepo.effectiveCriteria(widget.cls?.id);
    final ov = widget.cls == null ? true : await ResultsRepo.hasClassOverride(widget.cls!.id);
    final h = await ResultsRepo.criteriaHistory(scope);
    if (!mounted) return;
    setState(() {
      cfg = eff.config.copy();
      override = ov;
      history = h;
      loading = false;
    });
  }

  Future<void> _save() async {
    final ok = await confirm(context, 'اعتماد المعايير',
        'ستُطبق المعايير الجديدة على الفترات غير المعتمدة. النتائج المعتمدة سابقًا تبقى كما هي.', ok: 'اعتماد');
    if (!ok) return;
    await ResultsRepo.saveCriteria(scope, cfg, Session.I.actor, note.text.trim());
    note.clear();
    if (mounted) toast(context, 'تم حفظ إصدار جديد من المعايير');
    _load();
  }

  Future<void> _suggest() async {
    final c = widget.cls;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    Map<String, dynamic> stats;
    if (c != null) {
      final st = await ResultsRepo.classStats(c.id, start, end);
      stats = {
        'scope': 'class',
        'level': c.level,
        'students': st.students,
        'stories_assigned': st.storiesAssigned,
        'attempts_last_2_months': st.attempts,
        'participants_last_2_months': st.participants,
        'avg_percent': st.avgPercent.round(),
      };
    } else {
      final classes = await PeopleRepo.classes();
      var students = 0, attempts = 0, part = 0;
      for (final x in classes) {
        final st = await ResultsRepo.classStats(x.id, start, end);
        students += st.students;
        attempts += st.attempts;
        part += st.participants;
      }
      stats = {
        'scope': 'school',
        'classes': classes.length,
        'levels': classes.map((x) => x.level).toSet().toList(),
        'students': students,
        'attempts_last_2_months': attempts,
        'participants_last_2_months': part,
      };
    }
    if (!mounted) return;
    final r = await withProgress(context, 'طلب اقتراح من الذكاء الاصطناعي...', () => AiClient.suggestCriteria(stats));
    if (r == null || !mounted) return;
    setState(() {
      cfg = r.$1;
      aiRationale = r.$2;
      note.text = 'اقتراح الذكاء الاصطناعي (بعد مراجعة)';
    });
    toast(context, 'تم ملء الاقتراح. راجعه ثم اضغط «اعتماد».');
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged, {String? help}) => ListTile(
        title: Text(label),
        subtitle: help != null ? Text(help) : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
          IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
      );

  Widget _weight(String label, int value, ValueChanged<int> onChanged) => ListTile(
        title: Text('$label: $value'),
        subtitle: Slider(
          value: value.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: (v) => onChanged(v.round()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final c = widget.cls;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        color: const Color(0xFFEAF4F2),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            c == null
                ? 'معايير المؤسسة: تُطبق على كل الأقسام ما لم يحدد القسم معايير خاصة به.'
                : (override
                    ? 'يستعمل القسم ${c.code} معايير خاصة به.'
                    : 'يستعمل القسم ${c.code} حاليًا معايير المؤسسة. أي حفظ هنا ينشئ معايير خاصة بالقسم.'),
          ),
        ),
      ),
      Text(cfg.describe(), style: const TextStyle(color: AppColors.primaryDark)),
      const SectionTitle('شروط التأهل'),
      Card(
        child: Column(children: [
          _stepper('الحد الأدنى من القصص المنجزة شهريًا', cfg.minStoriesMonthly, 0, 30,
              (v) => setState(() => cfg.minStoriesMonthly = v)),
          _stepper('الحد الأدنى من القصص المنجزة سنويًا', cfg.minStoriesAnnual, 0, 200,
              (v) => setState(() => cfg.minStoriesAnnual = v)),
          _stepper('نسبة النجاح لاعتبار القصة منجزة (%)', cfg.passPercent, 0, 100,
              (v) => setState(() => cfg.passPercent = v), help: 'مثال: 50 تعني أن التلميذ أجاب عن نصف الأسئلة على الأقل'),
        ]),
      ),
      const SectionTitle('الترتيب النهائي'),
      Card(
        child: Column(children: [
          _weight('وزن متوسط الفهم', cfg.wComprehension, (v) => setState(() => cfg.wComprehension = v)),
          _weight('وزن عدد القصص', cfg.wStories, (v) => setState(() => cfg.wStories = v)),
          _weight('وزن الانتظام في المشاركة', cfg.wRegularity, (v) => setState(() => cfg.wRegularity = v)),
          _stepper('العدد المستهدف من القصص شهريًا', cfg.targetStoriesMonthly, 1, 40,
              (v) => setState(() => cfg.targetStoriesMonthly = v)),
          _stepper('العدد المستهدف من القصص سنويًا', cfg.targetStoriesAnnual, 1, 300,
              (v) => setState(() => cfg.targetStoriesAnnual = v)),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('عند التعادل: الأعلى في متوسط الفهم، ثم الأكثر قصصًا، ثم الأسبق إنجازًا. '
                'إذا بقي التعادل يتقاسم التلاميذ المرتبة نفسها.', style: TextStyle(color: AppColors.muted)),
          ),
        ]),
      ),
      if (aiRationale != null && aiRationale!.isNotEmpty)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('تعليل الاقتراح: $aiRationale'))),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextField(controller: note, decoration: const InputDecoration(labelText: 'سبب التعديل (يُحفظ في السجل)')),
      ),
      Wrap(spacing: 10, runSpacing: 10, children: [
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('اعتماد المعايير')),
        OutlinedButton.icon(onPressed: _suggest, icon: const Icon(Icons.auto_awesome), label: const Text('اقتراح بالذكاء الاصطناعي')),
        if (c != null && override)
          OutlinedButton.icon(
            onPressed: () async {
              await ResultsRepo.removeClassOverride(c.id, Session.I.actor);
              _load();
            },
            icon: const Icon(Icons.undo),
            label: const Text('الرجوع إلى معايير المؤسسة'),
          ),
        OutlinedButton(onPressed: () => setState(() => cfg = RankingConfig()), child: const Text('القيم الأولية')),
      ]),
      const SectionTitle('سجل التعديلات'),
      if (history.isEmpty) const Text('لا توجد إصدارات محفوظة لهذا النطاق بعد.'),
      for (final h in history)
        ListTile(
          dense: true,
          leading: Icon(h.active ? Icons.check_circle : Icons.history, color: h.active ? AppColors.ok : AppColors.muted),
          title: Text('#${h.id} — ${h.createdAt.substring(0, 16).replaceFirst('T', ' ')} — ${h.createdBy}'),
          subtitle: Text('${h.config.describe()}${h.note.isNotEmpty ? '\nالسبب: ${h.note}' : ''}'),
        ),
    ]);
  }
}
