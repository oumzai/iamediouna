import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/security.dart';
import '../services/ranking.dart';
import '../services/scoring.dart';
import 'db.dart';
import 'models.dart';
import 'school_repo.dart';

class ClassStats {
  final int students;
  final int participants;
  final int attempts;
  final double avgPercent;
  final int storiesAssigned;
  ClassStats(this.students, this.participants, this.attempts, this.avgPercent, this.storiesAssigned);
  double get participation => students == 0 ? 0.0 : participants * 100 / students;
}

class SeriesPoint {
  final String label;
  final int attempts;
  final int participants;
  final double avg;
  SeriesPoint(this.label, this.attempts, this.participants, this.avg);
}

class CriteriaVersion {
  final int id;
  final String scope;
  final RankingConfig config;
  final String createdAt;
  final String createdBy;
  final String note;
  final bool active;
  CriteriaVersion(this.id, this.scope, this.config, this.createdAt, this.createdBy, this.note, this.active);
}

/// المحاولات والأجوبة والتصحيح والإحصائيات ومعايير الترتيب والشهادات.
class ResultsRepo {
  ResultsRepo._();

  static Database get _db => AppDb.I.db;

  static String _iso(DateTime d) => d.toIso8601String();

  // ---------------- المحاولات ----------------

  static Future<Attempt?> inProgress(int studentId, int quizId) async {
    final r = await _db.query('quiz_attempts',
        where: "student_id = ? AND quiz_id = ? AND status = 'in_progress'",
        whereArgs: [studentId, quizId],
        orderBy: 'started_at DESC',
        limit: 1);
    return r.isEmpty ? null : Attempt.fromMap(r.first);
  }

  static Future<int> completedCount(int studentId, int quizId) async {
    final r = await _db.rawQuery(
        "SELECT COUNT(*) AS n FROM quiz_attempts WHERE student_id = ? AND quiz_id = ? AND status = 'completed'",
        [studentId, quizId]);
    return r.first['n'] as int;
  }

  /// هل أنجز التلميذ اختبار هذه القصة (أي اختبار لها)؟ ← أفضل نسبة أو null
  static Future<double?> bestForStory(int studentId, int storyId) async {
    final r = await _db.rawQuery(
        "SELECT MAX(percent) AS p FROM quiz_attempts WHERE student_id = ? AND story_id = ? AND status = 'completed'",
        [studentId, storyId]);
    final p = r.first['p'];
    return p == null ? null : (p as num).toDouble();
  }

  static Future<int> allowedAttempts(int studentId, int quizId) async {
    final r = await _db.query('retake_grants', where: 'student_id = ? AND quiz_id = ?', whereArgs: [studentId, quizId]);
    return 1 + (r.isEmpty ? 0 : r.first['extra'] as int);
  }

  /// رسالة المنع أو null إذا كان مسموحًا ببدء/استئناف الاختبار.
  static Future<String?> canStart(int studentId, int quizId) async {
    if (await inProgress(studentId, quizId) != null) return null;
    final done = await completedCount(studentId, quizId);
    final allowed = await allowedAttempts(studentId, quizId);
    if (done >= allowed) return 'لقد أنجزت هذا الاختبار. يمكن لأستاذك أن يسمح لك بمحاولة جديدة.';
    return null;
  }

  static Future<void> grantRetake(int studentId, int quizId, String actor) async {
    final r = await _db.query('retake_grants', where: 'student_id = ? AND quiz_id = ?', whereArgs: [studentId, quizId]);
    if (r.isEmpty) {
      await _db.insert('retake_grants', {'student_id': studentId, 'quiz_id': quizId, 'extra': 1});
    } else {
      await _db.update('retake_grants', {'extra': (r.first['extra'] as int) + 1},
          where: 'student_id = ? AND quiz_id = ?', whereArgs: [studentId, quizId]);
    }
    await SchoolRepo.audit(actor, 'السماح بمحاولة جديدة', 'تلميذ $studentId، اختبار $quizId');
  }

  static Future<Attempt> startOrResume(Student s, Quiz q, int classId) async {
    final existing = await inProgress(s.id, q.id);
    if (existing != null) return existing;
    final year = await SchoolRepo.currentYear();
    final r = await _db.rawQuery('SELECT MAX(attempt_no) AS m FROM quiz_attempts WHERE student_id = ? AND quiz_id = ?',
        [s.id, q.id]);
    final no = ((r.first['m'] as int?) ?? 0) + 1;
    final id = Security.uuid();
    final now = DateTime.now();
    await _db.insert('quiz_attempts', {
      'id': id,
      'student_id': s.id,
      'quiz_id': q.id,
      'story_id': q.storyId,
      'class_id': classId,
      'year_id': year.id,
      'attempt_no': no,
      'started_at': _iso(now),
      'status': 'in_progress',
      'device_id': 'tablet',
    });
    return Attempt(id: id, studentId: s.id, quizId: q.id, storyId: q.storyId, classId: classId,
        attemptNo: no, startedAt: now);
  }

  static Future<Map<int, StudentAnswer>> answersFor(String attemptId) async {
    final r = await _db.query('student_answers', where: 'attempt_id = ?', whereArgs: [attemptId]);
    return {for (final m in r) m['question_id'] as int: StudentAnswer.fromJson(m['answer'] as String?)};
  }

  /// حفظ الجواب فور اختياره (لا يضيع شيء إذا انقطع التطبيق).
  static Future<void> saveAnswer(String attemptId, int questionId, StudentAnswer a) async {
    await _db.insert(
      'student_answers',
      {'attempt_id': attemptId, 'question_id': questionId, 'answer': a.toJson()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Attempt> finishAttempt(Attempt attempt, List<Question> questions) async {
    final answers = await answersFor(attempt.id);
    double score = 0, max = 0;
    var review = false;
    final now = DateTime.now();
    await _db.transaction((txn) async {
      for (final q in questions) {
        final a = answers[q.id] ?? const StudentAnswer();
        final g = Grader.grade(q, a);
        score += g.points;
        max += g.max;
        if (g.needsReview) review = true;
        await txn.insert(
          'student_answers',
          {
            'attempt_id': attempt.id,
            'question_id': q.id,
            'answer': a.toJson(),
            'is_correct': g.correct ? 1 : 0,
            'points': g.points,
            'needs_review': g.needsReview ? 1 : 0,
            'reviewed': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final percent = max == 0 ? 0.0 : score * 100 / max;
      await txn.update(
        'quiz_attempts',
        {
          'finished_at': _iso(now),
          'duration_sec': now.difference(attempt.startedAt).inSeconds,
          'score': score,
          'max_score': max,
          'percent': percent,
          'status': 'completed',
          'needs_review': review ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [attempt.id],
      );
    });
    return Attempt(
      id: attempt.id,
      studentId: attempt.studentId,
      quizId: attempt.quizId,
      storyId: attempt.storyId,
      classId: attempt.classId,
      attemptNo: attempt.attemptNo,
      startedAt: attempt.startedAt,
      finishedAt: now,
      score: score,
      maxScore: max,
      percent: max == 0 ? 0.0 : score * 100 / max,
      status: 'completed',
      needsReview: review,
    );
  }

  // ---------------- مراجعة الأجوبة القصيرة ----------------

  static Future<List<Map<String, Object?>>> pendingReviews(int classId) => _db.rawQuery('''
      SELECT a.id AS answer_id, a.attempt_id, a.answer, a.points, q.prompt, q.keywords, q.points AS max_points,
             s.first_name, s.last_name, st.title AS story_title, t.finished_at
      FROM student_answers a
      JOIN quiz_attempts t ON t.id = a.attempt_id
      JOIN questions q ON q.id = a.question_id
      JOIN students s ON s.id = t.student_id
      JOIN stories st ON st.id = t.story_id
      WHERE t.class_id = ? AND a.needs_review = 1 AND a.reviewed = 0
      ORDER BY t.finished_at DESC''', [classId]);

  static Future<int> pendingReviewCount(int classId) async {
    final r = await _db.rawQuery('''SELECT COUNT(*) AS n FROM student_answers a JOIN quiz_attempts t ON t.id = a.attempt_id
        WHERE t.class_id = ? AND a.needs_review = 1 AND a.reviewed = 0''', [classId]);
    return r.first['n'] as int;
  }

  static Future<void> setReview(int answerId, bool correct, String actor) async {
    await _db.transaction((txn) async {
      final r = await txn.rawQuery('''SELECT a.attempt_id, q.points AS max_points FROM student_answers a
          JOIN questions q ON q.id = a.question_id WHERE a.id = ?''', [answerId]);
      if (r.isEmpty) return;
      final attemptId = r.first['attempt_id'] as String;
      final maxPts = (r.first['max_points'] as num).toDouble();
      await txn.update('student_answers',
          {'is_correct': correct ? 1 : 0, 'points': correct ? maxPts : 0, 'reviewed': 1, 'needs_review': 0},
          where: 'id = ?', whereArgs: [answerId]);
      final tot = await txn.rawQuery(
          'SELECT SUM(points) AS s FROM student_answers WHERE attempt_id = ?', [attemptId]);
      final score = ((tot.first['s'] as num?) ?? 0).toDouble();
      final at = await txn.query('quiz_attempts', columns: ['max_score'], where: 'id = ?', whereArgs: [attemptId]);
      final max = ((at.first['max_score'] as num?) ?? 0).toDouble();
      final pending = await txn.rawQuery(
          'SELECT COUNT(*) AS n FROM student_answers WHERE attempt_id = ? AND needs_review = 1 AND reviewed = 0',
          [attemptId]);
      await txn.update(
          'quiz_attempts',
          {
            'score': score,
            'percent': max == 0 ? 0 : score * 100 / max,
            'needs_review': (pending.first['n'] as int) > 0 ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [attemptId]);
      await txn.insert('audit_log', {
        'ts': AppDb.now(),
        'actor': actor,
        'action': 'تصحيح جواب قصير',
        'details': 'جواب $answerId ← ${correct ? 'صحيح' : 'خاطئ'}',
      });
    });
  }

  // ---------------- الإحصائيات ----------------

  static Future<List<PerfRecord>> perfRecords(int classId, DateTime start, DateTime end) async {
    final r = await _db.rawQuery('''
      SELECT student_id, story_id, percent, finished_at FROM quiz_attempts
      WHERE class_id = ? AND status = 'completed' AND finished_at >= ? AND finished_at < ?''',
        [classId, _iso(start), _iso(end)]);
    return r
        .map((m) => PerfRecord(m['student_id'] as int, m['story_id'] as int, (m['percent'] as num).toDouble(),
            DateTime.parse(m['finished_at'] as String)))
        .toList();
  }

  static Future<ClassStats> classStats(int classId, DateTime start, DateTime end) async {
    final st = await _db.rawQuery('SELECT COUNT(*) AS n FROM students WHERE class_id = ? AND archived = 0', [classId]);
    final a = await _db.rawQuery('''
      SELECT COUNT(*) AS n, COUNT(DISTINCT student_id) AS p, AVG(percent) AS avg FROM quiz_attempts
      WHERE class_id = ? AND status = 'completed' AND finished_at >= ? AND finished_at < ?''',
        [classId, _iso(start), _iso(end)]);
    final sa = await _db.rawQuery('SELECT COUNT(*) AS n FROM story_assignments WHERE class_id = ?', [classId]);
    return ClassStats(
      st.first['n'] as int,
      a.first['p'] as int,
      a.first['n'] as int,
      ((a.first['avg'] as num?) ?? 0).toDouble(),
      sa.first['n'] as int,
    );
  }

  /// سلسلة أسبوعية (آخر [weeks] أسابيع) — classId = null للمؤسسة كلها.
  static Future<List<SeriesPoint>> weekly({int? classId, int weeks = 8}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final out = <SeriesPoint>[];
    for (var i = weeks - 1; i >= 0; i--) {
      final s = monday.subtract(Duration(days: 7 * i));
      final e = s.add(const Duration(days: 7));
      out.add(await _point('${s.day}/${s.month}', classId, s, e));
    }
    return out;
  }

  /// سلسلة شهرية للموسم (شتنبر ← غشت).
  static Future<List<SeriesPoint>> monthly(AcademicYear y, {int? classId, bool untilNow = true}) async {
    final out = <SeriesPoint>[];
    final now = DateTime.now();
    for (var i = 0; i < 10; i++) {
      final s = DateTime(y.startYear, 9 + i, 1);
      if (untilNow && s.isAfter(now)) break;
      final e = DateTime(s.year, s.month + 1, 1);
      const names = ['يناير', 'فبراير', 'مارس', 'أبريل', 'ماي', 'يونيو', 'يوليوز', 'غشت', 'شتنبر', 'أكتوبر', 'نونبر', 'دجنبر'];
      out.add(await _point(names[s.month - 1], classId, s, e));
    }
    return out;
  }

  static Future<SeriesPoint> _point(String label, int? classId, DateTime s, DateTime e) async {
    final r = await _db.rawQuery('''
      SELECT COUNT(*) AS n, COUNT(DISTINCT student_id) AS p, AVG(percent) AS avg FROM quiz_attempts
      WHERE status = 'completed' AND finished_at >= ? AND finished_at < ? ${classId != null ? 'AND class_id = ?' : ''}''',
        [_iso(s), _iso(e), if (classId != null) classId]);
    return SeriesPoint(label, r.first['n'] as int, r.first['p'] as int, ((r.first['avg'] as num?) ?? 0).toDouble());
  }

  static Future<int> completedAttemptsTotal(DateTime start, DateTime end) async {
    final r = await _db.rawQuery(
        "SELECT COUNT(*) AS n FROM quiz_attempts WHERE status = 'completed' AND finished_at >= ? AND finished_at < ?",
        [_iso(start), _iso(end)]);
    return r.first['n'] as int;
  }

  static Future<List<Map<String, Object?>>> studentHistory(int studentId) => _db.rawQuery('''
      SELECT t.*, s.title AS story_title FROM quiz_attempts t JOIN stories s ON s.id = t.story_id
      WHERE t.student_id = ? AND t.status = 'completed' ORDER BY t.finished_at DESC''', [studentId]);

  static Future<List<double>> recentPercents(int studentId) async {
    final r = await _db.rawQuery('''SELECT percent FROM quiz_attempts WHERE student_id = ? AND status = 'completed'
        ORDER BY finished_at DESC LIMIT 10''', [studentId]);
    return r.map((m) => (m['percent'] as num).toDouble()).toList();
  }

  /// أفضل نتيجة لكل تلميذ في قصة معينة داخل قسم: studentId → percent
  static Future<Map<int, double>> storyProgress(int classId, int storyId) async {
    final r = await _db.rawQuery('''SELECT student_id, MAX(percent) AS p FROM quiz_attempts
        WHERE class_id = ? AND story_id = ? AND status = 'completed' GROUP BY student_id''', [classId, storyId]);
    return {for (final m in r) m['student_id'] as int: (m['p'] as num).toDouble()};
  }

  /// عدد القصص المنجزة (≥ نسبة النجاح) لكل تلميذ: studentId → count
  static Future<Map<int, int>> passedCounts(int classId, int passPercent) async {
    final r = await _db.rawQuery('''SELECT student_id, COUNT(DISTINCT story_id) AS n FROM quiz_attempts
        WHERE class_id = ? AND status = 'completed' AND percent >= ? GROUP BY student_id''', [classId, passPercent]);
    return {for (final m in r) m['student_id'] as int: m['n'] as int};
  }

  // ---------------- معايير الترتيب (مع سجل الإصدارات) ----------------

  static String classScope(int classId) => 'class:$classId';
  static const schoolScope = 'school';

  static Future<CriteriaVersion> effectiveCriteria(int? classId) async {
    if (classId != null) {
      final r = await _db.query('ranking_criteria',
          where: 'scope = ? AND active = 1', whereArgs: [classScope(classId)], orderBy: 'id DESC', limit: 1);
      if (r.isNotEmpty) return _cv(r.first);
    }
    final r = await _db.query('ranking_criteria',
        where: 'scope = ? AND active = 1', whereArgs: [schoolScope], orderBy: 'id DESC', limit: 1);
    if (r.isNotEmpty) return _cv(r.first);
    final id = await _db.insert('ranking_criteria', {
      'scope': schoolScope,
      'config': RankingConfig().toJson(),
      'note': 'المعايير الافتراضية الأولية',
      'created_by': 'النظام',
      'created_at': AppDb.now(),
      'active': 1,
    });
    final n = await _db.query('ranking_criteria', where: 'id = ?', whereArgs: [id]);
    return _cv(n.first);
  }

  static CriteriaVersion _cv(Map<String, Object?> m) => CriteriaVersion(
        m['id'] as int,
        m['scope'] as String,
        RankingConfig.fromJson(m['config'] as String?),
        m['created_at'] as String,
        (m['created_by'] as String?) ?? '',
        (m['note'] as String?) ?? '',
        (m['active'] as int) == 1,
      );

  static Future<bool> hasClassOverride(int classId) async {
    final r = await _db.query('ranking_criteria',
        where: 'scope = ? AND active = 1', whereArgs: [classScope(classId)], limit: 1);
    return r.isNotEmpty;
  }

  static Future<int> saveCriteria(String scope, RankingConfig cfg, String actor, String note) async {
    late int id;
    await _db.transaction((txn) async {
      await txn.update('ranking_criteria', {'active': 0}, where: 'scope = ? AND active = 1', whereArgs: [scope]);
      id = await txn.insert('ranking_criteria', {
        'scope': scope,
        'config': cfg.sanitized().toJson(),
        'note': note,
        'created_by': actor,
        'created_at': AppDb.now(),
        'active': 1,
      });
      await txn.insert('audit_log', {
        'ts': AppDb.now(),
        'actor': actor,
        'action': 'تعديل معايير الترتيب',
        'details': '$scope: ${cfg.sanitized().toJson()} — $note',
      });
    });
    return id;
  }

  static Future<void> removeClassOverride(int classId, String actor) async {
    await _db.update('ranking_criteria', {'active': 0},
        where: 'scope = ? AND active = 1', whereArgs: [classScope(classId)]);
    await SchoolRepo.audit(actor, 'إلغاء معايير خاصة بالقسم', 'قسم $classId');
  }

  static Future<List<CriteriaVersion>> criteriaHistory(String scope) async {
    final r = await _db.query('ranking_criteria', where: 'scope = ?', whereArgs: [scope], orderBy: 'id DESC');
    return r.map(_cv).toList();
  }

  static Future<CriteriaVersion?> criteriaById(int id) async {
    final r = await _db.query('ranking_criteria', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _cv(r.first);
  }

  // ---------------- اعتماد النتائج (لقطات تاريخية) ----------------

  static Future<Map<String, Object?>?> snapshot(int classId, String periodType, String period) async {
    final r = await _db.query('ranking_snapshots',
        where: 'class_id = ? AND period_type = ? AND period = ?', whereArgs: [classId, periodType, period]);
    return r.isEmpty ? null : r.first;
  }

  static List<RankRow> snapshotRows(Map<String, Object?> snap) {
    final list = jsonDecode(snap['result'] as String) as List;
    return list.map((e) => RankRow.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveSnapshot(
      int classId, String periodType, String period, int criteriaId, List<RankRow> rows, String actor) async {
    await _db.insert(
      'ranking_snapshots',
      {
        'class_id': classId,
        'period_type': periodType,
        'period': period,
        'criteria_id': criteriaId,
        'result': jsonEncode(rows.map((r) => r.toMap()).toList()),
        'created_by': actor,
        'created_at': AppDb.now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await SchoolRepo.audit(actor, 'اعتماد نتائج الترتيب', 'قسم $classId — $periodType $period (معايير #$criteriaId)');
  }

  // ---------------- الشهادات ----------------

  static Future<String> issueCertificate({
    required int studentId,
    required int classId,
    required String kind,
    required String periodType,
    required String period,
    int? rank,
    required String actor,
  }) async {
    final r = await _db.query('certificates',
        where: 'student_id = ? AND kind = ? AND period_type = ? AND period = ?',
        whereArgs: [studentId, kind, periodType, period]);
    if (r.isNotEmpty) {
      await _db.update('certificates', {'rank': rank}, where: 'id = ?', whereArgs: [r.first['id']]);
      return r.first['serial'] as String;
    }
    final serial = 'SCL-${period.replaceAll('/', '')}-${Security.token(6)}';
    await _db.insert('certificates', {
      'serial': serial,
      'student_id': studentId,
      'class_id': classId,
      'kind': kind,
      'period_type': periodType,
      'period': period,
      'rank': rank,
      'issued_by': actor,
      'issued_at': AppDb.now(),
    });
    return serial;
  }

  static Future<List<Map<String, Object?>>> certificatesForStudent(int studentId) =>
      _db.query('certificates', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'issued_at DESC');
}
