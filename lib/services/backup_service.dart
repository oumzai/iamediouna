import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../core/security.dart';
import '../data/db.dart';
import '../data/school_repo.dart';

/// النسخ الاحتياطي والاستعادة.
///
/// الملف الناتج (.maktabati) هو أرشيف ZIP يحتوي على:
/// - data.enc : قاعدة البيانات مشفرة بـ AES-256-GCM بكلمة سر يختارها المدير (فيها بيانات التلاميذ).
/// - files/   : الأغلفة، صور الأسئلة، تسجيلات الأستاذ، الشعار، وملفات PDF للقصص (اختياريًا).
/// إضافة إلى ذلك: نسخة تلقائية يومية لقاعدة البيانات داخل مساحة التطبيق (آخر 7 أيام).
class BackupService {
  BackupService._();

  static const _fileDirs = ['covers', 'images', 'audio', 'logo'];

  static Future<Uint8List> _readDbBytes() async {
    await AppDb.I.close();
    try {
      return await File(AppDb.I.dbPath).readAsBytes();
    } finally {
      await AppDb.I.open();
    }
  }

  static Future<Uint8List> create(String password, {bool includePdfs = false}) async {
    final dbBytes = await _readDbBytes();
    final enc = await Isolate.run(() => Security.encrypt(dbBytes, password));
    final archive = Archive();
    final manifest = {
      'app': 'maktabati',
      'format': 1,
      'schema': AppDb.schemaVersion,
      'created_at': DateTime.now().toIso8601String(),
      'includes_pdfs': includePdfs,
    };
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.addFile(ArchiveFile.bytes('data.enc', enc));
    final dirs = [..._fileDirs, if (includePdfs) 'stories'];
    for (final d in dirs) {
      final dir = Directory(p.join(AppDb.I.rootDir, d));
      if (!await dir.exists()) continue;
      await for (final e in dir.list()) {
        if (e is File) {
          archive.addFile(ArchiveFile.bytes('files/$d/${p.basename(e.path)}', await e.readAsBytes()));
        }
      }
    }
    final bytes = ZipEncoder().encodeBytes(archive);
    await SchoolRepo.audit('المدير', 'إنشاء نسخة احتياطية', includePdfs ? 'مع ملفات PDF' : 'دون ملفات PDF');
    return bytes;
  }

  /// استعادة نسخة احتياطية: تستبدل كل البيانات الحالية.
  static Future<void> restore(Uint8List bytes, String password) async {
    final Archive archive = _decode(bytes);
    final manifestFile = archive.findFile('manifest.json');
    final dataFile = archive.findFile('data.enc');
    if (manifestFile == null || dataFile == null) {
      throw const FormatException('هذا الملف ليس نسخة احتياطية لتطبيق مكتبتي الصفية.');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    final schema = (manifest['schema'] as num?)?.toInt() ?? 1;
    if (schema > AppDb.schemaVersion) {
      throw const FormatException('النسخة الاحتياطية من إصدار أحدث للتطبيق. حدّث التطبيق أولًا.');
    }
    final enc = Uint8List.fromList(dataFile.content);
    final dbBytes = await Isolate.run(() => Security.decrypt(enc, password));
    const header = 'SQLite format 3';
    if (dbBytes.length < 16 || String.fromCharCodes(dbBytes.sublist(0, 15)) != header) {
      throw const FormatException('محتوى النسخة الاحتياطية تالف.');
    }

    // نسخة أمان من الوضع الحالي قبل الاستبدال
    await autoBackup(force: true, tag: 'before_restore');

    await AppDb.I.close();
    try {
      await File(AppDb.I.dbPath).writeAsBytes(dbBytes, flush: true);
      final includesPdfs = manifest['includes_pdfs'] == true;
      final dirs = [..._fileDirs, if (includesPdfs) 'stories'];
      for (final d in dirs) {
        final dir = Directory(p.join(AppDb.I.rootDir, d));
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      for (final f in archive.files) {
        if (!f.isFile || !f.name.startsWith('files/')) continue;
        final rel = f.name.substring('files/'.length);
        final parts = p.split(rel);
        // حماية من المسارات الخبيثة (../)
        if (parts.length != 2 || parts.contains('..') || !dirs.contains(parts.first)) continue;
        final out = File(p.join(AppDb.I.rootDir, parts[0], parts[1]));
        await out.writeAsBytes(f.content, flush: true);
      }
    } finally {
      await AppDb.I.open();
    }
    await SchoolRepo.audit('المدير', 'استعادة نسخة احتياطية', manifest['created_at']?.toString());
  }

  static Archive _decode(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح.');
    }
  }

  /// نسخة تلقائية يومية لقاعدة البيانات (تحمي من الأعطال). تحتفظ بآخر 7 نسخ.
  static Future<void> autoBackup({bool force = false, String tag = 'auto'}) async {
    try {
      final last = DateTime.tryParse(await SchoolRepo.getSetting(SchoolRepo.kLastAutoBackup) ?? '');
      if (!force && last != null && DateTime.now().difference(last).inHours < 20) return;
      final dir = Directory(p.join(AppDb.I.rootDir, 'auto_backups'));
      await dir.create(recursive: true);
      final bytes = await _readDbBytes();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      await File(p.join(dir.path, '${tag}_$stamp.db')).writeAsBytes(bytes, flush: true);
      await SchoolRepo.setSetting(SchoolRepo.kLastAutoBackup, DateTime.now().toIso8601String());
      final files = (await dir.list().toList()).whereType<File>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      final autos = files.where((f) => p.basename(f.path).startsWith('auto_')).toList();
      for (final f in autos.skip(7)) {
        await f.delete();
      }
    } catch (_) {
      // النسخ التلقائي لا يجب أن يمنع تشغيل التطبيق
    }
  }

  static Future<List<File>> autoBackups() async {
    final dir = Directory(p.join(AppDb.I.rootDir, 'auto_backups'));
    if (!await dir.exists()) return [];
    final files = (await dir.list().toList()).whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// استرجاع نسخة تلقائية محلية.
  static Future<void> restoreAuto(File f) async {
    final bytes = await f.readAsBytes();
    await AppDb.I.close();
    try {
      await File(AppDb.I.dbPath).writeAsBytes(bytes, flush: true);
    } finally {
      await AppDb.I.open();
    }
    await SchoolRepo.audit('المدير', 'استرجاع نسخة تلقائية', p.basename(f.path));
  }

  /// حذف كل البيانات (إعادة التطبيق إلى حالته الأولى).
  static Future<void> factoryReset() async {
    await autoBackup(force: true, tag: 'before_reset');
    await AppDb.I.close();
    await File(AppDb.I.dbPath).delete();
    for (final d in [..._fileDirs, 'stories', 'tmp']) {
      final dir = Directory(p.join(AppDb.I.rootDir, d));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    await AppDb.I.open();
  }
}
