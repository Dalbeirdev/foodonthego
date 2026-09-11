import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/app_strings.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'dev/development_harness.dart';
import 'features/auth/session_splash.dart';
import 'shared/state/auth_controller.dart';
import 'shared/state/auth_state.dart';

/// The router lives in a provider so a test can override it with one pointed at
/// a specific initial route, and so it is created once rather than on rebuild —
/// recreating a GoRouter loses the navigation stack.
final routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = createRouter(ref: ref);
  ref.onDispose(router.dispose);
  return router;
});

/// FoodOnTheGo — customer application root.
///
/// Everything global is configured here and nowhere else: theme, localization,
/// routing and scroll behaviour. A screen that needs one of them reads it from
/// context rather than configuring its own.
class FoodOnTheGoApp extends ConsumerWidget {
  const FoodOnTheGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    // Watched here rather than inside a screen because the answer decides what
    // the *whole* app shows for its first frames.
    final bool restoring = ref.watch(authControllerProvider) is AuthRestoring;

    return MaterialApp.router(
      title: 'FoodOnTheGo',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: FotgTheme.light(),
      darkTheme: FotgTheme.dark(),
      // Follows the OS. A phone in a windscreen cradle at night is in dark mode
      // for a reason, and overriding that choice is not ours to make.
      themeMode: ThemeMode.system,
      localizationsDelegates: <LocalizationsDelegate<Object>>[
        const AppStringsDelegate(),
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppStringsDelegate.supportedLocales,
      builder: (BuildContext context, Widget? child) {
        // Text scaling is honoured, but clamped at the top. Android allows up to
        // 2.0x, which turns a 34sp greeting into 68sp and pushes the primary
        // action off screen; 1.4x keeps large-print settings working while the
        // layout still holds. The floor stops a device-wide shrink making the
        // app illegible in a moving vehicle.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.4,
            ),
          ),
          // The harness returns its child untouched outside development, so this
          // wrapper costs a production build nothing.
          //
          // The splash replaces the routed page rather than covering it, so the
          // home screen behind it never builds and never fires a request for a
          // customer who turns out not to be signed in.
          child: DevelopmentHarness(
            child: restoring
                ? const SessionSplash()
                : (child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
