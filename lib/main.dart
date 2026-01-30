import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  runApp(const GasAhorroApp());
}
