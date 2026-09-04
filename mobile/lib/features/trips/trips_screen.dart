import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/trips_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import 'trip_detail_screen.dart';
import 'trip_error_messages.dart';
import 'trip_form_screen.dart';
import 'widgets/trip_card.dart';

/// The customer's journeys.
///
/// Three scopes behind one list, and the same four states as every other list in
/// this app: loading, empty, error, data. The scope lives in a provider rather
/// than in this widget, because the list provider watches it — a `setState` here
/// would leave the segment and the data one rebuild out of step.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  /// The journey whose row action is in flight, if any.
  String? _busyId;

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

  Future<void> _openPlanner({Trip? existing}) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => TripFormScreen(existing: existing),
      ),
    );

    if (saved == true && mounted) {
      _toast(
        existing == null
            ? AppStrings.of(context).tripPlanned
            : AppStrings.of(context).tripUpdated,
      );
    }
  }

  Future<void> _openDetail(Trip trip) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TripDetailScreen(tripId: trip.id),
      ),
    );
  }

  Future<void> _confirmCancel(Trip trip) async {
    final AppStrings strings = AppStrings.of(context);

    final String? reason = await showTripCancelDialog(context);
    if (reason == null || !mounted) return;

    if (_busyId != null) return;
    setState(() => _busyId = trip.id);

    try {
      await ref
          .read(tripsControllerProvider.notifier)
          .cancel(trip.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      _toast(strings.tripCancelled);
    } on ApiException catch (error) {
      if (!mounted) return;
      _toast(tripErrorMessage(strings, error), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final TripScope scope = ref.watch(tripScopeProvider);
    final AsyncValue<List<Trip>> trips = ref.watch(tripsControllerProvider);

    final bool hasJourneys = trips.hasValue && trips.value!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(strings.tripsTitle)),
      floatingActionButton: hasJourneys
          ? FloatingActionButton.extended(
              onPressed: () => _openPlanner(),
              icon: const Icon(Icons.add_road_rounded),
              label: Text(strings.tripsPlan),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _ScopeSelector(
              scope: scope,
              onChanged: (TripScope next) =>
                  ref.read(tripScopeProvider.notifier).select(next),
            ),
            Expanded(
              child: trips.when(
                loading: () => const _TripListSkeleton(),
                error: (Object error, StackTrace _) => _TripsError(
                  message: error is ApiException
                      ? tripErrorMessage(strings, error)
                      : strings.tripsLoadFailed,
                  onRetry: () =>
                      ref.read(tripsControllerProvider.notifier).reload(),
                ),
                data: (List<Trip> list) => list.isEmpty
                    ? _EmptyTrips(scope: scope, onPlan: () => _openPlanner())
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(tripsControllerProvider.notifier).reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.only(
                            top: FotgSpacing.x2,
                            // Clear of the extended FAB and the bottom bar, so
                            // the last row is reachable rather than sitting
                            // under a control.
                            bottom: FotgSpacing.x16 + FotgSpacing.x6,
                          ),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: FotgSpacing.x16),
                          itemBuilder: (BuildContext context, int index) {
                            final Trip trip = list[index];

                            return TripListItem(
                              trip: trip,
                              busy: _busyId == trip.id,
                              onOpen: () => _openDetail(trip),
                              // Offered only while the server says the journey
                              // is editable. A menu that offers an edit the
                              // server will refuse teaches people not to trust
                              // the menu.
                              onEdit: trip.isEditable
                                  ? () => _openPlanner(existing: trip)
                                  : null,
                              onCancel: trip.isEditable
                                  ? () => _confirmCancel(trip)
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upcoming / Past / Cancelled.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.scope, required this.onChanged});

  final TripScope scope;
  final ValueChanged<TripScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x4,
        FotgSpacing.x2,
        FotgSpacing.x4,
        FotgSpacing.x2,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget segments = SegmentedButton<TripScope>(
            segments: <ButtonSegment<TripScope>>[
              ButtonSegment<TripScope>(
                value: TripScope.upcoming,
                label: Text(strings.tripsScopeUpcoming),
              ),
              ButtonSegment<TripScope>(
                value: TripScope.past,
                label: Text(strings.tripsScopePast),
              ),
              ButtonSegment<TripScope>(
                value: TripScope.cancelled,
                label: Text(strings.tripsScopeCancelled),
              ),
            ],
            selected: <TripScope>{scope},
            showSelectedIcon: false,
            onSelectionChanged: (Set<TripScope> selection) =>
                onChanged(selection.first),
          );

          // Below this width the three labels cannot sit side by side without
          // breaking mid-word — the defect the Module 04 type selector had.
          // Scrolling keeps every option reachable and every word whole.
          if (constraints.maxWidth >= 320) return segments;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: segments,
          );
        },
      ),
    );
  }
}

/// The empty state, worded for the scope being shown.
///
/// "No journeys" under Past means something different from "No journeys" under
/// Upcoming, and only one of the three is worth offering a button for.
class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips({required this.scope, required this.onPlan});

  final TripScope scope;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return switch (scope) {
      TripScope.past => EmptyStateView(
        icon: Icons.history_rounded,
        title: strings.tripsPastEmptyTitle,
        body: strings.tripsPastEmptyBody,
      ),
      TripScope.cancelled => EmptyStateView(
        icon: Icons.block_rounded,
        title: strings.tripsCancelledEmptyTitle,
        body: strings.tripsCancelledEmptyBody,
      ),
      _ => EmptyStateView(
        icon: Icons.route_rounded,
        title: strings.tripsEmptyTitle,
        body: strings.tripsEmptyBody,
        action: PrimaryButton(
          label: strings.tripsPlanFirst,
          icon: Icons.near_me_rounded,
          expand: false,
          onPressed: onPlan,
        ),
      ),
    };
  }
}

/// Content-shaped rather than a spinner, so nothing jumps when the data lands.
class _TripListSkeleton extends StatelessWidget {
  const _TripListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x2),
      itemCount: 3,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: FotgSpacing.x16),
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: FotgSpacing.x5,
          vertical: FotgSpacing.x4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSkeleton(width: 44, height: 44, radius: FotgRadius.md),
            SizedBox(width: FotgSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppSkeleton(width: 150, height: 16),
                  SizedBox(height: FotgSpacing.x2),
                  AppSkeleton(width: 110, height: 13),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsError extends StatelessWidget {
  const _TripsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: FotgSpacing.x6),
            SecondaryButton(label: strings.customerRetry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
