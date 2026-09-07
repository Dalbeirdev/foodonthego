import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// How serious a notice is, and therefore what it looks like.
enum CartNoticeTone {
  /// Something the customer must deal with before they could order.
  blocking,

  /// Something they should look at and decide about.
  advisory,

  /// Context, not a problem.
  neutral,
}

/// A banner above the cart, saying what changed.
///
/// One shape for every message so a customer learns to read them in one place,
/// and three tones because "your prices went up" and "this dish is gone" are
/// not the same news and must not look the same.
///
/// Colour is never the only signal: each tone has its own icon and its own
/// wording, so the difference survives a monochrome screen and a customer who
/// cannot tell amber from red.
class CartNotice extends StatelessWidget {
  const CartNotice({
    required this.title,
    required this.body,
    required this.tone,
    this.action,
    super.key,
  });

  final String title;
  final String body;
  final CartNoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final (Color colour, Color surface, IconData icon) = switch (tone) {
      CartNoticeTone.blocking => (
        FotgColors.error,
        FotgColors.errorSurface,
        Icons.remove_shopping_cart_outlined,
      ),
      CartNoticeTone.advisory => (
        FotgColors.warning,
        FotgColors.warningSurface,
        Icons.price_change_outlined,
      ),
      CartNoticeTone.neutral => (
        FotgColors.info,
        FotgColors.infoSurface,
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: FotgRadius.card,
        border: Border.all(color: colour.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
                const SizedBox(height: FotgSpacing.x1),
                Text(body, style: theme.textTheme.bodySmall),
                if (action case final Widget control) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x2),
                  control,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
