import 'package:sqflite/sqflite.dart';

import '../core/arabic.dart';
import '../core/security.dart';
import 'db.dart';
import 'models.dart';

/// المؤسسة، الموسم الدراسي، حساب المدير، الإعدادات، سجل العمليات.
class SchoolRepo {
  SchoolRepo._();

  static Database get _db => AppDb.I.db;

  // ---------------- المؤسسة ----------------

  static Future<bool> isSetupDone() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM school');
    final a = await _db.rawQuery("SELECT COUNT(*) AS n FROM accounts WHERE role = 'admin'");
    return (r.first['n'] as int) > 0 && (a.first['n'] as int) > 0;
  }

  static Future<School?> getSchool() async {
    final r = await _db.query('school', where: 'id = 1');
    return r.isEmpty ? null : School.fromMap(r.first);
  }

  static Future<void> saveSchool(School s) async {
    final m = s.toMap();
    final existing = await _db.query('school', where: 'id = 1');
    if (existing.isEmpty) {
      m['created_at'] = AppDb.now();
      await _db.insert('school', m);
    } else {
      await _db.update('school', m, where: 'id = 1');
    }
  }

  // ---------------- الموسم الدراسي ----------------

  static Future<AcademicYear> currentYear() async {
    final r = await _db.query('academic_years', where: 'is_current = 1', limit: 1);
    if (r.isNotEmpty) return AcademicYear.fromMap(r.first);
    return ensureYear(Ar.currentSchoolYear(), makeCurrent: true);
  }

  static Future<List<AcademicYear>> years() async {
    final r = await _db.query('academic_years', orderBy: 'label DESC');
    return r.map(AcademicYear.fromMap).toList();
  }

  static Future<AcademicYear> ensureYear(String label, {bool makeCurrent = false}) async {
    final l = Ar.clean(label);
    var r = await _db.query('academic_years', where: 'label = ?', whereArgs: [l]);
    if (r.isEmpty) {
      await _db.insert('academic_years', {'label': l, 'is_current': 0});
      r = await _db.query('academic_years', where: 'label = ?', whereArgs: [l]);
    }
    final y = AcademicYear.fromMap(r.first);
    if (makeCurrent && !y.isCurrent) {
      await _db.transaction((txn) async {
        await txn.update('academic_years', {'is_current': 0});
        await txn.update('academic_years', {'is_current': 1}, where: 'id = ?', whereArgs: [y.id]);
      });
      return AcademicYear(y.id, y.label, true);
    }
    return y;
  }

  // ---------------- حساب المدير ----------------

  /// ينشئ حساب المدير ويُرجع رمز الاسترجاع (يُعرض مرة واحدة فقط).
  static Future<String> createAdmin(String password) async {
    final h = Security.hashPassword(password);
    final recovery = Security.recoveryCode();
    final rh = Security.hashPassword(recovery.replaceAll('-', ''));
    await _db.delete('accounts', where: "role = 'admin'");
    await _db.insert('accounts', {
      'role': 'admin',
      'username': 'admin',
      'pass_hash': h.hash,
      'pass_salt': h.salt,
      'iterations': h.iterations,
      'recovery_hash': rh.hash,
      'recovery_salt': rh.salt,
      'created_at': AppDb.now(),
    });
    return recovery;
  }

  static Future<Map<String, Object?>?> _admin() async {
    final r = await _db.query('accounts', where: "role = 'admin'", limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<bool> verifyAdmin(String password) async {
    final a = await _admin();
    if (a == null) return false;
    return Security.verifyPassword(
        password, a['pass_hash'] as String?, a['pass_salt'] as String?, a['iterations'] as int?);
  }

  static Future<void> changeAdminPassword(String newPassword) async {
    final h = Security.hashPassword(newPassword);
    await _db.update(
      'accounts',
      {'pass_hash': h.hash, 'pass_salt': h.salt, 'iterations': h.iterations, 'updated_at': AppDb.now()},
      where: "role = 'admin'",
    );
  }

  /// استرجاع الحساب برمز الاسترجاع: يغيّر كلمة السر ويولّد رمز استرجاع جديدًا.
  static Future<String?> recoverAdmin(String code, String newPassword) async {
    final a = await _admin();
    if (a == null) return null;
    final norm = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final ok = Security.verifyPassword(norm, a['recovery_hash'] as String?, a['recovery_salt'] as String?,
        Security.strongIterations);
    if (!ok) return null;
    final h = Security.hashPassword(newPassword);
    final recovery = Security.recoveryCode();
    final rh = Security.hashPassword(recovery.replaceAll('-', ''));
    await _db.update(
      'accounts',
      {
        'pass_hash': h.hash,
        'pass_salt': h.salt,
        'iterations': h.iterations,
        'recovery_hash': rh.hash,
        'recovery_salt': rh.salt,
        'updated_at': AppDb.now(),
      },
      where: "role = 'admin'",
    );
    await audit('admin', 'استرجاع حساب المدير برمز الاسترجاع');
    return recovery;
  }

  // ---------------- الإعدادات ----------------

  static Future<String?> getSetting(String key) async {
    final r = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> setSetting(String key, String? value) async {
    await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getInt(String key, int def) async => int.tryParse(await getSetting(key) ?? '') ?? def;

  // مفاتيح الإعدادات
  static const kAiUrl = 'ai_url';
  static const kAiToken = 'ai_token';
  static const kIdleMinutes = 'idle_minutes';
  static const kMinistry = 'ministry_name';
  static const kShowOfficialHeader = 'official_header';
  static const kDemo = 'demo_data';
  static const kLastAutoBackup = 'last_auto_backup';
  static const kPinDigits = 'pin_digits';

  static const defaultMinistry = 'وزارة التربية الوطنية والتعليم الأولي والرياضة';

  // ---------------- سجل العمليات ----------------

  static Future<void> audit(String actor, String action, [String? details]) async {
    await _db.insert('audit_log', {
      'ts': AppDb.now(),
      'actor': actor,
      'action': action,
      'details': details,
    });
  }

  static Future<List<Map<String, Object?>>> auditLog({int limit = 300}) =>
      _db.query('audit_log', orderBy: 'id DESC', limit: limit);
}
