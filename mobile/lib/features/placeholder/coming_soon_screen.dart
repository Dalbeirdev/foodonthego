import 'package:flutter/material.dart';

import '../../core/config/app_environment.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/empty_state_view.dart';

/// Where an unbuilt feature goes.
///
/// The rule this exists to satisfy: tapping a future feature must never show a
/// broken button and must never silently do nothing. It goes somewhere
/// deliberate that names the feature and the module delivering it.
///
/// **This screen is development scaffolding.** In production, features that are
/// off are hidden by their feature flag and this route is unreachable; if it is
/// somehow reached, it degrades to a neutral "not available yet" with no module
/// numbers and no internal language.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    required this.feature,
    required this.module,
    super.key,
  });

  final String feature;
  final String module;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final bool showsDevelopmentDetail =
        AppEnvironment.current.showsDevelopmentNotices;

    return Scaffold(
      appBar: AppBar(title: Text(feature)),
      body: SafeArea(
        child: EmptyStateView(
          icon: Icons.construction_rounded,
          title: feature,
          body: showsDevelopmentDetail
              ? strings.placeholderBody
              : 'This part of FoodOnTheGo is not available yet.',
          action: showsDevelopmentDetail
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FotgSpacing.x4,
                    vertical: FotgSpacing.x3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: FotgRadius.control,
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        strings.notBuiltYet.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: FotgSpacing.x1),
                      Text(
                        strings.comingInModule(module),
                        style: theme.textTheme.labelMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
