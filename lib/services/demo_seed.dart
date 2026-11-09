import 'dart:math';

import '../core/security.dart';
import '../data/db.dart';
import '../data/library_repo.dart';
import '../data/models.dart';
import '../data/school_repo.dart';

/// بيانات تجريبية وهمية بالكامل لتجربة الواجهات (لا علاقة لها بأي تلميذ حقيقي).
class DemoSeed {
  DemoSeed._();

  static const adminPassword = 'admin123';
  static const classPassword = 'demo1234';
  static const studentPin = '2468';

  static const _firsts = ['آدم', 'ياسين', 'سلمى', 'مريم', 'هبة', 'رياض', 'نور', 'سارة', 'حمزة', 'عمر', 'زينب', 'أيوب', 'آية', 'إلياس', 'لينا', 'بلال'];
  static const _lasts = ['العلوي', 'الإدريسي', 'بنعلي', 'الفاسي', 'الحسني', 'بوزيد', 'التازي', 'السوسي', 'الكتاني', 'الوزاني'];

  static Future<void> seed() async {
    final db = AppDb.I.db;
    final rnd = Random(7);
    await SchoolRepo.saveSchool(School(
      name: 'مدرسة تجريبية (بيانات وهمية)',
      code: 'DEMO',
      academy: 'الدار البيضاء - سطات',
      directorate: 'مديونة',
      commune: 'جماعة تجريبية',
      directorName: 'المدير التجريبي',
    ));
    await SchoolRepo.createAdmin(adminPassword);
    final year = await SchoolRepo.currentYear();
    await SchoolRepo.setSetting(SchoolRepo.kDemo, '1');

    final classHash = Security.hashPassword(classPassword);
    final pinHash = Security.hashPassword(studentPin, iterations: Security.pinIterations);
    final now = AppDb.now();
    final classIds = <int, int>{};
    final studentIds = <int, List<int>>{};
    var codeN = 100000000;
    for (final level in [1, 3, 5]) {
      final cid = await db.insert('classes', {
        'year_id': year.id,
        'code': '${level}APG-1',
        'level': level,
        'level_name': '${['', 'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس'][level]} ابتدائي',
        'teacher_name': 'أستاذ(ة) تجريبي(ة)',
        'pass_hash': classHash.hash,
        'pass_salt': classHash.salt,
        'iterations': classHash.iterations,
        'active': 1,
        'created_at': now,
      });
      classIds[level] = cid;
      studentIds[cid] = [];
      for (var i = 0; i < 12; i++) {
        codeN += rnd.nextInt(5000) + 1;
        final sid = await db.insert('students', {
          'massar_code': 'Z$codeN',
          'last_name': _lasts[rnd.nextInt(_lasts.length)],
          'first_name': _firsts[(i + level) % _firsts.length],
          'gender': i.isEven ? 'ذكر' : 'أنثى',
          'class_id': cid,
          'pin_hash': pinHash.hash,
          'pin_salt': pinHash.salt,
          'reading_level': 0,
          'archived': 0,
          'created_at': now,
        });
        studentIds[cid]!.add(sid);
      }
    }

    final stories = [
      ('الأرنب والسلحفاة', [1, 2]),
      ('رحلة إلى الغابة', [1, 2, 3]),
      ('سرّ المكتبة القديمة', [3, 4]),
      ('مغامرة في الصحراء', [5, 6]),
      ('الطائر الصغير', [1, 3, 5]),
    ];
    final quizByStory = <int, int>{};
    final storyIds = <int>[];
    for (final (title, levels) in stories) {
      final assign = levels.map((l) => classIds[l]).whereType<int>().toList();
      final sid = await LibraryRepo.createStory(
        title: title,
        author: 'قصة تجريبية',
        levels: levels,
        assignToClassIds: assign,
        actor: 'بيانات تجريبية',
      );
      storyIds.add(sid);
      for (final l in levels.where(classIds.containsKey)) {
        final qid = await LibraryRepo.createQuiz(storyId: sid, level: l, title: 'اختبار $title', actor: 'بيانات تجريبية');
        await LibraryRepo.saveQuestions(qid, _questions(title));
        await LibraryRepo.setQuizStatus(qid, 'published', 'بيانات تجريبية');
        quizByStory[sid * 10 + l] = qid;
      }
    }

    // نتائج وهمية خلال الشهرين الأخيرين
    final today = DateTime.now();
    for (final level in classIds.keys) {
      final cid = classIds[level]!;
      final levelStories = <int>[];
      for (var i = 0; i < stories.length; i++) {
        if (stories[i].$2.contains(level)) levelStories.add(storyIds[i]);
      }
      for (final sid in studentIds[cid]!) {
        final ability = 35 + rnd.nextInt(60);
        for (final storyId in levelStories) {
          if (rnd.nextDouble() < 0.25) continue;
          final qid = quizByStory[storyId * 10 + level];
          if (qid == null) continue;
          final d = today.subtract(Duration(days: rnd.nextInt(55), hours: rnd.nextInt(6)));
          final pct = (ability + rnd.nextInt(25) - 10).clamp(0, 100).toDouble();
          await db.insert('quiz_attempts', {
            'id': Security.uuid(),
            'student_id': sid,
            'quiz_id': qid,
            'story_id': storyId,
            'class_id': cid,
            'year_id': year.id,
            'attempt_no': 1,
            'started_at': d.toIso8601String(),
            'finished_at': d.add(const Duration(minutes: 6)).toIso8601String(),
            'duration_sec': 360,
            'score': pct / 20,
            'max_score': 5,
            'percent': pct,
            'status': 'completed',
            'needs_review': 0,
            'device_id': 'demo',
          });
        }
      }
    }
    await SchoolRepo.audit('النظام', 'إنشاء بيانات تجريبية وهمية');
  }

  static List<Question> _questions(String title) => [
        Question(type: QType.single, prompt: 'من هي الشخصية الرئيسية في قصة «$title»؟', options: [
          AnswerOption(label: 'الشخصية الأولى', isCorrect: true),
          AnswerOption(label: 'الشخصية الثانية'),
          AnswerOption(label: 'الشخصية الثالثة'),
        ]),
        Question(type: QType.truefalse, prompt: 'وقعت أحداث القصة في الليل.', options: [
          AnswerOption(label: 'صح'),
          AnswerOption(label: 'خطأ', isCorrect: true),
        ]),
        Question(type: QType.order, prompt: 'رتّب أحداث القصة:', options: [
          AnswerOption(label: 'البداية'),
          AnswerOption(label: 'المشكلة'),
          AnswerOption(label: 'الحل'),
        ]),
        Question(type: QType.multi, prompt: 'اختر كل الأماكن التي ذُكرت في القصة:', options: [
          AnswerOption(label: 'البيت', isCorrect: true),
          AnswerOption(label: 'المدرسة', isCorrect: true),
          AnswerOption(label: 'البحر'),
        ]),
        Question(type: QType.short, prompt: 'ماذا تعلمت من هذه القصة؟', keywords: 'التعاون، الصبر، الصدق'),
      ];
}
