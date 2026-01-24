import 'dart:io' show Platform;

const _webKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY_WEB',
  defaultValue: '',
);
const _androidKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY_ANDROID',
  defaultValue: '',
);
const _iosKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY_IOS',
  defaultValue: '',
);
const _defaultKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
);

String get googleMapsApiKey {
  if (_webKey.isNotEmpty) {
    return _webKey;
  }
  if (Platform.isAndroid && _androidKey.isNotEmpty) {
    return _androidKey;
  }
  if (Platform.isIOS && _iosKey.isNotEmpty) {
    return _iosKey;
  }
  if (_androidKey.isEmpty && _iosKey.isEmpty && _defaultKey.isNotEmpty) {
    return _defaultKey;
  }
  return '';
}
