import 'dart:convert';

/// نماذج البيانات (Dart خالص، بدون Flutter).

int _i(Object? v, [int d = 0]) => v == null ? d : (v is int ? v : int.tryParse('$v') ?? d);
double _d(Object? v, [double d = 0]) => v == null ? d : (v is num ? v.toDouble() : double.tryParse('$v') ?? d);
String _s(Object? v) => v == null ? '' : '$v';
String? _sn(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

class School {
  final int id;
  String name;
  String code;
  String academy;
  String directorate;
  String commune;
  String directorName;
  String? logoPath;

  School({
    this.id = 1,
    required this.name,
    this.code = '',
    this.academy = '',
    this.directorate = '',
    this.commune = '',
    this.directorName = '',
    this.logoPath,
  });

  factory School.fromMap(Map<String, Object?> m) => School(
        id: _i(m['id'], 1),
        name: _s(m['name']),
        code: _s(m['code']),
        academy: _s(m['academy']),
        directorate: _s(m['directorate']),
        commune: _s(m['commune']),
        directorName: _s(m['director_name']),
        logoPath: _sn(m['logo_path']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'academy': academy,
        'directorate': directorate,
        'commune': commune,
        'director_name': directorName,
        'logo_path': logoPath,
      };
}

class AcademicYear {
  final int id;
  final String label;
  final bool isCurrent;
  AcademicYear(this.id, this.label, this.isCurrent);

  factory AcademicYear.fromMap(Map<String, Object?> m) =>
      AcademicYear(_i(m['id']), _s(m['label']), _i(m['is_current']) == 1);

  /// بداية الموسم (1 شتنبر) ونهايته (31 غشت).
  int get startYear => int.tryParse(label.split('/').first.trim()) ?? DateTime.now().year;
  DateTime get start => DateTime(startYear, 9, 1);
  DateTime get end => DateTime(startYear + 1, 9, 1);
}

class SchoolClass {
  final int id;
  final int yearId;
  final String code;
  final int level;
  final String levelName;
  String teacherName;
  final bool hasPassword;
  final bool active;
  final int studentCount;

  SchoolClass({
    required this.id,
    required this.yearId,
    required this.code,
    required this.level,
    this.levelName = '',
    this.teacherName = '',
    this.hasPassword = false,
    this.active = true,
    this.studentCount = 0,
  });

  factory SchoolClass.fromMap(Map<String, Object?> m) => SchoolClass(
        id: _i(m['id']),
        yearId: _i(m['year_id']),
        code: _s(m['code']),
        level: _i(m['level']),
        levelName: _s(m['level_name']),
        teacherName: _s(m['teacher_name']),
        hasPassword: _s(m['pass_hash']).isNotEmpty,
        active: _i(m['active'], 1) == 1,
        studentCount: _i(m['student_count']),
      );
}

class Student {
  final int id;
  final String massarCode;
  final String lastName;
  final String firstName;
  final String gender;
  final int? classId;
  final bool hasPin;
  final int readingLevel;
  final bool archived;

  Student({
    required this.id,
    required this.massarCode,
    required this.lastName,
    required this.firstName,
    this.gender = '',
    this.classId,
    this.hasPin = false,
    this.readingLevel = 0,
    this.archived = false,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory Student.fromMap(Map<String, Object?> m) => Student(
        id: _i(m['id']),
        massarCode: _s(m['massar_code']),
        lastName: _s(m['last_name']),
        firstName: _s(m['first_name']),
        gender: _s(m['gender']),
        classId: m['class_id'] == null ? null : _i(m['class_id']),
        hasPin: _s(m['pin_hash']).isNotEmpty,
        readingLevel: _i(m['reading_level']),
        archived: _i(m['archived']) == 1,
      );
}

class Story {
  final int id;
  String title;
  String author;
  String language;
  List<int> levels;
  int difficulty;
  String summary;
  String? pdfPath;
  String? coverPath;
  bool hasPaper;
  final String qrToken;
  final int? ownerClassId;
  final String createdAt;

  Story({
    required this.id,
    required this.title,
    this.author = '',
    this.language = 'ar',
    this.levels = const [],
    this.difficulty = 2,
    this.summary = '',
    this.pdfPath,
    this.coverPath,
    this.hasPaper = true,
    required this.qrToken,
    this.ownerClassId,
    this.createdAt = '',
  });

  static List<int> parseLevels(String s) =>
      s.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();

  factory Story.fromMap(Map<String, Object?> m) => Story(
        id: _i(m['id']),
        title: _s(m['title']),
        author: _s(m['author']),
        language: _s(m['language']).isEmpty ? 'ar' : _s(m['language']),
        levels: parseLevels(_s(m['levels'])),
        difficulty: _i(m['difficulty'], 2),
        summary: _s(m['summary']),
        pdfPath: _sn(m['pdf_path']),
        coverPath: _sn(m['cover_path']),
        hasPaper: _i(m['has_paper'], 1) == 1,
        qrToken: _s(m['qr_token']),
        ownerClassId: m['owner_class_id'] == null ? null : _i(m['owner_class_id']),
        createdAt: _s(m['created_at']),
      );

  /// محتوى رمز QR: يعرّف القصة فقط، ولا يحتوي على أي معلومة عن التلاميذ.
  String get qrData => 'SCL1:$qrToken';

  static String? tokenFromQr(String raw) {
    final t = raw.trim();
    if (t.startsWith('SCL1:')) return t.substring(5);
    return null;
  }
}

enum QType {
  single('single', 'اختيار من متعدد'),
  multi('multi', 'خانات اختيار (أكثر من جواب صحيح)'),
  truefalse('truefalse', 'صح أو خطأ'),
  image('image', 'اختيار صورة'),
  order('order', 'ترتيب الأحداث'),
  complete('complete', 'إكمال جملة'),
  short('short', 'جواب قصير');

  final String id;
  final String label;
  const QType(this.id, this.label);

  static QType fromId(String id) =>
      QType.values.firstWhere((t) => t.id == id, orElse: () => QType.single);

  bool get usesOptions => this != QType.short;
}

class AnswerOption {
  int? id;
  int position;
  String label;
  String? imagePath;
  bool isCorrect;

  AnswerOption({this.id, this.position = 0, this.label = '', this.imagePath, this.isCorrect = false});

  factory AnswerOption.fromMap(Map<String, Object?> m) => AnswerOption(
        id: _i(m['id']),
        position: _i(m['position']),
        label: _s(m['label']),
        imagePath: _sn(m['image_path']),
        isCorrect: _i(m['is_correct']) == 1,
      );

  AnswerOption copy() =>
      AnswerOption(id: id, position: position, label: label, imagePath: imagePath, isCorrect: isCorrect);
}

class Question {
  int? id;
  int quizId;
  int position;
  QType type;
  String prompt;
  String? imagePath;
  String? audioPath;
  int difficulty;
  String skill;
  String sourceRef;
  String keywords;
  int points;
  List<AnswerOption> options;

  Question({
    this.id,
    this.quizId = 0,
    this.position = 0,
    this.type = QType.single,
    this.prompt = '',
    this.imagePath,
    this.audioPath,
    this.difficulty = 2,
    this.skill = '',
    this.sourceRef = '',
    this.keywords = '',
    this.points = 1,
    List<AnswerOption>? options,
  }) : options = options ?? [];

  factory Question.fromMap(Map<String, Object?> m, List<AnswerOption> opts) => Question(
        id: _i(m['id']),
        quizId: _i(m['quiz_id']),
        position: _i(m['position']),
        type: QType.fromId(_s(m['type'])),
        prompt: _s(m['prompt']),
        imagePath: _sn(m['image_path']),
        audioPath: _sn(m['audio_path']),
        difficulty: _i(m['difficulty'], 2),
        skill: _s(m['skill']),
        sourceRef: _s(m['source_ref']),
        keywords: _s(m['keywords']),
        points: _i(m['points'], 1),
        options: opts,
      );

  Question copy() => Question(
        id: id,
        quizId: quizId,
        position: position,
        type: type,
        prompt: prompt,
        imagePath: imagePath,
        audioPath: audioPath,
        difficulty: difficulty,
        skill: skill,
        sourceRef: sourceRef,
        keywords: keywords,
        points: points,
        options: options.map((o) => o.copy()).toList(),
      );

  List<String> get keywordList => keywords
      .split(RegExp(r'[,،\n;؛]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// التحقق من صلاحية السؤال قبل النشر. يُرجع رسالة الخطأ أو null.
  String? validate() {
    if (prompt.trim().isEmpty && imagePath == null && audioPath == null) return 'نص السؤال فارغ';
    switch (type) {
      case QType.short:
        return null;
      case QType.order:
        if (options.length < 2) return 'الترتيب يحتاج إلى عنصرين على الأقل';
        if (options.any((o) => o.label.trim().isEmpty && o.imagePath == null)) return 'يوجد عنصر فارغ';
        return null;
      case QType.multi:
        if (options.length < 2) return 'يلزم اختياران على الأقل';
        if (!options.any((o) => o.isCorrect)) return 'حدد جوابًا صحيحًا واحدًا على الأقل';
        break;
      case QType.image:
        if (options.length < 2) return 'يلزم اختياران على الأقل';
        if (options.any((o) => o.imagePath == null && o.label.trim().isEmpty)) return 'أضف صورة أو نصًا لكل اختيار';
        if (options.where((o) => o.isCorrect).length != 1) return 'حدد جوابًا صحيحًا واحدًا';
        break;
      default:
        if (options.length < 2) return 'يلزم اختياران على الأقل';
        if (options.where((o) => o.isCorrect).length != 1) return 'حدد جوابًا صحيحًا واحدًا';
    }
    if (options.any((o) => o.label.trim().isEmpty && o.imagePath == null)) return 'يوجد اختيار فارغ';
    return null;
  }
}

class Quiz {
  final int id;
  final int storyId;
  String title;
  int level;
  int difficulty;
  String status; // draft | published
  String source; // manual | ai
  int passPercent;
  final String createdAt;
  final int questionCount;

  Quiz({
    required this.id,
    required this.storyId,
    this.title = '',
    required this.level,
    this.difficulty = 2,
    this.status = 'draft',
    this.source = 'manual',
    this.passPercent = 50,
    this.createdAt = '',
    this.questionCount = 0,
  });

  bool get published => status == 'published';

  factory Quiz.fromMap(Map<String, Object?> m) => Quiz(
        id: _i(m['id']),
        storyId: _i(m['story_id']),
        title: _s(m['title']),
        level: _i(m['level']),
        difficulty: _i(m['difficulty'], 2),
        status: _s(m['status']),
        source: _s(m['source']),
        passPercent: _i(m['pass_percent'], 50),
        createdAt: _s(m['created_at']),
        questionCount: _i(m['question_count']),
      );
}

/// جواب التلميذ: قائمة معرفات الاختيارات (بالترتيب) أو نص.
class StudentAnswer {
  final List<int> optionIds;
  final String text;
  const StudentAnswer({this.optionIds = const [], this.text = ''});

  bool get isEmpty => optionIds.isEmpty && text.trim().isEmpty;

  String toJson() => jsonEncode({'o': optionIds, 't': text});

  factory StudentAnswer.fromJson(String? s) {
    if (s == null || s.isEmpty) return const StudentAnswer();
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final o = (m['o'] as List? ?? const []).map((e) => _i(e)).toList();
      return StudentAnswer(optionIds: o, text: _s(m['t']));
    } catch (_) {
      return const StudentAnswer();
    }
  }
}

class Attempt {
  final String id;
  final int studentId;
  final int quizId;
  final int storyId;
  final int classId;
  final int attemptNo;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final double score;
  final double maxScore;
  final double percent;
  final String status; // in_progress | completed
  final bool needsReview;

  Attempt({
    required this.id,
    required this.studentId,
    required this.quizId,
    required this.storyId,
    required this.classId,
    required this.attemptNo,
    required this.startedAt,
    this.finishedAt,
    this.score = 0,
    this.maxScore = 0,
    this.percent = 0,
    this.status = 'in_progress',
    this.needsReview = false,
  });

  bool get completed => status == 'completed';

  factory Attempt.fromMap(Map<String, Object?> m) => Attempt(
        id: _s(m['id']),
        studentId: _i(m['student_id']),
        quizId: _i(m['quiz_id']),
        storyId: _i(m['story_id']),
        classId: _i(m['class_id']),
        attemptNo: _i(m['attempt_no'], 1),
        startedAt: DateTime.tryParse(_s(m['started_at'])) ?? DateTime.now(),
        finishedAt: DateTime.tryParse(_s(m['finished_at'])),
        score: _d(m['score']),
        maxScore: _d(m['max_score']),
        percent: _d(m['percent']),
        status: _s(m['status']),
        needsReview: _i(m['needs_review']) == 1,
      );
}
