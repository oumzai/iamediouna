import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);

  String get ext {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }
}

/// كل عمليات اختيار الملفات وحفظها في مكان واحد (file_picker v13).
class Pick {
  Pick._();

  static Future<PickedFile?> _one(FileType type, [List<String>? ext]) async {
    final f = await FilePicker.pickFile(type: type, allowedExtensions: ext);
    if (f == null) return null;
    return PickedFile(f.name, await f.readAsBytes());
  }

  static Future<PickedFile?> excel() => _one(FileType.custom, ['xlsx']);

  static Future<PickedFile?> pdf() => _one(FileType.custom, ['pdf']);

  static Future<PickedFile?> image() => _one(FileType.image);

  static Future<PickedFile?> backup() => _one(FileType.any);

  /// حفظ ملف في مكان يختاره المستخدم (ذاكرة التابلت، بطاقة SD، Google Drive...).
  static Future<bool> save(String fileName, Uint8List bytes, {String mime = 'application/octet-stream'}) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mime);
    return uri != null;
  }
}
