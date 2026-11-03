// config.dart - the ONE place for the API address.
//
// Default: Android emulator -> http://10.0.2.2:8000 (10.0.2.2 = "your PC" as seen from the emulator)
//
// Real phone: no code change needed, pass the PC's local IP when running:
//   flutter run --dart-define=API_BASE_URL=http://192.168.1.15:8000
// (Phone and PC on the same Wi-Fi, uvicorn started with --host 0.0.0.0,
//  PC's IP from `ipconfig` -> "IPv4 Address".)

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// How long to wait for the API before giving up.
const Duration requestTimeout = Duration(seconds: 30);
