import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/trip_planner_controller.dart';
import '../../shared/widgets/buttons.dart';
import 'trip_error_messages.dart';
import 'widgets/location_picker_sheet.dart';

/// The trip planner: two places and a button.
///
/// What this screen deliberately does **not** have: a map, a route line, a
/// distance, a travel time, an arrival estimate. Those belong to Module 06, and
/// none of them can be shown honestly before it exists. A "0 km" or a spinning
/// map placeholder is read as a real answer by everybody who sees it, so this
/// screen says plainly that the route comes later and gets on with the job it
/// can do: recording where somebody is going.
class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({super.key});

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  /// The failure from the last create attempt, kept on the screen rather than in
  /// the controller so both chosen places survive it.
  String? _createError;

  /// True once the customer has tried to create, so validation messages appear
  /// after an attempt rather than scolding somebody who has just arrived.
  bool _hasAttempted = false;

  Future<void> _pick(TripEndpointSlot slot) async {
    final TripLocation? chosen = await showLocationPicker(context, slot: slot);

    if (chosen == null || !mounted) return;

    setState(() => _createError = null);
    ref.read(tripPlannerControllerProvider.notifier).select(slot, chosen);
  }

  Future<void> _create() async {
    final AppStrings strings = AppStrings.of(context);
    final TripPlannerController controller = ref.read(
      tripPlannerControllerProvider.notifier,
    );

    setState(() {
      _hasAttempted = true;
      _createError = null;
    });

    if (!ref.read(tripPlannerControllerProvider).canCreate) return;

    try {
      final Trip trip = await controller.create();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.tripCreated)));

      // Replaces rather than pushes: going back to a planner still holding the
      // journey that was just created invites planning it twice.
      context.pushReplacement(Routes.tripDetailPath(trip.id));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _createError = tripErrorMessage(strings, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final TripPlannerState plan = ref.watch(tripPlannerControllerProvider);

    final String? validation = _hasAttempted
        ? switch (plan.issue) {
            TripValidationIssue.originMissing =>
              strings.tripErrorOriginRequired,
            TripValidationIssue.destinationMissing =>
              strings.tripErrorDestinationRequired,
            TripValidationIssue.sameLocation => strings.tripErrorSamePlace,
            null => null,
          }
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(strings.tripPlannerTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FotgSpacing.x5),
          children: <Widget>[
            _EndpointRow(
              label: strings.tripPlannerFrom,
              hint: strings.tripPlannerFromHint,
              location: plan.origin,
              marker: _Marker.origin,
              onTap: () => _pick(TripEndpointSlot.origin),
              onClear: plan.origin == null
                  ? null
                  : () => ref
                        .read(tripPlannerControllerProvider.notifier)
                        .clear(TripEndpointSlot.origin),
            ),
            _SwapRow(
              onSwap: plan.hasAnything
                  ? () =>
                        ref.read(tripPlannerControllerProvider.notifier).swap()
                  : null,
            ),
            _EndpointRow(
              label: strings.tripPlannerTo,
              hint: strings.tripPlannerToHint,
              location: plan.destination,
              marker: _Marker.destination,
              onTap: () => _pick(TripEndpointSlot.destination),
              onClear: plan.destination == null
                  ? null
                  : () => ref
                        .read(tripPlannerControllerProvider.notifier)
                        .clear(TripEndpointSlot.destination),
            ),

            if (validation != null || _createError != null) ...<Widget>[
              const SizedBox(height: FotgSpacing.x4),
              _Problem(message: _createError ?? validation!),
            ],

            const SizedBox(height: FotgSpacing.x6),
            PrimaryButton(
              label: plan.isCreating
                  ? strings.tripPlannerCreating
                  : strings.tripPlannerCreate,
              icon: Icons.near_me_rounded,
              // Enabled even when incomplete, so tapping it *says* what is
              // missing. A disabled button that will not explain itself is the
              // most common dead end in a form.
              onPressed: plan.isCreating ? null : _create,
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              strings.tripPlannerRouteLater,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Marker { origin, destination }

/// One end of the journey: label, chosen place or hint, and a clear button.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.label,
    required this.hint,
    required this.location,
    required this.marker,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String hint;
  final TripLocation? location;
  final _Marker marker;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final bool isChosen = location != null;

    final String primary = isChosen ? location!.displayName : hint;
    final String secondary = isChosen ? location!.secondaryLine : '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: FotgRadius.card,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: '$label, ${isChosen ? primary : hint}',
              // The tap action has to be declared on the node that carries the
              // label. `excludeSemantics` drops the InkWell's own action, so
              // without this the row announces itself as a button and then
              // cannot be activated by anything but a finger on the glass.
              onTap: onTap,
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: FotgRadius.card,
                child: Padding(
                  padding: const EdgeInsets.all(FotgSpacing.x4),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 28,
                        child: Center(child: _MarkerDot(marker: marker)),
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
                              primary,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isChosen
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (secondary.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                secondary,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onClear != null)
            Padding(
              padding: const EdgeInsets.only(right: FotgSpacing.x2),
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: strings.tripPlannerClearFor(label),
                onPressed: onClear,
              ),
            ),
        ],
      ),
    );
  }
}

/// The dashed connector, with the swap control sitting on it.
class _SwapRow extends StatelessWidget {
  const _SwapRow({required this.onSwap});

  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x2),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 30),
          SizedBox(
            width: 2,
            height: 28,
            child: CustomPaint(
              painter: _DashedLinePainter(color: theme.colorScheme.outline),
            ),
          ),
          const Spacer(),
          IconButton.filledTonal(
            icon: const Icon(Icons.swap_vert_rounded),
            tooltip: strings.tripPlannerSwap,
            onPressed: onSwap,
          ),
        ],
      ),
    );
  }
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.marker});

  final _Marker marker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (marker == _Marker.origin) {
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

class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(FotgSpacing.x3),
        decoration: BoxDecoration(
          borderRadius: FotgRadius.control,
          color: theme.colorScheme.errorContainer,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: FotgSizing.iconSm,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: FotgSpacing.x2),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
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
