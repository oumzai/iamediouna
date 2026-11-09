import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// نتيجة تجزئة كلمة سر (لا تُحفظ كلمات السر أبدًا كنص عادي).
class PasswordHash {
  final String hash;
  final String salt;
  final int iterations;
  const PasswordHash(this.hash, this.salt, this.iterations);
}

/// أدوات الأمان: PBKDF2-SHA256 للتجزئة، AES-GCM لتشفير النسخ الاحتياطية.
class Security {
  Security._();

  static final Random _rnd = Random.secure();

  /// عدد التكرارات: أعلى لحسابات المدير والأقسام، وأخف لرموز التلاميذ.
  static const int strongIterations = 30000;
  static const int pinIterations = 3000;

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rnd.nextInt(256)));

  static Uint8List pbkdf2(String password, Uint8List salt, int iterations, int length) {
    final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, length));
    return d.process(Uint8List.fromList(utf8.encode(password)));
  }

  static PasswordHash hashPassword(String password, {int iterations = strongIterations}) {
    final salt = randomBytes(16);
    final h = pbkdf2(password, salt, iterations, 32);
    return PasswordHash(base64Encode(h), base64Encode(salt), iterations);
  }

  static bool verifyPassword(String password, String? hash, String? salt, int? iterations) {
    if (hash == null || salt == null || iterations == null || hash.isEmpty) return false;
    final h = pbkdf2(password, base64Decode(salt), iterations, 32);
    final expected = base64Decode(hash);
    if (h.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < h.length; i++) {
      diff |= h[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// رمز رقمي للتلميذ (4 أرقام افتراضيًا). يتجنب الرموز السهلة مثل 0000 و 1234.
  static String generatePin([int digits = 4]) {
    while (true) {
      final s = List<int>.generate(digits, (_) => _rnd.nextInt(10)).join();
      if (RegExp(r'^(\d)\1+$').hasMatch(s)) continue;
      if ('0123456789'.contains(s) || '9876543210'.contains(s)) continue;
      return s;
    }
  }

  /// كلمة سر للقسم: حروف وأرقام دون الرموز الملتبسة (0/O، 1/l/I).
  static String generatePassword([int length = 8]) {
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    return List<String>.generate(length, (_) => alphabet[_rnd.nextInt(alphabet.length)]).join();
  }

  /// رمز استرجاع للمدير بصيغة XXXX-XXXX-XXXX
  static String recoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String part() => List<String>.generate(4, (_) => alphabet[_rnd.nextInt(alphabet.length)]).join();
    return '${part()}-${part()}-${part()}';
  }

  static String sha256Hex(Uint8List data) {
    final out = SHA256Digest().process(data);
    final sb = StringBuffer();
    for (final b in out) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// معرّف فريد (UUID v4) — يُستعمل لمحاولات الاختبار لتفادي التكرار عند المزامنة مستقبلًا.
  static String uuid() {
    final b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final h = List<String>.generate(16, hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// رمز قصير عشوائي (لرموز QR الخاصة بالقصص).
  static String token([int length = 12]) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List<String>.generate(length, (_) => alphabet[_rnd.nextInt(alphabet.length)]).join();
  }

  // ---------------- تشفير النسخ الاحتياطية ----------------

  static final Uint8List _magic = Uint8List.fromList(utf8.encode('SCLB1'));

  /// صيغة الملف: SCLB1 + salt(16) + nonce(12) + ciphertext(+tag 16)
  static Uint8List encrypt(Uint8List plain, String password) {
    final salt = randomBytes(16);
    final nonce = randomBytes(12);
    final key = pbkdf2(password, salt, 60000, 32);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ct = cipher.process(plain);
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(salt)
      ..add(nonce)
      ..add(ct);
    return out.toBytes();
  }

  /// يرمي [FormatException] إذا كان الملف غير صالح أو كلمة السر خاطئة.
  static Uint8List decrypt(Uint8List data, String password) {
    if (data.length < 5 + 16 + 12 + 16) throw const FormatException('ملف غير صالح');
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) throw const FormatException('ليس ملف نسخة احتياطية لهذا التطبيق');
    }
    final salt = Uint8List.sublistView(data, 5, 21);
    final nonce = Uint8List.sublistView(data, 21, 33);
    final ct = Uint8List.sublistView(data, 33);
    final key = pbkdf2(password, Uint8List.fromList(salt), 60000, 32);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, Uint8List.fromList(nonce), Uint8List(0)));
      return cipher.process(Uint8List.fromList(ct));
    } catch (_) {
      throw const FormatException('كلمة سر النسخة الاحتياطية غير صحيحة أو الملف تالف');
    }
  }
}
