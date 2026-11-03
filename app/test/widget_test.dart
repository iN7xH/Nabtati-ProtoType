import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plant_doctor/main.dart';

void main() {
  testWidgets('Home screen is Arabic and right-to-left', (WidgetTester tester) async {
    await tester.pumpWidget(const NabtatiApp());
    await tester.pumpAndSettle();

    expect(find.text('Nabtati'), findsOneWidget); // app bar title
    expect(find.text('اختيار صورة من المعرض'), findsOneWidget); // Gallery button
    expect(find.byIcon(Icons.camera_alt), findsNothing); // camera removed
    expect(find.text('تشخيص'), findsOneWidget); // Diagnose button

    // Layout direction comes from the Arabic locale.
    final context = tester.element(find.text('تشخيص'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
