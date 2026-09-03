import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../shared/state/auth_controller.dart';
import '../../shared/state/auth_state.dart';
import '../../shared/widgets/buttons.dart';

/// The first screen an unauthenticated customer sees.
///
/// One decision on it, and no form. Asking for a phone number before explaining
/// what the app does is how a sign-in screen becomes the last screen somebody
/// sees, so the value proposition comes first and the number comes on the next
/// screen.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    // Explains an unexpected arrival here. Without it, a customer whose token
    // was revoked simply finds themselves signed out with no reason given.
    final bool wasSignedOut =
        auth is AuthSignedOut && auth.reason == SignedOutReason.sessionExpired;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FotgSpacing.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // The copy scrolls; the action does not. Pinning the button means
              // it stays reachable at a 1.4x text scale on a short device,
              // which a single scroll view containing everything would not.
              //
              // The minHeight/center pair is what centres the copy when it fits
              // and lets it scroll when it does not. A Spacer cannot do this: a
              // scroll view gives its child unbounded height, and a flex child
              // in an unbounded column throws on layout.
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints available) =>
                      SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: available.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (wasSignedOut) ...<Widget>[
                                _SignedOutNotice(
                                  message: strings.authSessionExpiredNotice,
                                ),
                                const SizedBox(height: FotgSpacing.x6),
                              ],
                              const _BrandMark(),
                              const SizedBox(height: FotgSpacing.x8),
                              Text(
                                strings.authWelcomeTitle,
                                style: theme.textTheme.displaySmall,
                              ),
                              const SizedBox(height: FotgSpacing.x4),
                              Text(
                                strings.authWelcomeBody,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
              ),
              PrimaryButton(
                label: strings.authWelcomeCta,
                icon: Icons.smartphone_outlined,
                onPressed: () => context.go(Routes.authPhone),
              ),
              const SizedBox(height: FotgSpacing.x4),
              Text(
                strings.authWelcomeLegal,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: FotgRadius.card,
          ),
          child: Icon(
            Icons.route_outlined,
            size: FotgSizing.iconLg,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: FotgSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(strings.appName, style: theme.textTheme.titleLarge),
              Text(
                strings.tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: FotgRadius.control,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: FotgSizing.iconSm,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
