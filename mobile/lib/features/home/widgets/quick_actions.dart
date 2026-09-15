import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// A short row of secondary destinations.
///
/// Three, not twelve. A quick-action grid that lists everything is a second
/// navigation bar competing with the real one; these are the three places a
/// traveller actually reaches for outside the main flow.
class QuickActions extends StatelessWidget {
  const QuickActions({required this.actions, super.key});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: FotgSpacing.x3),
          Expanded(child: _QuickActionTile(action: actions[i])),
        ],
      ],
    );
  }
}

class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      label: action.label,
      // Same reason as the planner rows: without this the tile is announced as
      // a button and cannot be activated by assistive technology.
      onTap: action.onTap,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: FotgRadius.card,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: FotgRadius.card,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(
              vertical: FotgSpacing.x4,
              horizontal: FotgSpacing.x2,
            ),
            decoration: BoxDecoration(
              borderRadius: FotgRadius.card,
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  action.icon,
                  size: FotgSizing.iconMd,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: FotgSpacing.x2),
                Text(
                  action.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
