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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: FotgSpacing.x6,
          vertical: FotgSpacing.x8,
        ),
        child: ConstrainedBox(
          // Capped so the block stays a readable column on a large phone or a
          // tablet instead of stretching into a full-width banner.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RouteMotifIcon(icon: icon),
              const SizedBox(height: FotgSpacing.x6),
              Text(
                title,
                style: theme.textTheme.headlineMedium,
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
                const SizedBox(height: FotgSpacing.x6),
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
  }
}

/// The empty-state icon, set on the product's route motif: a soft dashed ring
/// standing in for a road, with the subject at its centre.
class _RouteMotifIcon extends StatelessWidget {
  const _RouteMotifIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
