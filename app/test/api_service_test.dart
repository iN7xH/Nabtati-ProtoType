// Tests for ApiService using a FAKE server (MockClient), so no API needs to be running.
// Run with:  flutter test

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plant_doctor/api_service.dart';

void main() {
  late File image;

  setUp(() {
    image = File('${Directory.systemTemp.path}/plant_doctor_test.jpg')
      ..writeAsBytesSync([1, 2, 3]);
  });

  // Helper: fake server that always answers with `status` and `body`.
  MockClient server(int status, String body) =>
      MockClient((request) async => http.Response(body, status));

  test('200 -> parses the prediction', () async {
    final client = server(200, '''
      {"label":"tomato__late_blight","crop":"tomato","disease":"late_blight",
       "is_healthy":false,"confidence":0.92,
       "top3":[{"label":"tomato__late_blight","confidence":0.92}]}''');

    final p = await ApiService.predict(image, client: client);
    expect(p.crop, 'tomato');
    expect(p.disease, 'late_blight');
    expect(p.isHealthy, false);
    expect(p.confidence, 0.92);
  });

  test('sends the file in the "image" field', () async {
    String? sentBody;
    final client = MockClient((request) async {
      sentBody = request.body; // MockClient gives us the encoded multipart body
      return http.Response('{"error":"x"}', 400);
    });
    await expectLater(ApiService.predict(image, client: client), throwsA(isA<ApiException>()));
    expect(sentBody, contains('name="image"'));
  });

  test('400 -> shows the server error message', () async {
    final client = server(400, '{"error":"File is not a valid image."}');
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'File is not a valid image.')),
    );
  });

  test('500 -> generic server error', () async {
    final client = server(500, '{"error":"boom"}');
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Server error (500)'))),
    );
  });

  test('200 with non-JSON body -> invalid response', () async {
    final client = server(200, '<html>oops</html>');
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('invalid response'))),
    );
  });

  test('200 with missing fields -> unexpected format', () async {
    final client = server(200, '{"label":"tomato__healthy"}');
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('unexpected'))),
    );
  });

  test('connection refused (ClientException) -> friendly message', () async {
    final client = MockClient((_) async => throw http.ClientException(
        'SocketException: Connection refused', Uri.parse('http://10.0.2.2:8000/predict')));
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Cannot reach'))),
    );
  });

  test('server unreachable -> friendly message', () async {
    final client = MockClient((_) async => throw const SocketException('refused'));
    expect(
      () => ApiService.predict(image, client: client),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Cannot reach'))),
    );
  });
}
