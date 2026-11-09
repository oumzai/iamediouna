import 'package:flutter/foundation.dart';

import '../data/models.dart';

enum Role { none, admin, teacher, student }

/// الجلسة الحالية وصلاحياتها. يُفصل المدير عن القسم عن التلميذ.
class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  Role role = Role.none;
  SchoolClass? cls; // قسم الأستاذ (أو القسم الذي فتح فضاء التلاميذ)
  Student? student;
  bool adminViewingClass = false;

  int _failed = 0;
  DateTime? _lockedUntil;

  bool get isAdmin => role == Role.admin;

  String get actor {
    switch (role) {
      case Role.admin:
        return 'المدير';
      case Role.teacher:
        return 'القسم ${cls?.code ?? ''}';
      case Role.student:
        return 'التلميذ ${student?.massarCode ?? ''}';
      case Role.none:
        return 'غير معروف';
    }
  }

  void loginAdmin() {
    role = Role.admin;
    cls = null;
    student = null;
    _failed = 0;
    notifyListeners();
  }

  void loginTeacher(SchoolClass c) {
    role = Role.teacher;
    cls = c;
    student = null;
    _failed = 0;
    notifyListeners();
  }

  /// يبقى القسم مفتوحًا (فضاء التلاميذ) ويدخل التلميذ.
  void loginStudent(Student s) {
    role = Role.student;
    student = s;
    notifyListeners();
  }

  /// إنهاء جلسة التلميذ وإخفاء معلوماته (العودة إلى لائحة القسم).
  void logoutStudent() {
    student = null;
    role = cls != null ? Role.teacher : Role.none;
    notifyListeners();
  }

  void logout() {
    role = Role.none;
    cls = null;
    student = null;
    notifyListeners();
  }

  /// حماية من التخمين: بعد 5 محاولات خاطئة يُقفل الدخول 30 ثانية.
  String? checkLocked() {
    final l = _lockedUntil;
    if (l != null && DateTime.now().isBefore(l)) {
      final s = l.difference(DateTime.now()).inSeconds + 1;
      return 'محاولات كثيرة خاطئة. أعد المحاولة بعد $s ثانية.';
    }
    return null;
  }

  void registerFailure() {
    _failed++;
    if (_failed >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
      _failed = 0;
    }
  }

  void registerSuccess() {
    _failed = 0;
    _lockedUntil = null;
  }
}
