import 'dart:io' show Platform;

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
const _androidPackage = String.fromEnvironment(
  'ANDROID_PACKAGE_NAME',
  defaultValue: '',
);
const _androidSha1 = String.fromEnvironment(
  'ANDROID_SHA1_CERT',
  defaultValue: '',
);
const _iosBundleId = String.fromEnvironment(
  'IOS_BUNDLE_ID',
  defaultValue: '',
);
bool _loggedMapsKeyInfo = false;

String get googleMapsApiKey {
  String key;
  if (Platform.isAndroid && _androidKey.isNotEmpty) {
    key = _androidKey;
  } else if (Platform.isIOS && _iosKey.isNotEmpty) {
    key = _iosKey;
  } else if (_androidKey.isEmpty && _iosKey.isEmpty && _defaultKey.isNotEmpty) {
    key = _defaultKey;
  } else {
    key = '';
  }

  key = key.trim();
  if (!_loggedMapsKeyInfo) {
    _loggedMapsKeyInfo = true;
    // Log only a suffix to avoid exposing the full key.
    // ignore: avoid_print
    print(
      'Maps key suffix: ${key.isEmpty ? "empty" : key.substring(key.length - 4)} '
      'platform=${Platform.isAndroid ? "android" : Platform.isIOS ? "ios" : "other"}',
    );
  }
  return key;
}

Map<String, String> get googleMapsWebServiceHeaders {
  final androidPackage = _androidPackage.trim();
  final androidSha1 = _androidSha1
      .trim()
      .replaceAll(':', '')
      .replaceAll(' ', '')
      .toUpperCase();
  final iosBundleId = _iosBundleId.trim();
  if (Platform.isAndroid && androidPackage.isNotEmpty && androidSha1.isNotEmpty) {
    // ignore: avoid_print
    print(
      'Maps headers: Android package=$androidPackage cert=${androidSha1.isNotEmpty ? "set" : "empty"}',
    );
    return {
      'X-Android-Package': androidPackage,
      'X-Android-Cert': androidSha1,
    };
  }
  if (Platform.isIOS && iosBundleId.isNotEmpty) {
    // ignore: avoid_print
    print('Maps headers: iOS bundle=$iosBundleId');
    return {
      'X-Ios-Bundle-Identifier': iosBundleId,
    };
  }
  // ignore: avoid_print
  print('Maps headers: empty (missing package/bundle or cert).');
  return {};
}
