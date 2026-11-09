import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../services/ai_client.dart';
import '../../services/pick.dart';
import '../student/quiz_player.dart';
import '../widgets/common.dart';
import 'pdf_pages.dart';

/// مراجعة الاختبار وتعديله قبل النشر. لا يُعتمد الاختبار إلا بعد موافقة الأستاذ.
class QuizEditorScreen extends StatefulWidget {
  final int quizId;
  final Story story;
  const QuizEditorScreen({super.key, required this.quizId, required this.story});

  @override
  State<QuizEditorScreen> createState() => _QuizEditorScreenState();
}

class _QuizEditorScreenState extends State<QuizEditorScreen> {
  Quiz? quiz;
  List<Question> questions = [];
  bool locked = false; // للاختبار نتائج ← للقراءة فقط
  bool dirty = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await LibraryRepo.quizById(widget.quizId);
    final qs = await LibraryRepo.loadQuestions(widget.quizId);
    final attempts = await LibraryRepo.attemptsForQuiz(widget.quizId);
    if (!mounted) return;
    setState(() {
      quiz = q;
      questions = qs;
      locked = attempts > 0;
      dirty = false;
      loading = false;
    });
  }

  Future<bool> _save({bool silent = false}) async {
    final q = quiz;
    if (q == null || locked) return !locked;
    try {
      await LibraryRepo.updateQuizMeta(q);
      await LibraryRepo.saveQuestions(q.id, questions);
      dirty = false;
      if (!silent && mounted) toast(context, 'تم حفظ المسودة');
      return true;
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
      return false;
    }
  }

  Future<void> _publish() async {
    if (questions.isEmpty) {
      toast(context, 'أضف سؤالًا واحدًا على الأقل', error: true);
      return;
    }
    for (var i = 0; i < questions.length; i++) {
      final err = questions[i].validate();
      if (err != null) {
        toast(context, 'السؤال ${i + 1}: $err', error: true);
        return;
      }
    }
    final ok = await confirm(context, 'اعتماد ونشر الاختبار',
        'بعد النشر يظهر الاختبار للتلاميذ. هل راجعت جميع الأسئلة وأجوبتها الصحيحة؟', ok: 'نشر');
    if (!ok || !await _save(silent: true)) return;
    await LibraryRepo.setQuizStatus(quiz!.id, 'published', Session.I.actor);
    if (mounted) {
      toast(context, 'تم نشر الاختبار');
      Navigator.pop(context);
    }
  }

  Future<void> _preview() async {
    if (!locked && !await _save(silent: true)) return;
    final qs = await LibraryRepo.loadQuestions(widget.quizId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuizPlayerScreen(story: widget.story, quiz: quiz!, questions: qs, preview: true)),
    );
    _load();
  }

  Future<void> _editQuestion(int? index, {QType? newType}) async {
    final original = index == null ? Question(type: newType ?? QType.single) : questions[index].copy();
    if (index == null) _prepareForType(original);
    final edited = await Navigator.push<Question>(
      context,
      MaterialPageRoute(builder: (_) => QuestionEditorScreen(question: original, story: widget.story, level: quiz!.level)),
    );
    if (edited == null) return;
    setState(() {
      if (index == null) {
        questions.add(edited);
      } else {
        questions[index] = edited;
      }
      dirty = true;
    });
    await _save(silent: true);
  }

  static void _prepareForType(Question q) {
    switch (q.type) {
      case QType.truefalse:
        q.options = [AnswerOption(label: 'صح', isCorrect: true), AnswerOption(label: 'خطأ')];
        break;
      case QType.short:
        q.options = [];
        break;
      case QType.order:
        q.options = [AnswerOption(label: ''), AnswerOption(label: ''), AnswerOption(label: '')];
        break;
      default:
        q.options = [AnswerOption(label: '', isCorrect: true), AnswerOption(label: ''), AnswerOption(label: '')];
    }
  }

  Future<void> _regenerate(int index) async {
    final pdf = await PdfTools.readStoryPdf(widget.story.pdfPath);
    if (!mounted) return;
    if (pdf == null) {
      toast(context, 'لا يوجد ملف PDF لهذه القصة', error: true);
      return;
    }
    final old = questions[index];
    final q = await withProgress(
      context,
      'إعادة توليد السؤال...',
      () => AiClient.regenerateQuestion(
        story: widget.story,
        pdf: pdf,
        level: quiz!.level,
        type: old.type,
        difficulty: old.difficulty,
        avoidPrompts: questions.map((e) => e.prompt).toList(),
      ),
    );
    if (q == null || !mounted) return;
    setState(() {
      questions[index] = q;
      dirty = true;
    });
    await _save(silent: true);
  }

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= questions.length) return;
    setState(() {
      final t = questions[i];
      questions[i] = questions[j];
      questions[j] = t;
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = quiz;
    if (loading || q == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirm(context, 'تغييرات غير محفوظة', 'هل تريد حفظ التعديلات قبل الخروج؟', ok: 'حفظ');
        if (ok) await _save(silent: true);
        dirty = false;
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(q.published ? 'اختبار منشور' : 'مراجعة الاختبار (مسودة)'),
          actions: [
            IconButton(tooltip: 'معاينة كما يراه التلميذ', icon: const Icon(Icons.visibility), onPressed: _preview),
            if (!locked) IconButton(tooltip: 'حفظ', icon: const Icon(Icons.save), onPressed: _save),
          ],
        ),
        floatingActionButton: locked
            ? null
            : PopupMenuButton<QType>(
                tooltip: 'إضافة سؤال',
                onSelected: (t) => _editQuestion(null, newType: t),
                itemBuilder: (_) => [for (final t in QType.values) PopupMenuItem(value: t, child: Text(t.label))],
                child: const FloatingActionButton.extended(
                  onPressed: null,
                  icon: Icon(Icons.add),
                  label: Text('إضافة سؤال'),
                ),
              ),
        bottomNavigationBar: locked || q.published
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: ElevatedButton.icon(
                    onPressed: _publish,
                    icon: const Icon(Icons.verified),
                    label: const Text('اعتماد ونشر الاختبار للتلاميذ'),
                  ),
                ),
              ),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
          if (locked)
            Card(
              color: const Color(0xFFFFF4E0),
              child: ListTile(
                leading: const Icon(Icons.lock, color: AppColors.student),
                title: const Text('أجاب التلاميذ عن هذا الاختبار، لذلك لا يمكن تعديله (لحماية النتائج).'),
                trailing: TextButton(
                  onPressed: () async {
                    final id = await LibraryRepo.duplicateQuiz(q.id, Session.I.actor);
                    if (!context.mounted) return;
                    await Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => QuizEditorScreen(quizId: id, story: widget.story)));
                  },
                  child: const Text('نسخ كمسودة جديدة'),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 320,
                  child: TextFormField(
                    initialValue: q.title,
                    enabled: !locked,
                    decoration: const InputDecoration(labelText: 'عنوان الاختبار'),
                    onChanged: (v) {
                      q.title = v;
                      dirty = true;
                    },
                  ),
                ),
                DropdownButton<int>(
                  value: q.level,
                  items: [for (var l = 1; l <= 6; l++) DropdownMenuItem(value: l, child: Text(Ar.levelName(l)))],
                  onChanged: locked ? null : (v) => setState(() {
                        q.level = v ?? q.level;
                        dirty = true;
                      }),
                ),
                DropdownButton<int>(
                  value: q.difficulty,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('سهل')),
                    DropdownMenuItem(value: 2, child: Text('متوسط')),
                    DropdownMenuItem(value: 3, child: Text('صعب')),
                  ],
                  onChanged: locked ? null : (v) => setState(() {
                        q.difficulty = v ?? q.difficulty;
                        dirty = true;
                      }),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('نسبة النجاح: ${q.passPercent}%'),
                  SizedBox(
                    width: 180,
                    child: Slider(
                      value: q.passPercent.toDouble(),
                      min: 30,
                      max: 80,
                      divisions: 10,
                      onChanged: locked ? null : (v) => setState(() {
                            q.passPercent = v.round();
                            dirty = true;
                          }),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          if (q.source == 'ai')
            const Padding(
              padding: EdgeInsets.all(6),
              child: Text(
                'أسئلة مقترحة بالذكاء الاصطناعي: تحقق من أنها مستندة إلى القصة فعلًا (المرجع يظهر تحت كل سؤال) '
                'وأن الجواب الصحيح سليم. أسئلة الصور تحتاج إلى إضافة الصور.',
                style: TextStyle(color: AppColors.student),
              ),
            ),
          if (questions.isEmpty)
            const EmptyState(icon: Icons.quiz, text: 'لا توجد أسئلة بعد. أضف سؤالًا بالزر في الأسفل.'),
          for (var i = 0; i < questions.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 8),
                    Chip(label: Text(questions[i].type.label)),
                    const SizedBox(width: 6),
                    Text(Ar.difficultyNames[questions[i].difficulty] ?? '', style: const TextStyle(color: AppColors.muted)),
                    if (questions[i].validate() != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('⚠ ${questions[i].validate()}', style: const TextStyle(color: AppColors.danger)),
                      ),
                    const Spacer(),
                    if (!locked) ...[
                      IconButton(icon: const Icon(Icons.arrow_upward), onPressed: () => _move(i, -1)),
                      IconButton(icon: const Icon(Icons.arrow_downward), onPressed: () => _move(i, 1)),
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _editQuestion(i)),
                      IconButton(
                          tooltip: 'إعادة توليد بالذكاء الاصطناعي',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: () => _regenerate(i)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                        onPressed: () async {
                          final ok = await confirm(context, 'حذف السؤال', 'حذف السؤال ${i + 1}؟', danger: true);
                          if (!ok) return;
                          setState(() {
                            questions.removeAt(i);
                            dirty = true;
                          });
                          await _save(silent: true);
                        },
                      ),
                    ],
                  ]),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (questions[i].imagePath != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LocalImage(questions[i].imagePath, width: 70, height: 70),
                        ),
                      ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(questions[i].prompt, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        if (questions[i].audioPath != null)
                          const Row(children: [Icon(Icons.volume_up, size: 18), Text(' سؤال مسجل بصوت الأستاذ')]),
                        for (var j = 0; j < questions[i].options.length; j++)
                          Text(
                            questions[i].type == QType.order
                                ? '${j + 1}. ${questions[i].options[j].label}'
                                : '${questions[i].options[j].isCorrect ? '✔' : '○'} ${questions[i].options[j].label}'
                                    '${questions[i].options[j].imagePath != null ? ' [صورة]' : ''}',
                            style: TextStyle(
                              color: questions[i].options[j].isCorrect && questions[i].type != QType.order
                                  ? AppColors.ok
                                  : null,
                            ),
                          ),
                        if (questions[i].type == QType.short)
                          Text('الكلمات المفتاحية: ${questions[i].keywords.isEmpty ? '—' : questions[i].keywords}',
                              style: const TextStyle(color: AppColors.muted)),
                        if (questions[i].sourceRef.isNotEmpty)
                          Text('المرجع في القصة: ${questions[i].sourceRef}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------- محرر سؤال واحد ----------------

class QuestionEditorScreen extends StatefulWidget {
  final Question question;
  final Story story;
  final int level;
  const QuestionEditorScreen({super.key, required this.question, required this.story, required this.level});

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late Question q;
  late TextEditingController prompt;
  late TextEditingController keywords;
  late TextEditingController sourceRef;
  final optionCtls = <TextEditingController>[];
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  bool recording = false;

  @override
  void initState() {
    super.initState();
    q = widget.question;
    prompt = TextEditingController(text: q.prompt);
    keywords = TextEditingController(text: q.keywords);
    sourceRef = TextEditingController(text: q.sourceRef);
    for (final o in q.options) {
      optionCtls.add(TextEditingController(text: o.label));
    }
  }

  @override
  void dispose() {
    recorder.dispose();
    player.dispose();
    super.dispose();
  }

  void _setType(QType t) {
    setState(() {
      q.type = t;
      if (t == QType.truefalse) {
        q.options = [AnswerOption(label: 'صح', isCorrect: true), AnswerOption(label: 'خطأ')];
      } else if (t == QType.short) {
        q.options = [];
      } else if (q.options.length < 2) {
        q.options = [AnswerOption(label: '', isCorrect: true), AnswerOption(label: '')];
      }
      if (t == QType.single || t == QType.image || t == QType.complete) {
        var seen = false;
        for (final o in q.options) {
          if (o.isCorrect && !seen) {
            seen = true;
          } else {
            o.isCorrect = false;
          }
        }
        if (!seen && q.options.isNotEmpty) q.options.first.isCorrect = true;
      }
      optionCtls
        ..clear()
        ..addAll(q.options.map((o) => TextEditingController(text: o.label)));
    });
  }

  Future<String?> _pickImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo), title: const Text('من معرض الصور'), onTap: () => Navigator.pop(c, 'gallery')),
          if (widget.story.pdfPath != null)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('صفحة من القصة'),
              onTap: () => Navigator.pop(c, 'pdf'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return null;
    if (choice == 'gallery') {
      final f = await Pick.image();
      if (f == null) return null;
      return AppDb.I.saveBytes('images', f.ext.isEmpty ? 'png' : f.ext, f.bytes);
    }
    final pdf = await PdfTools.readStoryPdf(widget.story.pdfPath);
    if (pdf == null || !mounted) return null;
    final png = await PdfPagePicker.pick(context, pdf);
    if (png == null) return null;
    return AppDb.I.saveBytes('images', 'png', png);
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      final path = await recorder.stop();
      setState(() => recording = false);
      if (path != null) {
        final name = File(path).uri.pathSegments.last;
        setState(() => q.audioPath = 'audio/$name');
      }
      return;
    }
    if (!await recorder.hasPermission()) {
      if (mounted) toast(context, 'يجب السماح للتطبيق باستعمال الميكروفون', error: true);
      return;
    }
    final rel = 'audio/q_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(), path: AppDb.I.abs(rel));
    setState(() => recording = true);
  }

  void _save() {
    q.prompt = prompt.text.trim();
    q.keywords = keywords.text.trim();
    q.sourceRef = sourceRef.text.trim();
    for (var i = 0; i < q.options.length && i < optionCtls.length; i++) {
      q.options[i].label = optionCtls[i].text.trim();
    }
    final err = q.validate();
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    Navigator.pop(context, q);
  }

  @override
  Widget build(BuildContext context) {
    final singleCorrect = q.type == QType.single || q.type == QType.image || q.type == QType.complete || q.type == QType.truefalse;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل السؤال'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        DropdownButtonFormField<QType>(
          initialValue: q.type,
          decoration: const InputDecoration(labelText: 'نوع السؤال'),
          items: [for (final t in QType.values) DropdownMenuItem(value: t, child: Text(t.label))],
          onChanged: (t) {
            if (t != null) _setType(t);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: prompt,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'نص السؤال',
            hintText: q.type == QType.complete ? 'اكتب الجملة واترك فراغًا: ذهب الأرنب إلى ...' : null,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (q.imagePath != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LocalImage(q.imagePath, width: 90, height: 90)),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await _pickImage();
              if (p != null) setState(() => q.imagePath = p);
            },
            icon: const Icon(Icons.image),
            label: Text(q.imagePath == null ? 'إضافة صورة للسؤال' : 'تغيير الصورة'),
          ),
          if (q.imagePath != null)
            TextButton(onPressed: () => setState(() => q.imagePath = null), child: const Text('إزالة الصورة')),
          OutlinedButton.icon(
            onPressed: _toggleRecord,
            icon: Icon(recording ? Icons.stop : Icons.mic, color: recording ? AppColors.danger : null),
            label: Text(recording ? 'إيقاف التسجيل' : (q.audioPath == null ? 'تسجيل السؤال بصوتي' : 'إعادة التسجيل')),
          ),
          if (q.audioPath != null && !recording) ...[
            IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => player.play(DeviceFileSource(AppDb.I.abs(q.audioPath!)))),
            TextButton(onPressed: () => setState(() => q.audioPath = null), child: const Text('حذف التسجيل')),
          ],
        ]),
        const Text('التسجيل الصوتي مفيد لتلاميذ المستوى الأول الذين لا يقرؤون السؤال بعد.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        if (q.type == QType.short) ...[
          const SectionTitle('التصحيح'),
          TextField(
            controller: keywords,
            decoration: const InputDecoration(
              labelText: 'كلمات مفتاحية للجواب الصحيح (مفصولة بفاصلة)',
              helperText: 'يُقبل الجواب إذا احتوى إحداها. وإلا يظهر لك في «تصحيح الأجوبة» لتقرر.',
            ),
          ),
        ] else ...[
          SectionTitle(q.type == QType.order
              ? 'العناصر بالترتيب الصحيح (ستُعرض للتلميذ مختلطة)'
              : (singleCorrect ? 'الاختيارات (حدد الجواب الصحيح)' : 'الاختيارات (حدد كل الأجوبة الصحيحة)')),
          for (var i = 0; i < q.options.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  if (q.type == QType.order)
                    CircleAvatar(radius: 14, child: Text('${i + 1}'))
                  else if (singleCorrect)
                    IconButton(
                      tooltip: 'الجواب الصحيح',
                      icon: Icon(
                        q.options[i].isCorrect ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: q.options[i].isCorrect ? AppColors.ok : null,
                      ),
                      onPressed: () => setState(() {
                        for (var k = 0; k < q.options.length; k++) {
                          q.options[k].isCorrect = k == i;
                        }
                      }),
                    )
                  else
                    Checkbox(
                      value: q.options[i].isCorrect,
                      onChanged: (v) => setState(() => q.options[i].isCorrect = v ?? false),
                    ),
                  if (q.options[i].imagePath != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LocalImage(q.options[i].imagePath, width: 56, height: 56)),
                    ),
                  Expanded(
                    child: TextField(
                      controller: optionCtls[i],
                      enabled: q.type != QType.truefalse,
                      decoration: InputDecoration(
                        hintText: q.type == QType.image ? 'وصف قصير (اختياري مع الصورة)' : 'الاختيار ${i + 1}',
                      ),
                    ),
                  ),
                  if (q.type == QType.image || q.type == QType.order || q.type == QType.single || q.type == QType.multi)
                    IconButton(
                      tooltip: 'صورة',
                      icon: const Icon(Icons.add_photo_alternate),
                      onPressed: () async {
                        final p = await _pickImage();
                        if (p != null) setState(() => q.options[i].imagePath = p);
                      },
                    ),
                  if (q.type == QType.order) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                                final o = q.options.removeAt(i);
                                q.options.insert(i - 1, o);
                                final c = optionCtls.removeAt(i);
                                optionCtls.insert(i - 1, c);
                              }),
                    ),
                  ],
                  if (q.type != QType.truefalse)
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.danger),
                      onPressed: q.options.length <= 2
                          ? null
                          : () => setState(() {
                                q.options.removeAt(i);
                                optionCtls.removeAt(i);
                              }),
                    ),
                ]),
              ),
            ),
          if (q.type != QType.truefalse && q.options.length < 8)
            TextButton.icon(
              onPressed: () => setState(() {
                q.options.add(AnswerOption(label: ''));
                optionCtls.add(TextEditingController());
              }),
              icon: const Icon(Icons.add),
              label: const Text('إضافة اختيار'),
            ),
        ],
        const SectionTitle('معلومات تربوية'),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('سهل')),
              ButtonSegment(value: 2, label: Text('متوسط')),
              ButtonSegment(value: 3, label: Text('صعب')),
            ],
            selected: {q.difficulty},
            onSelectionChanged: (s) => setState(() => q.difficulty = s.first),
          ),
          DropdownButton<int>(
            value: q.points,
            items: const [
              DropdownMenuItem(value: 1, child: Text('نقطة واحدة')),
              DropdownMenuItem(value: 2, child: Text('نقطتان')),
              DropdownMenuItem(value: 3, child: Text('3 نقط')),
            ],
            onChanged: (v) => setState(() => q.points = v ?? 1),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: sourceRef,
          decoration: const InputDecoration(labelText: 'المرجع في القصة (الصفحة أو الفقرة)'),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('حفظ السؤال')),
      ]),
    );
  }
}
