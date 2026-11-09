import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../core/security.dart';
import 'db.dart';
import 'models.dart';

class StoryInfo {
  final Story story;
  final List<int> assignedClassIds;
  final int quizCount;
  final int publishedCount;
  StoryInfo(this.story, this.assignedClassIds, this.quizCount, this.publishedCount);
}

/// القصص (تُخزن مرة واحدة)، إسنادها للأقسام، الاختبارات والأسئلة.
class LibraryRepo {
  LibraryRepo._();

  static Database get _db => AppDb.I.db;

  // ---------------- القصص ----------------

  /// [classId] != null و [onlyAssigned] = true ← القصص المسندة لهذا القسم فقط.
  static Future<List<StoryInfo>> stories({int? classId, bool onlyAssigned = false, String? search}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (classId != null && onlyAssigned) {
      where.add('s.id IN (SELECT story_id FROM story_assignments WHERE class_id = ?)');
      args.add(classId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(s.title LIKE ? OR s.author LIKE ?)');
      args.add('%${search.trim()}%');
      args.add('%${search.trim()}%');
    }
    final r = await _db.rawQuery('''
      SELECT s.*,
        (SELECT GROUP_CONCAT(class_id) FROM story_assignments a WHERE a.story_id = s.id) AS assigned,
        (SELECT COUNT(*) FROM quizzes q WHERE q.story_id = s.id AND q.status != 'archived') AS quiz_count,
        (SELECT COUNT(*) FROM quizzes q WHERE q.story_id = s.id AND q.status = 'published') AS published_count
      FROM stories s
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.title COLLATE NOCASE
    ''', args);
    return r.map((m) {
      final assigned = (m['assigned'] as String? ?? '')
          .split(',')
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toList();
      return StoryInfo(Story.fromMap(m), assigned, (m['quiz_count'] as int?) ?? 0,
          (m['published_count'] as int?) ?? 0);
    }).toList();
  }

  static Future<int> storyCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM stories');
    return r.first['n'] as int;
  }

  static Future<Story?> storyById(int id) async {
    final r = await _db.query('stories', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Story.fromMap(r.first);
  }

  static Future<Story?> storyByToken(String token) async {
    final r = await _db.query('stories', where: 'qr_token = ?', whereArgs: [token]);
    return r.isEmpty ? null : Story.fromMap(r.first);
  }

  static Future<Story?> storyByPdfHash(String hash) async {
    final r = await _db.query('stories', where: 'pdf_hash = ?', whereArgs: [hash]);
    return r.isEmpty ? null : Story.fromMap(r.first);
  }

  static Future<int> createStory({
    required String title,
    String author = '',
    String language = 'ar',
    required List<int> levels,
    int difficulty = 2,
    String summary = '',
    bool hasPaper = true,
    List<int>? pdfBytes,
    List<int>? coverBytes,
    String coverExt = 'png',
    int? ownerClassId,
    List<int> assignToClassIds = const [],
    required String actor,
  }) async {
    final token = Security.token();
    String? pdfPath, pdfHash, coverPath;
    if (pdfBytes != null) {
      pdfHash = Security.sha256Hex(_u8(pdfBytes));
      pdfPath = await AppDb.I.saveBytes('stories', 'pdf', pdfBytes, name: '$token.pdf');
    }
    if (coverBytes != null) {
      coverPath = await AppDb.I.saveBytes('covers', coverExt, coverBytes, name: '$token.$coverExt');
    }
    final now = AppDb.now();
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('stories', {
        'title': title.trim(),
        'author': author.trim(),
        'language': language,
        'levels': levels.join(','),
        'difficulty': difficulty,
        'summary': summary,
        'pdf_path': pdfPath,
        'pdf_hash': pdfHash,
        'cover_path': coverPath,
        'has_paper': hasPaper ? 1 : 0,
        'qr_token': token,
        'owner_class_id': ownerClassId,
        'created_at': now,
      });
      for (final c in assignToClassIds.toSet()) {
        await txn.insert('story_assignments', {'story_id': id, 'class_id': c, 'assigned_at': now, 'assigned_by': actor},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.insert('audit_log', {'ts': now, 'actor': actor, 'action': 'إضافة قصة', 'details': title});
    });
    return id;
  }

  static Future<void> updateStory(Story s, {List<int>? newPdfBytes, List<int>? newCoverBytes, String coverExt = 'png'}) async {
    final m = <String, Object?>{
      'title': s.title.trim(),
      'author': s.author.trim(),
      'language': s.language,
      'levels': s.levels.join(','),
      'difficulty': s.difficulty,
      'summary': s.summary,
      'has_paper': s.hasPaper ? 1 : 0,
      'updated_at': AppDb.now(),
    };
    if (newPdfBytes != null) {
      await AppDb.I.deleteFile(s.pdfPath);
      m['pdf_hash'] = Security.sha256Hex(_u8(newPdfBytes));
      m['pdf_path'] = await AppDb.I.saveBytes('stories', 'pdf', newPdfBytes,
          name: '${s.qrToken}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    }
    if (newCoverBytes != null) {
      await AppDb.I.deleteFile(s.coverPath);
      m['cover_path'] = await AppDb.I.saveBytes('covers', coverExt, newCoverBytes,
          name: '${s.qrToken}_${DateTime.now().millisecondsSinceEpoch}.$coverExt');
    }
    await _db.update('stories', m, where: 'id = ?', whereArgs: [s.id]);
  }

  static Future<int> attemptsForStory(int storyId) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM quiz_attempts WHERE story_id = ?', [storyId]);
    return r.first['n'] as int;
  }

  /// الحذف ممنوع إذا كانت هناك نتائج مرتبطة بالقصة (حماية السجلات التاريخية).
  static Future<String?> deleteStory(int storyId, String actor) async {
    if (await attemptsForStory(storyId) > 0) {
      return 'لا يمكن حذف قصة لها نتائج تلاميذ. يمكنك إلغاء إسنادها بدل الحذف.';
    }
    final s = await storyById(storyId);
    if (s == null) return null;
    final qs = await _db.rawQuery('''SELECT image_path, audio_path FROM questions WHERE quiz_id IN
        (SELECT id FROM quizzes WHERE story_id = ?)''', [storyId]);
    final opts = await _db.rawQuery('''SELECT image_path FROM answer_options WHERE question_id IN
        (SELECT id FROM questions WHERE quiz_id IN (SELECT id FROM quizzes WHERE story_id = ?))''', [storyId]);
    await _db.transaction((txn) async {
      await txn.delete('stories', where: 'id = ?', whereArgs: [storyId]);
      await txn.insert('audit_log', {'ts': AppDb.now(), 'actor': actor, 'action': 'حذف قصة', 'details': s.title});
    });
    await AppDb.I.deleteFile(s.pdfPath);
    await AppDb.I.deleteFile(s.coverPath);
    for (final q in qs) {
      await AppDb.I.deleteFile(q['image_path'] as String?);
      await AppDb.I.deleteFile(q['audio_path'] as String?);
    }
    for (final o in opts) {
      await AppDb.I.deleteFile(o['image_path'] as String?);
    }
    return null;
  }

  static Future<void> assign(int storyId, int classId, String actor) async {
    await _db.insert('story_assignments',
        {'story_id': storyId, 'class_id': classId, 'assigned_at': AppDb.now(), 'assigned_by': actor},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> unassign(int storyId, int classId) =>
      _db.delete('story_assignments', where: 'story_id = ? AND class_id = ?', whereArgs: [storyId, classId]);

  // ---------------- الاختبارات ----------------

  static Future<List<Quiz>> quizzesForStory(int storyId, {bool includeArchived = false}) async {
    final r = await _db.rawQuery('''
      SELECT q.*, (SELECT COUNT(*) FROM questions x WHERE x.quiz_id = q.id) AS question_count
      FROM quizzes q WHERE q.story_id = ? ${includeArchived ? '' : "AND q.status != 'archived'"}
      ORDER BY q.level, q.difficulty, q.id''', [storyId]);
    return r.map(Quiz.fromMap).toList();
  }

  static Future<Quiz?> quizById(int id) async {
    final r = await _db.rawQuery('''
      SELECT q.*, (SELECT COUNT(*) FROM questions x WHERE x.quiz_id = q.id) AS question_count
      FROM quizzes q WHERE q.id = ?''', [id]);
    return r.isEmpty ? null : Quiz.fromMap(r.first);
  }

  static Future<int> createQuiz({
    required int storyId,
    required int level,
    int difficulty = 2,
    String title = '',
    String source = 'manual',
    int passPercent = 50,
    required String actor,
  }) =>
      _db.insert('quizzes', {
        'story_id': storyId,
        'title': title,
        'level': level,
        'difficulty': difficulty,
        'status': 'draft',
        'source': source,
        'pass_percent': passPercent,
        'created_by': actor,
        'created_at': AppDb.now(),
      });

  static Future<void> updateQuizMeta(Quiz q) => _db.update(
      'quizzes',
      {
        'title': q.title,
        'level': q.level,
        'difficulty': q.difficulty,
        'pass_percent': q.passPercent,
        'updated_at': AppDb.now(),
      },
      where: 'id = ?',
      whereArgs: [q.id]);

  static Future<void> setQuizStatus(int quizId, String status, String actor) async {
    await _db.update(
        'quizzes',
        {
          'status': status,
          if (status == 'published') 'published_at': AppDb.now(),
          'updated_at': AppDb.now(),
        },
        where: 'id = ?',
        whereArgs: [quizId]);
    await _db.insert('audit_log', {
      'ts': AppDb.now(),
      'actor': actor,
      'action': status == 'published' ? 'نشر اختبار' : 'تغيير حالة اختبار',
      'details': 'اختبار رقم $quizId ← $status',
    });
  }

  static Future<int> attemptsForQuiz(int quizId) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM quiz_attempts WHERE quiz_id = ?', [quizId]);
    return r.first['n'] as int;
  }

  /// حذف مسودة، أو أرشفة اختبار له نتائج.
  static Future<void> deleteOrArchiveQuiz(int quizId, String actor) async {
    if (await attemptsForQuiz(quizId) > 0) {
      await setQuizStatus(quizId, 'archived', actor);
      return;
    }
    final qs = await loadQuestions(quizId);
    await _db.delete('quizzes', where: 'id = ?', whereArgs: [quizId]);
    for (final q in qs) {
      await AppDb.I.deleteFile(q.imagePath);
      await AppDb.I.deleteFile(q.audioPath);
      for (final o in q.options) {
        await AppDb.I.deleteFile(o.imagePath);
      }
    }
  }

  static Future<List<Question>> loadQuestions(int quizId) async {
    final qs = await _db.query('questions', where: 'quiz_id = ?', whereArgs: [quizId], orderBy: 'position, id');
    if (qs.isEmpty) return [];
    final ids = qs.map((e) => e['id']).join(',');
    final os = await _db.rawQuery('SELECT * FROM answer_options WHERE question_id IN ($ids) ORDER BY position, id');
    final byQ = <int, List<AnswerOption>>{};
    for (final o in os) {
      byQ.putIfAbsent(o['question_id'] as int, () => []).add(AnswerOption.fromMap(o));
    }
    return qs.map((q) => Question.fromMap(q, byQ[q['id'] as int] ?? [])).toList();
  }

  /// حفظ أسئلة الاختبار (يستبدل الأسئلة السابقة). ممنوع إذا كانت للاختبار نتائج.
  static Future<void> saveQuestions(int quizId, List<Question> questions) async {
    if (await attemptsForQuiz(quizId) > 0) {
      throw StateError('لا يمكن تعديل اختبار أجاب عنه التلاميذ. أنشئ نسخة جديدة منه.');
    }
    await _db.transaction((txn) async {
      await txn.delete('questions', where: 'quiz_id = ?', whereArgs: [quizId]);
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        final qid = await txn.insert('questions', {
          'quiz_id': quizId,
          'position': i,
          'type': q.type.id,
          'prompt': q.prompt.trim(),
          'image_path': q.imagePath,
          'audio_path': q.audioPath,
          'difficulty': q.difficulty,
          'skill': q.skill,
          'source_ref': q.sourceRef,
          'keywords': q.keywords,
          'points': q.points,
        });
        q.id = qid;
        q.quizId = quizId;
        q.position = i;
        for (var j = 0; j < q.options.length; j++) {
          final o = q.options[j];
          o.position = j;
          o.id = await txn.insert('answer_options', {
            'question_id': qid,
            'position': j,
            'label': o.label.trim(),
            'image_path': o.imagePath,
            'is_correct': o.isCorrect ? 1 : 0,
          });
        }
      }
      await txn.update('quizzes', {'updated_at': AppDb.now()}, where: 'id = ?', whereArgs: [quizId]);
    });
  }

  /// نسخ اختبار (مع أسئلته) كمسودة جديدة.
  static Future<int> duplicateQuiz(int quizId, String actor) async {
    final q = await quizById(quizId);
    if (q == null) throw StateError('اختبار غير موجود');
    final newId = await createQuiz(
      storyId: q.storyId,
      level: q.level,
      difficulty: q.difficulty,
      title: q.title.isEmpty ? 'نسخة' : '${q.title} (نسخة)',
      source: q.source,
      passPercent: q.passPercent,
      actor: actor,
    );
    final qs = (await loadQuestions(quizId)).map((e) {
      final c = e.copy();
      c.id = null;
      for (final o in c.options) {
        o.id = null;
      }
      return c;
    }).toList();
    await saveQuestions(newId, qs);
    return newId;
  }

  /// اختيار الاختبار المناسب للتلميذ: نفس مستوى قسمه، وأقرب صعوبة لمستواه القرائي.
  static Future<Quiz?> quizForStudent(int storyId, int classLevel, int readingLevel) async {
    final all = (await quizzesForStory(storyId)).where((q) => q.published).toList();
    if (all.isEmpty) return null;
    var candidates = all.where((q) => q.level == classLevel).toList();
    if (candidates.isEmpty) {
      // أقرب مستوى إن لم يوجد اختبار لنفس المستوى
      final sorted = [...all]..sort((a, b) => (a.level - classLevel).abs().compareTo((b.level - classLevel).abs()));
      final best = sorted.first.level;
      candidates = all.where((q) => q.level == best).toList();
    }
    final desired = readingLevel <= 0 ? 2 : (readingLevel <= 2 ? 1 : (readingLevel == 3 ? 2 : 3));
    candidates.sort((a, b) => (a.difficulty - desired).abs().compareTo((b.difficulty - desired).abs()));
    return candidates.first;
  }
}

/// تحويل List<int> إلى Uint8List دون نسخ إن أمكن.
Uint8List _u8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);
