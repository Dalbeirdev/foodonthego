import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The placeholder that keeps Module 01 honest on mobile.
///
/// Every tab without a feature behind it renders this: it says in words that the
/// screen is scaffolding and names the module that will replace it. Nothing here
/// may look like a working feature — that is a requirement of the module spec.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    required this.icon,
    required this.title,
    required this.module,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String module;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: FotgRadius.card,
              ),
              child: Icon(
                icon,
                size: 34,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: FotgSpacing.x5),
            Text(
              title,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FotgSpacing.x2),
            Chip(
              label: const Text('Not built yet'),
              backgroundColor: theme.brightness == Brightness.dark
                  ? const Color(0xFF241A06)
                  : FotgColors.warningSurface,
              // Derived from the theme rather than constructed fresh, so it keeps
              // the app font family.
              labelStyle: theme.textTheme.labelSmall!.copyWith(
                color: theme.brightness == Brightness.dark
                    ? FotgColors.darkWarning
                    : FotgColors.warning,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide.none,
            ),
            const SizedBox(height: FotgSpacing.x4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: FotgSpacing.x5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(FotgSpacing.x4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: FotgRadius.control,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text(
                  'Scheduled for $module. This screen is navigation scaffolding — it holds no data '
                  'and calls no API.',
                  style: theme.textTheme.labelMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
