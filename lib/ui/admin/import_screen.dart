import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/people_repo.dart';
import '../../data/school_repo.dart';
import '../../services/massar_parser.dart';
import '../../services/pick.dart';
import '../widgets/common.dart';

/// استيراد لائحة التلاميذ المحمّلة من منظومة مسار، مع معاينة وتصحيح قبل الحفظ.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  MassarFile? file;
  String fileName = '';
  Map<String, ImportStatus> statuses = {};
  final selected = <String>{};
  bool archiveMissing = true;
  String currentYear = '';

  Future<void> _pick() async {
    final f = await Pick.excel();
    if (f == null || !mounted) return;
    final parsed = await withProgress(context, 'قراءة الملف وتحليل بنيته...', () => _parse(f.bytes));
    if (parsed == null || !mounted) return;
    final y = await SchoolRepo.currentYear();
    final st = await PeopleRepo.previewStatuses(parsed);
    setState(() {
      file = parsed;
      fileName = f.name;
      statuses = st;
      currentYear = y.label;
      selected
        ..clear()
        ..addAll(parsed.classes.where((c) => c.isPrimary && c.students.isNotEmpty).map((c) => c.code));
    });
  }

  /// التحليل في Isolate منفصل (دالة ساكنة حتى لا يُلتقط كائن الواجهة).
  static Future<MassarFile> _parse(Uint8List bytes) => Isolate.run(() => MassarParser.parseBytes(bytes));

  Future<void> _refreshStatuses() async {
    final f = file;
    if (f == null) return;
    final st = await PeopleRepo.previewStatuses(f);
    if (mounted) setState(() => statuses = st);
  }

  Future<void> _edit(MassarStudent s) async {
    final code = TextEditingController(text: s.code);
    final last = TextEditingController(text: s.lastName);
    final first = TextEditingController(text: s.firstName);
    var gender = s.gender;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('تصحيح السطر ${s.row}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز مسار')),
              const SizedBox(height: 8),
              TextField(controller: last, decoration: const InputDecoration(labelText: 'النسب')),
              const SizedBox(height: 8),
              TextField(controller: first, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: gender,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('غير محدد')),
                  DropdownMenuItem(value: 'ذكر', child: Text('ذكر')),
                  DropdownMenuItem(value: 'أنثى', child: Text('أنثى')),
                ],
                onChanged: (v) => setD(() => gender = v ?? ''),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ التصحيح')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      s.code = code.text;
      s.lastName = last.text;
      s.firstName = first.text;
      s.gender = gender;
      s.revalidate();
    });
    await _refreshStatuses();
  }

  Future<void> _import() async {
    final f = file;
    if (f == null || selected.isEmpty) return;
    final yearLabel = f.meta.year.isNotEmpty ? f.meta.year : currentYear;
    final newYear = yearLabel != currentYear;
    final ok = await confirm(
      context,
      'تأكيد الاستيراد',
      'سيتم استيراد ${selected.length} قسم(ا).'
          '${newYear ? '\n\nتنبيه: الملف يخص الموسم $yearLabel وهو مختلف عن الموسم الحالي ($currentYear). '
              'سيُعتمد $yearLabel موسمًا حاليًا، وتبقى نتائج المواسم السابقة محفوظة.' : ''}'
          '${archiveMissing ? '\n\nالتلاميذ غير الموجودين في الملف داخل الأقسام المحددة سيُؤرشفون (دون حذف نتائجهم).' : ''}',
      ok: 'استيراد',
    );
    if (!ok || !mounted) return;
    final res = await withProgress(
      context,
      'جارٍ الاستيراد...',
      () => PeopleRepo.applyImport(f,
          selectedClassCodes: selected, yearLabel: yearLabel, archiveMissing: archiveMissing, actor: Session.I.actor),
    );
    if (res == null || !mounted) return;
    await info(
      context,
      'تم الاستيراد بنجاح',
      Text('أقسام جديدة: ${res.classesCreated}\n'
          'تلاميذ جدد: ${res.added}\n'
          'تلاميذ محدَّثون: ${res.updated}\n'
          'تلاميذ منقولون إلى قسم آخر: ${res.moved}\n'
          'دون تغيير: ${res.unchanged}\n'
          'مؤرشفون: ${res.archived}\n'
          'سطور متجاهلة (أخطاء/تكرار): ${res.skipped}\n\n'
          'الخطوة التالية: من «الأقسام والتلاميذ» حدد كلمة سر لكل قسم، وولّد كلمات سر التلاميذ واطبع بطاقاتهم.'),
    );
    setState(() {
      file = null;
      statuses = {};
    });
  }

  Map<ImportStatus, int> _counts(MassarClass c) {
    final m = <ImportStatus, int>{};
    for (final s in c.students) {
      final st = s.blocking ? ImportStatus.error : (statuses[s.code] ?? ImportStatus.added);
      m[st] = (m[st] ?? 0) + 1;
    }
    return m;
  }

  static const _labels = {
    ImportStatus.added: 'جديد',
    ImportStatus.updated: 'محدَّث',
    ImportStatus.moved: 'منقول',
    ImportStatus.unchanged: 'دون تغيير',
    ImportStatus.error: 'خطأ',
  };

  static const _colors = {
    ImportStatus.added: AppColors.ok,
    ImportStatus.updated: AppColors.admin,
    ImportStatus.moved: AppColors.student,
    ImportStatus.unchanged: AppColors.muted,
    ImportStatus.error: AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final f = file;
    if (f == null) {
      return EmptyState(
        icon: Icons.upload_file,
        text: 'حمّل لائحة التلاميذ من منظومة مسار (ListEleve_....xlsx) ثم اخترها هنا.\n'
            'سيتعرف التطبيق تلقائيًا على الأقسام والتلاميذ، ويمكنك المعاينة والتصحيح قبل الحفظ.\n'
            'لا تُستورد تواريخ الازدياد ولا أماكنه.',
        action: ElevatedButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف مسار')),
      );
    }
    final total = f.classes.where((c) => selected.contains(c.code)).fold<int>(0, (s, c) => s + c.students.length);
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الملف: $fileName', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('المؤسسة: ${f.meta.school}'),
                Text('الأكاديمية: ${f.meta.academy} — المديرية: ${f.meta.directorate} — الجماعة: ${f.meta.commune}'),
                Text('الموسم الدراسي: ${f.meta.year.isEmpty ? 'غير محدد' : f.meta.year}'
                    '${f.meta.year.isNotEmpty && f.meta.year != currentYear ? '  (الموسم الحالي في التطبيق: $currentYear)' : ''}'),
                Text('عدد الأقسام: ${f.classes.length} — عدد التلاميذ: ${f.studentCount}'),
                for (final w in f.warnings) Text('⚠ $w', style: const TextStyle(color: AppColors.student)),
              ]),
            ),
          ),
          SwitchListTile(
            value: archiveMissing,
            onChanged: (v) => setState(() => archiveMissing = v),
            title: const Text('أرشفة التلاميذ غير الموجودين في الملف (داخل الأقسام المحددة)'),
            subtitle: const Text('مفيد عند تحديث اللائحة بعد مغادرة تلاميذ. لا تُحذف نتائجهم.'),
          ),
          Row(children: [
            TextButton(
                onPressed: () => setState(() => selected.addAll(f.classes.map((c) => c.code))),
                child: const Text('تحديد الكل')),
            TextButton(onPressed: () => setState(selected.clear), child: const Text('إلغاء التحديد')),
            const Spacer(),
            Text('محدد: ${selected.length} قسم، $total تلميذ'),
          ]),
          for (final c in f.classes)
            Card(
              child: ExpansionTile(
                leading: Checkbox(
                  value: selected.contains(c.code),
                  onChanged: (v) => setState(() => v == true ? selected.add(c.code) : selected.remove(c.code)),
                ),
                title: Text('${c.code} — ${c.levelName.isNotEmpty ? c.levelName : Ar.levelName(c.level)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Wrap(spacing: 6, children: [
                  Text('${c.students.length} تلميذ'),
                  if (c.isPreschool) const Text('(تعليم أولي)', style: TextStyle(color: AppColors.student)),
                  for (final e in _counts(c).entries)
                    Text('${_labels[e.key]}: ${e.value}', style: TextStyle(color: _colors[e.key])),
                  for (final i in c.issues) Text('⚠ $i', style: const TextStyle(color: AppColors.danger)),
                ]),
                children: [
                  for (final s in c.students)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        s.issues.isEmpty ? Icons.check_circle : Icons.error,
                        color: s.issues.isEmpty
                            ? _colors[statuses[s.code] ?? ImportStatus.added]
                            : (s.blocking ? AppColors.danger : AppColors.student),
                      ),
                      title: Text('${s.lastName} ${s.firstName}'),
                      subtitle: Text([
                        s.code,
                        if (s.gender.isNotEmpty) s.gender,
                        _labels[s.blocking ? ImportStatus.error : (statuses[s.code] ?? ImportStatus.added)]!,
                        ...s.issues,
                      ].join(' • ')),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(s)),
                    ),
                ],
              ),
            ),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text('ملف آخر')),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: selected.isEmpty ? null : _import,
                icon: const Icon(Icons.download_done),
                label: Text('استيراد ${selected.length} قسم(ا)'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
