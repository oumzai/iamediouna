import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/arabic.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/people_repo.dart';
import '../data/school_repo.dart';
import '../services/demo_seed.dart';
import '../services/massar_parser.dart';
import '../services/pick.dart';
import 'admin/admin_home.dart';
import 'student/kiosk_screen.dart';
import 'teacher/class_home.dart';
import 'widgets/common.dart';

/// الشاشة الرئيسية: ثلاثة فضاءات مستقلة (المدير، القسم، التلاميذ).
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool? setupDone;
  School? school;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await SchoolRepo.isSetupDone();
    final s = done ? await SchoolRepo.getSchool() : null;
    if (!mounted) return;
    setState(() {
      setupDone = done;
      school = s;
    });
  }

  Future<void> _adminLogin() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const AdminLoginDialog());
    if (ok == true && mounted) {
      Session.I.loginAdmin();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHome()));
      Session.I.logout();
      _load();
    }
  }

  Future<void> _classLogin({required bool kiosk}) async {
    final c = await Navigator.push<SchoolClass>(
      context,
      MaterialPageRoute(builder: (_) => ClassLoginScreen(kiosk: kiosk)),
    );
    if (c == null || !mounted) return;
    Session.I.loginTeacher(c);
    if (kiosk) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => KioskScreen(cls: c)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassHome(cls: c)));
    }
    Session.I.logout();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (setupDone == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (setupDone == false) return FirstRunScreen(onDone: _load);
    final wide = MediaQuery.of(context).size.width >= 700;
    final tiles = [
      BigTile(
        icon: Icons.admin_panel_settings,
        label: 'الإدارة',
        subtitle: 'لوحة القيادة والتتبع',
        color: AppColors.admin,
        onTap: _adminLogin,
      ),
      BigTile(
        icon: Icons.class_,
        label: 'فضاء القسم',
        subtitle: 'القصص والاختبارات والنتائج',
        color: AppColors.teacher,
        onTap: () => _classLogin(kiosk: false),
      ),
      BigTile(
        icon: Icons.child_care,
        label: 'فضاء التلاميذ',
        subtitle: 'يفتحه الأستاذ للإجابة عن الاختبارات',
        color: AppColors.student,
        onTap: () => _classLogin(kiosk: true),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(children: [
                Image.asset('assets/images/app_icon.png', width: 96, height: 96),
                const SizedBox(height: 8),
                const Text('مكتبتي الصفية الذكية',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                Text(school?.name ?? '', style: const TextStyle(fontSize: 18, color: AppColors.muted)),
                const SizedBox(height: 28),
                if (wide)
                  Row(children: [
                    for (final t in tiles) Expanded(child: Padding(padding: const EdgeInsets.all(10), child: t)),
                  ])
                else
                  Column(children: [
                    for (final t in tiles) Padding(padding: const EdgeInsets.all(8), child: t),
                  ]),
                const SizedBox(height: 18),
                const Text('اقرأ القصة الورقية من مكتبة قسمك، ثم أجب عن أسئلتها هنا.',
                    style: TextStyle(color: AppColors.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- دخول المدير واسترجاع الحساب ----------------

class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final ctl = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _submit() async {
    final locked = Session.I.checkLocked();
    if (locked != null) {
      setState(() => error = locked);
      return;
    }
    setState(() => busy = true);
    final ok = await SchoolRepo.verifyAdmin(ctl.text);
    if (!mounted) return;
    if (ok) {
      Session.I.registerSuccess();
      await SchoolRepo.audit('المدير', 'دخول المدير');
      if (mounted) Navigator.pop(context, true);
    } else {
      Session.I.registerFailure();
      setState(() {
        busy = false;
        error = 'كلمة السر غير صحيحة';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('دخول الإدارة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: ctl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: 'كلمة سر المدير', errorText: error),
          onSubmitted: (_) => _submit(),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              nav.pop(false);
              await showDialog<void>(context: nav.context, builder: (_) => const RecoveryDialog());
            },
            child: const Text('نسيت كلمة السر؟'),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: busy ? null : _submit, child: const Text('دخول')),
      ],
    );
  }
}

class RecoveryDialog extends StatefulWidget {
  const RecoveryDialog({super.key});

  @override
  State<RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<RecoveryDialog> {
  final code = TextEditingController();
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? error;
  String? newCode;

  Future<void> _submit() async {
    if (p1.text.length < 6) {
      setState(() => error = 'كلمة السر 6 أحرف على الأقل');
      return;
    }
    if (p1.text != p2.text) {
      setState(() => error = 'كلمتا السر غير متطابقتين');
      return;
    }
    final locked = Session.I.checkLocked();
    if (locked != null) {
      setState(() => error = locked);
      return;
    }
    final r = await SchoolRepo.recoverAdmin(code.text, p1.text);
    if (!mounted) return;
    if (r == null) {
      Session.I.registerFailure();
      setState(() => error = 'رمز الاسترجاع غير صحيح');
    } else {
      setState(() => newCode = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (newCode != null) {
      return AlertDialog(
        title: const Text('تم تغيير كلمة السر'),
        content: RecoveryCodeView(code: newCode!),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('حفظت الرمز'))],
      );
    }
    return AlertDialog(
      title: const Text('استرجاع حساب المدير'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل رمز الاسترجاع الذي ظهر عند إنشاء المؤسسة.'),
          const SizedBox(height: 10),
          TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز الاسترجاع XXXX-XXXX-XXXX')),
          const SizedBox(height: 10),
          TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة')),
          const SizedBox(height: 10),
          TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة السر')),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: AppColors.danger)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(onPressed: _submit, child: const Text('تغيير')),
      ],
    );
  }
}

class RecoveryCodeView extends StatelessWidget {
  final String code;
  const RecoveryCodeView({super.key, required this.code});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('رمز الاسترجاع الجديد (اكتبه واحفظه في مكان آمن، لن يظهر مرة أخرى):'),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(code,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2)),
        ),
      ]);
}

// ---------------- دخول القسم ----------------

class ClassLoginScreen extends StatefulWidget {
  final bool kiosk;
  const ClassLoginScreen({super.key, required this.kiosk});

  @override
  State<ClassLoginScreen> createState() => _ClassLoginScreenState();
}

class _ClassLoginScreenState extends State<ClassLoginScreen> {
  List<SchoolClass>? classes;

  @override
  void initState() {
    super.initState();
    PeopleRepo.classes().then((c) {
      if (mounted) setState(() => classes = c);
    });
  }

  Future<void> _login(SchoolClass c) async {
    if (!c.hasPassword) {
      toast(context, 'لم يحدد المدير بعد كلمة سر لهذا القسم.', error: true);
      return;
    }
    final locked = Session.I.checkLocked();
    if (locked != null) {
      toast(context, locked, error: true);
      return;
    }
    final pw = await askPassword(context, 'دخول القسم ${c.code}', label: 'كلمة سر القسم');
    if (pw == null || !mounted) return;
    final ok = await PeopleRepo.verifyClass(c.id, pw);
    if (!mounted) return;
    if (ok) {
      Session.I.registerSuccess();
      await SchoolRepo.audit('القسم ${c.code}', widget.kiosk ? 'فتح فضاء التلاميذ' : 'دخول القسم');
      if (mounted) Navigator.pop(context, c);
    } else {
      Session.I.registerFailure();
      toast(context, 'كلمة السر غير صحيحة', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = classes;
    final color = widget.kiosk ? AppColors.student : AppColors.teacher;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        title: Text(widget.kiosk ? 'فتح فضاء التلاميذ — اختر القسم' : 'فضاء القسم — اختر قسمك'),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const EmptyState(
                  icon: Icons.class_outlined,
                  text: 'لا توجد أقسام بعد. يجب على المدير استيراد لائحة التلاميذ من ملف مسار أولًا.')
              : GridView.extent(
                  padding: const EdgeInsets.all(16),
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    for (final c in list)
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        elevation: 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _login(c),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(c.code, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
                            Text(c.levelName.isNotEmpty ? c.levelName : Ar.levelName(c.level),
                                style: const TextStyle(color: AppColors.muted)),
                            Text('${c.studentCount} تلميذ(ة)', style: const TextStyle(color: AppColors.muted)),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ---------------- الإعداد الأول ----------------

class FirstRunScreen extends StatefulWidget {
  final VoidCallback onDone;
  const FirstRunScreen({super.key, required this.onDone});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final code = TextEditingController();
  final academy = TextEditingController();
  final directorate = TextEditingController();
  final commune = TextEditingController();
  final director = TextEditingController();
  final year = TextEditingController(text: Ar.currentSchoolYear());
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  Uint8List? logo;
  String logoExt = 'png';
  bool busy = false;

  Future<void> _fromMassar() async {
    final f = await Pick.excel();
    if (f == null || !mounted) return;
    try {
      final file = MassarParser.parseBytes(f.bytes);
      setState(() {
        if (file.meta.school.isNotEmpty) name.text = file.meta.school;
        if (file.meta.academy.isNotEmpty) academy.text = file.meta.academy;
        if (file.meta.directorate.isNotEmpty) directorate.text = file.meta.directorate;
        if (file.meta.commune.isNotEmpty) commune.text = file.meta.commune;
        if (file.meta.year.isNotEmpty) year.text = file.meta.year;
      });
      toast(context, 'تم ملء معلومات المؤسسة من الملف. ستستورد التلاميذ لاحقًا من فضاء الإدارة.');
    } catch (e) {
      toast(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      String? logoPath;
      if (logo != null) logoPath = await AppDb.I.saveBytes('logo', logoExt, logo!, name: 'logo.$logoExt');
      await SchoolRepo.saveSchool(School(
        name: name.text.trim(),
        code: code.text.trim(),
        academy: academy.text.trim(),
        directorate: directorate.text.trim(),
        commune: commune.text.trim(),
        directorName: director.text.trim(),
        logoPath: logoPath,
      ));
      await SchoolRepo.ensureYear(year.text.trim().isEmpty ? Ar.currentSchoolYear() : year.text.trim(),
          makeCurrent: true);
      final recovery = await SchoolRepo.createAdmin(p1.text);
      await SchoolRepo.audit('المدير', 'إنشاء ملف المؤسسة', name.text.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('تم إنشاء المؤسسة'),
          content: RecoveryCodeView(code: recovery),
          actions: [ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text('كتبت الرمز وحفظته'))],
        ),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
      setState(() => busy = false);
    }
  }

  Future<void> _demo() async {
    final ok = await confirm(context, 'بيانات تجريبية',
        'سيتم إنشاء مؤسسة وأقسام وتلاميذ وقصص ونتائج وهمية لتجربة التطبيق. يمكن حذفها لاحقًا من الإعدادات (إعادة التعيين).');
    if (!ok || !mounted) return;
    final r = await withProgress(context, 'إنشاء البيانات التجريبية...', () async {
      await DemoSeed.seed();
      return true;
    });
    if (r != true || !mounted) return;
    await info(
      context,
      'بيانات الدخول التجريبية',
      const Text('كلمة سر المدير: ${DemoSeed.adminPassword}\n'
          'كلمة سر كل قسم: ${DemoSeed.classPassword}\n'
          'كلمة سر كل تلميذ: ${DemoSeed.studentPin}'),
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {bool req = false, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: c,
            decoration: InputDecoration(labelText: req ? '$label *' : label, hintText: hint),
            validator: req ? (v) => (v ?? '').trim().isEmpty ? 'هذا الحقل إلزامي' : null : null,
          ),
        );
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.admin, title: const Text('إعداد المؤسسة — التشغيل الأول')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('مرحبًا! يقوم المدير بإنشاء ملف المؤسسة مرة واحدة.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _fromMassar,
                  icon: const Icon(Icons.table_view),
                  label: const Text('ملء المعلومات تلقائيًا من ملف مسار (اختياري)'),
                ),
                field(name, 'اسم المؤسسة', req: true),
                field(code, 'رمز المؤسسة'),
                field(year, 'الموسم الدراسي', req: true, hint: '2026/2027'),
                field(academy, 'الأكاديمية الجهوية'),
                field(directorate, 'المديرية الإقليمية'),
                field(commune, 'الجماعة'),
                field(director, 'اسم المدير(ة) (يظهر في الشهادات)'),
                const SizedBox(height: 8),
                Row(children: [
                  if (logo != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Image.memory(logo!, width: 64, height: 64),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final f = await Pick.image();
                      if (f != null) {
                        setState(() {
                          logo = f.bytes;
                          logoExt = f.ext.isEmpty ? 'png' : f.ext;
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: Text(logo == null ? 'إضافة شعار المؤسسة (اختياري)' : 'تغيير الشعار'),
                  ),
                ]),
                const SectionTitle('حساب المدير'),
                TextFormField(
                  controller: p1,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة سر المدير *'),
                  validator: (v) => (v ?? '').length < 6 ? '6 أحرف على الأقل' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: p2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة السر *'),
                  validator: (v) => v != p1.text ? 'كلمتا السر غير متطابقتين' : null,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: busy ? null : _create,
                  icon: const Icon(Icons.check),
                  label: const Text('إنشاء المؤسسة'),
                ),
                const SizedBox(height: 30),
                const Divider(),
                TextButton.icon(
                  onPressed: busy ? null : _demo,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('تجربة التطبيق ببيانات وهمية'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
