import 'dart:math';

import '../core/arabic.dart';
import '../data/models.dart';

class GradeResult {
  final double points;
  final double max;
  final bool correct;
  final bool needsReview;
  const GradeResult(this.points, this.max, this.correct, {this.needsReview = false});
}

/// تصحيح الأجوبة محليًا (دون إنترنت).
class Grader {
  Grader._();

  static GradeResult grade(Question q, StudentAnswer a) {
    final max = q.points.toDouble();
    switch (q.type) {
      case QType.single:
      case QType.truefalse:
      case QType.image:
      case QType.complete:
        {
          final correctIds = q.options.where((o) => o.isCorrect).map((o) => o.id).whereType<int>().toSet();
          final ok = a.optionIds.length == 1 && correctIds.contains(a.optionIds.first);
          return GradeResult(ok ? max : 0, max, ok);
        }
      case QType.multi:
        {
          final c = q.options.where((o) => o.isCorrect).map((o) => o.id).whereType<int>().toSet();
          final s = a.optionIds.toSet();
          if (c.isEmpty) return GradeResult(0, max, false);
          final tp = s.intersection(c).length;
          final fp = s.difference(c).length;
          final frac = max0((tp - fp) / c.length);
          final ok = tp == c.length && fp == 0;
          return GradeResult(ok ? max : max * frac, max, ok);
        }
      case QType.order:
        {
          // الترتيب الصحيح هو ترتيب الاختيارات كما حفظها الأستاذ (position).
          final correct = [...q.options]..sort((x, y) => x.position.compareTo(y.position));
          final ids = correct.map((o) => o.id).toList();
          if (ids.isEmpty || a.optionIds.length != ids.length) return GradeResult(0, max, false);
          var good = 0;
          for (var i = 0; i < ids.length; i++) {
            if (a.optionIds[i] == ids[i]) good++;
          }
          final ok = good == ids.length;
          return GradeResult(ok ? max : max * good / ids.length, max, ok);
        }
      case QType.short:
        {
          final ans = Ar.normalize(a.text);
          if (ans.isEmpty) return GradeResult(0, max, false);
          final kws = q.keywordList.map(Ar.normalize).where((k) => k.isNotEmpty).toList();
          final matched = kws.any((k) => ans.contains(k));
          // إذا لم تتطابق الكلمات المفتاحية، يراجع الأستاذ الجواب (قد يكون صحيحًا بصيغة أخرى).
          return GradeResult(matched ? max : 0, max, matched, needsReview: !matched);
        }
    }
    // ignore: dead_code
    return GradeResult(0, max, false);
  }

  static double max0(double v) => v < 0 ? 0.0 : v;

  /// عدد النجوم المعروض للتلميذ (تشجيعي، دون كشف الأجوبة).
  static int stars(double percent) {
    if (percent >= 85) return 3;
    if (percent >= 60) return 2;
    if (percent >= 30) return 1;
    return 0;
  }

  static String encouragement(double percent) {
    if (percent >= 85) return 'ممتاز! يبدو أنك قرأت القصة بتمعن.';
    if (percent >= 60) return 'أحسنت! فهمت القصة جيدًا.';
    if (percent >= 30) return 'مجهود طيب! أعد قراءة القصة لتفهمها أكثر.';
    return 'شكرًا على مشاركتك! اقرأ القصة مرة أخرى وستنجح.';
  }

  /// ترتيب عشوائي ثابت لنفس المحاولة (حتى يجد التلميذ الترتيب نفسه عند الاستئناف).
  static List<T> seededShuffle<T>(List<T> items, String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final list = [...items];
    list.shuffle(Random(h));
    return list;
  }

  /// العدد المقترح للأسئلة حسب المستوى (قابل للتعديل من طرف الأستاذ).
  static int suggestedQuestionCount(int level) {
    if (level <= 2) return 5;
    if (level <= 4) return 7;
    return 8;
  }
}
