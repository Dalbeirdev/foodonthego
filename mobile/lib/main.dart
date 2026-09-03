import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Required before touching platform channels (SystemChrome) ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only for now. The customer app is used one-handed, often in a
  // cradle; landscape is a real layout with real work behind it, and shipping a
  // stretched portrait layout would be worse than not offering it.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge-to-edge, with transparent system bars: the app paints under the status
  // and gesture bars, and every screen uses SafeArea to keep content clear of
  // them. This is what makes a notch or a Dynamic Island look deliberate.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: FoodOnTheGoApp()));
}
