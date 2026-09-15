import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../core/phone/supported_country.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/trip.dart';
import '../../shared/state/addresses_controller.dart';
import '../../shared/state/trip_planner_controller.dart';
import '../../shared/widgets/buttons.dart';
import '../auth/auth_error_messages.dart';
import '../trips/widgets/location_picker_sheet.dart';
import 'widgets/address_type_selector.dart';
import 'widgets/postal_code_rules.dart';

/// Add or edit a saved address.
///
/// One screen for both, because the fields are identical and two would drift.
/// The field order follows an Indian address as somebody writes it — building,
/// street, landmark, city, state, PIN — rather than the order the database
/// happens to store it in.
class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({this.existing, super.key});

  /// Null when adding.
  final SavedAddress? existing;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _label;
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final TextEditingController _landmark;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _postal;

  late AddressType _type;
  late String _countryCode;
  late bool _makeDefault;

  bool _submitting = false;
  String? _error;

  /// Where this address is, once the customer has found it.
  ///
  /// Kept separately from the text fields on purpose: an address is a
  /// description a person writes, and a coordinate is a claim about a point on
  /// the earth. Deriving the second from the first — geocoding the typed lines
  /// silently on save — is how somebody's journey starts in the wrong city
  /// while the screen looks entirely correct.
  double? _latitude;
  double? _longitude;
  String? _placeId;
  String? _locatedLabel;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final SavedAddress? existing = widget.existing;

    _label = TextEditingController(text: existing?.label ?? '');
    _line1 = TextEditingController(text: existing?.addressLine1 ?? '');
    _line2 = TextEditingController(text: existing?.addressLine2 ?? '');
    _landmark = TextEditingController(text: existing?.landmark ?? '');
    _city = TextEditingController(text: existing?.city ?? '');
    _state = TextEditingController(text: existing?.state ?? '');
    _postal = TextEditingController(text: existing?.postalCode ?? '');

    _type = existing?.type ?? AddressType.home;
    _countryCode = existing?.countryCode ?? SupportedCountry.fallback.iso;
    // Editing does not offer to un-default: the server ignores that anyway, so a
    // switch that appeared to do it would be a lie.
    _makeDefault = existing?.isDefault ?? false;

    _latitude = existing?.latitude;
    _longitude = existing?.longitude;
    _placeId = existing?.placeId;
    _locatedLabel = existing?.hasCoordinates == true
        ? existing!.formattedAddress
        : null;
  }

  bool get _isLocated => _latitude != null && _longitude != null;

  Future<void> _locate() async {
    final AppStrings strings = AppStrings.of(context);

    // Search only. Offering the saved addresses here would be circular, and
    // offering the device's position would pin an address the customer is
    // describing from memory to wherever they happen to be standing.
    final TripLocation? found = await showLocationPicker(
      context,
      slot: TripEndpointSlot.origin,
      searchOnly: true,
      title: strings.addressLocateSheetTitle,
    );

    if (found == null || !mounted) return;

    setState(() {
      _latitude = found.latitude;
      _longitude = found.longitude;
      _placeId = found.placeId;
      _locatedLabel = found.formattedAddress.isNotEmpty
          ? found.formattedAddress
          : found.displayName;
    });
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _label,
      _line1,
      _line2,
      _landmark,
      _city,
      _state,
      _postal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  AddressDraft get _draft => AddressDraft(
    type: _type,
    label: _label.text,
    addressLine1: _line1.text,
    addressLine2: _line2.text,
    landmark: _landmark.text,
    city: _city.text,
    state: _state.text,
    postalCode: _postal.text,
    countryCode: _countryCode,
    isDefault: _makeDefault,
    latitude: _latitude,
    longitude: _longitude,
    placeId: _placeId,
  );

  Future<void> _save() async {
    // The submission lock. Without it, tapping Save twice on a slow connection
    // creates two identical addresses — the server has no way to tell a double
    // tap from two deliberate saves of the same place.
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final AddressesController controller = ref.read(
        addressesControllerProvider.notifier,
      );

      if (_isEditing) {
        await controller.edit(widget.existing!.id, _draft);
      } else {
        await controller.add(_draft);
      }

      if (!mounted) return;

      // Only now. Nothing on this screen says "saved" before the server has
      // said so.
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(ApiException error) {
    final AppStrings strings = AppStrings.of(context);

    if (error.code == ApiErrorCode.validationFailed) {
      // The server's field message is more specific than anything this screen
      // could compose — it names the field and the rule.
      for (final List<String> messages in error.fieldErrors.values) {
        if (messages.isNotEmpty) return messages.first;
      }
    }

    return switch (error.code) {
      ApiErrorCode.network => strings.customerErrorSaveOffline,
      ApiErrorCode.addressLimitReached => error.message,
      ApiErrorCode.addressNotFound => strings.customerErrorAddressGone,
      _ => authErrorMessage(strings, error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final PostalCodeRule postal = PostalCodeRule.forCountry(_countryCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? strings.addressFormEditTitle
              : strings.addressFormAddTitle,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Expanded(
                // A scrolling Column, not a ListView. ListView builds lazily, so
                // a field scrolled out of view is not in the tree — and a
                // FormField that is not in the tree is never registered with the
                // Form, so validate() silently skips it. On a phone that means
                // saving an address whose city was never checked.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    FotgSpacing.x5,
                    FotgSpacing.x4,
                    FotgSpacing.x5,
                    FotgSpacing.x6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AddressTypeSelector(
                        selected: _type,
                        onChanged: (AddressType type) => setState(() {
                          _type = type;
                          // A label auto-filled for one type must not linger on
                          // another. One the customer typed is theirs and stays.
                          if (!type.needsCustomLabel &&
                              (_label.text == strings.addressTypeHome ||
                                  _label.text == strings.addressTypeWork)) {
                            _label.clear();
                          }
                        }),
                      ),

                      if (_type.needsCustomLabel) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x4),
                        TextFormField(
                          controller: _label,
                          enabled: !_submitting,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(60),
                          ],
                          decoration: InputDecoration(
                            labelText: strings.addressLabelField,
                            hintText: strings.addressLabelHint,
                          ),
                          validator: (String? value) =>
                              (value?.trim().isEmpty ?? true)
                              ? strings.addressLabelRequired
                              : null,
                        ),
                      ],

                      const SizedBox(height: FotgSpacing.x5),
                      _Field(
                        controller: _line1,
                        enabled: !_submitting,
                        label: strings.addressLine1Field,
                        capitalization: TextCapitalization.words,
                        maxLength: 180,
                        validator: (String? value) =>
                            (value?.trim().isEmpty ?? true)
                            ? strings.addressLine1Required
                            : null,
                      ),
                      _Field(
                        controller: _line2,
                        enabled: !_submitting,
                        label: strings.addressLine2Field,
                        capitalization: TextCapitalization.words,
                        maxLength: 180,
                      ),
                      _Field(
                        controller: _landmark,
                        enabled: !_submitting,
                        label: strings.addressLandmarkField,
                        capitalization: TextCapitalization.sentences,
                        maxLength: 120,
                      ),
                      _Field(
                        controller: _city,
                        enabled: !_submitting,
                        label: strings.addressCityField,
                        capitalization: TextCapitalization.words,
                        maxLength: 90,
                        validator: (String? value) =>
                            (value?.trim().isEmpty ?? true)
                            ? strings.addressCityRequired
                            : null,
                      ),
                      _Field(
                        controller: _state,
                        enabled: !_submitting,
                        label: strings.addressStateField,
                        capitalization: TextCapitalization.words,
                        maxLength: 90,
                        validator: (String? value) =>
                            (value?.trim().isEmpty ?? true)
                            ? strings.addressStateRequired
                            : null,
                      ),
                      _Field(
                        controller: _postal,
                        enabled: !_submitting,
                        label: postal.isNumeric
                            ? strings.addressPostalField
                            : strings.addressPostalFieldGeneric,
                        // A numeric keypad only where the format is numeric. A UK
                        // postcode typed on a number pad is impossible.
                        keyboardType: postal.isNumeric
                            ? TextInputType.number
                            : TextInputType.text,
                        capitalization: TextCapitalization.characters,
                        maxLength: 16,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        validator: (String? value) {
                          final String code = value?.trim() ?? '';

                          if (code.isEmpty) {
                            return postal.required
                                ? strings.addressPostalRequired
                                : null;
                          }

                          // Client-side for a fast keyboard; the server
                          // re-checks and its answer is the one that counts.
                          return postal.matches(code)
                              ? null
                              : strings.addressPostalInvalid(
                                  postal.example ?? '110016',
                                );
                        },
                      ),

                      const SizedBox(height: FotgSpacing.x2),
                      _CountryRow(countryCode: _countryCode),

                      const SizedBox(height: FotgSpacing.x5),
                      _LocationRow(
                        heading: strings.addressLocationHeading,
                        value: _isLocated
                            ? (_locatedLabel ?? '')
                            : strings.addressNotLocated,
                        help: strings.addressLocateHelp,
                        isLocated: _isLocated,
                        actionLabel: _isLocated
                            ? strings.addressChangeLocation
                            : strings.addressLocateCta,
                        onPressed: _submitting ? null : _locate,
                      ),

                      const SizedBox(height: FotgSpacing.x2),
                      SwitchListTile.adaptive(
                        value: _makeDefault,
                        // Editing the address that is already the default cannot
                        // un-default it — the server ignores that, so the control
                        // must not pretend otherwise.
                        onChanged:
                            _submitting || (widget.existing?.isDefault ?? false)
                            ? null
                            : (bool value) =>
                                  setState(() => _makeDefault = value),
                        title: Text(strings.addressMakeDefault),
                        contentPadding: EdgeInsets.zero,
                      ),

                      if (_error != null) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x4),
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Pinned, not the last thing in the scroll view. A seven-field form
              // is taller than a phone, so a Save button at the bottom of the
              // scroll is both invisible on arrival and the first thing the
              // keyboard covers.
              _PinnedAction(
                label: strings.addressFormSave,
                isLoading: _submitting,
                onPressed: _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary action, held at the bottom of the screen above the keyboard.
class _PinnedAction extends StatelessWidget {
  const _PinnedAction({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      // No keyboard inset arithmetic here: Scaffold already shrinks its body
      // when the keyboard opens, so this bar rides up with it.
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x3,
        FotgSpacing.x5,
        FotgSpacing.x4,
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

/// One text field with the spacing and counter settings every field here shares.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.maxLength,
    this.capitalization = TextCapitalization.none,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final int maxLength;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FotgSpacing.x4),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        textCapitalization: capitalization,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(maxLength),
        ],
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          // The limit is enforced by the formatter; a running counter under
          // every field is visual noise on a seven-field form.
          counterText: '',
          errorMaxLines: 2,
        ),
        validator: validator,
      ),
    );
  }
}

/// The country, shown and fixed.
///
/// India-first: the launch market is the only one the address form is designed
/// around, and offering a picker before any other market is supported would be a
/// choice with one option. The schema, the validator and the postal rules are
/// all country-aware already, so adding the picker later changes this widget and
/// nothing else.
class _CountryRow extends StatelessWidget {
  const _CountryRow({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    final SupportedCountry country = SupportedCountry.all.firstWhere(
      (SupportedCountry c) => c.iso == countryCode,
      orElse: () => SupportedCountry.fallback,
    );

    return Row(
      children: <Widget>[
        Text(
          '${strings.addressCountryField}: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(country.name, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Whether this address has a position, and how to give it one.
///
/// Optional, and said so: an address with no coordinates is perfectly good for
/// a delivery and simply cannot be one end of a journey. The planner explains
/// that when it comes up; this row is where somebody fixes it in advance.
class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.heading,
    required this.value,
    required this.help,
    required this.isLocated,
    required this.actionLabel,
    required this.onPressed,
  });

  final String heading;
  final String value;
  final String help;
  final bool isLocated;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        borderRadius: FotgRadius.card,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isLocated
                    ? Icons.where_to_vote_rounded
                    : Icons.location_searching_rounded,
                size: FotgSizing.iconSm,
                color: isLocated
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FotgSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      heading,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isLocated
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isLocated) ...<Widget>[
            const SizedBox(height: FotgSpacing.x2),
            Text(
              help,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: FotgSpacing.x1),
          // On its own line rather than beside the text. At 320dp a button
          // reading "Find this address" and a two-line address cannot share a
          // row without one of them being squeezed off the edge.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ),
        ],
      ),
    );
  }
}
