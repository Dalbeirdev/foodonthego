import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/journey_measures.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/journey_time.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/providers.dart';
import '../../shared/state/trips_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import 'trip_error_messages.dart';

/// One journey, in full.
///
/// Reads the journey from the list the customer came from rather than issuing a
/// second request for something already on screen; if it is not there — a deep
/// link, or a list that has moved on — it fetches. Either way what is displayed
/// is the server's answer.
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  bool _discarding = false;

  Trip? _fromList() {
    final List<Trip>? list = ref.watch(tripsControllerProvider).value;
    if (list == null) return null;

    for (final Trip trip in list) {
      if (trip.id == widget.tripId) return trip;
    }
    return null;
  }

  void _toast(String message, {bool isError = false}) {
    final ThemeData theme = Theme.of(context);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? theme.colorScheme.error : null,
        ),
      );
  }

  Future<void> _discard(Trip trip) async {
    final AppStrings strings = AppStrings.of(context);

    final bool confirmed = await showTripDiscardDialog(context);
    if (!confirmed || !mounted || _discarding) return;

    setState(() => _discarding = true);

    try {
      await ref.read(tripsControllerProvider.notifier).discard(trip.id);
      if (!mounted) return;
      _toast(strings.tripDiscarded);
    } on ApiException catch (error) {
      if (!mounted) return;
      _toast(tripErrorMessage(strings, error), isError: true);
    } finally {
      if (mounted) setState(() => _discarding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final Trip? fromList = _fromList();

    return Scaffold(
      appBar: AppBar(title: Text(strings.tripDetailTitle)),
      body: SafeArea(
        child: fromList != null
            ? _Body(
                trip: fromList,
                discarding: _discarding,
                onDiscard: () => _discard(fromList),
              )
            : _FetchedBody(
                tripId: widget.tripId,
                discarding: _discarding,
                onDiscard: _discard,
              ),
      ),
    );
  }
}

/// The fallback path: the journey was not in the list, so fetch it.
class _FetchedBody extends ConsumerWidget {
  const _FetchedBody({
    required this.tripId,
    required this.discarding,
    required this.onDiscard,
  });

  final String tripId;
  final bool discarding;
  final Future<void> Function(Trip) onDiscard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);

    return FutureBuilder<Trip>(
      future: ref.read(tripRepositoryProvider).trip(tripId),
      builder: (BuildContext context, AsyncSnapshot<Trip> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _DetailSkeleton();
        }

        final Object? error = snapshot.error;
        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(FotgSpacing.x6),
              child: Text(
                error is ApiException
                    ? tripErrorMessage(strings, error)
                    : strings.tripsLoadFailed,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final Trip trip = snapshot.data!;

        return _Body(
          trip: trip,
          discarding: discarding,
          onDiscard: () => onDiscard(trip),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.trip,
    required this.discarding,
    required this.onDiscard,
  });

  final Trip trip;
  final bool discarding;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x5,
        FotgSpacing.x5,
        FotgSpacing.x8,
      ),
      children: <Widget>[
        Text(trip.routeSummary, style: theme.textTheme.headlineSmall),
        const SizedBox(height: FotgSpacing.x2),
        Text(
          // Module 06 is what made this line say something. Both halves of
          // `hasRoute` matter: a READY status with no summary means the
          // endpoints moved, and showing the old distance would be the most
          // convincing wrong number in the app.
          trip.hasRoute
              ? '${JourneyMeasures.duration(trip.selectedRoute!.effectiveDurationSeconds)}'
                    ' · ${JourneyMeasures.distance(trip.selectedRoute!.distanceMeters)}'
              : strings.tripRouteNotCalculated,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (trip.hasRoute &&
            JourneyMeasures.trafficDelay(
                  trip.selectedRoute!.trafficDelaySeconds,
                ) !=
                null) ...<Widget>[
          const SizedBox(height: FotgSpacing.x1),
          Text(
            '${strings.routeTrafficLabel} '
            '${JourneyMeasures.trafficDelay(trip.selectedRoute!.trafficDelaySeconds)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (trip.isCancelled) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          // Says why the action is absent. A screen that silently omits the
          // button makes people think the app is broken.
          _Notice(message: strings.tripReadOnlyCancelled),
        ],
        const SizedBox(height: FotgSpacing.x6),
        _PlaceBlock(
          icon: Icons.trip_origin_rounded,
          label: strings.tripPlannerFrom,
          place: trip.origin,
        ),
        const SizedBox(height: FotgSpacing.x5),
        _PlaceBlock(
          icon: Icons.place_rounded,
          label: strings.tripPlannerTo,
          place: trip.destination,
        ),
        const SizedBox(height: FotgSpacing.x6),
        if (trip.createdAt != null)
          _Detail(
            label: strings.tripCreatedAtLabel,
            value: JourneyTime.full(trip.createdAt!),
          ),
        const SizedBox(height: FotgSpacing.x6),
        // The way to the map. Named for what it does now rather than for what
        // it will do: a journey with no route needs one worked out, and one
        // that has a route is worth looking at.
        PrimaryButton(
          label: trip.hasRoute ? strings.routeTitle : strings.routeCalculate,
          icon: Icons.alt_route_rounded,
          onPressed: () => context.push(Routes.tripRoutePath(trip.id)),
        ),
        if (trip.isDiscardable) ...<Widget>[
          const SizedBox(height: FotgSpacing.x3),
          SecondaryButton(
            label: strings.tripDetailDiscard,
            isLoading: discarding,
            onPressed: onDiscard,
          ),
        ],
      ],
    );
  }
}

class _PlaceBlock extends StatelessWidget {
  const _PlaceBlock({
    required this.icon,
    required this.label,
    required this.place,
  });

  final IconData icon;
  final String label;
  final TripEndpoint place;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: FotgSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FotgSpacing.x1),
              Text(place.shortName, style: theme.textTheme.titleMedium),
              if (place.formattedAddress.isNotEmpty)
                Text(
                  place.formattedAddress,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FotgRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(FotgSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSkeleton(width: 200, height: 24),
          SizedBox(height: FotgSpacing.x3),
          AppSkeleton(width: 140, height: 16),
          SizedBox(height: FotgSpacing.x8),
          AppSkeleton(height: 16),
          SizedBox(height: FotgSpacing.x3),
          AppSkeleton(height: 16),
        ],
      ),
    );
  }
}

/// Confirms discarding a journey.
///
/// A plain confirmation and nothing else. The previous version collected an
/// optional reason; there is no field on the server to put one in, and a form
/// that discards what somebody typed is worse than not asking.
Future<bool> showTripDiscardDialog(BuildContext context) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final AppStrings strings = AppStrings.of(dialogContext);

      return AlertDialog(
        title: Text(strings.tripDiscardTitle),
        content: Text(strings.tripDiscardBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.tripDiscardKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(strings.tripDiscardConfirm),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
