import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/school_repo.dart';
import 'ranking.dart';

/// الاتصال بخدمة الذكاء الاصطناعي عبر خادم وسيط آمن.
///
/// - مفتاح API السري لا يوجد داخل التطبيق: يُحفظ في الخادم الوسيط فقط (backend/worker.js).
/// - التطبيق يحمل «رمز وصول» خاصًا بالمؤسسة يمكن إلغاؤه من الخادم.
/// - لا تُرسَل أي معلومة عن التلاميذ: فقط ملف القصة ومستوى القسم.
class AiClient {
  AiClient._();

  static Future<(String, String)> _config() async {
    final url = (await SchoolRepo.getSetting(SchoolRepo.kAiUrl) ?? '').trim();
    final token = (await SchoolRepo.getSetting(SchoolRepo.kAiToken) ?? '').trim();
    return (url.endsWith('/') ? url.substring(0, url.length - 1) : url, token);
  }

  static Future<bool> isConfigured() async {
    final (url, token) = await _config();
    return url.isNotEmpty && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 180)}) async {
    final (url, token) = await _config();
    if (url.isEmpty || token.isEmpty) {
      throw Exception('خدمة الذكاء الاصطناعي غير مُعدّة. يضبطها المدير من الإعدادات (عنوان الخادم ورمز الوصول).');
    }
    http.Response? res;
    try {
      res = await http
          .post(Uri.parse('$url$path'),
              headers: {'Content-Type': 'application/json', 'X-Access-Token': token}, body: jsonEncode(body))
          .timeout(timeout);
    } catch (_) {
      res = null;
    }
    if (res == null) {
      throw Exception('تعذر الاتصال بخدمة الذكاء الاصطناعي. تحقق من الاتصال بالإنترنت ثم أعد المحاولة.');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('رد غير مفهوم من الخادم (رمز ${res.statusCode}).');
    }
    if (res.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'خطأ من الخادم (رمز ${res.statusCode}).');
    }
    return data;
  }

  static Future<String> ping() async {
    final (url, token) = await _config();
    if (url.isEmpty) throw Exception('أدخل عنوان الخادم أولًا.');
    final res = await http
        .get(Uri.parse('$url/v1/health'), headers: {'X-Access-Token': token})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) return 'الاتصال ناجح ✔';
    if (res.statusCode == 401) throw Exception('رمز الوصول غير صحيح.');
    throw Exception('الخادم أجاب برمز ${res.statusCode}.');
  }

  /// توليد أسئلة من ملف PDF للقصة.
  static Future<List<Question>> generateQuiz({
    required Story story,
    required Uint8List pdf,
    required int level,
    required int difficulty,
    required int count,
    required List<QType> types,
  }) async {
    if (pdf.length > 24 * 1024 * 1024) {
      throw Exception('ملف القصة كبير جدًا للإرسال (أكثر من 24 ميغابايت). استعمل نسخة PDF أخف.');
    }
    final data = await _post('/v1/generate-quiz', {
      'pdf_base64': base64Encode(pdf),
      'title': story.title,
      'language': story.language,
      'level': level,
      'difficulty': difficulty,
      'count': count,
      'types': types.map((t) => t.id).toList(),
    });
    final list = (data['questions'] as List? ?? const []);
    final out = <Question>[];
    for (final q in list) {
      final parsed = _parseQuestion(q as Map<String, dynamic>);
      if (parsed != null) out.add(parsed);
    }
    if (out.isEmpty) throw Exception('لم تُرجع الخدمة أسئلة صالحة. أعد المحاولة.');
    return out;
  }

  static Future<Question> regenerateQuestion({
    required Story story,
    required Uint8List pdf,
    required int level,
    required QType type,
    required int difficulty,
    required List<String> avoidPrompts,
  }) async {
    final data = await _post('/v1/regenerate-question', {
      'pdf_base64': base64Encode(pdf),
      'title': story.title,
      'language': story.language,
      'level': level,
      'type': type.id,
      'difficulty': difficulty,
      'avoid': avoidPrompts,
    });
    final q = _parseQuestion((data['question'] as Map).cast<String, dynamic>());
    if (q == null) throw Exception('لم تُرجع الخدمة سؤالًا صالحًا.');
    return q;
  }

  /// اقتراح معايير الترتيب من إحصائيات مجهولة (دون أسماء).
  static Future<(RankingConfig, String)> suggestCriteria(Map<String, dynamic> anonymousStats) async {
    final data = await _post('/v1/suggest-criteria', {'stats': anonymousStats}, timeout: const Duration(seconds: 60));
    final cfg = RankingConfig.fromJson(jsonEncode(data['config'] ?? {}));
    return (cfg.sanitized(), (data['rationale'] ?? '').toString());
  }

  static Question? _parseQuestion(Map<String, dynamic> m) {
    final type = QType.fromId((m['type'] ?? 'single').toString());
    final prompt = (m['prompt'] ?? '').toString().trim();
    if (prompt.isEmpty) return null;
    final opts = <AnswerOption>[];
    final rawOpts = m['options'] as List? ?? const [];
    for (var i = 0; i < rawOpts.length; i++) {
      final o = rawOpts[i];
      if (o is Map) {
        opts.add(AnswerOption(
          position: i,
          label: (o['label'] ?? '').toString().trim(),
          isCorrect: o['correct'] == true,
        ));
      } else if (o != null) {
        opts.add(AnswerOption(position: i, label: o.toString()));
      }
    }
    if (type == QType.truefalse && opts.length != 2) {
      final answer = m['answer'] == true || m['answer'].toString() == 'true';
      opts
        ..clear()
        ..add(AnswerOption(position: 0, label: 'صح', isCorrect: answer))
        ..add(AnswerOption(position: 1, label: 'خطأ', isCorrect: !answer));
    }
    final kws = m['keywords'];
    final hint = (m['image_hint'] ?? '').toString();
    return Question(
      type: type,
      prompt: prompt,
      difficulty: (m['difficulty'] is num) ? (m['difficulty'] as num).round().clamp(1, 3).toInt() : 2,
      skill: (m['skill'] ?? '').toString(),
      sourceRef: [
        (m['source_ref'] ?? '').toString(),
        if (hint.isNotEmpty) 'صورة مقترحة: $hint',
      ].where((e) => e.isNotEmpty).join(' — '),
      keywords: kws is List ? kws.join('، ') : (kws ?? '').toString(),
      options: type == QType.short ? [] : opts,
    );
  }
}
