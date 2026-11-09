import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/arabic.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/people_repo.dart';
import '../data/results_repo.dart';
import '../data/school_repo.dart';
import 'ranking.dart';
import 'ranking_service.dart';

/// بيانات شهادة تقديرية.
class CertificateData {
  final Student student;
  final SchoolClass cls;
  final String kind; // top | improvement | regularity
  final int? rank;
  final Period period;
  final String serial;
  CertificateData(this.student, this.cls, this.kind, this.rank, this.period, this.serial);
}

/// إعداد ملفات PDF قابلة للطباعة: التقارير، الشهادات، بطاقات الدخول، ملصقات QR.
class Reports {
  Reports._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  static const _green = PdfColor.fromInt(0xFF1F7A6D);
  static const _gold = PdfColor.fromInt(0xFFB8860B);
  static const _light = PdfColor.fromInt(0xFFEAF4F2);
  static const _grey = PdfColor.fromInt(0xFF6B7B78);

  static Future<pw.ThemeData> _theme() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
    return pw.ThemeData.withFont(base: _regular!, bold: _bold!);
  }

  // ---------------- الترويسة ----------------

  static Future<pw.Widget> _header() async {
    final school = await SchoolRepo.getSchool();
    final official = (await SchoolRepo.getSetting(SchoolRepo.kShowOfficialHeader)) != '0';
    final ministry = (await SchoolRepo.getSetting(SchoolRepo.kMinistry)) ?? SchoolRepo.defaultMinistry;
    final logo = await _logo(school);
    final lines = <String>[
      if (official) 'المملكة المغربية',
      if (official) ministry,
      if (school != null && school.academy.isNotEmpty) 'الأكاديمية الجهوية للتربية والتكوين: ${school.academy}',
      if (school != null && school.directorate.isNotEmpty) 'المديرية الإقليمية: ${school.directorate}',
      if (school != null) 'المؤسسة: ${school.name}${school.code.isNotEmpty ? ' (${school.code})' : ''}',
    ];
    return pw.Column(children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [for (final l in lines) pw.Text(l, style: const pw.TextStyle(fontSize: 10.5))],
          ),
        ),
        if (logo != null) pw.SizedBox(width: 60, height: 60, child: pw.Image(logo, fit: pw.BoxFit.contain)),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: _green, thickness: 1.5),
    ]);
  }

  static Future<pw.MemoryImage?> _logo(School? school) async {
    final p = school?.logoPath;
    if (p == null) return null;
    final f = File(AppDb.I.abs(p));
    if (!await f.exists()) return null;
    try {
      return pw.MemoryImage(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _title(String t, [String? sub]) => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 8),
        alignment: pw.Alignment.center,
        child: pw.Column(children: [
          pw.Text(t, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _green)),
          if (sub != null) pw.Text(sub, style: const pw.TextStyle(fontSize: 12, color: _grey)),
        ]),
      );

  static pw.Widget _section(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: const pw.BoxDecoration(color: _light),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green)),
      );

  /// جدول من اليمين إلى اليسار: الأعمدة تُعكس يدويًا لأن الجداول لا تنعكس تلقائيًا.
  static pw.Widget _table(List<String> headers, List<List<String>> rows, {List<double>? flex}) {
    final n = headers.length;
    final widths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < n; i++) {
      final f = flex != null && i < flex.length ? flex[i] : 1.0;
      widths[n - 1 - i] = pw.FlexColumnWidth(f);
    }
    pw.Widget cell(String t, {bool head = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(t,
              style: pw.TextStyle(fontSize: head ? 10.5 : 10, fontWeight: head ? pw.FontWeight.bold : null)),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _light),
          children: headers.reversed.map((h) => cell(h, head: true)).toList(),
        ),
        for (final r in rows) pw.TableRow(children: r.reversed.map((c) => cell(c)).toList()),
      ],
    );
  }

  static pw.Widget _kv(List<MapEntry<String, String>> items) => pw.Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [
          for (final e in items)
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(text: '${e.key}: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: e.value),
              ]),
            ),
        ],
      );

  static pw.Widget _signatures(List<String> who) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 24),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            for (final w in who)
              pw.Column(children: [
                pw.Text(w, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 36),
                pw.Text('التوقيع: .......................', style: const pw.TextStyle(color: _grey)),
              ]),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context ctx) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text('مكتبتي الصفية الذكية — ${Ar.formatDate(DateTime.now())} — صفحة ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _grey)),
      );

  static List<String> _notes(ClassStats st, int noAttempt) {
    final notes = <String>[];
    if (st.students > 0 && st.participation < 50) {
      notes.add('نسبة المشاركة ضعيفة؛ يُستحسن تخصيص وقت أسبوعي للقراءة وتشجيع التلاميذ على استعارة القصص.');
    }
    if (st.attempts > 0 && st.avgPercent < 50) {
      notes.add('متوسط الفهم دون المتوسط؛ تفيد القراءة الجماعية ومناقشة القصص قبل الاختبار.');
    } else if (st.attempts > 0 && st.avgPercent >= 75) {
      notes.add('مستوى فهم جيد؛ يمكن اقتراح قصص أطول أو أكثر تحديًا.');
    }
    if (noAttempt > 0) notes.add('عدد التلاميذ الذين لم ينجزوا أي تقييم خلال الفترة: $noAttempt.');
    notes.add('ملاحظة: عدم إنجاز الاختبار لا يعني بالضرورة عدم قراءة القصة، والأوصاف تربوية وقابلة للمراجعة.');
    return notes;
  }

  // ---------------- التقرير الشهري / السنوي للقسم ----------------

  static Future<Uint8List> classReport(SchoolClass c, Period p) async {
    final theme = await _theme();
    final header = await _header();
    final school = await SchoolRepo.getSchool();
    final st = await ResultsRepo.classStats(c.id, p.start, p.end);
    final outcome = await RankingService.compute(c, p);
    final students = await PeopleRepo.students(c.id);
    final rowsById = {for (final r in outcome.rows) r.studentId: r};
    final year = await SchoolRepo.currentYear();
    final series = p.annual ? await ResultsRepo.monthly(year, classId: c.id) : <SeriesPoint>[];
    final noAttempt = students.where((s) => (rowsById[s.id]?.attemptedStories ?? 0) == 0).length;
    final improved = p.annual ? await _improvedSection(c, students) : <pw.Widget>[];

    final doc = pw.Document(title: 'تقرير ${c.code} — ${p.label}');
    doc.addPage(pw.MultiPage(
      theme: theme,
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1 ? header : pw.SizedBox(),
      footer: _footer,
      build: (ctx) => [
        _title(p.annual ? 'التقرير السنوي للقراءة' : 'التقرير الشهري للقراءة', p.label),
        _kv([
          MapEntry('المؤسسة', school?.name ?? ''),
          MapEntry('القسم', c.code),
          MapEntry('المستوى', c.levelName.isNotEmpty ? c.levelName : Ar.levelName(c.level)),
          if (c.teacherName.isNotEmpty) MapEntry('الأستاذ(ة)', c.teacherName),
        ]),
        _section('مؤشرات عامة'),
        _table(
          ['عدد التلاميذ', 'القصص المسندة', 'المشاركون', 'نسبة المشاركة', 'الاختبارات المنجزة', 'متوسط الفهم'],
          [
            [
              '${st.students}',
              '${st.storiesAssigned}',
              '${st.participants}',
              Ar.percent(st.participation),
              '${st.attempts}',
              st.attempts == 0 ? '—' : Ar.percent(st.avgPercent),
            ]
          ],
        ),
        if (p.annual && series.isNotEmpty) ...[
          _section('تطور القراءة عبر الأشهر'),
          _table(['الشهر', 'المشاركون', 'الاختبارات', 'متوسط الفهم'], [
            for (final s in series)
              [s.label, '${s.participants}', '${s.attempts}', s.attempts == 0 ? '—' : Ar.percent(s.avg)],
          ]),
        ],
        _section(p.annual ? 'أفضل القراء خلال الموسم' : 'أفضل ثلاثة قراء'),
        if (outcome.top3.isEmpty)
          pw.Text('لا يوجد تلميذ مؤهل للترتيب خلال هذه الفترة حسب المعايير المعتمدة.')
        else
          _table(['المرتبة', 'الاسم الكامل', 'القصص المنجزة', 'متوسط الفهم'], [
            for (final r in (p.annual ? outcome.ranked.take(10) : outcome.top3))
              [
                RankingService.rankWord(r.rank),
                outcome.students[r.studentId]?.fullName ?? '',
                '${r.passedStories}',
                Ar.percent(r.avgPercent),
              ],
          ], flex: [1, 3, 1.2, 1.2]),
        pw.Text(outcome.criteria.config.describe(annual: p.annual),
            style: const pw.TextStyle(fontSize: 9, color: _grey)),
        if (outcome.fromSnapshot)
          pw.Text('نتائج معتمدة بتاريخ ${outcome.snapshotDate?.substring(0, 10) ?? ''}.',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
        _section('نتائج التلاميذ'),
        _table(['الاسم الكامل', 'قصص منجزة', 'قصص مُقيَّمة', 'متوسط الفهم', 'وصف القارئ'], [
          for (final s in students)
            [
              s.fullName,
              '${rowsById[s.id]?.passedStories ?? 0}',
              '${rowsById[s.id]?.attemptedStories ?? 0}',
              (rowsById[s.id]?.attemptedStories ?? 0) == 0 ? '—' : Ar.percent(rowsById[s.id]?.avgPercent),
              Ar.readingLevelName(s.readingLevel),
            ],
        ], flex: [3, 1, 1, 1, 2]),
        ...improved,
        _section('ملاحظات تربوية'),
        for (final n in _notes(st, noAttempt)) pw.Bullet(text: n, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10.5)),
        _signatures(['الأستاذ(ة)', 'المدير(ة)']),
      ],
    ));
    return doc.save();
  }

  /// التلاميذ الذين تحسن مستواهم: مقارنة متوسط النصف الأول من اختباراتهم بالنصف الثاني.
  static Future<List<pw.Widget>> _improvedSection(SchoolClass c, List<Student> students) async {
    final rows = <List<String>>[];
    for (final s in students) {
      final h = (await ResultsRepo.recentPercents(s.id)).reversed.toList(); // الأقدم أولًا
      if (h.length < 4) continue;
      final half = h.length ~/ 2;
      final a = h.take(half).reduce((x, y) => x + y) / half;
      final b = h.skip(half).reduce((x, y) => x + y) / (h.length - half);
      if (b - a >= 15) rows.add([s.fullName, Ar.percent(a), Ar.percent(b), '+${(b - a).round()}']);
    }
    return [
      _section('تلاميذ تحسّن مستواهم'),
      if (rows.isEmpty)
        pw.Text('لا توجد معطيات كافية لرصد التحسن (يلزم 4 اختبارات على الأقل لكل تلميذ).')
      else
        _table(['الاسم الكامل', 'المتوسط في البداية', 'المتوسط مؤخرًا', 'التحسن'], rows, flex: [3, 1, 1, 1]),
    ];
  }

  // ---------------- تقرير المؤسسة ----------------

  static Future<Uint8List> schoolReport(Period p) async {
    final theme = await _theme();
    final header = await _header();
    final classes = await PeopleRepo.classes();
    final rows = <List<String>>[];
    var tStudents = 0, tPart = 0, tAttempts = 0;
    double sumAvg = 0;
    var avgN = 0;
    for (final c in classes) {
      final st = await ResultsRepo.classStats(c.id, p.start, p.end);
      final o = await RankingService.compute(c, p);
      final best = o.ranked.isEmpty ? '—' : (o.students[o.ranked.first.studentId]?.fullName ?? '—');
      rows.add([c.code, '${st.students}', '${st.participants}', Ar.percent(st.participation), '${st.attempts}',
          st.attempts == 0 ? '—' : Ar.percent(st.avgPercent), best]);
      tStudents += st.students;
      tPart += st.participants;
      tAttempts += st.attempts;
      if (st.attempts > 0) {
        sumAvg += st.avgPercent * st.attempts;
        avgN += st.attempts;
      }
    }
    final doc = pw.Document(title: 'تقرير المؤسسة — ${p.label}');
    doc.addPage(pw.MultiPage(
      theme: theme,
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1 ? header : pw.SizedBox(),
      footer: _footer,
      build: (ctx) => [
        _title('حصيلة القراءة بالمؤسسة', p.label),
        _table(['عدد التلاميذ', 'المشاركون', 'نسبة المشاركة', 'الاختبارات', 'متوسط الفهم'], [
          [
            '$tStudents',
            '$tPart',
            Ar.percent(tStudents == 0 ? 0 : tPart * 100 / tStudents),
            '$tAttempts',
            avgN == 0 ? '—' : Ar.percent(sumAvg / avgN),
          ]
        ]),
        _section('النتائج حسب القسم'),
        _table(['القسم', 'التلاميذ', 'المشاركون', 'المشاركة', 'الاختبارات', 'الفهم', 'أفضل قارئ'], rows,
            flex: [1.2, 1, 1, 1, 1, 1, 2.5]),
        _signatures(['المدير(ة)']),
      ],
    ));
    return doc.save();
  }

  // ---------------- الشهادات التقديرية ----------------

  static Future<Uint8List> certificates(List<CertificateData> list) async {
    final theme = await _theme();
    final school = await SchoolRepo.getSchool();
    final logo = await _logo(school);
    final official = (await SchoolRepo.getSetting(SchoolRepo.kShowOfficialHeader)) != '0';
    final ministry = (await SchoolRepo.getSetting(SchoolRepo.kMinistry)) ?? SchoolRepo.defaultMinistry;
    final doc = pw.Document(title: 'شواهد تقديرية');
    for (final d in list) {
      final g = d.student.gender;
      final who = Ar.byGender(g, 'التلميذ', 'التلميذة');
      String reason;
      switch (d.kind) {
        case 'improvement':
          reason = 'تقديرًا ${Ar.byGender(g, 'لتحسّنه', 'لتحسّنها')} الملحوظ في قراءة القصص وفهمها خلال ${d.period.label}.';
          break;
        case 'regularity':
          reason = 'تقديرًا ${Ar.byGender(g, 'لمواظبته', 'لمواظبتها')} على قراءة القصص خلال ${d.period.label}.';
          break;
        default:
          reason = 'تقديرًا ${Ar.byGender(g, 'لتفوقه', 'لتفوقها')} في قراءة القصص وفهمها، '
              '${Ar.byGender(g, 'وحصوله', 'وحصولها')} على المرتبة ${RankingService.rankWord(d.rank)} '
              'في القسم خلال ${d.period.label}.';
      }
      doc.addPage(pw.Page(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        build: (ctx) => pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _gold, width: 4)),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _green, width: 1.5)),
            padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 18),
            child: pw.Column(children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    if (official) pw.Text('المملكة المغربية', style: const pw.TextStyle(fontSize: 11)),
                    if (official) pw.Text(ministry, style: const pw.TextStyle(fontSize: 11)),
                    if (school != null && school.directorate.isNotEmpty)
                      pw.Text('المديرية الإقليمية: ${school.directorate}', style: const pw.TextStyle(fontSize: 11)),
                    if (school != null) pw.Text('المؤسسة: ${school.name}', style: const pw.TextStyle(fontSize: 11)),
                  ]),
                ),
                if (logo != null) pw.SizedBox(width: 70, height: 70, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              ]),
              pw.Spacer(),
              pw.Text('شهادة تقديرية', style: pw.TextStyle(fontSize: 44, fontWeight: pw.FontWeight.bold, color: _green)),
              pw.SizedBox(height: 14),
              pw.Text('تُمنح هذه الشهادة إلى $who:', style: const pw.TextStyle(fontSize: 18)),
              pw.SizedBox(height: 6),
              pw.Text(d.student.fullName, style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(height: 6),
              pw.Text('بالقسم ${d.cls.code} — ${d.cls.levelName.isNotEmpty ? d.cls.levelName : Ar.levelName(d.cls.level)}',
                  style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 12),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                child: pw.Text(reason, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 18)),
              ),
              pw.SizedBox(height: 6),
              pw.Text('متمنين ${Ar.byGender(g, 'له', 'لها')} مزيدًا من التألق في عالم القراءة.',
                  style: const pw.TextStyle(fontSize: 15, color: _grey)),
              pw.Spacer(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(children: [
                  pw.Text('الأستاذ(ة)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  if (d.cls.teacherName.isNotEmpty) pw.Text(d.cls.teacherName),
                  pw.SizedBox(height: 30),
                ]),
                pw.Column(children: [
                  pw.Text('حُرّر بتاريخ: ${Ar.formatDate(DateTime.now())}'),
                  pw.Text('رقم الشهادة: ${d.serial}', style: const pw.TextStyle(fontSize: 9, color: _grey)),
                ]),
                pw.Column(children: [
                  pw.Text('المدير(ة)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  if (school != null && school.directorName.isNotEmpty) pw.Text(school.directorName),
                  pw.SizedBox(height: 30),
                ]),
              ]),
            ]),
          ),
        ),
      ));
    }
    return doc.save();
  }

  /// إصدار شهادات أفضل ثلاثة قراء لفترة (تُسجل في قاعدة البيانات برقم تسلسلي).
  static Future<Uint8List?> topCertificates(SchoolClass c, Period p, String actor) async {
    final o = await RankingService.compute(c, p);
    final list = <CertificateData>[];
    for (final r in o.top3) {
      final s = o.students[r.studentId];
      if (s == null) continue;
      final serial = await ResultsRepo.issueCertificate(
        studentId: s.id,
        classId: c.id,
        kind: 'top',
        periodType: p.type,
        period: p.key,
        rank: r.rank,
        actor: actor,
      );
      list.add(CertificateData(s, c, 'top', r.rank, p, serial));
    }
    if (list.isEmpty) return null;
    return certificates(list);
  }

  /// شهادة تحسن أو مواظبة لتلميذ محدد.
  static Future<Uint8List> singleCertificate(Student s, SchoolClass c, String kind, Period p, String actor) async {
    final serial = await ResultsRepo.issueCertificate(
        studentId: s.id, classId: c.id, kind: kind, periodType: p.type, period: p.key, actor: actor);
    return certificates([CertificateData(s, c, kind, null, p, serial)]);
  }

  // ---------------- بطاقات الدخول للتلاميذ ----------------

  static Future<Uint8List> pinCards(SchoolClass c, Map<Student, String> pins) async {
    final theme = await _theme();
    final school = await SchoolRepo.getSchool();
    final entries = pins.entries.toList()..sort((a, b) => a.key.lastName.compareTo(b.key.lastName));
    final doc = pw.Document(title: 'بطاقات الدخول — ${c.code}');
    const perPage = 10;
    for (var i = 0; i < entries.length; i += perPage) {
      final chunk = entries.skip(i).take(perPage).toList();
      doc.addPage(pw.Page(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in chunk)
              pw.Container(
                width: 262,
                height: 140,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _green, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('مكتبتي الصفية — ${school?.name ?? ''}',
                      style: const pw.TextStyle(fontSize: 9, color: _grey)),
                  pw.Text(e.key.fullName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.Text('القسم: ${c.code}', style: const pw.TextStyle(fontSize: 11)),
                  pw.SizedBox(height: 6),
                  pw.Text('اسم المستخدم (رمز مسار): ${e.key.massarCode}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('كلمة السر: ${e.value}',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green)),
                  pw.Spacer(),
                  pw.Text('احتفظ ببطاقتك ولا تعطِ كلمة السر لأحد.', style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
                ]),
              ),
          ],
        ),
      ));
    }
    return doc.save();
  }

  // ---------------- ملصقات QR للقصص ----------------

  static Future<Uint8List> qrLabels(List<Story> stories) async {
    final theme = await _theme();
    final doc = pw.Document(title: 'ملصقات QR');
    const perPage = 12;
    for (var i = 0; i < stories.length; i += perPage) {
      final chunk = stories.skip(i).take(perPage).toList();
      doc.addPage(pw.Page(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => pw.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in chunk)
              pw.Container(
                width: 170,
                height: 190,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(children: [
                  pw.BarcodeWidget(data: s.qrData, barcode: pw.Barcode.qrCode(), width: 110, height: 110),
                  pw.SizedBox(height: 6),
                  pw.Text(s.title,
                      maxLines: 2,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('امسح الرمز للإجابة عن أسئلة القصة', style: const pw.TextStyle(fontSize: 8, color: _grey)),
                ]),
              ),
          ],
        ),
      ));
    }
    return doc.save();
  }

  // ---------------- العرض والطباعة ----------------

  static Future<void> printOrShare(Uint8List bytes, String name) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }

  static Future<void> share(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// للوصول إلى RankingEngine في مكان واحد عند الحاجة.
  static int suggest(List<double> p) => RankingEngine.suggestReadingLevel(p);
}
