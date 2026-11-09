/// أدوات عربية: تطبيع النص، أسماء الأشهر، المستويات، أوصاف القراء.
/// ملف Dart خالص (بدون Flutter) لكي يمكن اختباره.
class Ar {
  Ar._();

  /// أسماء الأشهر كما تُستعمل في المغرب.
  static const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'ماي', 'يونيو',
    'يوليوز', 'غشت', 'شتنبر', 'أكتوبر', 'نونبر', 'دجنبر',
  ];

  static String monthName(int m) => months[(m - 1) % 12];

  /// تطبيع النص العربي للمقارنة: حذف التشكيل والتطويل وتوحيد الهمزات والتاء المربوطة والياء.
  static String normalize(String input) {
    var s = input.trim().toLowerCase();
    final buf = StringBuffer();
    for (final r in s.runes) {
      // التشكيل U+064B..U+0652 و U+0670 والتطويل U+0640
      if ((r >= 0x064B && r <= 0x0652) || r == 0x0670 || r == 0x0640) continue;
      switch (r) {
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0671: // ٱ
          buf.writeCharCode(0x0627); // ا
          break;
        case 0x0629: // ة
          buf.writeCharCode(0x0647); // ه
          break;
        case 0x0649: // ى
        case 0x0626: // ئ
          buf.writeCharCode(0x064A); // ي
          break;
        case 0x0624: // ؤ
          buf.writeCharCode(0x0648); // و
          break;
        default:
          // الأرقام العربية المشرقية ← أرقام لاتينية
          if (r >= 0x0660 && r <= 0x0669) {
            buf.writeCharCode(0x30 + (r - 0x0660));
          } else if (_isPunct(r)) {
            buf.write(' ');
          } else {
            buf.writeCharCode(r);
          }
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isPunct(int r) {
    const p = '.,;:!?،؛؟«»"\'()[]{}-_/\\…';
    return p.runes.contains(r);
  }

  /// حذف المسافات الزائدة (مثلاً " الأولى  أولي " ← "الأولى أولي").
  static String clean(String? s) => (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ---------------- المستويات ----------------

  /// رموز المستوى: 1..6 للابتدائي، 91 و 92 للتعليم الأولي، 0 غير معروف.
  static const int preschool1 = 91;
  static const int preschool2 = 92;

  static bool isPrimary(int level) => level >= 1 && level <= 6;
  static bool isPreschool(int level) => level == preschool1 || level == preschool2;

  static String levelName(int level) {
    switch (level) {
      case 1: return 'الأول ابتدائي';
      case 2: return 'الثاني ابتدائي';
      case 3: return 'الثالث ابتدائي';
      case 4: return 'الرابع ابتدائي';
      case 5: return 'الخامس ابتدائي';
      case 6: return 'السادس ابتدائي';
      case preschool1: return 'الأولى أولي';
      case preschool2: return 'الثانية أولي';
      default: return 'مستوى غير محدد';
    }
  }

  static String levelShort(int level) {
    if (isPrimary(level)) return 'م$level';
    if (level == preschool1) return 'أولي 1';
    if (level == preschool2) return 'أولي 2';
    return '؟';
  }

  /// استخراج المستوى من رمز القسم (1APG-1 ← 1، PS2-1 ← 92) أو من اسم المستوى.
  static int levelFromCode(String code, [String? levelName]) {
    final c = code.trim().toUpperCase();
    final ap = RegExp(r'^([1-6])\s*AP').firstMatch(c);
    if (ap != null) return int.parse(ap.group(1)!);
    final ps = RegExp(r'^PS\s*([12])').firstMatch(c);
    if (ps != null) return ps.group(1) == '1' ? preschool1 : preschool2;
    final n = clean(levelName);
    if (n.isNotEmpty) {
      if (n.contains('أولي')) {
        return (n.contains('الثانية') || n.contains('ثانية')) ? preschool2 : preschool1;
      }
      const words = {
        'الأول': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4, 'الخامس': 5, 'السادس': 6,
      };
      for (final e in words.entries) {
        if (n.startsWith(e.key)) return e.value;
      }
    }
    final d = RegExp(r'^([1-6])').firstMatch(c);
    if (d != null) return int.parse(d.group(1)!);
    return 0;
  }

  // ---------------- أوصاف القراء (تربوية وقابلة للمراجعة) ----------------

  static const readingLevels = [
    'لم ينجز التقييم بعد',
    'يحتاج إلى دعم في الفهم',
    'قارئ مبتدئ',
    'قارئ في طور التطور',
    'قارئ جيد',
    'قارئ متميز',
  ];

  static String readingLevelName(int l) =>
      readingLevels[l.clamp(0, readingLevels.length - 1).toInt()];

  /// صيغة حسب الجنس: g('ذكر'/'أنثى')
  static String byGender(String? gender, String male, String female) =>
      (gender ?? '').contains('أنث') ? female : male;

  static const difficultyNames = {1: 'سهل', 2: 'متوسط', 3: 'صعب'};

  static String percent(num? v) => v == null ? '—' : '${v.round()}%';

  /// "2026/2027" للموسم الحالي حسب التاريخ (يبدأ الموسم في شتنبر).
  static String currentSchoolYear([DateTime? now]) {
    final d = now ?? DateTime.now();
    final start = d.month >= 8 ? d.year : d.year - 1;
    return '$start/${start + 1}';
  }

  static String formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
