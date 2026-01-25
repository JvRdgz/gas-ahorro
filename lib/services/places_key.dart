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

String get googleMapsApiKey {
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

Map<String, String> get googleMapsWebServiceHeaders {
  if (Platform.isAndroid && _androidPackage.isNotEmpty && _androidSha1.isNotEmpty) {
    // ignore: avoid_print
    print('Maps headers: Android package=$_androidPackage cert=${_androidSha1.isNotEmpty ? "set" : "empty"}');
    return {
      'X-Android-Package': _androidPackage,
      'X-Android-Cert': _androidSha1,
    };
  }
  if (Platform.isIOS && _iosBundleId.isNotEmpty) {
    // ignore: avoid_print
    print('Maps headers: iOS bundle=$_iosBundleId');
    return {
      'X-Ios-Bundle-Identifier': _iosBundleId,
    };
  }
  // ignore: avoid_print
  print('Maps headers: empty (missing package/bundle or cert).');
  return {};
}
