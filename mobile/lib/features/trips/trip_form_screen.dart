import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/time/journey_time.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/trips_controller.dart';
import '../../shared/widgets/buttons.dart';
import 'trip_error_messages.dart';
import 'widgets/place_picker_sheet.dart';

/// Planning a journey, and editing one.
///
/// One screen for both, because they are the same fields and two screens would
/// drift apart.
///
/// Two layout rules, both learned in Module 04 and both pinned by tests here:
/// the form scrolls in a **non-lazy `Column`**, never a `ListView` — a `ListView`
/// builds lazily, so a field scrolled out of view is never registered with the
/// `Form` and `validate()` skips it in silence — and the primary action is
/// **pinned above the keyboard**, not placed after the last field where a small
/// screen puts it under the bottom navigation bar.
class TripFormScreen extends ConsumerStatefulWidget {
  const TripFormScreen({this.existing, super.key});

  /// Null when planning a new journey.
  final Trip? existing;

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _note = TextEditingController();

  PlaceChoice? _origin;
  PlaceChoice? _destination;

  DateTime? _departure;
  DateTime? _arrival;
  int _travellers = 1;

  /// Set once a save is in flight, so a second tap cannot plan two journeys.
  bool _saving = false;

  /// Shown against the two place rows, which are not `FormField`s and so cannot
  /// carry their own validator.
  String? _originError;
  String? _destinationError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final Trip? existing = widget.existing;
    if (existing == null) {
      // A sensible default rather than an empty field: most journeys are planned
      // for the near future, and the pickers open where the customer is likely
      // to be going anyway.
      _departure = _roundUp(DateTime.now().add(const Duration(hours: 2)));
      return;
    }

    _origin = PlaceChoice(
      draft: JourneyPlaceDraft.typed(
        city: existing.origin.city,
        countryCode: existing.origin.countryCode,
        label: existing.origin.label,
      ),
      title: existing.origin.shortName,
      subtitle: existing.origin.formattedAddress,
    );
    _destination = PlaceChoice(
      draft: JourneyPlaceDraft.typed(
        city: existing.destination.city,
        countryCode: existing.destination.countryCode,
        label: existing.destination.label,
      ),
      title: existing.destination.shortName,
      subtitle: existing.destination.formattedAddress,
    );
    _departure = existing.departureAt.toLocal();
    _arrival = existing.expectedArrivalAt?.toLocal();
    _travellers = existing.travellerCount;
    _note.text = existing.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Rounds to the next quarter hour. A default of "10:37" reads like data;
  /// "10:45" reads like a suggestion.
  static DateTime _roundUp(DateTime value) {
    final int minutes = ((value.minute + 14) ~/ 15) * 15;
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
    ).add(Duration(minutes: minutes));
  }

  Future<void> _pickPlace({required bool isOrigin}) async {
    final AppStrings strings = AppStrings.of(context);

    final PlaceChoice? choice = await showPlacePicker(
      context,
      title: isOrigin ? strings.tripFormFrom : strings.tripFormTo,
    );

    if (choice == null || !mounted) return;

    setState(() {
      if (isOrigin) {
        _origin = choice;
        _originError = null;
      } else {
        _destination = choice;
        _destinationError = null;
      }
    });
  }

  Future<void> _pickDeparture() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _departure ?? _roundUp(now);

    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      // No journey in the past, and the same one-year horizon the server
      // enforces — so the picker cannot offer a date the save would refuse.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (day == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null || !mounted) return;

    setState(
      () => _departure = JourneyTime.combine(day, time.hour, time.minute),
    );
  }

  Future<void> _pickArrival() async {
    final DateTime base = _departure ?? DateTime.now();
    final DateTime initial = _arrival ?? base.add(const Duration(hours: 4));

    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(base.year, base.month, base.day),
      lastDate: base.add(const Duration(days: 30)),
    );

    if (day == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null || !mounted) return;

    setState(() => _arrival = JourneyTime.combine(day, time.hour, time.minute));
  }

  /// Everything the form can decide for itself, before a request is spent on it.
  bool _validate() {
    final AppStrings strings = AppStrings.of(context);
    final bool formIsValid = _formKey.currentState?.validate() ?? false;

    setState(() {
      _originError = _origin == null ? strings.tripErrorOriginRequired : null;
      _destinationError = _destination == null
          ? strings.tripErrorDestinationRequired
          : null;

      // The client's own copy of the server's rule. Not a replacement for it —
      // the server checks again, and its answer wins — but it saves a round trip
      // and points at the field rather than at the screen.
      if (_origin != null &&
          _destination != null &&
          _isSamePlace(_origin!, _destination!)) {
        _destinationError = strings.tripErrorSamePlace;
      }

      if (_departure != null &&
          _arrival != null &&
          !_arrival!.isAfter(_departure!)) {
        _arrivalError = strings.tripErrorArrivalBeforeDeparture;
      } else {
        _arrivalError = null;
      }

      _departureError = _departure == null
          ? strings.tripErrorDepartureRequired
          : null;
    });

    return formIsValid &&
        _originError == null &&
        _destinationError == null &&
        _departureError == null &&
        _arrivalError == null;
  }

  String? _departureError;
  String? _arrivalError;

  static bool _isSamePlace(PlaceChoice a, PlaceChoice b) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    // Two picks of the same saved address are the same place whatever they are
    // labelled; two typed places are compared the way the server compares them.
    if (a.draft.isSavedAddress && b.draft.isSavedAddress) {
      return a.draft.savedAddressId == b.draft.savedAddressId;
    }

    return normalize(a.subtitle) == normalize(b.subtitle) &&
        normalize(a.title) == normalize(b.title);
  }

  Future<void> _save() async {
    if (_saving || !_validate()) return;

    final AppStrings strings = AppStrings.of(context);
    setState(() => _saving = true);

    final TripDraft draft = TripDraft(
      origin: _origin!.draft,
      destination: _destination!.draft,
      departureAt: _departure,
      expectedArrivalAt: _arrival,
      // An edit that removed the arrival has to say so explicitly, or the server
      // reads the absent key as "leave it" and the old value survives.
      clearArrival: _isEditing && _arrival == null,
      travellerCount: _travellers,
      note: _note.text,
      clearNote: _isEditing && _note.text.trim().isEmpty,
    );

    try {
      final TripsController trips = ref.read(tripsControllerProvider.notifier);

      if (_isEditing) {
        await trips.edit(widget.existing!.id, draft);
      } else {
        await trips.plan(draft);
      }

      if (!mounted) return;
      // Only now. Nothing on this screen reports success before the server has
      // confirmed it — a journey shown as saved that was not is a traveller
      // waiting for food nobody is cooking.
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showFailure(strings, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Puts the server's answer where the customer can act on it.
  ///
  /// A field error goes against its field; anything else becomes a snackbar. The
  /// server's own wording is preferred for a field, because it is the authority
  /// on why the value was refused.
  void _showFailure(AppStrings strings, ApiException error) {
    final String? departure = serverFieldError(error, 'departure_at');
    final String? arrival = serverFieldError(error, 'expected_arrival_at');
    final String? destination =
        serverFieldError(error, 'destination') ??
        serverFieldError(error, 'destination.city');
    final String? origin =
        serverFieldError(error, 'origin') ??
        serverFieldError(error, 'origin.city');

    if (departure != null ||
        arrival != null ||
        destination != null ||
        origin != null) {
      setState(() {
        _departureError = departure;
        _arrivalError = arrival;
        _destinationError = destination;
        _originError = origin;
      });
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(tripErrorMessage(strings, error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? strings.tripFormEditTitle : strings.tripFormPlanTitle,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    FotgSpacing.x5,
                    FotgSpacing.x5,
                    FotgSpacing.x5,
                    FotgSpacing.x6,
                  ),
                  // A Column, not a ListView. See the class comment: lazy
                  // building silently skips validation on off-screen fields.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _PlaceRow(
                        icon: Icons.trip_origin_rounded,
                        label: strings.tripFormFrom,
                        hint: strings.tripFormFromHint,
                        choice: _origin,
                        error: _originError,
                        onTap: () => _pickPlace(isOrigin: true),
                      ),
                      const SizedBox(height: FotgSpacing.x4),
                      _PlaceRow(
                        icon: Icons.place_rounded,
                        label: strings.tripFormTo,
                        hint: strings.tripFormToHint,
                        choice: _destination,
                        error: _destinationError,
                        onTap: () => _pickPlace(isOrigin: false),
                      ),
                      const SizedBox(height: FotgSpacing.x6),
                      _MomentRow(
                        icon: Icons.schedule_rounded,
                        label: strings.tripFormDeparture,
                        value: _departure,
                        error: _departureError,
                        onTap: _pickDeparture,
                      ),
                      const SizedBox(height: FotgSpacing.x4),
                      _MomentRow(
                        icon: Icons.flag_rounded,
                        label: strings.tripFormArrival,
                        value: _arrival,
                        error: _arrivalError,
                        emptyText: strings.tripArrivalUnknown,
                        onTap: _pickArrival,
                        onClear: _arrival == null
                            ? null
                            : () => setState(() => _arrival = null),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: FotgSpacing.x2,
                          left: FotgSpacing.x1,
                        ),
                        child: Text(
                          // Says plainly that nothing computes this yet, rather
                          // than leaving a blank field looking like a failure.
                          strings.tripFormArrivalHelp,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      const SizedBox(height: FotgSpacing.x6),
                      _TravellerStepper(
                        value: _travellers,
                        onChanged: (int next) =>
                            setState(() => _travellers = next),
                      ),
                      const SizedBox(height: FotgSpacing.x6),
                      TextFormField(
                        controller: _note,
                        maxLength: 280,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: strings.tripFormNote,
                          hintText: strings.tripFormNoteHint,
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _PinnedAction(
              label: _isEditing ? strings.tripFormUpdate : strings.tripFormSave,
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// One end of the journey, as a tappable row.
///
/// Not a text field: a place is chosen, not typed, and a field would invite
/// somebody to type a line the app then has to parse into a city and a country.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.choice,
    required this.onTap,
    this.error,
  });

  final IconData icon;
  final String label;
  final String hint;
  final PlaceChoice? choice;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasError = error != null;

    // Labelled for assistive technology. An InkWell around an InputDecorator is
    // a tappable region with no accessible name — a screen-reader user would
    // hear the hint text and nothing about what choosing it does, or that it is
    // a button at all.
    return Semantics(
      button: true,
      label: choice == null
          ? '$label, $hint'
          : '$label, ${choice!.title}${hasError ? ", $error" : ""}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(FotgRadius.md),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                errorText: error,
                prefixIcon: Icon(icon),
              ),
              child: choice == null
                  ? Text(
                      hint,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: hasError
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(choice!.title, style: theme.textTheme.bodyLarge),
                        if (choice!.subtitle.isNotEmpty)
                          Text(
                            choice!.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A date and a time, as one tappable row.
class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
    this.emptyText,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final DateTime? value;
  final String? error;
  final String? emptyText;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final String spoken = value == null
        ? (emptyText ?? '')
        : JourneyTime.full(value!.toUtc(), now: DateTime.now());

    return Semantics(
      button: true,
      label: '$label, $spoken${error != null ? ", $error" : ""}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FotgRadius.md),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            prefixIcon: Icon(icon),
            suffixIcon: onClear == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    tooltip: strings.tripFormArrivalClear,
                    onPressed: onClear,
                  ),
          ),
          child: Text(
            spoken,
            style: value == null
                ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}

/// How many people are travelling.
///
/// A stepper rather than a text field: the range is one to twenty, and a keyboard
/// for a number in that range is more work than two buttons.
class _TravellerStepper extends StatelessWidget {
  const _TravellerStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Icon(Icons.group_rounded, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: FotgSpacing.x4),
        Expanded(
          child: Text(
            strings.tripFormTravellers,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.remove_rounded),
          tooltip: strings.tripTravellersFewer,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.add_rounded),
          tooltip: strings.tripTravellersMore,
          // Matches the server's ceiling, so the control cannot produce a value
          // the save would refuse.
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// The primary action, pinned above the keyboard.
///
/// Module 04's forms put this after the last field, where on a small screen it
/// sat under the bottom navigation bar and the tap went to the wrong widget.
class _PinnedAction extends StatelessWidget {
  const _PinnedAction({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x3,
        FotgSpacing.x5,
        FotgSpacing.x4 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: PrimaryButton(
        label: label,
        isLoading: isLoading,
        onPressed: onPressed,
      ),
    );
  }
}
