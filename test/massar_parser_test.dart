import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktabati/core/arabic.dart';
import 'package:maktabati/services/massar_parser.dart';
import 'package:maktabati/services/xlsx_reader.dart';

/// ملف xlsx مصغر يُبنى في الذاكرة بنفس بنية مسار (لاختبار الحالات الخاصة).
Uint8List buildXlsx(List<(String, List<List<String>>)> sheets) {
  final shared = <String>[];
  int si(String s) {
    var i = shared.indexOf(s);
    if (i < 0) {
      shared.add(s);
      i = shared.length - 1;
    }
    return i;
  }

  String col(int c) => String.fromCharCode(64 + c);
  final archive = Archive();
  final sheetEntries = StringBuffer();
  final rels = StringBuffer();
  for (var n = 0; n < sheets.length; n++) {
    final (name, rows) = sheets[n];
    final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].every((c) => c.isEmpty)) continue;
      sb.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        if (v.isEmpty) continue;
        sb.write('<c r="${col(c + 1)}${r + 1}" t="s"><v>${si(v)}</v></c>');
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');
    archive.addFile(ArchiveFile.string('xl/worksheets/sheet${n + 1}.xml', sb.toString()));
    sheetEntries.write('<sheet name="$name" sheetId="${n + 1}" r:id="rId${n + 1}"/>');
    rels.write('<Relationship Id="rId${n + 1}" Type="worksheet" Target="worksheets/sheet${n + 1}.xml"/>');
  }
  archive.addFile(ArchiveFile.string(
      'xl/workbook.xml',
      '﻿<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>$sheetEntries</sheets></workbook>'));
  archive.addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>'));
  final ss = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  for (final s in shared) {
    ss.write('<si><t>${s.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</t></si>');
  }
  ss.write('</sst>');
  archive.addFile(ArchiveFile.string('xl/sharedStrings.xml', ss.toString()));
  return ZipEncoder().encodeBytes(archive);
}

List<List<String>> massarSheet(String classCode, String level, List<List<String>> students) => [
      [],
      [],
      [],
      [],
      ['الأكاديمية :', '', 'الدار البيضاء - سطات', '', '', 'الجماعة :', 'جماعة اختبار'],
      [' : المديرية الإقليمية', '', 'إقليم: مديونة', '', '', 'المؤسسة:', 'مدرسة اختبار'],
      ['   : المستوى', '', level, '', '', 'السنة الدراسية :', '2026/2027'],
      ['   : القسم', '', classCode],
      [],
      ['ر.ت', 'الرمز', 'النسب ', 'الإسم', 'النوع', 'تاريخ الإزدياد', 'مكان الازدياد'],
      ...students,
    ];

void main() {
  group('ملف مسار الحقيقي (نسخة مجهولة البيانات)', () {
    late MassarFile file;

    setUpAll(() {
      final bytes = File('test/fixtures/massar_sample.xlsx').readAsBytesSync();
      file = MassarParser.parseBytes(bytes);
    });

    test('يتعرف على كل الأقسام والتلاميذ', () {
      expect(file.classes.length, 26);
      expect(file.studentCount, 774);
      expect(file.warnings.where((w) => w.contains('تجاهل')), isEmpty);
    });

    test('يقرأ معلومات المؤسسة من الترويسة', () {
      expect(file.meta.year, '2026/2027');
      expect(file.meta.directorate, 'مديونة');
      expect(file.meta.academy, contains('الدار البيضاء'));
      expect(file.meta.school, 'مدرسة تجريبية');
    });

    test('يحدد المستويات ومنها التعليم الأولي', () {
      final byLevel = <int, int>{};
      for (final c in file.classes) {
        byLevel[c.level] = (byLevel[c.level] ?? 0) + c.students.length;
      }
      expect(byLevel[Ar.preschool1], 28);
      expect(byLevel[Ar.preschool2], 19);
      expect(byLevel[1], 121);
      expect(byLevel[6], 144);
      expect(file.classes.where((c) => c.isPreschool).length, 2);
      expect(file.classes.firstWhere((c) => c.code == '1APG-1').level, 1);
    });

    test('يقرأ التلميذ الأول بشكل صحيح ودون أخطاء', () {
      final c = file.classes.firstWhere((c) => c.code == '1APG-1');
      final s = c.students.first;
      expect(s.code, 'F473799650');
      expect(s.lastName, 'الزياني');
      expect(s.firstName, 'نور');
      expect(s.gender, 'أنثى');
      expect(file.classes.expand((c) => c.students).where((s) => s.issues.isNotEmpty), isEmpty);
    });
  });

  group('حالات خاصة', () {
    test('يكتشف الرموز المكررة والسطور الناقصة', () {
      final bytes = buildXlsx([
        (
          '3APG-1',
          massarSheet('3APG-1', 'الثالث ابتدائي عام', [
            ['1', 'G111111111', 'العلوي', 'سلمى', 'أنثى', '2017-01-01', 'X'],
            ['2', 'G111111111', 'الإدريسي', 'ياسين', 'ذكر', '', ''],
            ['3', '', 'بدون', 'رمز', 'ذكر', '', ''],
            ['4', 'BAD', 'رمز', 'غريب', 'ذكر', '', ''],
          ])
        ),
      ]);
      final f = MassarParser.parseBytes(bytes);
      final st = f.classes.single.students;
      expect(st.length, 4);
      expect(st[1].issues.any((i) => i.contains('مكرر')), isTrue);
      expect(st[2].blocking, isTrue);
      expect(st[3].issues.any((i) => i.contains('غير معتادة')), isTrue);
      expect(st[3].blocking, isFalse);
      expect(f.classes.single.level, 3);
    });

    test('يتجاهل الأوراق غير المتعلقة باللوائح', () {
      final bytes = buildXlsx([
        ('ملاحظات', [['نص عادي'], ['بدون عناوين']]),
        ('5APG-2', massarSheet('5APG-2', 'الخامس ابتدائي عام', [['1', 'R222222222', 'بنعلي', 'آدم', 'ذكر', '', '']])),
      ]);
      final f = MassarParser.parseBytes(bytes);
      expect(f.classes.length, 1);
      expect(f.classes.single.code, '5APG-2');
      expect(f.warnings.length, 1);
    });

    test('يرفض ملفًا ليس Excel', () {
      expect(() => XlsxWorkbook.decode(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<FormatException>()));
    });

    test('استخراج المستوى من رمز القسم', () {
      expect(Ar.levelFromCode('6APG-3'), 6);
      expect(Ar.levelFromCode('PS2-1'), Ar.preschool2);
      expect(Ar.levelFromCode('X-1', 'الرابع ابتدائي عام'), 4);
      expect(Ar.levelFromCode('X-1', ' الأولى  أولي '), Ar.preschool1);
    });
  });
}
