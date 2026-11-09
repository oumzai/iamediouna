import 'dart:typed_data';

import '../core/arabic.dart';
import 'xlsx_reader.dart';

/// معلومات المؤسسة كما تظهر في ترويسة أوراق ملف مسار.
class MassarMeta {
  String academy = '';
  String directorate = '';
  String commune = '';
  String school = '';
  String year = '';
}

class MassarStudent {
  String code;
  String lastName;
  String firstName;
  String gender;
  final int row;
  final List<String> issues = [];

  MassarStudent({
    required this.code,
    required this.lastName,
    required this.firstName,
    required this.gender,
    required this.row,
  });

  String get fullName => '$lastName $firstName'.trim();

  /// خطأ يمنع الاستيراد (وليس مجرد تنبيه).
  bool get blocking => code.isEmpty || (lastName.isEmpty && firstName.isEmpty);

  static final RegExp codePattern = RegExp(r'^[A-Z]\d{9}$');

  void revalidate() {
    issues.clear();
    code = code.trim().toUpperCase();
    lastName = Ar.clean(lastName);
    firstName = Ar.clean(firstName);
    if (code.isEmpty) {
      issues.add('رمز مسار فارغ');
    } else if (!codePattern.hasMatch(code)) {
      issues.add('رمز مسار بصيغة غير معتادة');
    }
    if (lastName.isEmpty || firstName.isEmpty) issues.add('الاسم أو النسب ناقص');
  }
}

class MassarClass {
  final String sheetName;
  final String code;
  final String levelName;
  final int level;
  final List<MassarStudent> students = [];
  final List<String> issues = [];

  MassarClass({
    required this.sheetName,
    required this.code,
    required this.levelName,
    required this.level,
  });

  bool get isPreschool => Ar.isPreschool(level);
  bool get isPrimary => Ar.isPrimary(level);
}

class MassarFile {
  final MassarMeta meta;
  final List<MassarClass> classes;
  final List<String> warnings;

  MassarFile(this.meta, this.classes, this.warnings);

  int get studentCount => classes.fold(0, (s, c) => s + c.students.length);
}

/// يحلل ملف لائحة التلاميذ المصدَّر من منظومة مسار.
///
/// البنية المعتمدة (تم التحقق منها على ملفات حقيقية):
/// - ورقة لكل قسم، اسمها رمز القسم (1APG-1، PS1-1...).
/// - ترويسة: الأكاديمية، المديرية الإقليمية، الجماعة، المؤسسة، المستوى، السنة الدراسية، القسم.
/// - صف عناوين: ر.ت | الرمز | النسب | الإسم | النوع | تاريخ الإزدياد | مكان الازدياد
/// يبحث المحلل عن العناوين بالاسم وليس بالموقع، لكي يتحمل تغييرات بسيطة في الصيغة.
/// لا تُقرأ تواريخ الازدياد ولا أماكنه (تقليل البيانات الشخصية).
class MassarParser {
  MassarParser._();

  static MassarFile parseBytes(Uint8List bytes) => parse(XlsxWorkbook.decode(bytes));

  static const _labels = <String, String>{
    'الأكاديمية': 'academy',
    'المديرية': 'directorate',
    'الجماعة': 'commune',
    'المؤسسة': 'school',
    'السنة الدراسية': 'year',
    'المستوى': 'level',
    'القسم': 'class',
  };

  static String? _labelKey(String text) {
    final t = Ar.clean(text);
    if (!t.contains(':') || t.length > 40) return null;
    for (final e in _labels.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return null;
  }

  static MassarFile parse(XlsxWorkbook wb) {
    final meta = MassarMeta();
    final classes = <MassarClass>[];
    final warnings = <String>[];

    for (final sheet in wb.sheets) {
      // 1) صف العناوين
      int headerRow = 0;
      final colMap = <String, int>{};
      for (final r in sheet.rowNumbers) {
        if (r > 40) break;
        final cells = sheet.rowCells(r);
        final hasCode = cells.any((c) => Ar.normalize(c.value) == 'الرمز');
        if (!hasCode) continue;
        headerRow = r;
        for (final c in cells) {
          final n = Ar.normalize(c.value);
          if (n == 'الرمز') {
            colMap['code'] = c.key;
          } else if (n.startsWith('النسب')) {
            colMap['last'] = c.key;
          } else if (n == 'الاسم' || n.startsWith('الاسم')) {
            colMap['first'] = c.key;
          } else if (n.startsWith('النوع') || n.startsWith('الجنس')) {
            colMap['gender'] = c.key;
          }
        }
        break;
      }
      if (headerRow == 0 || !colMap.containsKey('code')) {
        warnings.add('الورقة «${sheet.name}» لا تحتوي على لائحة تلاميذ بصيغة مسار، تم تجاهلها.');
        continue;
      }

      // 2) الترويسة (قبل صف العناوين)
      final sheetMeta = <String, String>{};
      for (final r in sheet.rowNumbers) {
        if (r >= headerRow) break;
        final cells = sheet.rowCells(r);
        for (var i = 0; i < cells.length; i++) {
          final key = _labelKey(cells[i].value);
          if (key == null) continue;
          for (var j = i + 1; j < cells.length; j++) {
            if (_labelKey(cells[j].value) != null) break;
            final v = Ar.clean(cells[j].value);
            if (v.isNotEmpty) {
              sheetMeta[key] = v;
              break;
            }
          }
        }
      }

      void setMeta(String current, String? value, void Function(String) assign, String label) {
        final v = Ar.clean(value);
        if (v.isEmpty) return;
        if (current.isEmpty) {
          assign(v);
        } else if (current != v) {
          final w = 'تنبيه: $label مختلف في الورقة «${sheet.name}» ($v).';
          if (!warnings.contains(w)) warnings.add(w);
        }
      }

      setMeta(meta.academy, sheetMeta['academy'], (v) => meta.academy = v, 'اسم الأكاديمية');
      setMeta(meta.directorate, _stripPrefix(sheetMeta['directorate']), (v) => meta.directorate = v,
          'اسم المديرية');
      setMeta(meta.commune, sheetMeta['commune'], (v) => meta.commune = v, 'اسم الجماعة');
      setMeta(meta.school, sheetMeta['school'], (v) => meta.school = v, 'اسم المؤسسة');
      setMeta(meta.year, sheetMeta['year'], (v) => meta.year = v, 'الموسم الدراسي');

      final code = Ar.clean(sheetMeta['class']).isNotEmpty
          ? Ar.clean(sheetMeta['class']).toUpperCase()
          : Ar.clean(sheet.name).toUpperCase();
      final levelName = Ar.clean(sheetMeta['level']);
      final mc = MassarClass(
        sheetName: sheet.name,
        code: code,
        levelName: levelName,
        level: Ar.levelFromCode(code, levelName),
      );
      if (mc.level == 0) mc.issues.add('تعذر تحديد المستوى من رمز القسم');

      // 3) التلاميذ
      for (final r in sheet.rowNumbers) {
        if (r <= headerRow) continue;
        final codeVal = sheet.cell(r, colMap['code']!);
        final last = colMap['last'] != null ? sheet.cell(r, colMap['last']!) : '';
        final first = colMap['first'] != null ? sheet.cell(r, colMap['first']!) : '';
        if (Ar.clean(codeVal).isEmpty && Ar.clean(last).isEmpty && Ar.clean(first).isEmpty) continue;
        final g = colMap['gender'] != null ? sheet.cell(r, colMap['gender']!) : '';
        final s = MassarStudent(
          code: codeVal,
          lastName: last,
          firstName: first,
          gender: _gender(g),
          row: r,
        )..revalidate();
        mc.students.add(s);
      }
      if (mc.students.isEmpty) mc.issues.add('القسم لا يحتوي على تلاميذ');
      classes.add(mc);
    }

    // 4) رموز مكررة داخل الملف
    final seen = <String, MassarClass>{};
    for (final c in classes) {
      for (final s in c.students) {
        if (s.code.isEmpty) continue;
        final prev = seen[s.code];
        if (prev != null && prev != c) {
          s.issues.add('الرمز مكرر في القسم ${prev.code}');
        } else if (prev == c) {
          s.issues.add('الرمز مكرر داخل القسم');
        }
        seen[s.code] = c;
      }
    }

    // رموز أقسام مكررة
    final codes = <String>{};
    for (final c in classes) {
      if (!codes.add(c.code)) c.issues.add('رمز القسم مكرر في الملف');
    }

    if (classes.isEmpty) {
      warnings.add('لم يتم العثور على أي قسم في الملف. تأكد أنه لائحة التلاميذ المحملة من مسار.');
    }
    return MassarFile(meta, classes, warnings);
  }

  static String _gender(String g) {
    final t = Ar.clean(g);
    if (t.contains('أنث') || t.contains('انث')) return 'أنثى';
    if (t.contains('ذكر')) return 'ذكر';
    final u = t.toUpperCase();
    if (u == 'F') return 'أنثى';
    if (u == 'M' || u == 'G') return 'ذكر';
    return '';
  }

  static String _stripPrefix(String? v) {
    final t = Ar.clean(v);
    final i = t.indexOf(':');
    if (i >= 0 && i < 12) return Ar.clean(t.substring(i + 1));
    return t;
  }
}
