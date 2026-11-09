import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/results_repo.dart';
import '../../services/scoring.dart';
import '../widgets/common.dart';

/// مشغل الاختبار: سؤال واحد في كل شاشة، أزرار كبيرة، حفظ فوري لكل جواب.
/// في وضع المعاينة (للأستاذ) لا يُحفظ شيء وتظهر النتيجة التفصيلية.
class QuizPlayerScreen extends StatefulWidget {
  final Story story;
  final Quiz quiz;
  final List<Question> questions;
  final Attempt? attempt;
  final Map<int, StudentAnswer> initialAnswers;
  final bool preview;
  final VoidCallback? onHandOver;

  const QuizPlayerScreen({
    super.key,
    required this.story,
    required this.quiz,
    required this.questions,
    this.attempt,
    this.initialAnswers = const {},
    this.preview = false,
    this.onHandOver,
  });

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  int index = 0;
  late Map<int, StudentAnswer> answers;
  final Map<int, List<AnswerOption>> shuffled = {};
  final Map<int, List<int>> orderState = {};
  final Map<int, TextEditingController> textCtls = {};
  final player = AudioPlayer();
  Attempt? finished;
  double previewPercent = 0;
  bool saving = false;

  String get seed => widget.attempt?.id ?? 'preview';

  @override
  void initState() {
    super.initState();
    answers = Map.of(widget.initialAnswers);
    for (final q in widget.questions) {
      final qid = q.id ?? q.hashCode;
      shuffled[qid] = Grader.seededShuffle(q.options, '$seed-$qid');
      if (q.type == QType.order) {
        final saved = answers[qid]?.optionIds;
        orderState[qid] = (saved != null && saved.length == q.options.length)
            ? [...saved]
            : shuffled[qid]!.map((o) => o.id ?? 0).toList();
      }
      if (q.type == QType.short) textCtls[qid] = TextEditingController(text: answers[qid]?.text ?? '');
    }
    // البدء من أول سؤال لم يُجب عنه (عند الاستئناف)
    final firstOpen = widget.questions.indexWhere((q) => answers[q.id ?? q.hashCode]?.isEmpty ?? true);
    if (firstOpen > 0) index = firstOpen;
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Question get q => widget.questions[index];
  int get qid => q.id ?? q.hashCode;

  Future<void> _setAnswer(StudentAnswer a) async {
    setState(() => answers[qid] = a);
    final at = widget.attempt;
    if (!widget.preview && at != null && q.id != null) {
      await ResultsRepo.saveAnswer(at.id, q.id!, a);
    }
  }

  Future<void> _commitText() async {
    if (q.type != QType.short) return;
    final t = textCtls[qid]?.text ?? '';
    if ((answers[qid]?.text ?? '') != t) await _setAnswer(StudentAnswer(text: t));
  }

  Future<void> _next() async {
    await _commitText();
    if (index < widget.questions.length - 1) {
      setState(() => index++);
      player.stop();
    } else {
      await _finish();
    }
  }

  Future<void> _prev() async {
    await _commitText();
    if (index > 0) setState(() => index--);
  }

  Future<void> _finish() async {
    final unanswered = widget.questions.where((x) => answers[x.id ?? x.hashCode]?.isEmpty ?? true).length;
    if (unanswered > 0) {
      final ok = await confirm(context, 'إنهاء الاختبار',
          'لم تُجب عن $unanswered سؤال(ا). هل تريد الإنهاء رغم ذلك؟', ok: 'إنهاء');
      if (!ok) return;
    }
    setState(() => saving = true);
    if (widget.preview) {
      double score = 0, max = 0;
      for (final x in widget.questions) {
        final g = Grader.grade(x, answers[x.id ?? x.hashCode] ?? const StudentAnswer());
        score += g.points;
        max += g.max;
      }
      setState(() {
        previewPercent = max == 0 ? 0.0 : score * 100 / max;
        finished = Attempt(
            id: 'preview', studentId: 0, quizId: widget.quiz.id, storyId: widget.story.id, classId: 0,
            attemptNo: 1, startedAt: DateTime.now(), percent: previewPercent, status: 'completed');
        saving = false;
      });
      return;
    }
    final r = await ResultsRepo.finishAttempt(widget.attempt!, widget.questions);
    if (mounted) {
      setState(() {
        finished = r;
        saving = false;
      });
    }
  }

  // ---------------- عرض الأسئلة ----------------

  Widget _optionTile(AnswerOption o, bool selected, VoidCallback onTap, {bool multi = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: selected ? AppColors.student.withValues(alpha: 0.15) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AppColors.student : const Color(0xFFD5DEDC), width: selected ? 3 : 1.5),
            ),
            child: Row(children: [
              Icon(
                multi
                    ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                    : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                color: AppColors.student,
                size: 32,
              ),
              const SizedBox(width: 12),
              if (o.imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LocalImage(o.imagePath, width: 110, height: 110),
                  ),
                ),
              Expanded(child: Text(o.label, style: const TextStyle(fontSize: 22))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _imageGrid(List<AnswerOption> opts, StudentAnswer? a) {
    return Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
      for (final o in opts)
        GestureDetector(
          onTap: () => _setAnswer(StudentAnswer(optionIds: [o.id ?? 0])),
          child: Container(
            width: 190,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: a?.optionIds.contains(o.id) == true ? AppColors.student : const Color(0xFFD5DEDC),
                width: a?.optionIds.contains(o.id) == true ? 4 : 1.5,
              ),
            ),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LocalImage(o.imagePath, width: 170, height: 150,
                    placeholder: const SizedBox(width: 170, height: 150, child: Icon(Icons.image, size: 60))),
              ),
              if (o.label.isNotEmpty) Text(o.label, style: const TextStyle(fontSize: 19), textAlign: TextAlign.center),
            ]),
          ),
        ),
    ]);
  }

  Widget _orderList() {
    final ids = orderState[qid]!;
    final byId = {for (final o in q.options) (o.id ?? 0): o};
    final touched = !(answers[qid]?.isEmpty ?? true);
    return Column(children: [
      Text(touched ? 'رتّب الأحداث من الأول إلى الأخير باستعمال الأسهم' : 'استعمل الأسهم لترتيب الأحداث من الأول إلى الأخير',
          style: const TextStyle(color: AppColors.muted, fontSize: 16)),
      for (var i = 0; i < ids.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              CircleAvatar(backgroundColor: AppColors.student, child: Text('${i + 1}', style: const TextStyle(color: Colors.white))),
              const SizedBox(width: 10),
              if (byId[ids[i]]?.imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: LocalImage(byId[ids[i]]?.imagePath, width: 80, height: 80),
                ),
              Expanded(child: Text(byId[ids[i]]?.label ?? '', style: const TextStyle(fontSize: 21))),
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.arrow_circle_up, color: AppColors.primary),
                onPressed: i == 0 ? null : () => _swap(i, i - 1),
              ),
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.arrow_circle_down, color: AppColors.primary),
                onPressed: i == ids.length - 1 ? null : () => _swap(i, i + 1),
              ),
            ]),
          ),
        ),
      if (!touched)
        TextButton(
          onPressed: () => _setAnswer(StudentAnswer(optionIds: [...ids])),
          child: const Text('هذا هو الترتيب الصحيح', style: TextStyle(fontSize: 18)),
        ),
    ]);
  }

  void _swap(int a, int b) {
    final ids = orderState[qid]!;
    final t = ids[a];
    ids[a] = ids[b];
    ids[b] = t;
    _setAnswer(StudentAnswer(optionIds: [...ids]));
  }

  Widget _questionBody() {
    final a = answers[qid];
    final opts = shuffled[qid] ?? q.options;
    switch (q.type) {
      case QType.single:
      case QType.complete:
        return Column(children: [
          for (final o in opts)
            _optionTile(o, a?.optionIds.contains(o.id) == true, () => _setAnswer(StudentAnswer(optionIds: [o.id ?? 0]))),
        ]);
      case QType.truefalse:
        return Row(children: [
          for (final o in q.options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 120,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: a?.optionIds.contains(o.id) == true
                          ? (o.label.contains('صح') ? AppColors.ok : AppColors.danger)
                          : Colors.white,
                      foregroundColor: a?.optionIds.contains(o.id) == true ? Colors.white : AppColors.primaryDark,
                      side: const BorderSide(color: Color(0xFFD5DEDC), width: 1.5),
                    ),
                    onPressed: () => _setAnswer(StudentAnswer(optionIds: [o.id ?? 0])),
                    icon: Icon(o.label.contains('صح') ? Icons.thumb_up : Icons.thumb_down, size: 40),
                    label: Text(o.label, style: const TextStyle(fontSize: 30)),
                  ),
                ),
              ),
            ),
        ]);
      case QType.image:
        return _imageGrid(opts, a);
      case QType.multi:
        return Column(children: [
          const Text('يمكنك اختيار أكثر من جواب', style: TextStyle(color: AppColors.muted, fontSize: 16)),
          for (final o in opts)
            _optionTile(o, a?.optionIds.contains(o.id) == true, () {
              final set = [...?a?.optionIds];
              final id = o.id ?? 0;
              if (set.contains(id)) {
                set.remove(id);
              } else {
                set.add(id);
              }
              _setAnswer(StudentAnswer(optionIds: set));
            }, multi: true),
        ]);
      case QType.order:
        return _orderList();
      case QType.short:
        return TextField(
          controller: textCtls[qid],
          maxLines: 4,
          style: const TextStyle(fontSize: 22),
          decoration: const InputDecoration(hintText: 'اكتب جوابك هنا'),
          onChanged: (_) {},
        );
    }
    // ignore: dead_code
    return const SizedBox();
  }

  // ---------------- نتيجة الاختبار ----------------

  Widget _result() {
    final f = finished!;
    final stars = Grader.stars(f.percent);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 90, color: AppColors.accent),
          ]),
          const SizedBox(height: 12),
          Text(Grader.encouragement(f.percent),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('قصة: ${widget.story.title}', style: const TextStyle(fontSize: 18, color: AppColors.muted)),
          if (widget.preview) ...[
            const SizedBox(height: 16),
            Text('(معاينة الأستاذ) النتيجة: ${f.percent.round()}%', style: const TextStyle(fontSize: 18)),
            for (var i = 0; i < widget.questions.length; i++)
              Text(
                'س${i + 1}: ${Grader.grade(widget.questions[i], answers[widget.questions[i].id ?? widget.questions[i].hashCode] ?? const StudentAnswer()).correct ? '✔' : '✘'}',
              ),
          ],
          if (f.needsReview)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('سيراجع أستاذك بعض أجوبتك.', style: TextStyle(fontSize: 17, color: AppColors.muted)),
            ),
          const SizedBox(height: 30),
          Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.center, children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.home),
              label: Text(widget.preview ? 'إغلاق المعاينة' : 'العودة'),
            ),
            if (widget.onHandOver != null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.student),
                onPressed: widget.onHandOver,
                icon: const Icon(Icons.tablet_android),
                label: const Text('إنهاء وتسليم التابلت'),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.quiz, text: 'لا توجد أسئلة في هذا الاختبار.'));
    }
    if (finished != null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.student, automaticallyImplyLeading: false, title: Text(widget.story.title)),
        body: _result(),
      );
    }
    final total = widget.questions.length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.preview ? AppColors.teacher : AppColors.student,
        title: Text(widget.preview ? 'معاينة: ${widget.story.title}' : widget.story.title),
      ),
      body: SafeArea(
        child: Column(children: [
          LinearProgressIndicator(value: (index + 1) / total, minHeight: 8, color: AppColors.accent),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('السؤال ${index + 1} من $total', style: const TextStyle(fontSize: 18, color: AppColors.muted)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (q.audioPath != null)
                        IconButton.filled(
                          iconSize: 40,
                          style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                          onPressed: () => player.play(DeviceFileSource(AppDb.I.abs(q.audioPath!))),
                          icon: const Icon(Icons.volume_up),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(q.prompt, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.5)),
                      ),
                    ]),
                    if (q.imagePath != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: LocalImage(q.imagePath, height: 240, fit: BoxFit.contain),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _questionBody(),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (index > 0)
                OutlinedButton.icon(
                  onPressed: _prev,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('السابق', style: TextStyle(fontSize: 20)),
                ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: index == total - 1 ? AppColors.ok : AppColors.student,
                  minimumSize: const Size(200, 64),
                ),
                onPressed: saving ? null : _next,
                icon: Icon(index == total - 1 ? Icons.check : Icons.arrow_back),
                label: Text(index == total - 1 ? 'إنهاء الاختبار' : 'التالي', style: const TextStyle(fontSize: 22)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
