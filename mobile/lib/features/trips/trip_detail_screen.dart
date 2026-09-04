import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/journey_time.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/providers.dart';
import '../../shared/state/trips_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import 'trip_error_messages.dart';
import 'trip_form_screen.dart';

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
  bool _cancelling = false;

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

  Future<void> _edit(Trip trip) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => TripFormScreen(existing: trip),
      ),
    );

    if (saved == true && mounted) _toast(AppStrings.of(context).tripUpdated);
  }

  Future<void> _cancel(Trip trip) async {
    final AppStrings strings = AppStrings.of(context);

    final String? reason = await showTripCancelDialog(context);
    if (reason == null || !mounted || _cancelling) return;

    setState(() => _cancelling = true);

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
      if (mounted) setState(() => _cancelling = false);
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
                cancelling: _cancelling,
                onEdit: () => _edit(fromList),
                onCancel: () => _cancel(fromList),
              )
            : _FetchedBody(
                tripId: widget.tripId,
                cancelling: _cancelling,
                onEdit: _edit,
                onCancel: _cancel,
              ),
      ),
    );
  }
}

/// The fallback path: the journey was not in the list, so fetch it.
class _FetchedBody extends ConsumerWidget {
  const _FetchedBody({
    required this.tripId,
    required this.cancelling,
    required this.onEdit,
    required this.onCancel,
  });

  final String tripId;
  final bool cancelling;
  final Future<void> Function(Trip) onEdit;
  final Future<void> Function(Trip) onCancel;

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
          cancelling: cancelling,
          onEdit: () => onEdit(trip),
          onCancel: () => onCancel(trip),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.trip,
    required this.cancelling,
    required this.onEdit,
    required this.onCancel,
  });

  final Trip trip;
  final bool cancelling;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

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
          JourneyTime.full(trip.departureAt),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!trip.isEditable) ...<Widget>[
          const SizedBox(height: FotgSpacing.x4),
          _Notice(
            // Says why the actions are absent. A screen that silently omits the
            // buttons makes people think the app is broken.
            message: trip.isCancelled
                ? strings.tripReadOnlyCancelled
                : strings.tripReadOnlyDeparted,
          ),
        ],
        const SizedBox(height: FotgSpacing.x6),
        _PlaceBlock(
          icon: Icons.trip_origin_rounded,
          label: strings.tripFormFrom,
          place: trip.origin,
        ),
        const SizedBox(height: FotgSpacing.x5),
        _PlaceBlock(
          icon: Icons.place_rounded,
          label: strings.tripFormTo,
          place: trip.destination,
        ),
        const SizedBox(height: FotgSpacing.x6),
        _Detail(
          label: strings.tripDeparts,
          value: JourneyTime.full(trip.departureAt),
        ),
        _Detail(
          label: strings.tripArrives,
          value: trip.expectedArrivalAt == null
              ? strings.tripArrivalUnknown
              : JourneyTime.full(trip.expectedArrivalAt!),
        ),
        _Detail(
          label: strings.tripFormTravellers,
          value: strings.tripTravellers(trip.travellerCount),
        ),
        if ((trip.note ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: FotgSpacing.x5),
          Text(strings.tripNoteHeading, style: theme.textTheme.titleSmall),
          const SizedBox(height: FotgSpacing.x1),
          Text(trip.note!, style: theme.textTheme.bodyMedium),
        ],
        if (trip.isCancelled &&
            (trip.cancellationReason ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: FotgSpacing.x5),
          Text(
            strings.tripCancellationHeading,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FotgSpacing.x1),
          Text(trip.cancellationReason!, style: theme.textTheme.bodyMedium),
        ],
        if (trip.isEditable) ...<Widget>[
          const SizedBox(height: FotgSpacing.x8),
          PrimaryButton(
            label: strings.tripDetailEdit,
            icon: Icons.edit_rounded,
            onPressed: onEdit,
          ),
          const SizedBox(height: FotgSpacing.x3),
          SecondaryButton(
            label: strings.tripDetailCancel,
            isLoading: cancelling,
            onPressed: onCancel,
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
  final JourneyPlace place;

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

/// Confirms a cancellation, and takes an optional reason.
///
/// Returns the reason (possibly empty) if the customer confirmed, and **null**
/// if they did not — so a caller can tell "cancelled with no reason" from
/// "changed their mind", which a plain bool could not.
Future<String?> showTripCancelDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => const _CancelTripDialog(),
  );
}

/// A `StatefulWidget` purely so the text controller has an owner with a
/// lifecycle.
///
/// Creating the controller in `showTripCancelDialog` and disposing it after the
/// future completes looks equivalent and is not: the dialog's exit animation is
/// still running at that point, and the `TextField` rebuilds against a disposed
/// controller. This is the fix for that, and it is why the dialog is a widget
/// rather than four lines in a function.
class _CancelTripDialog extends StatefulWidget {
  const _CancelTripDialog();

  @override
  State<_CancelTripDialog> createState() => _CancelTripDialogState();
}

class _CancelTripDialogState extends State<_CancelTripDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return AlertDialog(
      title: Text(strings.tripCancelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(strings.tripCancelBody),
          const SizedBox(height: FotgSpacing.x4),
          TextField(
            controller: _reason,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: strings.tripCancelReason,
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.tripCancelKeep),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(strings.tripCancelConfirm),
        ),
      ],
    );
  }
}
