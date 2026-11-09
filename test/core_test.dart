import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maktabati/core/arabic.dart';
import 'package:maktabati/core/security.dart';
import 'package:maktabati/data/models.dart';
import 'package:maktabati/services/ranking.dart';
import 'package:maktabati/services/scoring.dart';

void main() {
  group('التطبيع العربي', () {
    test('يحذف التشكيل ويوحد الهمزات والتاء المربوطة', () {
      expect(Ar.normalize('الأَرْنَبُ'), 'الارنب');
      expect(Ar.normalize('مدرسة  جميلة.'), 'مدرسه جميله');
      expect(Ar.normalize('إلى'), 'الي');
      expect(Ar.normalize('٣ قصص'), '3 قصص');
    });

    test('الموسم الدراسي الحالي', () {
      expect(Ar.currentSchoolYear(DateTime(2026, 11, 3)), '2026/2027');
      expect(Ar.currentSchoolYear(DateTime(2027, 3, 1)), '2026/2027');
    });
  });

  group('الأمان', () {
    test('تجزئة كلمة السر والتحقق منها', () {
      final h = Security.hashPassword('motdepasse1', iterations: 1000);
      expect(h.hash, isNot(contains('motdepasse1')));
      expect(Security.verifyPassword('motdepasse1', h.hash, h.salt, h.iterations), isTrue);
      expect(Security.verifyPassword('خطأ', h.hash, h.salt, h.iterations), isFalse);
      expect(Security.verifyPassword('x', null, null, null), isFalse);
    });

    test('رموز التلاميذ ليست سهلة التخمين', () {
      for (var i = 0; i < 200; i++) {
        final p = Security.generatePin(4);
        expect(p.length, 4);
        expect(p, isNot('1234'));
        expect(RegExp(r'^(\d)\1{3}$').hasMatch(p), isFalse);
      }
    });

    test('تشفير النسخة الاحتياطية وفك تشفيرها', () {
      final data = Uint8List.fromList(utf8.encode('SQLite format 3 — بيانات تجريبية'));
      final enc = Security.encrypt(data, 'كلمة-سر-قوية');
      expect(enc, isNot(equals(data)));
      expect(Security.decrypt(enc, 'كلمة-سر-قوية'), equals(data));
      expect(() => Security.decrypt(enc, 'خاطئة'), throwsA(isA<FormatException>()));
    });

    test('معرّف فريد بصيغة UUID', () {
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(Security.uuid()),
          isTrue);
    });
  });

  group('التصحيح', () {
    Question q(QType t, List<(int, String, bool)> opts, {String keywords = ''}) => Question(
          id: 1,
          type: t,
          prompt: 'سؤال',
          keywords: keywords,
          options: [
            for (var i = 0; i < opts.length; i++)
              AnswerOption(id: opts[i].$1, position: i, label: opts[i].$2, isCorrect: opts[i].$3),
          ],
        );

    test('اختيار من متعدد', () {
      final x = q(QType.single, [(10, 'أ', true), (11, 'ب', false)]);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [10])).correct, isTrue);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [11])).points, 0);
      expect(Grader.grade(x, const StudentAnswer()).points, 0);
    });

    test('خانات اختيار: جزئي وكامل', () {
      final x = q(QType.multi, [(1, 'أ', true), (2, 'ب', true), (3, 'ج', false)]);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [1, 2])).correct, isTrue);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [1])).points, 0.5);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [1, 3])).points, 0);
    });

    test('ترتيب الأحداث', () {
      final x = q(QType.order, [(1, 'أول', false), (2, 'ثان', false), (3, 'ثالث', false)]);
      expect(Grader.grade(x, const StudentAnswer(optionIds: [1, 2, 3])).correct, isTrue);
      final partial = Grader.grade(x, const StudentAnswer(optionIds: [1, 3, 2]));
      expect(partial.correct, isFalse);
      expect(partial.points, closeTo(1 / 3, 0.001));
    });

    test('جواب قصير بالكلمات المفتاحية مع مراجعة الأستاذ', () {
      final x = q(QType.short, [], keywords: 'الصبر، التعاون');
      final ok = Grader.grade(x, const StudentAnswer(text: 'تعلمت الصَّبر'));
      expect(ok.correct, isTrue);
      expect(ok.needsReview, isFalse);
      final unsure = Grader.grade(x, const StudentAnswer(text: 'أن لا أستسلم'));
      expect(unsure.correct, isFalse);
      expect(unsure.needsReview, isTrue);
    });

    test('ترتيب عشوائي ثابت لنفس المحاولة', () {
      final items = List<int>.generate(10, (i) => i);
      expect(Grader.seededShuffle(items, 'abc'), equals(Grader.seededShuffle(items, 'abc')));
    });

    test('التحقق من صلاحية السؤال', () {
      expect(q(QType.single, [(1, 'أ', false), (2, 'ب', false)]).validate(), isNotNull);
      expect(q(QType.single, [(1, 'أ', true), (2, 'ب', false)]).validate(), isNull);
      expect(Question(type: QType.short, prompt: 'لماذا؟').validate(), isNull);
    });
  });

  group('الترتيب', () {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 12, 1);
    DateTime d(int day) => DateTime(2026, 11, day, 10);

    test('شروط التأهل والترتيب والتعادل', () {
      final cfg = RankingConfig(minStoriesMonthly: 2, passPercent: 50, targetStoriesMonthly: 4);
      final records = [
        // التلميذ 1: 3 قصص ممتازة
        PerfRecord(1, 100, 90, d(2)), PerfRecord(1, 101, 95, d(9)), PerfRecord(1, 102, 85, d(16)),
        // التلميذ 2: قصتان متوسطتان
        PerfRecord(2, 100, 60, d(3)), PerfRecord(2, 101, 70, d(4)),
        // التلميذ 3: قصة واحدة فقط ← غير مؤهل
        PerfRecord(3, 100, 100, d(5)),
        // التلميذ 4: محاولتان للقصة نفسها ← تُحتسب الأفضل مرة واحدة
        PerfRecord(4, 100, 40, d(5)), PerfRecord(4, 100, 80, d(6)), PerfRecord(4, 101, 65, d(20)),
        // خارج الفترة ← لا يُحتسب
        PerfRecord(2, 103, 100, DateTime(2026, 10, 30)),
      ];
      final rows = RankingEngine.compute(
          studentIds: [1, 2, 3, 4, 5], records: records, config: cfg, start: start, end: end, annual: false);
      final byId = {for (final r in rows) r.studentId: r};
      expect(rows.first.studentId, 1);
      expect(byId[1]!.rank, 1);
      expect(byId[3]!.qualified, isFalse);
      expect(byId[3]!.rank, isNull);
      expect(byId[5]!.attemptedStories, 0);
      expect(byId[4]!.attemptedStories, 2);
      expect(byId[4]!.avgPercent, closeTo(72.5, 0.01));
      expect(byId[2]!.attemptedStories, 2);
    });

    test('تعادل تام ← نفس المرتبة', () {
      final cfg = RankingConfig(minStoriesMonthly: 1);
      final t = d(10);
      final rows = RankingEngine.compute(
        studentIds: [1, 2, 3],
        records: [PerfRecord(1, 1, 80, t), PerfRecord(2, 1, 80, t), PerfRecord(3, 1, 50, t)],
        config: cfg,
        start: start,
        end: end,
        annual: false,
      );
      final byId = {for (final r in rows) r.studentId: r};
      expect(byId[1]!.rank, 1);
      expect(byId[2]!.rank, 1);
      expect(byId[3]!.rank, 3);
    });

    test('حفظ المعايير واسترجاعها', () {
      final c = RankingConfig(minStoriesMonthly: 5, wComprehension: 70);
      final back = RankingConfig.fromJson(c.toJson());
      expect(back.minStoriesMonthly, 5);
      expect(back.wComprehension, 70);
      expect(RankingConfig.fromJson('غير صالح').passPercent, RankingConfig().passPercent);
    });

    test('اقتراح وصف القارئ يتطلب 3 اختبارات', () {
      expect(RankingEngine.suggestReadingLevel([90, 95]), -1);
      expect(RankingEngine.suggestReadingLevel([90, 95, 88]), 5);
      expect(RankingEngine.suggestReadingLevel([30, 35, 20]), 1);
    });
  });

  group('النماذج', () {
    test('رمز QR يعرّف القصة فقط', () {
      final s = Story(id: 1, title: 'قصة', qrToken: 'ABC123');
      expect(s.qrData, 'SCL1:ABC123');
      expect(Story.tokenFromQr(s.qrData), 'ABC123');
      expect(Story.tokenFromQr('https://example.com'), isNull);
    });

    test('ترميز جواب التلميذ', () {
      const a = StudentAnswer(optionIds: [3, 1], text: 'نص');
      final b = StudentAnswer.fromJson(a.toJson());
      expect(b.optionIds, [3, 1]);
      expect(b.text, 'نص');
      expect(StudentAnswer.fromJson('{خطأ').isEmpty, isTrue);
    });
  });
}
