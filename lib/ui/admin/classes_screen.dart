import 'package:flutter/material.dart';

import '../../core/arabic.dart';
import '../../core/security.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/people_repo.dart';
import '../../data/school_repo.dart';
import '../../services/reports.dart';
import '../shared/students_screen.dart';
import '../widgets/common.dart';

/// إدارة الأقسام: كلمة سر كل قسم، اسم الأستاذ، التلاميذ وكلمات سرهم.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  List<SchoolClass>? classes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await PeopleRepo.classes();
    if (mounted) setState(() => classes = c);
  }

  Future<void> _setPassword(SchoolClass c) async {
    final ctl = TextEditingController(text: Security.generatePassword());
    final pw = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('كلمة سر القسم ${c.code}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اقترحنا كلمة سر عشوائية. يمكنك تغييرها. سلّمها لأستاذ(ة) القسم.'),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
            decoration: const InputDecoration(labelText: 'كلمة السر (6 أحرف على الأقل)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('اعتماد')),
        ],
      ),
    );
    if (pw == null || !mounted) return;
    if (pw.length < 6) {
      toast(context, 'كلمة السر قصيرة جدًا', error: true);
      return;
    }
    await PeopleRepo.setClassPassword(c.id, pw);
    await SchoolRepo.audit(Session.I.actor, c.hasPassword ? 'إعادة تعيين كلمة سر قسم' : 'تحديد كلمة سر قسم', c.code);
    if (!mounted) return;
    await info(
      context,
      'تم حفظ كلمة السر',
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('القسم: ${c.code}'),
        const SizedBox(height: 8),
        SelectableText(pw, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('دوّنها الآن: لا يمكن عرضها مرة أخرى (تُحفظ مشفّرة).', style: TextStyle(color: AppColors.muted)),
      ]),
    );
    _load();
  }

  Future<void> _teacher(SchoolClass c) async {
    final name = await askText(context, 'اسم أستاذ(ة) القسم ${c.code}', label: 'الاسم (يظهر في الشهادات)',
        initial: c.teacherName);
    if (name == null) return;
    await PeopleRepo.setTeacherName(c.id, name);
    await SchoolRepo.audit(Session.I.actor, 'تغيير اسم أستاذ القسم', '${c.code}: $name');
    _load();
  }

  Future<void> _pins(SchoolClass c, {required bool onlyMissing}) async {
    if (!onlyMissing) {
      final ok = await confirm(context, 'إعادة توليد كلمات السر',
          'ستتغير كلمات سر جميع تلاميذ القسم ${c.code}، وتصبح البطاقات القديمة غير صالحة. هل تريد المتابعة؟',
          danger: true);
      if (!ok || !mounted) return;
    }
    final digits = await SchoolRepo.getInt(SchoolRepo.kPinDigits, 4);
    if (!mounted) return;
    final pins = await withProgress(context, 'توليد كلمات السر وتشفيرها...',
        () => PeopleRepo.generatePins(c.id, onlyMissing: onlyMissing, digits: digits));
    if (pins == null || !mounted) return;
    if (pins.isEmpty) {
      toast(context, 'جميع التلاميذ لديهم كلمات سر.');
      return;
    }
    await SchoolRepo.audit(Session.I.actor, 'توليد كلمات سر التلاميذ', '${c.code}: ${pins.length} تلميذ');
    if (!mounted) return;
    final bytes = await withProgress(context, 'إعداد بطاقات الدخول...', () => Reports.pinCards(c, pins));
    if (bytes != null) await Reports.printOrShare(bytes, 'بطاقات_${c.code}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = classes;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return const EmptyState(icon: Icons.groups, text: 'لا توجد أقسام. ابدأ باستيراد لائحة التلاميذ من «استيراد مسار».');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        const Text(
          'لكل قسم حساب خاص (رمز القسم + كلمة سر) يستعمله أستاذ(ة) القسم. '
          'التلاميذ يدخلون برمز مسار وكلمة سر يولّدها المدير وتُطبع في بطاقات.',
          style: TextStyle(color: AppColors.muted),
        ),
        for (final c in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(c.code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.admin)),
                  const SizedBox(width: 10),
                  Text(c.levelName.isNotEmpty ? c.levelName : Ar.levelName(c.level)),
                  const Spacer(),
                  Chip(
                    label: Text(c.hasPassword ? 'كلمة السر محددة' : 'بدون كلمة سر',
                        style: const TextStyle(color: Colors.white)),
                    backgroundColor: c.hasPassword ? AppColors.ok : AppColors.danger,
                  ),
                ]),
                Text('${c.studentCount} تلميذ(ة)${c.teacherName.isNotEmpty ? ' — الأستاذ(ة): ${c.teacherName}' : ''}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () => _setPassword(c),
                    icon: const Icon(Icons.key),
                    label: Text(c.hasPassword ? 'إعادة تعيين كلمة السر' : 'تحديد كلمة السر'),
                  ),
                  OutlinedButton.icon(onPressed: () => _teacher(c), icon: const Icon(Icons.person), label: const Text('اسم الأستاذ(ة)')),
                  OutlinedButton.icon(
                    onPressed: () => _pins(c, onlyMissing: true),
                    icon: const Icon(Icons.badge),
                    label: const Text('كلمات سر التلاميذ الجدد + البطاقات'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pins(c, onlyMissing: false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة توليد للجميع'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(backgroundColor: AppColors.admin, title: Text('تلاميذ القسم ${c.code}')),
                          body: StudentsScreen(cls: c),
                        ),
                      ),
                    ).then((_) => _load()),
                    icon: const Icon(Icons.list),
                    label: const Text('التلاميذ'),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
