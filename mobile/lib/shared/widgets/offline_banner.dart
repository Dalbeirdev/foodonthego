import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../state/connectivity.dart';

/// The global offline indicator.
///
/// It sits below the status bar and above the content, and it **does not block**:
/// a traveller who has lost signal should still be able to read the order they
/// already have on screen. A modal "no connection" dialog would take away the
/// only useful thing left.
///
/// It animates in and out by size so the content below settles rather than
/// jumping, and it is a live region so a screen reader announces the change.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.status, super.key});

  final ConnectivityStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final bool isOffline = status == ConnectivityStatus.offline;

    return AnimatedSize(
      duration: FotgMotion.respectingReducedMotion(context, FotgMotion.normal),
      curve: FotgMotion.standard,
      alignment: Alignment.topCenter,
      child: isOffline
          ? Semantics(
              liveRegion: true,
              label: '${strings.offlineTitle}. ${strings.offlineBody}',
              excludeSemantics: true,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: FotgSpacing.x4,
                  vertical: FotgSpacing.x3,
                ),
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF241A06)
                    : FotgColors.warningSurface,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_off_rounded,
                      size: FotgSizing.iconSm,
                      color: theme.brightness == Brightness.dark
                          ? FotgColors.darkWarning
                          : FotgColors.warning,
                    ),
                    const SizedBox(width: FotgSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            strings.offlineTitle,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.brightness == Brightness.dark
                                  ? FotgColors.darkWarning
                                  : FotgColors.warning,
                            ),
                          ),
                          Text(
                            strings.offlineBody,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.brightness == Brightness.dark
                                  ? FotgColors.darkWarning
                                  : FotgColors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
