import 'dart:isolate';

import 'package:sqflite/sqflite.dart';

import '../core/security.dart';
import '../services/massar_parser.dart';
import 'db.dart';
import 'models.dart';
import 'school_repo.dart';

enum ImportStatus { added, updated, moved, unchanged, error }

class ImportResult {
  int classesCreated = 0;
  int added = 0;
  int updated = 0;
  int moved = 0;
  int unchanged = 0;
  int skipped = 0;
  int archived = 0;
}

/// الأقسام والتلاميذ وحساباتهم + استيراد ملف مسار.
class PeopleRepo {
  PeopleRepo._();

  static Database get _db => AppDb.I.db;

  // ---------------- الأقسام ----------------

  static Future<List<SchoolClass>> classes({int? yearId, bool onlyActive = true}) async {
    final y = yearId ?? (await SchoolRepo.currentYear()).id;
    final r = await _db.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id AND s.archived = 0) AS student_count
      FROM classes c
      WHERE c.year_id = ? ${onlyActive ? 'AND c.active = 1' : ''}
      ORDER BY c.level, c.code
    ''', [y]);
    final list = r.map(SchoolClass.fromMap).toList();
    // التعليم الأولي في آخر اللائحة
    list.sort((a, b) {
      final la = a.level > 6 ? a.level + 100 : a.level;
      final lb = b.level > 6 ? b.level + 100 : b.level;
      final c = la.compareTo(lb);
      return c != 0 ? c : a.code.compareTo(b.code);
    });
    return list;
  }

  static Future<SchoolClass?> classById(int id) async {
    final r = await _db.rawQuery('''
      SELECT c.*, (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id AND s.archived = 0) AS student_count
      FROM classes c WHERE c.id = ?''', [id]);
    return r.isEmpty ? null : SchoolClass.fromMap(r.first);
  }

  static Future<void> setClassPassword(int classId, String password) async {
    final h = Security.hashPassword(password);
    await _db.update('classes', {'pass_hash': h.hash, 'pass_salt': h.salt, 'iterations': h.iterations},
        where: 'id = ?', whereArgs: [classId]);
  }

  static Future<bool> verifyClass(int classId, String password) async {
    final r = await _db.query('classes', where: 'id = ?', whereArgs: [classId]);
    if (r.isEmpty) return false;
    final m = r.first;
    return Security.verifyPassword(
        password, m['pass_hash'] as String?, m['pass_salt'] as String?, m['iterations'] as int?);
  }

  static Future<void> setTeacherName(int classId, String name) =>
      _db.update('classes', {'teacher_name': name.trim()}, where: 'id = ?', whereArgs: [classId]);

  // ---------------- التلاميذ ----------------

  static Future<List<Student>> students(int classId, {bool includeArchived = false}) async {
    final r = await _db.query('students',
        where: includeArchived ? 'class_id = ?' : 'class_id = ? AND archived = 0',
        whereArgs: [classId],
        orderBy: 'last_name, first_name');
    return r.map(Student.fromMap).toList();
  }

  static Future<Student?> studentById(int id) async {
    final r = await _db.query('students', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Student.fromMap(r.first);
  }

  static Future<Student?> studentByMassar(String code) async {
    final r = await _db.query('students',
        where: 'massar_code = ? AND archived = 0', whereArgs: [code.trim().toUpperCase()]);
    return r.isEmpty ? null : Student.fromMap(r.first);
  }

  static Future<int> totalStudents() async {
    final r = await _db.rawQuery('''
      SELECT COUNT(*) AS n FROM students s JOIN classes c ON c.id = s.class_id
      JOIN academic_years y ON y.id = c.year_id AND y.is_current = 1
      WHERE s.archived = 0 AND c.active = 1''');
    return r.first['n'] as int;
  }

  /// يولّد كلمات سر للتلاميذ ويُرجعها مرة واحدة للطباعة (تُحفظ مجزأة فقط).
  static Future<Map<Student, String>> generatePins(int classId,
      {bool onlyMissing = false, List<int>? studentIds, int digits = 4}) async {
    var list = await students(classId);
    if (studentIds != null) list = list.where((s) => studentIds.contains(s.id)).toList();
    if (onlyMissing) list = list.where((s) => !s.hasPin).toList();
    if (list.isEmpty) return {};
    final pins = List<String>.generate(list.length, (_) => Security.generatePin(digits));
    final hashes = await Isolate.run(() =>
        pins.map((p) => Security.hashPassword(p, iterations: Security.pinIterations)).toList());
    final batch = _db.batch();
    for (var i = 0; i < list.length; i++) {
      batch.update('students', {'pin_hash': hashes[i].hash, 'pin_salt': hashes[i].salt, 'updated_at': AppDb.now()},
          where: 'id = ?', whereArgs: [list[i].id]);
    }
    await batch.commit(noResult: true);
    return {for (var i = 0; i < list.length; i++) list[i]: pins[i]};
  }

  static Future<bool> verifyStudentPin(int studentId, String pin) async {
    final r = await _db.query('students', columns: ['pin_hash', 'pin_salt'], where: 'id = ?', whereArgs: [studentId]);
    if (r.isEmpty) return false;
    return Security.verifyPassword(
        pin, r.first['pin_hash'] as String?, r.first['pin_salt'] as String?, Security.pinIterations);
  }

  static Future<void> setReadingLevel(int studentId, int level, {String source = 'teacher', String? note}) async {
    await _db.transaction((txn) async {
      await txn.update('students', {'reading_level': level, 'updated_at': AppDb.now()},
          where: 'id = ?', whereArgs: [studentId]);
      await txn.insert('student_level_history', {
        'student_id': studentId,
        'level': level,
        'source': source,
        'note': note,
        'created_at': AppDb.now(),
      });
    });
  }

  static Future<List<Map<String, Object?>>> levelHistory(int studentId) =>
      _db.query('student_level_history', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'id DESC');

  static Future<void> setArchived(int studentId, bool archived) => _db.update(
      'students', {'archived': archived ? 1 : 0, 'updated_at': AppDb.now()},
      where: 'id = ?', whereArgs: [studentId]);

  // ---------------- استيراد مسار ----------------

  /// حالة كل تلميذ قبل الاستيراد (للمعاينة).
  static Future<Map<String, ImportStatus>> previewStatuses(MassarFile file) async {
    final rows = await _db.rawQuery('''
      SELECT s.massar_code, s.last_name, s.first_name, s.gender, s.archived, c.code AS class_code
      FROM students s LEFT JOIN classes c ON c.id = s.class_id''');
    final existing = {for (final r in rows) r['massar_code'] as String: r};
    final out = <String, ImportStatus>{};
    for (final c in file.classes) {
      for (final s in c.students) {
        if (s.blocking) {
          out[s.code] = ImportStatus.error;
          continue;
        }
        final e = existing[s.code];
        if (e == null) {
          out[s.code] = ImportStatus.added;
        } else if (e['class_code'] != c.code) {
          out[s.code] = ImportStatus.moved;
        } else if (e['last_name'] != s.lastName || e['first_name'] != s.firstName ||
            (e['gender'] ?? '') != s.gender || e['archived'] == 1) {
          out[s.code] = ImportStatus.updated;
        } else {
          out[s.code] = ImportStatus.unchanged;
        }
      }
    }
    return out;
  }

  /// تطبيق الاستيراد داخل معاملة واحدة (إما كل شيء أو لا شيء).
  static Future<ImportResult> applyImport(
    MassarFile file, {
    required Set<String> selectedClassCodes,
    required String yearLabel,
    bool archiveMissing = false,
    required String actor,
  }) async {
    final res = ImportResult();
    final year = await SchoolRepo.ensureYear(yearLabel, makeCurrent: true);
    final now = AppDb.now();

    await _db.transaction((txn) async {
      final seenCodes = <String>{};
      final touchedClassIds = <int>{};
      for (final mc in file.classes) {
        if (!selectedClassCodes.contains(mc.code)) continue;
        var cr = await txn.query('classes', where: 'year_id = ? AND code = ?', whereArgs: [year.id, mc.code]);
        int classId;
        if (cr.isEmpty) {
          classId = await txn.insert('classes', {
            'year_id': year.id,
            'code': mc.code,
            'level': mc.level,
            'level_name': mc.levelName,
            'active': 1,
            'created_at': now,
          });
          res.classesCreated++;
        } else {
          classId = cr.first['id'] as int;
          await txn.update('classes', {'level': mc.level, 'level_name': mc.levelName, 'active': 1},
              where: 'id = ?', whereArgs: [classId]);
        }
        touchedClassIds.add(classId);

        for (final s in mc.students) {
          if (s.blocking || seenCodes.contains(s.code)) {
            res.skipped++;
            continue;
          }
          seenCodes.add(s.code);
          final er = await txn.query('students', where: 'massar_code = ?', whereArgs: [s.code]);
          if (er.isEmpty) {
            await txn.insert('students', {
              'massar_code': s.code,
              'last_name': s.lastName,
              'first_name': s.firstName,
              'gender': s.gender,
              'class_id': classId,
              'archived': 0,
              'created_at': now,
            });
            res.added++;
          } else {
            final e = er.first;
            final moved = e['class_id'] != classId;
            final changed = e['last_name'] != s.lastName || e['first_name'] != s.firstName ||
                (e['gender'] ?? '') != s.gender || e['archived'] == 1;
            if (moved || changed) {
              await txn.update(
                  'students',
                  {
                    'last_name': s.lastName,
                    'first_name': s.firstName,
                    'gender': s.gender,
                    'class_id': classId,
                    'archived': 0,
                    'updated_at': now,
                  },
                  where: 'id = ?',
                  whereArgs: [e['id']]);
              if (moved) {
                res.moved++;
              } else {
                res.updated++;
              }
            } else {
              res.unchanged++;
            }
          }
        }
      }

      if (archiveMissing && touchedClassIds.isNotEmpty) {
        final ids = touchedClassIds.join(',');
        final missing = await txn.rawQuery(
            'SELECT id, massar_code FROM students WHERE archived = 0 AND class_id IN ($ids)');
        for (final m in missing) {
          if (!seenCodes.contains(m['massar_code'])) {
            await txn.update('students', {'archived': 1, 'updated_at': now}, where: 'id = ?', whereArgs: [m['id']]);
            res.archived++;
          }
        }
      }

      await txn.insert('audit_log', {
        'ts': now,
        'actor': actor,
        'action': 'استيراد لائحة مسار',
        'details': 'أقسام جديدة: ${res.classesCreated}، تلاميذ جدد: ${res.added}، '
            'محدثون: ${res.updated}، منقولون: ${res.moved}، مؤرشفون: ${res.archived}، متجاهلون: ${res.skipped}',
      });
    });

    // استكمال معلومات المؤسسة من الملف إن كانت فارغة
    final school = await SchoolRepo.getSchool();
    if (school != null) {
      var changed = false;
      if (school.academy.isEmpty && file.meta.academy.isNotEmpty) {
        school.academy = file.meta.academy;
        changed = true;
      }
      if (school.directorate.isEmpty && file.meta.directorate.isNotEmpty) {
        school.directorate = file.meta.directorate;
        changed = true;
      }
      if (school.commune.isEmpty && file.meta.commune.isNotEmpty) {
        school.commune = file.meta.commune;
        changed = true;
      }
      if (changed) await SchoolRepo.saveSchool(school);
    }
    return res;
  }
}
