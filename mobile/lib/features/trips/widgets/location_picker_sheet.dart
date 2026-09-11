import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/place.dart';
import '../../../domain/models/saved_address.dart';
import '../../../domain/models/trip.dart';
import '../../../shared/state/addresses_controller.dart';
import '../../../shared/state/current_location_controller.dart';
import '../../../shared/state/place_search_controller.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/state/trip_planner_controller.dart';
import '../../../shared/widgets/buttons.dart';
import '../../addresses/saved_addresses_screen.dart';

/// Choosing one end of a journey.
///
/// Three ways in, in the order people actually reach for them: the device's own
/// position, a place they have already saved, and a search. All three produce
/// the same [TripLocation], so nothing downstream has to know which was used —
/// except the server's log, which records the *kind* because how people choose
/// places is worth knowing and where they went is not.
///
/// Opened with [showLocationPicker]. Returns the chosen location, or null if the
/// customer backed out.
Future<TripLocation?> showLocationPicker(
  BuildContext context, {
  required TripEndpointSlot slot,
  bool searchOnly = false,
  String? title,
}) {
  return showModalBottomSheet<TripLocation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        LocationPickerSheet(slot: slot, searchOnly: searchOnly, title: title),
  );
}

class LocationPickerSheet extends ConsumerStatefulWidget {
  const LocationPickerSheet({
    required this.slot,
    this.searchOnly = false,
    this.title,
    super.key,
  });

  final TripEndpointSlot slot;

  /// Search alone, with no current-location row and no saved addresses.
  ///
  /// Used when the sheet is *how an address gets located in the first place*:
  /// offering the saved addresses there would be circular, and offering the
  /// device's position would attach wherever the customer happens to be
  /// standing to an address they are describing from memory.
  final bool searchOnly;

  final String? title;

  @override
  ConsumerState<LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<LocationPickerSheet> {
  final TextEditingController _query = TextEditingController();

  /// Held so "Search instead" — the way out of every location refusal — can put
  /// the cursor in the field rather than leaving the customer to find it.
  final FocusNode _searchFocus = FocusNode();

  /// Set while a chosen suggestion is being resolved into a position, so the row
  /// can show a spinner and a second tap cannot start a second lookup.
  String? _resolvingPlaceId;

  String? _resolveError;

  @override
  void initState() {
    super.initState();

    // The session token is minted once, here, and covers every keystroke plus
    // the one details call that ends the search. See PlaceSearchController for
    // the full lifecycle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(placeSearchControllerProvider.notifier).beginSession();
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _choose(TripLocation location) {
    // Closing the sheet disposes the search controller, and with it the query,
    // the results and the token. Nothing about this search outlives the sheet.
    ref.read(placeSearchControllerProvider.notifier).endSession();
    Navigator.of(context).pop(location);
  }

  Future<void> _useCurrentLocation() async {
    final AppStrings strings = AppStrings.of(context);

    final TripLocation? location = await ref
        .read(currentLocationControllerProvider.notifier)
        .resolve(fallbackLabel: strings.placeCurrentLocationName);

    if (!mounted || location == null) return;

    // A coarse fix is still usable, and the customer is told rather than left to
    // discover it later. They choose whether to keep it.
    final CurrentLocationStatus status = ref.read(
      currentLocationControllerProvider,
    );
    if (status is CurrentLocationReady && status.isCoarse) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.locationCoarseWarning)));
    }

    _choose(location);
  }

  Future<void> _resolveSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _resolvingPlaceId = suggestion.placeId;
      _resolveError = null;
    });

    final AppStrings strings = AppStrings.of(context);
    final String? token = ref
        .read(placeSearchControllerProvider.notifier)
        .sessionToken;

    try {
      final PlaceDetails details = await ref
          .read(placeRepositoryProvider)
          .details(suggestion.placeId, sessionToken: token);

      if (!mounted) return;
      _choose(TripLocation.fromPlace(details));
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _resolvingPlaceId = null;
        _resolveError = strings.placePickerResolveFailed;
      });
    } catch (_) {
      // Includes a details response with no position. There is nothing to fall
      // back to: a place with no coordinates cannot be one end of a journey,
      // and giving it some would be inventing them.
      if (!mounted) return;
      setState(() {
        _resolvingPlaceId = null;
        _resolveError = strings.placePickerResolveFailed;
      });
    }
  }

  void _useSavedAddress(SavedAddress address) {
    final TripLocation? location = TripLocation.fromSavedAddress(address);

    if (location == null) {
      // An address that has never been located. Sending it would make the
      // server refuse; assigning it a plausible coordinate would be worse.
      setState(
        () => _resolveError = AppStrings.of(context).placeSavedNotLocatedHelp,
      );
      return;
    }

    _choose(location);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final PlaceSearchState search = ref.watch(placeSearchControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController controller) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FotgSpacing.x5,
                  0,
                  FotgSpacing.x5,
                  FotgSpacing.x3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title ??
                          (widget.slot.isOrigin
                              ? strings.placePickerOriginTitle
                              : strings.placePickerDestinationTitle),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: FotgSpacing.x4),
                    _SearchField(
                      controller: _query,
                      focusNode: _searchFocus,
                      state: search,
                      onChanged: (String value) => ref
                          .read(placeSearchControllerProvider.notifier)
                          .query(value),
                      onClear: () {
                        _query.clear();
                        ref
                            .read(placeSearchControllerProvider.notifier)
                            .clear();
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                    FotgSpacing.x5,
                    0,
                    FotgSpacing.x5,
                    FotgSpacing.x6,
                  ),
                  children: <Widget>[
                    if (_resolveError != null)
                      _InlineNotice(message: _resolveError!),

                    // Searching replaces the browse list entirely. Two competing
                    // lists on one sheet is how somebody taps the wrong row.
                    if (widget.searchOnly || search.query.trim().isNotEmpty)
                      ..._searchResults(strings, search)
                    else
                      ..._browse(strings),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _searchResults(AppStrings strings, PlaceSearchState search) {
    if (search.query.trim().isEmpty || search.isTooShort) {
      return <Widget>[_Hint(text: strings.placePickerTypeMore)];
    }

    if (search.isSearching) {
      return const <Widget>[_SearchProgress()];
    }

    if (search.failure != null) {
      return <Widget>[
        _InlineNotice(message: strings.placePickerSearchFailed),
        const SizedBox(height: FotgSpacing.x3),
        SecondaryButton(
          label: strings.locationRetry,
          onPressed: () =>
              ref.read(placeSearchControllerProvider.notifier).retry(),
        ),
      ];
    }

    if (search.isEmptyResult) {
      return <Widget>[_Hint(text: strings.placePickerNoResults)];
    }

    return search.results
        .map(
          (PlaceSuggestion suggestion) => _PlaceRow(
            primary: suggestion.primaryText,
            secondary: suggestion.secondaryText,
            icon: Icons.place_outlined,
            isBusy: _resolvingPlaceId == suggestion.placeId,
            onTap: _resolvingPlaceId == null
                ? () => _resolveSuggestion(suggestion)
                : null,
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _browse(AppStrings strings) {
    final AsyncValue<List<SavedAddress>> addresses = ref.watch(
      addressesControllerProvider,
    );
    final CurrentLocationStatus location = ref.watch(
      currentLocationControllerProvider,
    );

    return <Widget>[
      _CurrentLocationSection(
        status: location,
        onUse: _useCurrentLocation,
        onOpenSettings: () async {
          final bool opened = await ref
              .read(currentLocationControllerProvider.notifier)
              .openSettings();

          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.locationSettingsUnavailable)),
            );
          }
        },
        onSearchInstead: () => _searchFocus.requestFocus(),
      ),
      const SizedBox(height: FotgSpacing.x5),
      Text(
        strings.placePickerSaved,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: FotgSpacing.x2),
      addresses.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: FotgSpacing.x4),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
        error: (Object error, StackTrace stack) =>
            _Hint(text: strings.placePickerSavedEmpty),
        data: (List<SavedAddress> saved) {
          if (saved.isEmpty) {
            return _Hint(text: strings.placePickerSavedEmpty);
          }

          return Column(
            children: saved
                .map(
                  (SavedAddress address) => _PlaceRow(
                    primary: address.label,
                    secondary: address.hasCoordinates
                        ? address.shortAddress
                        : strings.placeSavedNotLocated,
                    icon: address.isDefault
                        ? Icons.star_rounded
                        : Icons.bookmark_outline_rounded,
                    // Not disabled. A tap explains *why* it cannot be used and
                    // what to do instead; a greyed row explains nothing.
                    isUnlocated: !address.hasCoordinates,
                    onTap: () => _useSavedAddress(address),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
      const SizedBox(height: FotgSpacing.x3),
      LinkAction(
        label: strings.placePickerManageAddresses,
        onPressed: () {
          // The navigator is taken before the sheet closes: afterwards this
          // context is gone, and looking it up then is how a "nothing happened"
          // tap gets shipped.
          //
          // Pushed, not routed. The profile sub-screens have no registered
          // paths — ProfileScreen pushes them over its branch so the bottom bar
          // stays put — so routing to one here lands the customer on Page Not
          // Found instead of their addresses.
          final NavigatorState navigator = Navigator.of(context);
          navigator.pop();
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const SavedAddressesScreen(),
            ),
          );
        },
      ),
    ];
  }
}

/// The search field.
///
/// A plain [TextField] whose `onChanged` goes straight to the debounced
/// controller. No `onSubmitted` search: a search that only runs on Enter is a
/// search nobody on a phone ever runs.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.state,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PlaceSearchState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: strings.placePickerSearchLabel,
        hintText: strings.placePickerSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: strings.placePickerSearchClear,
                onPressed: onClear,
              ),
      ),
    );
  }
}

/// The current-location block, in whichever of its seven states applies.
class _CurrentLocationSection extends StatelessWidget {
  const _CurrentLocationSection({
    required this.status,
    required this.onUse,
    required this.onOpenSettings,
    required this.onSearchInstead,
  });

  final CurrentLocationStatus status;
  final VoidCallback onUse;
  final VoidCallback onOpenSettings;
  final VoidCallback onSearchInstead;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return switch (status) {
      CurrentLocationLocating() => _PlaceRow(
        primary: strings.placePickerLocating,
        secondary: '',
        icon: Icons.my_location_rounded,
        isBusy: true,
        onTap: null,
      ),
      CurrentLocationBlocked(reason: final LocationResult reason) =>
        _LocationProblem(
          reason: reason,
          onRetry: onUse,
          onOpenSettings: onOpenSettings,
          onSearchInstead: onSearchInstead,
        ),
      // Idle, and Ready — which only persists for the instant before the sheet
      // closes with the chosen location.
      _ => _PlaceRow(
        primary: strings.placePickerCurrentLocation,
        secondary: strings.placePickerCurrentLocationHint,
        icon: Icons.my_location_rounded,
        onTap: onUse,
      ),
    };
  }
}

/// The six ways asking the device can fail, each with its own words.
///
/// The distinction that matters most: [LocationServicesDisabled] is **not** a
/// denial. Telling somebody they refused permission when they did not sends them
/// into an app-settings screen where everything already looks correct.
class _LocationProblem extends StatelessWidget {
  const _LocationProblem({
    required this.reason,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onSearchInstead,
  });

  final LocationResult reason;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onSearchInstead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);

    final (String title, String body, Widget action) = switch (reason) {
      LocationPermissionDenied() => (
        strings.locationDeniedTitle,
        strings.locationDeniedBody,
        SecondaryButton(label: strings.locationRetry, onPressed: onRetry),
      ),
      LocationPermissionDeniedForever() => (
        strings.locationDeniedForeverTitle,
        strings.locationDeniedForeverBody,
        SecondaryButton(
          label: strings.locationOpenSettings,
          onPressed: onOpenSettings,
        ),
      ),
      LocationServicesDisabled() => (
        strings.locationServicesOffTitle,
        strings.locationServicesOffBody,
        SecondaryButton(label: strings.locationRetry, onPressed: onRetry),
      ),
      LocationTimedOut() => (
        strings.locationTimeoutTitle,
        strings.locationTimeoutBody,
        SecondaryButton(label: strings.locationRetry, onPressed: onRetry),
      ),
      // LocationUnavailable, and LocationFix which cannot reach here.
      _ => (
        strings.locationUnavailableTitle,
        strings.locationUnavailableBody,
        SecondaryButton(label: strings.locationRetry, onPressed: onRetry),
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(FotgSpacing.x4),
        decoration: BoxDecoration(
          borderRadius: FotgRadius.card,
          border: Border.all(color: theme.colorScheme.outline),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.location_off_rounded,
                  size: FotgSizing.iconSm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: FotgSpacing.x2),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: FotgSpacing.x2),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FotgSpacing.x3),
            // Always a way onwards that does not depend on location at all. A
            // permission screen with no alternative is how an app traps someone.
            Wrap(
              spacing: FotgSpacing.x3,
              runSpacing: FotgSpacing.x2,
              children: <Widget>[
                action,
                LinkAction(
                  label: strings.locationSearchInstead,
                  onPressed: onSearchInstead,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable place — a suggestion, a saved address, or the current-location
/// row. One widget for all three so they cannot drift apart visually.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.primary,
    required this.secondary,
    required this.icon,
    this.onTap,
    this.isBusy = false,
    this.isUnlocated = false,
  });

  final String primary;
  final String secondary;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isBusy;

  /// A saved address with no coordinates. Shown, and explained on tap.
  final bool isUnlocated;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: onTap != null,
      label: secondary.isEmpty ? primary : '$primary, $secondary',
      // Declared here as well as on the InkWell: `excludeSemantics` removes the
      // child's action, and a labelled button with no action is a row assistive
      // technology can read but not press.
      onTap: isBusy ? null : onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: FotgRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: FotgSpacing.x3,
            horizontal: FotgSpacing.x1,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        icon,
                        size: FotgSizing.iconMd,
                        color: isUnlocated
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: FotgSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      primary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
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
    );
  }
}

class _SearchProgress extends StatelessWidget {
  const _SearchProgress();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: FotgSpacing.x6),
    child: Center(child: CircularProgressIndicator.adaptive()),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: FotgSpacing.x3),
        padding: const EdgeInsets.all(FotgSpacing.x3),
        decoration: BoxDecoration(
          borderRadius: FotgRadius.control,
          color: theme.colorScheme.errorContainer,
        ),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
