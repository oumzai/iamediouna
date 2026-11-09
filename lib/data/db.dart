import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// قاعدة البيانات المحلية (SQLite) — تعمل دون إنترنت.
/// جميع المسارات المخزنة نسبية إلى مجلد التطبيق لكي تعمل النسخ الاحتياطية على أي جهاز.
class AppDb {
  AppDb._();
  static final AppDb I = AppDb._();

  static const int schemaVersion = 1;
  static const String fileName = 'maktabati.db';

  Database? _db;
  late String rootDir;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('قاعدة البيانات غير مفتوحة');
    return d;
  }

  String get dbPath => p.join(rootDir, fileName);

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    rootDir = p.join(docs.path, 'maktabati');
    for (final sub in ['', 'stories', 'covers', 'images', 'audio', 'logo', 'auto_backups', 'tmp']) {
      await Directory(p.join(rootDir, sub)).create(recursive: true);
    }
    await open();
  }

  Future<void> open() async {
    _db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final stmt in schema) {
          batch.execute(stmt);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldV, newV) async {
        // الترحيلات المستقبلية تضاف هنا حسب الإصدار:
        // if (oldV < 2) { await db.execute('ALTER TABLE ...'); }
      },
    );
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }

  /// المسار المطلق لملف مخزن بمسار نسبي.
  String abs(String relative) => p.join(rootDir, relative);

  File file(String relative) => File(abs(relative));

  /// حفظ بايتات في مجلد فرعي وإرجاع المسار النسبي.
  Future<String> saveBytes(String subdir, String ext, List<int> bytes, {String? name}) async {
    final n = name ?? '${DateTime.now().microsecondsSinceEpoch}.$ext';
    final rel = p.join(subdir, n);
    await File(abs(rel)).writeAsBytes(bytes, flush: true);
    return rel;
  }

  Future<void> deleteFile(String? relative) async {
    if (relative == null || relative.isEmpty) return;
    final f = File(abs(relative));
    if (await f.exists()) await f.delete();
  }

  static String now() => DateTime.now().toIso8601String();

  /// مخطط الجداول — النسخة 1.
  static const List<String> schema = [
    '''CREATE TABLE school (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      name TEXT NOT NULL,
      code TEXT,
      academy TEXT,
      directorate TEXT,
      commune TEXT,
      director_name TEXT,
      logo_path TEXT,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE academic_years (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL UNIQUE,
      is_current INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      role TEXT NOT NULL,
      username TEXT NOT NULL UNIQUE,
      pass_hash TEXT NOT NULL,
      pass_salt TEXT NOT NULL,
      iterations INTEGER NOT NULL,
      recovery_hash TEXT,
      recovery_salt TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''',
    '''CREATE TABLE classes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year_id INTEGER NOT NULL REFERENCES academic_years(id),
      code TEXT NOT NULL,
      level INTEGER NOT NULL,
      level_name TEXT,
      teacher_name TEXT,
      pass_hash TEXT,
      pass_salt TEXT,
      iterations INTEGER,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      UNIQUE (year_id, code)
    )''',
    '''CREATE TABLE students (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      massar_code TEXT NOT NULL UNIQUE,
      last_name TEXT NOT NULL,
      first_name TEXT NOT NULL,
      gender TEXT,
      class_id INTEGER REFERENCES classes(id),
      pin_hash TEXT,
      pin_salt TEXT,
      reading_level INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''',
    'CREATE INDEX idx_students_class ON students(class_id)',
    '''CREATE TABLE student_level_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      level INTEGER NOT NULL,
      source TEXT,
      note TEXT,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE stories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT,
      language TEXT NOT NULL DEFAULT 'ar',
      levels TEXT NOT NULL DEFAULT '',
      difficulty INTEGER NOT NULL DEFAULT 2,
      summary TEXT,
      pdf_path TEXT,
      pdf_hash TEXT UNIQUE,
      cover_path TEXT,
      has_paper INTEGER NOT NULL DEFAULT 1,
      qr_token TEXT NOT NULL UNIQUE,
      owner_class_id INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''',
    '''CREATE TABLE story_assignments (
      story_id INTEGER NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
      assigned_at TEXT NOT NULL,
      assigned_by TEXT,
      PRIMARY KEY (story_id, class_id)
    )''',
    '''CREATE TABLE quizzes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      story_id INTEGER NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      title TEXT,
      level INTEGER NOT NULL,
      difficulty INTEGER NOT NULL DEFAULT 2,
      status TEXT NOT NULL DEFAULT 'draft',
      source TEXT NOT NULL DEFAULT 'manual',
      pass_percent INTEGER NOT NULL DEFAULT 50,
      created_by TEXT,
      created_at TEXT NOT NULL,
      published_at TEXT,
      updated_at TEXT
    )''',
    'CREATE INDEX idx_quizzes_story ON quizzes(story_id)',
    '''CREATE TABLE questions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      quiz_id INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      type TEXT NOT NULL,
      prompt TEXT NOT NULL,
      image_path TEXT,
      audio_path TEXT,
      difficulty INTEGER NOT NULL DEFAULT 2,
      skill TEXT,
      source_ref TEXT,
      keywords TEXT,
      points INTEGER NOT NULL DEFAULT 1
    )''',
    'CREATE INDEX idx_questions_quiz ON questions(quiz_id)',
    '''CREATE TABLE answer_options (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      image_path TEXT,
      is_correct INTEGER NOT NULL DEFAULT 0
    )''',
    'CREATE INDEX idx_options_question ON answer_options(question_id)',
    '''CREATE TABLE quiz_attempts (
      id TEXT PRIMARY KEY,
      student_id INTEGER NOT NULL REFERENCES students(id),
      quiz_id INTEGER NOT NULL REFERENCES quizzes(id),
      story_id INTEGER NOT NULL,
      class_id INTEGER NOT NULL,
      year_id INTEGER NOT NULL,
      attempt_no INTEGER NOT NULL,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      duration_sec INTEGER,
      score REAL NOT NULL DEFAULT 0,
      max_score REAL NOT NULL DEFAULT 0,
      percent REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'in_progress',
      needs_review INTEGER NOT NULL DEFAULT 0,
      device_id TEXT,
      UNIQUE (student_id, quiz_id, attempt_no)
    )''',
    'CREATE INDEX idx_attempts_class ON quiz_attempts(class_id, finished_at)',
    'CREATE INDEX idx_attempts_student ON quiz_attempts(student_id)',
    '''CREATE TABLE student_answers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      attempt_id TEXT NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
      question_id INTEGER NOT NULL,
      answer TEXT NOT NULL,
      is_correct INTEGER NOT NULL DEFAULT 0,
      points REAL NOT NULL DEFAULT 0,
      needs_review INTEGER NOT NULL DEFAULT 0,
      reviewed INTEGER NOT NULL DEFAULT 0,
      UNIQUE (attempt_id, question_id)
    )''',
    '''CREATE TABLE retake_grants (
      student_id INTEGER NOT NULL,
      quiz_id INTEGER NOT NULL,
      extra INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (student_id, quiz_id)
    )''',
    '''CREATE TABLE ranking_criteria (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scope TEXT NOT NULL,
      config TEXT NOT NULL,
      note TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE ranking_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      class_id INTEGER NOT NULL,
      period_type TEXT NOT NULL,
      period TEXT NOT NULL,
      criteria_id INTEGER NOT NULL,
      result TEXT NOT NULL,
      created_by TEXT,
      created_at TEXT NOT NULL,
      UNIQUE (class_id, period_type, period)
    )''',
    '''CREATE TABLE certificates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      serial TEXT NOT NULL UNIQUE,
      student_id INTEGER NOT NULL,
      class_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      period_type TEXT NOT NULL,
      period TEXT NOT NULL,
      rank INTEGER,
      issued_by TEXT,
      issued_at TEXT NOT NULL,
      UNIQUE (student_id, kind, period_type, period)
    )''',
    '''CREATE TABLE audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts TEXT NOT NULL,
      actor TEXT NOT NULL,
      action TEXT NOT NULL,
      details TEXT
    )''',
    '''CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      op TEXT NOT NULL,
      ts TEXT NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )''',
  ];
}
