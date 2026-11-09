import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/db.dart';
import 'services/backup_service.dart';
import 'ui/start_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;
  try {
    await AppDb.I.init();
    await BackupService.autoBackup();
  } catch (e) {
    startupError = e.toString();
  }
  runApp(MaktabatiApp(startupError: startupError));
}

class MaktabatiApp extends StatelessWidget {
  final String? startupError;
  const MaktabatiApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتبتي الصفية الذكية',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: startupError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('تعذر تشغيل قاعدة البيانات:\n$startupError', textAlign: TextAlign.center),
                ),
              ),
            )
          : const StartScreen(),
    );
  }
}
