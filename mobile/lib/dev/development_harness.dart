import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/theme/tokens.dart';
import '../data/fixtures/development_personas.dart';
import '../domain/repositories/home_repository.dart';
import '../shared/state/connectivity.dart';
import '../shared/state/providers.dart';

/// A floating control that switches persona, connectivity and failure state.
///
/// It exists so the eleven required states can be inspected in a running app
/// rather than only asserted in tests — you cannot see a skeleton or an offline
/// banner in a passing test. It renders only where the environment allows
/// fixtures, and is not part of the customer UI.
class DevelopmentHarness extends ConsumerStatefulWidget {
  const DevelopmentHarness({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DevelopmentHarness> createState() => _DevelopmentHarnessState();
}

class _DevelopmentHarnessState extends ConsumerState<DevelopmentHarness> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!AppEnvironment.current.allowsFixtures) return widget.child;

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          left: 8,
          bottom: 96,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: _expanded ? _panel(context) : _handle(context),
            ),
          ),
        ),
      ],
    );
  }

  /// Built from Material + InkWell rather than a FloatingActionButton.
  ///
  /// This widget is installed through `MaterialApp.builder`, which sits ABOVE
  /// the Navigator — so there is no Overlay ancestor here, and anything needing
  /// one (a FAB's Tooltip, a Hero) asserts at runtime. Sitting above the
  /// Navigator is deliberate: it is what keeps the handle visible on every
  /// route, including a pushed placeholder.
  Widget _handle(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Semi-transparent: it floats over real content, and a developer needs to
    // read what is underneath it more often than they need to open it.
    return Opacity(
      opacity: 0.55,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.science_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DevelopmentPersona persona = ref.watch(developmentPersonaProvider);
    final HomeFailureKind? failure = ref.watch(
      developmentForcedFailureProvider,
    );
    final ConnectivityService connectivity = ref.watch(
      connectivityServiceProvider,
    );
    final bool offline =
        connectivity is ControllableConnectivity &&
        connectivity.status == ConnectivityStatus.offline;

    return Container(
      width: 236,
      padding: const EdgeInsets.all(FotgSpacing.x3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: FotgRadius.card,
        border: Border.all(color: theme.colorScheme.outline),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Development harness',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _expanded = false),
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(),
          Text('Persona', style: theme.textTheme.labelSmall),
          // RadioGroup, not per-tile onChanged: Flutter deprecated the latter
          // after 3.32.
          RadioGroup<DevelopmentPersona>(
            groupValue: persona,
            onChanged: (DevelopmentPersona? next) {
              if (next == null) return;
              ref.read(developmentPersonaProvider.notifier).select(next);
              ref.invalidate(homeDashboardProvider);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final DevelopmentPersona option
                    in DevelopmentPersona.values)
                  RadioListTile<DevelopmentPersona>(
                    value: option,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      option.label,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            value: offline,
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text('Offline', style: theme.textTheme.labelMedium),
            onChanged: (bool value) {
              if (connectivity is ControllableConnectivity) {
                connectivity.set(
                  value
                      ? ConnectivityStatus.offline
                      : ConnectivityStatus.online,
                );
              }
            },
          ),
          SwitchListTile(
            value: failure != null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text('Force failure', style: theme.textTheme.labelMedium),
            onChanged: (bool value) {
              ref
                  .read(developmentForcedFailureProvider.notifier)
                  .select(value ? HomeFailureKind.serverUnavailable : null);
              ref.invalidate(homeDashboardProvider);
            },
          ),
        ],
      ),
    );
  }
}
