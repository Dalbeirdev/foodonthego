import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/buttons.dart';

/// The most important control in the app: start a journey.
///
/// It is presented as a route rather than as a form — an origin dot, a dashed
/// line, a destination pin — because that is the product in one glance, and
/// because two stacked text fields look like every other search screen.
///
/// The fields are **display-only in Module 02**. They are rendered as tappable
/// rows, not `TextField`s, so no keyboard opens onto a control that cannot accept
/// input. Tapping any of them goes to the same controlled placeholder as the CTA.
class JourneyPlannerCard extends StatelessWidget {
  const JourneyPlannerCard({
    required this.onPlanJourney,
    this.originLabel,
    this.destinationLabel,
    this.isEnabled = true,
    super.key,
  });

  final VoidCallback onPlanJourney;
  final String? originLabel;
  final String? destinationLabel;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: FotgRadius.card,
        border: Border.all(color: theme.colorScheme.outline),
        // A restrained warm wash rather than a flat white card: this is the hero
        // of the screen and needs to read as such without shouting.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? <Color>[const Color(0xFF241A10), theme.colorScheme.surface]
              : <Color>[FotgColors.primary50, theme.colorScheme.surface],
        ),
      ),
      padding: const EdgeInsets.all(FotgSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(strings.plannerTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: FotgSpacing.x5),
          _RouteField(
            marker: _RouteMarker.origin,
            label: strings.plannerFromLabel,
            value: originLabel ?? strings.plannerCurrentLocation,
            isPlaceholder: originLabel == null,
            onTap: isEnabled ? onPlanJourney : null,
          ),
          _RouteConnector(color: theme.colorScheme.outline),
          _RouteField(
            marker: _RouteMarker.destination,
            label: strings.plannerToLabel,
            value: destinationLabel ?? strings.plannerDestinationHint,
            isPlaceholder: destinationLabel == null,
            onTap: isEnabled ? onPlanJourney : null,
          ),
          const SizedBox(height: FotgSpacing.x5),
          PrimaryButton(
            label: strings.plannerCta,
            icon: Icons.near_me_rounded,
            onPressed: isEnabled ? onPlanJourney : null,
          ),
        ],
      ),
    );
  }
}

enum _RouteMarker { origin, destination }

class _RouteField extends StatelessWidget {
  const _RouteField({
    required this.marker,
    required this.label,
    required this.value,
    required this.isPlaceholder,
    this.onTap,
  });

  final _RouteMarker marker;
  final String label;
  final String value;
  final bool isPlaceholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: onTap != null,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FotgRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Center(child: _Marker(marker: marker)),
              ),
              const SizedBox(width: FotgSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPlaceholder
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (marker == _RouteMarker.origin)
                Icon(
                  Icons.my_location_rounded,
                  size: FotgSizing.iconSm,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: FotgSizing.iconMd,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.marker});

  final _RouteMarker marker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (marker == _RouteMarker.origin) {
      // A ringed dot — "you are here" — rather than a pin, which reads as a
      // destination and would make both ends look the same.
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.secondary, width: 4),
        ),
      );
    }

    return Icon(
      Icons.place_rounded,
      size: 22,
      color: theme.colorScheme.primary,
    );
  }
}

/// The dashed segment between origin and destination — the route motif that
/// recurs in the empty states and the journey card.
class _RouteConnector extends StatelessWidget {
  const _RouteConnector({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 13),
      child: SizedBox(
        width: 2,
        height: 22,
        child: CustomPaint(painter: _DashedLinePainter(color: color)),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const double dash = 3;
    const double gap = 4;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + dash),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
