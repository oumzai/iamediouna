import 'dart:convert';

/// معايير الترتيب — قابلة للتعديل من طرف المدير والأستاذ، ويُحفظ كل إصدار منها.
/// لا توجد أوزان ثابتة مفروضة: هذه فقط قيم افتراضية أولية.
class RankingConfig {
  /// شروط التأهل
  int minStoriesMonthly;
  int minStoriesAnnual;

  /// نسبة النجاح في اختبار قصة (تُحتسب القصة «منجزة» عند بلوغها).
  int passPercent;

  /// العدد المستهدف من القصص (لحساب نقطة «عدد القصص»).
  int targetStoriesMonthly;
  int targetStoriesAnnual;

  /// الأوزان (تُطبّع تلقائيًا إلى 100%).
  int wComprehension;
  int wStories;
  int wRegularity;

  RankingConfig({
    this.minStoriesMonthly = 3,
    this.minStoriesAnnual = 15,
    this.passPercent = 50,
    this.targetStoriesMonthly = 8,
    this.targetStoriesAnnual = 50,
    this.wComprehension = 50,
    this.wStories = 30,
    this.wRegularity = 20,
  });

  factory RankingConfig.fromJson(String? s) {
    final c = RankingConfig();
    if (s == null || s.isEmpty) return c;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      int g(String k, int d) => (m[k] is num) ? (m[k] as num).round() : d;
      return RankingConfig(
        minStoriesMonthly: g('minStoriesMonthly', c.minStoriesMonthly),
        minStoriesAnnual: g('minStoriesAnnual', c.minStoriesAnnual),
        passPercent: g('passPercent', c.passPercent),
        targetStoriesMonthly: g('targetStoriesMonthly', c.targetStoriesMonthly),
        targetStoriesAnnual: g('targetStoriesAnnual', c.targetStoriesAnnual),
        wComprehension: g('wComprehension', c.wComprehension),
        wStories: g('wStories', c.wStories),
        wRegularity: g('wRegularity', c.wRegularity),
      );
    } catch (_) {
      return c;
    }
  }

  Map<String, int> toMap() => {
        'minStoriesMonthly': minStoriesMonthly,
        'minStoriesAnnual': minStoriesAnnual,
        'passPercent': passPercent,
        'targetStoriesMonthly': targetStoriesMonthly,
        'targetStoriesAnnual': targetStoriesAnnual,
        'wComprehension': wComprehension,
        'wStories': wStories,
        'wRegularity': wRegularity,
      };

  String toJson() => jsonEncode(toMap());

  RankingConfig copy() => RankingConfig.fromJson(toJson());

  /// تصحيح القيم غير المنطقية.
  RankingConfig sanitized() {
    final c = copy();
    c.passPercent = c.passPercent.clamp(0, 100).toInt();
    c.minStoriesMonthly = c.minStoriesMonthly.clamp(0, 100).toInt();
    c.minStoriesAnnual = c.minStoriesAnnual.clamp(0, 1000).toInt();
    c.targetStoriesMonthly = c.targetStoriesMonthly.clamp(1, 100).toInt();
    c.targetStoriesAnnual = c.targetStoriesAnnual.clamp(1, 1000).toInt();
    c.wComprehension = c.wComprehension.clamp(0, 100).toInt();
    c.wStories = c.wStories.clamp(0, 100).toInt();
    c.wRegularity = c.wRegularity.clamp(0, 100).toInt();
    if (c.wComprehension + c.wStories + c.wRegularity == 0) c.wComprehension = 100;
    return c;
  }

  String describe({bool annual = false}) {
    final total = wComprehension + wStories + wRegularity;
    String pct(int w) => total == 0 ? '0%' : '${(w * 100 / total).round()}%';
    final min = annual ? minStoriesAnnual : minStoriesMonthly;
    return 'التأهل: إنجاز $min قصص على الأقل (نجاح ≥ $passPercent%). '
        'الترتيب: الفهم ${pct(wComprehension)}، عدد القصص ${pct(wStories)}، الانتظام ${pct(wRegularity)}. '
        'عند التعادل: الأعلى فهمًا، ثم الأكثر قصصًا، ثم الأسبق إنجازًا.';
  }
}

/// أفضل نتيجة لتلميذ في قصة (أو محاولة مكتملة).
class PerfRecord {
  final int studentId;
  final int storyId;
  final double percent;
  final DateTime finishedAt;
  const PerfRecord(this.studentId, this.storyId, this.percent, this.finishedAt);
}

class RankRow {
  final int studentId;
  final int passedStories;
  final int attemptedStories;
  final double avgPercent;
  final double regularity; // 0..1
  final double score; // 0..100
  final bool qualified;
  final DateTime? lastAt;
  int? rank;

  RankRow({
    required this.studentId,
    required this.passedStories,
    required this.attemptedStories,
    required this.avgPercent,
    required this.regularity,
    required this.score,
    required this.qualified,
    this.lastAt,
    this.rank,
  });

  Map<String, Object?> toMap() => {
        'studentId': studentId,
        'passed': passedStories,
        'attempted': attemptedStories,
        'avg': double.parse(avgPercent.toStringAsFixed(2)),
        'regularity': double.parse(regularity.toStringAsFixed(3)),
        'score': double.parse(score.toStringAsFixed(2)),
        'qualified': qualified,
        'rank': rank,
        'lastAt': lastAt?.toIso8601String(),
      };

  factory RankRow.fromMap(Map<String, dynamic> m) => RankRow(
        studentId: (m['studentId'] as num).toInt(),
        passedStories: (m['passed'] as num? ?? 0).toInt(),
        attemptedStories: (m['attempted'] as num? ?? 0).toInt(),
        avgPercent: (m['avg'] as num? ?? 0).toDouble(),
        regularity: (m['regularity'] as num? ?? 0).toDouble(),
        score: (m['score'] as num? ?? 0).toDouble(),
        qualified: m['qualified'] == true,
        rank: (m['rank'] as num?)?.toInt(),
        lastAt: m['lastAt'] == null ? null : DateTime.tryParse('${m['lastAt']}'),
      );
}

class RankingEngine {
  RankingEngine._();

  /// يحسب الترتيب لفترة [start, end). [records] = المحاولات المكتملة في الفترة.
  /// كل قصة تُحتسب مرة واحدة بأفضل نتيجة.
  static List<RankRow> compute({
    required List<int> studentIds,
    required List<PerfRecord> records,
    required RankingConfig config,
    required DateTime start,
    required DateTime end,
    required bool annual,
  }) {
    final cfg = config.sanitized();
    final byStudent = <int, Map<int, PerfRecord>>{};
    for (final r in records) {
      if (r.finishedAt.isBefore(start) || !r.finishedAt.isBefore(end)) continue;
      final m = byStudent.putIfAbsent(r.studentId, () => {});
      final prev = m[r.storyId];
      if (prev == null || r.percent > prev.percent ||
          (r.percent == prev.percent && r.finishedAt.isBefore(prev.finishedAt))) {
        m[r.storyId] = r;
      }
    }

    final totalW = (cfg.wComprehension + cfg.wStories + cfg.wRegularity).toDouble();
    final minStories = annual ? cfg.minStoriesAnnual : cfg.minStoriesMonthly;
    final target = annual ? cfg.targetStoriesAnnual : cfg.targetStoriesMonthly;

    // عدد الأسابيع (شهري) أو الأشهر (سنوي) في الفترة
    final days = end.difference(start).inDays.clamp(1, 100000).toInt();
    final buckets = annual ? _monthsBetween(start, end) : ((days + 6) ~/ 7);

    final rows = <RankRow>[];
    for (final sid in studentIds) {
      final perStory = byStudent[sid]?.values.toList() ?? const <PerfRecord>[];
      if (perStory.isEmpty) {
        rows.add(RankRow(
          studentId: sid, passedStories: 0, attemptedStories: 0, avgPercent: 0,
          regularity: 0, score: 0, qualified: false,
        ));
        continue;
      }
      final passed = perStory.where((p) => p.percent >= cfg.passPercent).length;
      final avg = perStory.fold<double>(0, (s, p) => s + p.percent) / perStory.length;
      final active = <int>{};
      DateTime? last;
      for (final p in perStory) {
        final b = annual
            ? (p.finishedAt.year - start.year) * 12 + (p.finishedAt.month - start.month)
            : p.finishedAt.difference(start).inDays ~/ 7;
        active.add(b);
        if (last == null || p.finishedAt.isAfter(last)) last = p.finishedAt;
      }
      final double regularity = (active.length / (buckets == 0 ? 1 : buckets)).clamp(0.0, 1.0).toDouble();
      final double storiesScore = (passed / target).clamp(0.0, 1.0).toDouble() * 100;
      final double score = (cfg.wComprehension * avg + cfg.wStories * storiesScore + cfg.wRegularity * regularity * 100) /
          totalW;
      rows.add(RankRow(
        studentId: sid,
        passedStories: passed,
        attemptedStories: perStory.length,
        avgPercent: avg,
        regularity: regularity,
        score: score,
        qualified: passed >= minStories && passed > 0,
        lastAt: last,
      ));
    }

    int cmp(RankRow a, RankRow b) {
      if (a.qualified != b.qualified) return a.qualified ? -1 : 1;
      final s = _r(b.score).compareTo(_r(a.score));
      if (s != 0) return s;
      final av = _r(b.avgPercent).compareTo(_r(a.avgPercent));
      if (av != 0) return av;
      final p = b.passedStories.compareTo(a.passedStories);
      if (p != 0) return p;
      final la = a.lastAt, lb = b.lastAt;
      if (la != null && lb != null) return la.compareTo(lb); // الأسبق إنجازًا أولًا
      return 0;
    }

    rows.sort(cmp);
    int? prevRank;
    RankRow? prev;
    var position = 0;
    for (final r in rows) {
      if (!r.qualified) break;
      position++;
      if (prev != null && cmp(prev, r) == 0) {
        r.rank = prevRank;
      } else {
        r.rank = position;
      }
      prevRank = r.rank;
      prev = r;
    }
    return rows;
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;

  static int _monthsBetween(DateTime start, DateTime end) {
    final m = (end.year - start.year) * 12 + (end.month - start.month) + (end.day > 1 ? 1 : 0);
    return m < 1 ? 1 : m;
  }

  /// اقتراح وصف القارئ من آخر النتائج (يتطلب 3 اختبارات على الأقل).
  /// يُرجع -1 إذا كانت المعطيات غير كافية. القيم 1..5 حسب Ar.readingLevels.
  static int suggestReadingLevel(List<double> percentsNewestFirst) {
    if (percentsNewestFirst.length < 3) return -1;
    final recent = percentsNewestFirst.take(5).toList();
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    if (avg < 40) return 1;
    if (avg < 55) return 2;
    if (avg < 70) return 3;
    if (avg < 85) return 4;
    return 5;
  }
}
