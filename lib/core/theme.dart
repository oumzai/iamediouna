import 'package:flutter/material.dart';

/// ألوان هادئة وتربوية موحدة للواجهات الثلاث.
class AppColors {
  static const primary = Color(0xFF1F7A6D); // أخضر مائي
  static const primaryDark = Color(0xFF145A50);
  static const accent = Color(0xFFF6BE3C); // أصفر النجمة
  static const bg = Color(0xFFF6F8F7);
  static const card = Colors.white;
  static const admin = Color(0xFF2F5D8A); // أزرق للإدارة
  static const teacher = Color(0xFF1F7A6D); // أخضر للقسم
  static const student = Color(0xFFE07A3F); // برتقالي للتلاميذ
  static const danger = Color(0xFFC0392B);
  static const ok = Color(0xFF2E8B57);
  static const muted = Color(0xFF6B7B78);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Tajawal');
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    textTheme: base.textTheme.apply(fontFamily: 'Tajawal').copyWith(
          bodyMedium: const TextStyle(fontFamily: 'Tajawal', fontSize: 16),
          bodyLarge: const TextStyle(fontFamily: 'Tajawal', fontSize: 17),
        ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(120, 52),
        textStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(110, 50),
        textStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 1,
      margin: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
