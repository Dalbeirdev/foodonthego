import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x3),
      child: Row(
        children: <Widget>[
          Expanded(
            // A heading for assistive technology, so a screen-reader user can
            // jump between sections instead of reading the page linearly.
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
