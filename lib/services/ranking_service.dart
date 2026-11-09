import '../core/arabic.dart';
import '../data/models.dart';
import '../data/people_repo.dart';
import '../data/results_repo.dart';
import '../data/school_repo.dart';
import 'ranking.dart';

/// فترة الترتيب: شهر (YYYY-MM) أو موسم كامل.
class Period {
  final String type; // monthly | annual
  final String key; // 2026-11 | 2026/2027
  final DateTime start;
  final DateTime end;
  final String label;
  Period._(this.type, this.key, this.start, this.end, this.label);

  factory Period.month(int year, int month) {
    final s = DateTime(year, month, 1);
    return Period._('monthly', '$year-${month.toString().padLeft(2, '0')}', s, DateTime(year, month + 1, 1),
        'شهر ${Ar.monthName(month)} $year');
  }

  factory Period.year(AcademicYear y) =>
      Period._('annual', y.label, y.start, y.end, 'الموسم الدراسي ${y.label}');

  bool get annual => type == 'annual';

  /// أشهر الموسم الدراسي (شتنبر ← يونيو) حتى الشهر الحالي.
  static List<Period> monthsOf(AcademicYear y) {
    final now = DateTime.now();
    final out = <Period>[];
    for (var i = 0; i < 10; i++) {
      final d = DateTime(y.startYear, 9 + i, 1);
      if (d.isAfter(now)) break;
      out.add(Period.month(d.year, d.month));
    }
    if (out.isEmpty) out.add(Period.month(now.year, now.month));
    return out;
  }
}

class RankingOutcome {
  final List<RankRow> rows;
  final Map<int, Student> students;
  final CriteriaVersion criteria;
  final bool fromSnapshot;
  final String? snapshotDate;
  RankingOutcome(this.rows, this.students, this.criteria, this.fromSnapshot, this.snapshotDate);

  List<RankRow> get ranked => rows.where((r) => r.rank != null).toList();
  List<RankRow> get top3 => ranked.where((r) => (r.rank ?? 99) <= 3).toList();
}

class RankingService {
  RankingService._();

  /// إذا اعتُمدت نتائج الفترة سابقًا تُستعمل اللقطة المحفوظة (لا تتغير النتائج التاريخية).
  /// [live] = true لإعادة الحساب بالمعايير الحالية.
  static Future<RankingOutcome> compute(SchoolClass c, Period p, {bool live = false}) async {
    final studentsList = await PeopleRepo.students(c.id, includeArchived: true);
    final students = {for (final s in studentsList) s.id: s};
    if (!live) {
      final snap = await ResultsRepo.snapshot(c.id, p.type, p.key);
      if (snap != null) {
        final crit = await ResultsRepo.criteriaById(snap['criteria_id'] as int) ??
            await ResultsRepo.effectiveCriteria(c.id);
        return RankingOutcome(ResultsRepo.snapshotRows(snap), students, crit, true, snap['created_at'] as String?);
      }
    }
    final crit = await ResultsRepo.effectiveCriteria(c.id);
    final records = await ResultsRepo.perfRecords(c.id, p.start, p.end);
    final active = studentsList.where((s) => !s.archived).map((s) => s.id).toSet();
    // التلاميذ المؤرشفون الذين لهم نتائج في الفترة يبقون ضمن الحساب
    for (final r in records) {
      active.add(r.studentId);
    }
    final now = DateTime.now();
    final end = p.end.isAfter(now) ? DateTime(now.year, now.month, now.day + 1) : p.end;
    final rows = RankingEngine.compute(
      studentIds: active.toList(),
      records: records,
      config: crit.config,
      start: p.start,
      end: end,
      annual: p.annual,
    );
    return RankingOutcome(rows, students, crit, false, null);
  }

  static Future<void> approve(SchoolClass c, Period p, String actor) async {
    final o = await compute(c, p, live: true);
    await ResultsRepo.saveSnapshot(c.id, p.type, p.key, o.criteria.id, o.rows, actor);
  }

  static String rankWord(int? rank) {
    switch (rank) {
      case 1:
        return 'الأولى';
      case 2:
        return 'الثانية';
      case 3:
        return 'الثالثة';
      default:
        return rank == null ? '—' : '$rank';
    }
  }

  /// متوسط اقتراح وصف القارئ.
  static Future<int> suggestedLevel(int studentId) async =>
      RankingEngine.suggestReadingLevel(await ResultsRepo.recentPercents(studentId));

  static Future<AcademicYear> year() => SchoolRepo.currentYear();
}
