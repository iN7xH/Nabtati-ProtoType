// api_service.dart - everything about talking to the Python API lives here.
// The screen (main.dart) only calls ApiService.predict(file) and gets a Prediction back,
// or catches an ApiException whose message can be shown to the user as-is.

import 'dart:async'; // TimeoutException
import 'dart:convert'; // jsonDecode
import 'dart:io'; // File, SocketException

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:http/http.dart' as http;

import 'config.dart';

/// One prediction result, built from the API's JSON response.
/// (Like a Python dataclass: just holds the fields.)
class Prediction {
  final String label; // e.g. "tomato__late_blight"
  final String crop; // e.g. "tomato"
  final String disease; // e.g. "late_blight" or "healthy"
  final bool isHealthy;
  final double confidence; // 0.0 - 1.0

  Prediction({
    required this.label,
    required this.crop,
    required this.disease,
    required this.isHealthy,
    required this.confidence,
  });

  /// Build a Prediction from the decoded JSON map.
  /// `factory` = a constructor that can run code before creating the object.
  /// Throws if a field is missing or has the wrong type (caught in ApiService).
  factory Prediction.fromJson(Map<String, dynamic> json) {
    return Prediction(
      label: json['label'] as String,
      crop: json['crop'] as String,
      disease: json['disease'] as String,
      isHealthy: json['is_healthy'] as bool,
      confidence: (json['confidence'] as num).toDouble(), // num = int or double
    );
  }
}

/// An error with a message that is friendly enough to show on screen.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

// Messages shown to the user (Arabic UI).
const String _unreachableMessage =
    'تعذّر الاتصال بالخادم.\n'
    'تأكد أن الخادم يعمل وأن الهاتف والحاسوب على نفس شبكة الواي فاي.\n'
    '($apiBaseUrl)';
const String _timeoutMessage = 'استغرق الخادم وقتاً طويلاً للرد، حاول مرة أخرى.';
const String _fileMessage = 'تعذّرت قراءة الصورة المختارة، اخترها مرة أخرى.';
const String _invalidResponseMessage = 'وصل رد غير صالح من الخادم.';
const String _unexpectedFormatMessage = 'وصل رد بصيغة غير متوقعة من الخادم.';
const String _rejectedImageMessage = 'الصورة غير صالحة، اختر صورة بصيغة JPG أو PNG.';
String _serverErrorMessage(int code) => 'حدث خطأ في الخادم ($code)، حاول لاحقاً.';

class ApiService {
  /// Sends the image to POST /predict and returns the parsed result.
  /// Always throws ApiException (never anything else) when something goes wrong.
  /// `client` is only passed by tests (to fake the server); the app uses the default.
  static Future<Prediction> predict(File image, {http.Client? client}) async {
    final uri = Uri.parse('$apiBaseUrl/predict');
    final httpClient = client ?? http.Client();

    final http.Response response;
    try {
      // multipart/form-data with the file in the field named "image" (API contract).
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('image', image.path));
      // `..` is Dart's "cascade": call .files.add on the same object, then return the object.

      final streamed = await httpClient.send(request).timeout(requestTimeout);
      response = await http.Response.fromStream(streamed).timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException(_timeoutMessage);
    } on SocketException {
      throw ApiException(_unreachableMessage);
    } on http.ClientException {
      // The http package wraps "connection refused" etc. in a ClientException.
      throw ApiException(_unreachableMessage);
    } on FileSystemException {
      throw ApiException(_fileMessage);
    } finally {
      if (client == null) httpClient.close(); // free the connection we opened
    }

    // Try to decode the body as JSON (it may not be JSON, e.g. a proxy error page).
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200) {
      if (body == null) throw ApiException(_invalidResponseMessage);
      try {
        return Prediction.fromJson(body);
      } catch (_) {
        throw ApiException(_unexpectedFormatMessage);
      }
    }

    // 400 / 500 -> the API sends {"error": "..."} in English.
    // Show an Arabic message to the user; print the English detail for debugging.
    debugPrint('API error ${response.statusCode}: ${body?['error'] ?? response.body}');
    if (response.statusCode == 400) {
      throw ApiException(_rejectedImageMessage);
    }
    throw ApiException(_serverErrorMessage(response.statusCode));
  }
}
