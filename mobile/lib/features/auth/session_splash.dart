import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';

/// What is on screen while the app reads secure storage on launch.
///
/// It exists specifically to prevent a flash: without it, the first frame shows
/// either the welcome screen (wrong for a returning customer) or the home screen
/// (wrong for everybody else), and then swaps. Neither is a long wait — reading
/// the Keychain is milliseconds — but a swap at 60fps is exactly the kind of
/// jank that makes an app feel unfinished.
///
/// No spinner. A spinner for a 40ms operation is a flicker; the brand mark held
/// steady reads as intentional.
class SessionSplash extends StatelessWidget {
  const SessionSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: FotgRadius.card,
              ),
              child: Icon(
                Icons.route_outlined,
                size: 34,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: FotgSpacing.x5),
            Text(strings.appName, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
