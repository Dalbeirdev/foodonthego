import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../domain/repositories/home_repository.dart';
import 'buttons.dart';

/// The shared error screen.
///
/// It maps a [HomeFailureKind] to a cause the customer can act on. It never
/// renders an exception message: a raw error is meaningless to a traveller, and
/// a stack trace in a screenshot is an information leak.
class AppErrorView extends StatelessWidget {
  const AppErrorView({required this.kind, this.onRetry, super.key});

  final HomeFailureKind kind;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final (IconData icon, String title, String body) = switch (kind) {
      HomeFailureKind.offline => (
        Icons.wifi_off_rounded,
        strings.errorOfflineTitle,
        strings.errorOfflineBody,
      ),
      HomeFailureKind.timeout => (
        Icons.hourglass_empty_rounded,
        strings.errorTimeoutTitle,
        strings.errorTimeoutBody,
      ),
      HomeFailureKind.serverUnavailable => (
        Icons.cloud_off_rounded,
        strings.errorServerTitle,
        strings.errorServerBody,
      ),
      HomeFailureKind.unknown => (
        Icons.error_outline_rounded,
        strings.errorGenericTitle,
        strings.errorGenericBody,
      ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: FotgSpacing.x6,
          vertical: FotgSpacing.x8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: FotgSpacing.x5),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FotgSpacing.x2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: FotgSpacing.x6),
                PrimaryButton(
                  label: strings.retry,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                  expand: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
