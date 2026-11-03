// Every class in the API's labels.txt must have an Arabic name in labels_ar.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plant_doctor/labels_ar.dart';

void main() {
  test('all 19 labels have Arabic crop and disease names', () {
    final labels = File('../api/labels.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    expect(labels.length, 19);

    for (final label in labels) {
      final parts = label.split('__');
      expect(cropNamesAr.containsKey(parts[0]), isTrue, reason: 'missing crop: ${parts[0]}');
      expect(diseaseNamesAr.containsKey(parts[1]), isTrue, reason: 'missing disease: ${parts[1]}');
    }
  });

  test('unknown keys fall back to readable English', () {
    expect(diseaseAr('new_disease'), 'new disease');
  });
}
