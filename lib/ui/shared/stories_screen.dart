import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/security.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/library_repo.dart';
import '../../data/models.dart';
import '../../services/pick.dart';
import '../../services/reports.dart';
import '../widgets/common.dart';
import 'pdf_pages.dart';
import 'story_detail.dart';

/// مكتبة القصص: كل قصة تُخزن مرة واحدة وتُسند لقسم أو عدة أقسام.
class StoriesScreen extends StatefulWidget {
  final SchoolClass? cls; // null = المدير
  const StoriesScreen({super.key, required this.cls});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  List<StoryInfo>? stories;
  bool onlyMine = true;
  String search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.cls;
    final s = await LibraryRepo.stories(classId: c?.id, onlyAssigned: c != null && onlyMine, search: search);
    if (mounted) setState(() => stories = s);
  }

  Future<void> _add() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => StoryFormScreen(cls: widget.cls)));
    await _load();
    if (id != null && mounted) _open(id);
  }

  Future<void> _open(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StoryDetailScreen(storyId: id, cls: widget.cls)));
    _load();
  }

  Future<void> _printQr() async {
    final list = stories ?? [];
    if (list.isEmpty) return;
    final bytes = await withProgress(context, 'إعداد ملصقات QR...', () => Reports.qrLabels(list.map((e) => e.story).toList()));
    if (bytes != null) await Reports.printOrShare(bytes, 'ملصقات_QR');
  }

  @override
  Widget build(BuildContext context) {
    final list = stories;
    final c = widget.cls;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('إضافة قصة'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالعنوان أو المؤلف'),
                onChanged: (v) {
                  search = v;
                  _load();
                },
              ),
            ),
            if (c != null)
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text('قصص قسمي ${c.code}')),
                  const ButtonSegment(value: false, label: Text('كل قصص المؤسسة')),
                ],
                selected: {onlyMine},
                onSelectionChanged: (s) {
                  onlyMine = s.first;
                  _load();
                },
              ),
            OutlinedButton.icon(onPressed: _printQr, icon: const Icon(Icons.qr_code_2), label: const Text('طباعة ملصقات QR')),
          ]),
        ),
        Expanded(
          child: list == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.menu_book,
                      text: c != null && onlyMine
                          ? 'لا توجد قصص مسندة لقسمك بعد. أضف قصة أو اختر من «كل قصص المؤسسة».'
                          : 'لا توجد قصص بعد. أضف أول قصة (صورة الغلاف + ملف PDF).',
                    )
                  : GridView.extent(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.58,
                      children: [
                        for (final s in list)
                          InkWell(
                            onTap: () => _open(s.story.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: Stack(fit: StackFit.expand, children: [
                                  StoryCover(coverPath: s.story.coverPath, title: s.story.title, width: 190, height: 250),
                                  if (c != null && s.assignedClassIds.contains(c.id))
                                    const Positioned(
                                      top: 6,
                                      left: 6,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: AppColors.ok,
                                        child: Icon(Icons.check, size: 18, color: Colors.white),
                                      ),
                                    ),
                                ]),
                              ),
                              const SizedBox(height: 4),
                              Text(s.story.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                '${s.story.levels.map(Ar.levelShort).join('، ')} • اختبارات منشورة: ${s.publishedCount}',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ]),
                          ),
                      ],
                    ),
        ),
      ]),
    );
  }
}

/// إضافة قصة أو تعديلها: صورة الغلاف + ملف PDF + البيانات.
class StoryFormScreen extends StatefulWidget {
  final SchoolClass? cls;
  final Story? story;
  const StoryFormScreen({super.key, required this.cls, this.story});

  @override
  State<StoryFormScreen> createState() => _StoryFormScreenState();
}

class _StoryFormScreenState extends State<StoryFormScreen> {
  final title = TextEditingController();
  final author = TextEditingController();
  final summary = TextEditingController();
  String language = 'ar';
  final levels = <int>{};
  int difficulty = 2;
  bool hasPaper = true;
  Uint8List? cover;
  String coverExt = 'png';
  Uint8List? pdf;
  String pdfName = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.story;
    if (s != null) {
      title.text = s.title;
      author.text = s.author;
      summary.text = s.summary;
      language = s.language;
      levels.addAll(s.levels);
      difficulty = s.difficulty;
      hasPaper = s.hasPaper;
    } else if (widget.cls != null && Ar.isPrimary(widget.cls!.level)) {
      levels.add(widget.cls!.level);
    }
  }

  Future<void> _pickPdf() async {
    final f = await Pick.pdf();
    if (f == null || !mounted) return;
    final hash = Security.sha256Hex(f.bytes);
    final existing = await LibraryRepo.storyByPdfHash(hash);
    if (!mounted) return;
    if (existing != null && existing.id != widget.story?.id) {
      final c = widget.cls;
      final ok = await confirm(
        context,
        'القصة موجودة مسبقًا',
        'هذا الملف مسجل من قبل باسم «${existing.title}». لا داعي لتخزينه مرتين.'
            '${c != null ? '\nهل تريد إسناد هذه القصة لقسمك ${c.code}؟' : '\nهل تريد فتحها؟'}',
        ok: c != null ? 'إسناد لقسمي' : 'فتح القصة',
      );
      if (!ok || !mounted) return;
      if (c != null) await LibraryRepo.assign(existing.id, c.id, Session.I.actor);
      if (mounted) Navigator.pop(context, existing.id);
      return;
    }
    setState(() {
      pdf = f.bytes;
      pdfName = f.name;
      if (title.text.trim().isEmpty) title.text = f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    });
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      toast(context, 'عنوان القصة إلزامي', error: true);
      return;
    }
    if (levels.isEmpty) {
      toast(context, 'اختر مستوى واحدًا على الأقل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      var coverBytes = cover;
      var ext = coverExt;
      // غلاف افتراضي من الصفحة الأولى إن لم تُضف صورة
      if (coverBytes == null && pdf != null && widget.story?.coverPath == null) {
        coverBytes = await PdfTools.renderPage(pdf!, 0, dpi: 60);
        ext = 'png';
      }
      final s = widget.story;
      if (s == null) {
        final c = widget.cls;
        final id = await LibraryRepo.createStory(
          title: title.text,
          author: author.text,
          language: language,
          levels: levels.toList()..sort(),
          difficulty: difficulty,
          summary: summary.text.trim(),
          hasPaper: hasPaper,
          pdfBytes: pdf,
          coverBytes: coverBytes,
          coverExt: ext,
          ownerClassId: c?.id,
          assignToClassIds: c != null ? [c.id] : const [],
          actor: Session.I.actor,
        );
        if (mounted) Navigator.pop(context, id);
      } else {
        s
          ..title = title.text
          ..author = author.text
          ..language = language
          ..levels = (levels.toList()..sort())
          ..difficulty = difficulty
          ..summary = summary.text.trim()
          ..hasPaper = hasPaper;
        await LibraryRepo.updateStory(s, newPdfBytes: pdf, newCoverBytes: coverBytes, coverExt: ext);
        if (mounted) Navigator.pop(context, s.id);
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.story != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'تعديل القصة' : 'إضافة قصة')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  cover != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(cover!, width: 140, height: 190, fit: BoxFit.cover))
                      : StoryCover(
                          coverPath: widget.story?.coverPath,
                          title: title.text.isEmpty ? 'الغلاف' : title.text,
                          width: 140,
                          height: 190),
                  TextButton.icon(
                    onPressed: () async {
                      final f = await Pick.image();
                      if (f != null) {
                        setState(() {
                          cover = f.bytes;
                          coverExt = f.ext.isEmpty ? 'png' : f.ext;
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('صورة الغلاف'),
                  ),
                ]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    OutlinedButton.icon(
                      onPressed: _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(pdf != null
                          ? 'الملف: $pdfName'
                          : (editing && widget.story!.pdfPath != null ? 'استبدال ملف PDF' : 'اختيار ملف القصة PDF')),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 8),
                      child: Text('ملف PDF لا يراه التلاميذ: يُستعمل لتوليد الأسئلة ومراجعتها فقط.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'عنوان القصة *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: author, decoration: const InputDecoration(labelText: 'المؤلف / السلسلة')),
                  ]),
                ),
              ]),
              const SectionTitle('المستويات المناسبة'),
              Wrap(spacing: 8, children: [
                for (var l = 1; l <= 6; l++)
                  FilterChip(
                    label: Text(Ar.levelName(l)),
                    selected: levels.contains(l),
                    onSelected: (v) => setState(() => v ? levels.add(l) : levels.remove(l)),
                  ),
              ]),
              const SectionTitle('معلومات إضافية'),
              Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                DropdownButton<String>(
                  value: language,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'fr', child: Text('الفرنسية')),
                    DropdownMenuItem(value: 'amz', child: Text('الأمازيغية')),
                  ],
                  onChanged: (v) => setState(() => language = v ?? 'ar'),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('سهلة')),
                    ButtonSegment(value: 2, label: Text('متوسطة')),
                    ButtonSegment(value: 3, label: Text('صعبة')),
                  ],
                  selected: {difficulty},
                  onSelectionChanged: (s) => setState(() => difficulty = s.first),
                ),
              ]),
              SwitchListTile(
                value: hasPaper,
                onChanged: (v) => setState(() => hasPaper = v),
                title: const Text('القصة موجودة ورقيًا في المكتبة الصفية'),
              ),
              TextField(
                controller: summary,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملخص قصير (اختياري، للأستاذ)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: busy ? null : _save,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(editing ? 'حفظ التعديلات' : 'حفظ القصة'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
