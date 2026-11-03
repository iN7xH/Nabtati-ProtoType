import 'package:flutter_test/flutter_test.dart';

import 'package:plant_doctor/main.dart';

void main() {
  testWidgets('Home screen shows the app title', (WidgetTester tester) async {
    await tester.pumpWidget(const PlantDoctorApp());
    expect(find.text('Plant Doctor'), findsOneWidget);
  });
}
