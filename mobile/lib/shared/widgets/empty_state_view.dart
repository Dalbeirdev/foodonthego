import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The shared empty state.
///
/// An empty screen is a moment of instruction, not an apology: it says what will
/// appear here, why it is worth having, and offers the one action that fills it.
/// "No data" with a grey box teaches nothing.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.footnote,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Widget? footnote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // On a short surface the full-size motif pushes the action below the
        // fold — measured at 320x568, the smallest screen the app supports,
        // where the button landed 13px past the bottom of the display. It is
        // reachable by scrolling, but a primary call to action that has to be
        // hunted for is a call to action most people never see.
        //
        // So the motif shrinks rather than the action disappearing. Nothing is
        // removed: the same icon, drawn smaller, with the ring dropped only
        // when there is genuinely no room for it.
        final bool compact = constraints.maxHeight < 420;

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: FotgSpacing.x6,
              vertical: compact ? FotgSpacing.x4 : FotgSpacing.x8,
            ),
            child: ConstrainedBox(
              // Capped so the block stays a readable column on a large phone or
              // a tablet instead of stretching into a full-width banner.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _RouteMotifIcon(icon: icon, compact: compact),
                  SizedBox(height: compact ? FotgSpacing.x4 : FotgSpacing.x6),
                  Text(
                    title,
                    style: compact
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: FotgSpacing.x3),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (action != null) ...<Widget>[
                    SizedBox(height: compact ? FotgSpacing.x4 : FotgSpacing.x6),
                    action!,
                  ],
                  if (footnote != null) ...<Widget>[
                    const SizedBox(height: FotgSpacing.x4),
                    footnote!,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The empty-state icon, set on the product's route motif: a soft dashed ring
/// standing in for a road, with the subject at its centre.
class _RouteMotifIcon extends StatelessWidget {
  const _RouteMotifIcon({required this.icon, this.compact = false});

  final IconData icon;

  /// Drops the ring and halves the disc. The motif is decoration; the action
  /// under it is not, and on a short screen only one of them fits.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (compact) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 26,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    }

    return SizedBox(
      width: 116,
      height: 116,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: const Size.square(116),
            painter: _DashedRingPainter(color: theme.colorScheme.outline),
          ),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 34,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const int dashes = 28;
    const double gapRatio = 0.45;
    final double radius = size.width / 2 - 1;
    final Offset centre = Offset(size.width / 2, size.height / 2);
    const double sweep = 2 * 3.1415926535 / dashes;

    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        i * sweep,
        sweep * (1 - gapRatio),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
