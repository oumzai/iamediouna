import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/school_repo.dart';
import '../../services/ai_client.dart';
import '../../services/backup_service.dart';
import '../../services/pick.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  School? school;
  final name = TextEditingController();
  final code = TextEditingController();
  final academy = TextEditingController();
  final directorate = TextEditingController();
  final commune = TextEditingController();
  final director = TextEditingController();
  final ministry = TextEditingController();
  final aiUrl = TextEditingController();
  final aiToken = TextEditingController();
  bool official = true;
  int idle = 3;
  int pinDigits = 4;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SchoolRepo.getSchool();
    ministry.text = await SchoolRepo.getSetting(SchoolRepo.kMinistry) ?? SchoolRepo.defaultMinistry;
    aiUrl.text = await SchoolRepo.getSetting(SchoolRepo.kAiUrl) ?? '';
    aiToken.text = await SchoolRepo.getSetting(SchoolRepo.kAiToken) ?? '';
    official = (await SchoolRepo.getSetting(SchoolRepo.kShowOfficialHeader)) != '0';
    idle = await SchoolRepo.getInt(SchoolRepo.kIdleMinutes, 3);
    pinDigits = await SchoolRepo.getInt(SchoolRepo.kPinDigits, 4);
    if (s != null) {
      name.text = s.name;
      code.text = s.code;
      academy.text = s.academy;
      directorate.text = s.directorate;
      commune.text = s.commune;
      director.text = s.directorName;
    }
    if (mounted) {
      setState(() {
        school = s;
        loading = false;
      });
    }
  }

  Future<void> _saveSchool() async {
    final s = school;
    if (s == null) return;
    if (name.text.trim().isEmpty) {
      toast(context, 'اسم المؤسسة إلزامي', error: true);
      return;
    }
    s
      ..name = name.text.trim()
      ..code = code.text.trim()
      ..academy = academy.text.trim()
      ..directorate = directorate.text.trim()
      ..commune = commune.text.trim()
      ..directorName = director.text.trim();
    await SchoolRepo.saveSchool(s);
    await SchoolRepo.setSetting(SchoolRepo.kMinistry, ministry.text.trim());
    await SchoolRepo.setSetting(SchoolRepo.kShowOfficialHeader, official ? '1' : '0');
    await SchoolRepo.audit(Session.I.actor, 'تعديل معلومات المؤسسة');
    if (mounted) toast(context, 'تم الحفظ');
  }

  Future<void> _logo() async {
    final f = await Pick.image();
    final s = school;
    if (f == null || s == null) return;
    final ext = f.ext.isEmpty ? 'png' : f.ext;
    await AppDb.I.deleteFile(s.logoPath);
    s.logoPath = await AppDb.I.saveBytes('logo', ext, f.bytes, name: 'logo_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await SchoolRepo.saveSchool(s);
    setState(() {});
  }

  Future<void> _saveAi() async {
    await SchoolRepo.setSetting(SchoolRepo.kAiUrl, aiUrl.text.trim());
    await SchoolRepo.setSetting(SchoolRepo.kAiToken, aiToken.text.trim());
    await SchoolRepo.audit(Session.I.actor, 'تعديل إعدادات الذكاء الاصطناعي');
    if (!mounted) return;
    final r = await withProgress(context, 'اختبار الاتصال...', () => AiClient.ping());
    if (r != null && mounted) toast(context, r);
  }

  Future<void> _changePassword() async {
    final old = await askPassword(context, 'كلمة السر الحالية');
    if (old == null || !mounted) return;
    if (!await SchoolRepo.verifyAdmin(old)) {
      if (mounted) toast(context, 'كلمة السر الحالية غير صحيحة', error: true);
      return;
    }
    if (!mounted) return;
    final n1 = await askPassword(context, 'كلمة السر الجديدة (6 أحرف على الأقل)');
    if (n1 == null || !mounted) return;
    final n2 = await askPassword(context, 'تأكيد كلمة السر الجديدة');
    if (n2 == null || !mounted) return;
    if (n1.length < 6 || n1 != n2) {
      toast(context, 'كلمة السر قصيرة أو غير متطابقة', error: true);
      return;
    }
    await SchoolRepo.changeAdminPassword(n1);
    await SchoolRepo.audit(Session.I.actor, 'تغيير كلمة سر المدير');
    if (mounted) toast(context, 'تم تغيير كلمة السر');
  }

  Future<void> _backup() async {
    final ctl1 = TextEditingController();
    final ctl2 = TextEditingController();
    var includePdfs = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('إنشاء نسخة احتياطية'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('تُشفَّر بيانات التلاميذ بكلمة سر تختارها. احتفظ بها: لا يمكن استعادة النسخة بدونها.'),
              const SizedBox(height: 10),
              TextField(controller: ctl1, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة سر النسخة')),
              const SizedBox(height: 8),
              TextField(controller: ctl2, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة السر')),
              CheckboxListTile(
                value: includePdfs,
                onChanged: (v) => setD(() => includePdfs = v ?? false),
                title: const Text('تضمين ملفات PDF للقصص (حجم أكبر)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (ctl1.text.length < 6 || ctl1.text != ctl2.text) {
      toast(context, 'كلمة السر قصيرة أو غير متطابقة', error: true);
      return;
    }
    final bytes = await withProgress<Uint8List>(
        context, 'إعداد النسخة الاحتياطية...', () => BackupService.create(ctl1.text, includePdfs: includePdfs));
    if (bytes == null || !mounted) return;
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final saved = await Pick.save('maktabati_backup_$stamp.maktabati', bytes);
    if (mounted) toast(context, saved ? 'تم حفظ النسخة الاحتياطية' : 'لم يتم الحفظ');
  }

  Future<void> _restore() async {
    final f = await Pick.backup();
    if (f == null || !mounted) return;
    final pw = await askPassword(context, 'كلمة سر النسخة الاحتياطية');
    if (pw == null || !mounted) return;
    final ok = await confirm(context, 'استعادة نسخة احتياطية',
        'ستُستبدل كل البيانات الحالية بمحتوى النسخة. تُحفظ نسخة أمان تلقائية من الوضع الحالي قبل ذلك. متابعة؟',
        danger: true, ok: 'استعادة');
    if (!ok || !mounted) return;
    final r = await withProgress(context, 'جارٍ الاستعادة...', () async {
      await BackupService.restore(f.bytes, pw);
      return true;
    });
    if (r == true && mounted) {
      await info(context, 'تمت الاستعادة', const Text('تمت استعادة البيانات بنجاح. سيعود التطبيق إلى الشاشة الرئيسية.'));
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _autoBackups() async {
    final files = await BackupService.autoBackups();
    if (!mounted) return;
    final f = await showDialog<File>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('النسخ التلقائية المحلية'),
        children: [
          if (files.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد نسخ بعد.')),
          for (final x in files)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text(p.basename(x.path))),
        ],
      ),
    );
    if (f == null || !mounted) return;
    final ok = await confirm(context, 'استرجاع نسخة تلقائية',
        'سترجع قاعدة البيانات إلى حالتها في ${p.basename(f.path)}. متابعة؟', danger: true);
    if (!ok || !mounted) return;
    await BackupService.restoreAuto(f);
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _reset() async {
    final pw = await askPassword(context, 'إعادة تعيين التطبيق — كلمة سر المدير');
    if (pw == null || !mounted) return;
    if (!await SchoolRepo.verifyAdmin(pw)) {
      if (mounted) toast(context, 'كلمة السر غير صحيحة', error: true);
      return;
    }
    if (!mounted) return;
    final typed = await askText(context, 'للتأكيد اكتب كلمة: حذف', label: 'حذف');
    if (typed?.trim() != 'حذف' || !mounted) return;
    await BackupService.factoryReset();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    Widget field(TextEditingController c, String label, {bool obscure = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: TextField(controller: c, obscureText: obscure, decoration: InputDecoration(labelText: label)),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      const SectionTitle('معلومات المؤسسة'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            field(name, 'اسم المؤسسة'),
            field(code, 'رمز المؤسسة'),
            field(academy, 'الأكاديمية الجهوية'),
            field(directorate, 'المديرية الإقليمية'),
            field(commune, 'الجماعة'),
            field(director, 'اسم المدير(ة)'),
            SwitchListTile(
              value: official,
              onChanged: (v) => setState(() => official = v),
              title: const Text('إظهار الترويسة الرسمية في التقارير والشهادات'),
            ),
            field(ministry, 'اسم الوزارة (في الترويسة)'),
            Row(children: [
              if (school?.logoPath != null) LocalImage(school!.logoPath, width: 56, height: 56, fit: BoxFit.contain),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _logo, icon: const Icon(Icons.image), label: const Text('شعار المؤسسة')),
              const Spacer(),
              ElevatedButton(onPressed: _saveSchool, child: const Text('حفظ')),
            ]),
          ]),
        ),
      ),
      const SectionTitle('خدمة الذكاء الاصطناعي (توليد الأسئلة)'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'يتصل التطبيق بخادم وسيط آمن (انظر دليل backend). لا يوجد أي مفتاح سري داخل التطبيق، '
              'ولا تُرسل أسماء التلاميذ أو معلوماتهم: يُرسل ملف القصة ومستوى القسم فقط.',
              style: TextStyle(color: AppColors.muted),
            ),
            field(aiUrl, 'عنوان الخادم (https://...)'),
            field(aiToken, 'رمز الوصول الخاص بالمؤسسة', obscure: true),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(onPressed: _saveAi, icon: const Icon(Icons.wifi_tethering), label: const Text('حفظ واختبار')),
            ),
          ]),
        ),
      ),
      const SectionTitle('فضاء التلاميذ'),
      Card(
        child: Column(children: [
          ListTile(
            title: const Text('إغلاق جلسة التلميذ بعد عدم النشاط'),
            trailing: DropdownButton<int>(
              value: idle,
              items: [for (final m in [1, 2, 3, 5, 10]) DropdownMenuItem(value: m, child: Text('$m دقيقة'))],
              onChanged: (v) async {
                if (v == null) return;
                await SchoolRepo.setSetting(SchoolRepo.kIdleMinutes, '$v');
                setState(() => idle = v);
              },
            ),
          ),
          ListTile(
            title: const Text('طول كلمة سر التلميذ'),
            trailing: DropdownButton<int>(
              value: pinDigits,
              items: [for (final d in [4, 5, 6]) DropdownMenuItem(value: d, child: Text('$d أرقام'))],
              onChanged: (v) async {
                if (v == null) return;
                await SchoolRepo.setSetting(SchoolRepo.kPinDigits, '$v');
                setState(() => pinDigits = v);
              },
            ),
          ),
        ]),
      ),
      const SectionTitle('الأمان والنسخ الاحتياطي'),
      Card(
        child: Column(children: [
          ListTile(leading: const Icon(Icons.password), title: const Text('تغيير كلمة سر المدير'), onTap: _changePassword),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('إنشاء نسخة احتياطية مشفرة'),
            subtitle: const Text('احفظها في بطاقة SD أو مفتاح USB أو Google Drive'),
            onTap: _backup,
          ),
          ListTile(leading: const Icon(Icons.settings_backup_restore), title: const Text('استعادة نسخة احتياطية'), onTap: _restore),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('النسخ التلقائية اليومية (داخل التابلت)'),
            onTap: _autoBackups,
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('سجل العمليات الإدارية'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.danger),
            title: const Text('إعادة تعيين التطبيق (حذف كل البيانات)', style: TextStyle(color: AppColors.danger)),
            onTap: _reset,
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('مكتبتي الصفية الذكية — الإصدار 1.0.0', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      ),
    ]);
  }
}

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.admin, title: const Text('سجل العمليات')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: SchoolRepo.auditLog(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long, text: 'لا توجد عمليات مسجلة');
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) {
              final e = list[i];
              final ts = (e['ts'] as String).replaceFirst('T', ' ');
              return ListTile(
                dense: true,
                title: Text('${e['action']}'),
                subtitle: Text('${ts.length > 16 ? ts.substring(0, 16) : ts} — ${e['actor']}'
                    '${e['details'] != null ? '\n${e['details']}' : ''}'),
              );
            },
          );
        },
      ),
    );
  }
}
