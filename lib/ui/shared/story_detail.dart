import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../services/ai_client.dart';
import '../../services/reports.dart';
import '../../services/scoring.dart';
import '../widgets/common.dart';
import 'pdf_pages.dart';
import 'quiz_editor.dart';
import 'stories_screen.dart';

class StoryDetailScreen extends StatefulWidget {
  final int storyId;
  final SchoolClass? cls;
  const StoryDetailScreen({super.key, required this.storyId, required this.cls});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  Story? story;
  List<Quiz> quizzes = [];
  List<SchoolClass> classes = [];
  Set<int> assigned = {};
  bool loading = true;

  bool get isAdmin => Session.I.isAdmin;
  SchoolClass? get myClass => widget.cls;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await LibraryRepo.storyById(widget.storyId);
    final q = await LibraryRepo.quizzesForStory(widget.storyId);
    final cl = await PeopleRepo.classes();
    final all = await LibraryRepo.stories();
    final info = all.where((e) => e.story.id == widget.storyId).toList();
    if (!mounted) return;
    setState(() {
      story = s;
      quizzes = q;
      classes = cl;
      assigned = info.isEmpty ? {} : info.first.assignedClassIds.toSet();
      loading = false;
    });
  }

  bool get canEdit => isAdmin || (story?.ownerClassId != null && story?.ownerClassId == myClass?.id);
  bool get canManageQuizzes =>
      isAdmin || (myClass != null && (assigned.contains(myClass!.id) || story?.ownerClassId == myClass!.id));

  Future<void> _toggleAssign(SchoolClass c, bool value) async {
    if (!value && !isAdmin && c.id != myClass?.id) {
      toast(context, 'يمكنك إلغاء الإسناد من قسمك فقط.', error: true);
      return;
    }
    if (value) {
      await LibraryRepo.assign(widget.storyId, c.id, Session.I.actor);
    } else {
      await LibraryRepo.unassign(widget.storyId, c.id);
    }
    _load();
  }

  Future<void> _newManualQuiz() async {
    final level = myClass != null && Ar.isPrimary(myClass!.level) ? myClass!.level : (story!.levels.isNotEmpty ? story!.levels.first : 1);
    final id = await LibraryRepo.createQuiz(
      storyId: widget.storyId,
      level: level,
      difficulty: story!.difficulty,
      title: 'اختبار ${story!.title}',
      actor: Session.I.actor,
    );
    await _openEditor(id);
  }

  Future<void> _openEditor(int quizId) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuizEditorScreen(quizId: quizId, story: story!)));
    _load();
  }

  Future<void> _aiQuiz() async {
    final s = story!;
    final pdf = await PdfTools.readStoryPdf(s.pdfPath);
    if (!mounted) return;
    if (pdf == null) {
      toast(context, 'أضف ملف PDF للقصة أولًا (تعديل القصة) لكي يولّد الذكاء الاصطناعي الأسئلة.', error: true);
      return;
    }
    if (!await AiClient.isConfigured()) {
      if (mounted) {
        toast(context, 'خدمة الذكاء الاصطناعي غير مُعدّة بعد. يضبطها المدير من الإعدادات. يمكنك إنشاء اختبار يدوي.', error: true);
      }
      return;
    }
    if (!mounted) return;
    final opts = await showDialog<_AiOptions>(
      context: context,
      builder: (_) => _AiOptionsDialog(
        initialLevel: myClass != null && Ar.isPrimary(myClass!.level)
            ? myClass!.level
            : (s.levels.isNotEmpty ? s.levels.first : 3),
        initialDifficulty: s.difficulty,
      ),
    );
    if (opts == null || !mounted) return;
    final questions = await withProgress(
      context,
      'يحلل الذكاء الاصطناعي القصة ويقترح الأسئلة... (قد يستغرق دقيقة)',
      () => AiClient.generateQuiz(
        story: s,
        pdf: pdf,
        level: opts.level,
        difficulty: opts.difficulty,
        count: opts.count,
        types: opts.types,
      ),
    );
    if (questions == null || !mounted) return;
    final id = await LibraryRepo.createQuiz(
      storyId: s.id,
      level: opts.level,
      difficulty: opts.difficulty,
      title: 'اختبار ${s.title} — ${Ar.levelName(opts.level)}',
      source: 'ai',
      actor: Session.I.actor,
    );
    await LibraryRepo.saveQuestions(id, questions);
    if (!mounted) return;
    toast(context, 'تم اقتراح ${questions.length} سؤال. راجعها وعدّلها قبل النشر.');
    await _openEditor(id);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف القصة', 'هل تريد حذف القصة «${story!.title}» واختباراتها نهائيًا؟', danger: true, ok: 'حذف');
    if (!ok) return;
    final err = await LibraryRepo.deleteStory(widget.storyId, Session.I.actor);
    if (!mounted) return;
    if (err != null) {
      toast(context, err, error: true);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _quizAction(Quiz q, String action) async {
    switch (action) {
      case 'edit':
        await _openEditor(q.id);
        break;
      case 'unpublish':
        await LibraryRepo.setQuizStatus(q.id, 'draft', Session.I.actor);
        break;
      case 'duplicate':
        final id = await LibraryRepo.duplicateQuiz(q.id, Session.I.actor);
        await _openEditor(id);
        break;
      case 'delete':
        final has = await LibraryRepo.attemptsForQuiz(q.id) > 0;
        if (!mounted) return;
        final ok = await confirm(
            context,
            has ? 'أرشفة الاختبار' : 'حذف الاختبار',
            has
                ? 'لهذا الاختبار نتائج تلاميذ، لذلك سيُؤرشف (يختفي من التلاميذ وتبقى النتائج محفوظة).'
                : 'حذف هذا الاختبار نهائيًا؟',
            danger: true);
        if (ok) await LibraryRepo.deleteOrArchiveQuiz(q.id, Session.I.actor);
        break;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = story;
    if (loading || s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isAdmin ? AppColors.admin : AppColors.teacher,
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: 'ملصق QR',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () async {
              final b = await Reports.qrLabels([s]);
              await Reports.printOrShare(b, 'QR_${s.title}');
            },
          ),
          if (canEdit)
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => StoryFormScreen(cls: myClass, story: s)));
                _load();
              },
            ),
          if (canEdit) IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StoryCover(coverPath: s.coverPath, title: s.title, width: 150, height: 205),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              if (s.author.isNotEmpty) Text(s.author, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              Text('المستويات: ${s.levels.map(Ar.levelName).join('، ')}'),
              Text('الصعوبة: ${Ar.difficultyNames[s.difficulty] ?? ''}'),
              Text(s.hasPaper ? 'موجودة ورقيًا في المكتبة الصفية' : 'غير موجودة ورقيًا'),
              Text(s.pdfPath != null ? 'ملف PDF: متوفر' : 'ملف PDF: غير متوفر',
                  style: TextStyle(color: s.pdfPath != null ? AppColors.ok : AppColors.danger)),
              if (s.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.summary)),
              const SizedBox(height: 8),
              if (s.pdfPath != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final pdf = await PdfTools.readStoryPdf(s.pdfPath);
                    if (pdf != null && context.mounted) {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => PdfPagePicker(pdf: pdf, pickMode: false)));
                    }
                  },
                  icon: const Icon(Icons.chrome_reader_mode),
                  label: const Text('تصفح القصة (للأستاذ)'),
                ),
            ]),
          ),
        ]),
        const SectionTitle('الأقسام المسندة إليها القصة'),
        Card(
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in classes)
              FilterChip(
                label: Text(c.code),
                selected: assigned.contains(c.id),
                onSelected: (v) => _toggleAssign(c, v),
              ),
          ]),
        ),
        const Text('الإسناد لعدة أقسام لا يمنح أي قسم حق الاطلاع على تلاميذ أو نتائج الأقسام الأخرى.',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        SectionTitle(
          'الاختبارات',
          trailing: canManageQuizzes
              ? Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: _newManualQuiz, icon: const Icon(Icons.edit_note), label: const Text('يدوي')),
                  ElevatedButton.icon(
                      onPressed: _aiQuiz, icon: const Icon(Icons.auto_awesome), label: const Text('توليد بالذكاء الاصطناعي')),
                ])
              : null,
        ),
        if (!canManageQuizzes)
          const Text('أسند القصة لقسمك أولًا لكي تنشئ لها اختبارًا.', style: TextStyle(color: AppColors.muted)),
        if (quizzes.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('لا توجد اختبارات لهذه القصة بعد.')))
        else
          for (final q in quizzes)
            Card(
              child: ListTile(
                leading: Icon(q.published ? Icons.check_circle : Icons.drafts,
                    color: q.published ? AppColors.ok : AppColors.muted),
                title: Text(q.title.isEmpty ? 'اختبار' : q.title),
                subtitle: Text('${Ar.levelName(q.level)} • ${Ar.difficultyNames[q.difficulty]} • '
                    '${q.questionCount} سؤال • ${q.published ? 'منشور للتلاميذ' : 'مسودة'}'
                    '${q.source == 'ai' ? ' • مقترح بالذكاء الاصطناعي' : ''}'),
                onTap: canManageQuizzes ? () => _openEditor(q.id) : null,
                trailing: canManageQuizzes
                    ? PopupMenuButton<String>(
                        onSelected: (a) => _quizAction(q, a),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('فتح / مراجعة')),
                          if (q.published) const PopupMenuItem(value: 'unpublish', child: Text('إيقاف النشر')),
                          const PopupMenuItem(value: 'duplicate', child: Text('نسخ كمسودة جديدة')),
                          const PopupMenuItem(value: 'delete', child: Text('حذف / أرشفة')),
                        ],
                      )
                    : null,
              ),
            ),
      ]),
    );
  }
}

class _AiOptions {
  final int level;
  final int difficulty;
  final int count;
  final List<QType> types;
  _AiOptions(this.level, this.difficulty, this.count, this.types);
}

class _AiOptionsDialog extends StatefulWidget {
  final int initialLevel;
  final int initialDifficulty;
  const _AiOptionsDialog({required this.initialLevel, required this.initialDifficulty});

  @override
  State<_AiOptionsDialog> createState() => _AiOptionsDialogState();
}

class _AiOptionsDialogState extends State<_AiOptionsDialog> {
  late int level = widget.initialLevel;
  late int difficulty = widget.initialDifficulty;
  late int count = Grader.suggestedQuestionCount(widget.initialLevel);
  final types = <QType>{QType.single, QType.truefalse, QType.order, QType.short};

  @override
  void initState() {
    super.initState();
    if (level <= 2) {
      types
        ..remove(QType.short)
        ..add(QType.image);
    } else if (level >= 5) {
      types.add(QType.multi);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('توليد اختبار بالذكاء الاصطناعي'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('يُرسل ملف القصة فقط (دون أي معلومة عن التلاميذ). ستراجع الأسئلة قبل نشرها.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: level,
            decoration: const InputDecoration(labelText: 'المستوى الدراسي'),
            items: [for (var l = 1; l <= 6; l++) DropdownMenuItem(value: l, child: Text(Ar.levelName(l)))],
            onChanged: (v) => setState(() {
              level = v ?? level;
              count = Grader.suggestedQuestionCount(level);
            }),
          ),
          const SizedBox(height: 10),
          const Text('الصعوبة'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('سهل')),
              ButtonSegment(value: 2, label: Text('متوسط')),
              ButtonSegment(value: 3, label: Text('صعب')),
            ],
            selected: {difficulty},
            onSelectionChanged: (s) => setState(() => difficulty = s.first),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Text('عدد الأسئلة: '),
            IconButton(onPressed: count > 3 ? () => setState(() => count--) : null, icon: const Icon(Icons.remove)),
            Text('$count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(onPressed: count < 15 ? () => setState(() => count++) : null, icon: const Icon(Icons.add)),
          ]),
          const Text('أنواع الأسئلة'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in QType.values)
              FilterChip(
                label: Text(t.label),
                selected: types.contains(t),
                onSelected: (v) => setState(() => v ? types.add(t) : types.remove(t)),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: types.isEmpty ? null : () => Navigator.pop(context, _AiOptions(level, difficulty, count, types.toList())),
          child: const Text('توليد'),
        ),
      ],
    );
  }
}
