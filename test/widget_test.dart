import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktabati/ui/widgets/common.dart';

void main() {
  testWidgets('لوحة الأرقام تُرجع الرمز بعد إدخال 4 أرقام', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: PinPad(length: 4, onDone: (v) => result = v))),
    ));
    for (final d in ['2', '4', '6', '8']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    expect(result, '2468');
  });

  testWidgets('البطاقة الكبيرة تعرض العنوان وتستجيب للضغط', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BigTile(icon: Icons.book, label: 'قصصي', onTap: () => tapped = true)),
    ));
    expect(find.text('قصصي'), findsOneWidget);
    await tester.tap(find.text('قصصي'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('رسم الأعمدة يعرض التسميات', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SimpleBars(labels: ['أ', 'ب'], values: [3, 5])),
    ));
    expect(find.text('أ'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });
}
