import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/saved_address.dart';
import '../../../domain/models/trip.dart';
import '../../../shared/state/addresses_controller.dart';
import '../../../shared/widgets/buttons.dart';

/// What the customer chose, and how to show it back to them.
///
/// The draft alone is not enough for the form: a saved-address draft is just an
/// id, and the row that displays the choice needs a name and a line of text.
/// Carrying both means the form never has to look an address up again — and
/// never has to guess a label for a place it did not resolve.
class PlaceChoice {
  const PlaceChoice({
    required this.draft,
    required this.title,
    required this.subtitle,
  });

  factory PlaceChoice.fromSavedAddress(SavedAddress address) => PlaceChoice(
    draft: JourneyPlaceDraft.fromSavedAddress(address),
    title: address.label,
    subtitle: address.formattedAddress,
  );

  final JourneyPlaceDraft draft;
  final String title;
  final String subtitle;
}

/// Choosing one end of a journey.
///
/// Two ways in, in the order a traveller actually wants them: the places they
/// have already saved, then a field for anywhere else. Module 04 exists so this
/// sheet's first section is usually one tap.
///
/// There is **no map and no autocomplete**, and the typed branch produces no
/// coordinates. Module 09 adds Places; until it does, a "suggestion" here would
/// be a guess presented as a fact.
Future<PlaceChoice?> showPlacePicker(
  BuildContext context, {
  required String title,
  String? defaultCountryCode,
}) {
  return showModalBottomSheet<PlaceChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => _PlacePickerSheet(
      title: title,
      defaultCountryCode: defaultCountryCode ?? 'IN',
    ),
  );
}

class _PlacePickerSheet extends ConsumerStatefulWidget {
  const _PlacePickerSheet({
    required this.title,
    required this.defaultCountryCode,
  });

  final String title;
  final String defaultCountryCode;

  @override
  ConsumerState<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends ConsumerState<_PlacePickerSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _area = TextEditingController();
  final TextEditingController _state = TextEditingController();
  final TextEditingController _label = TextEditingController();
  late final TextEditingController _country = TextEditingController(
    text: widget.defaultCountryCode,
  );

  @override
  void dispose() {
    _city.dispose();
    _area.dispose();
    _state.dispose();
    _label.dispose();
    _country.dispose();
    super.dispose();
  }

  void _useTyped() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String city = _city.text.trim();
    final String label = _label.text.trim();

    Navigator.of(context).pop(
      PlaceChoice(
        draft: JourneyPlaceDraft.typed(
          city: city,
          countryCode: _country.text.trim().toUpperCase(),
          label: label.isEmpty ? null : label,
          addressLine: _area.text.trim(),
          state: _state.text.trim(),
          // No coordinates. Nothing here geocoded anything, and a plausible
          // pair would be indistinguishable to Module 09 from a real one.
        ),
        title: label.isEmpty ? city : label,
        subtitle: <String>[
          _area.text.trim(),
          city,
          _state.text.trim(),
        ].where((String part) => part.isNotEmpty).join(', '),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<SavedAddress>> addresses = ref.watch(
      addressesControllerProvider,
    );

    final List<SavedAddress> saved = addresses.value ?? const <SavedAddress>[];

    return Padding(
      // The keyboard's inset, so the field being typed into is never behind it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext context, ScrollController controller) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FotgSpacing.x5,
                  FotgSpacing.x4,
                  FotgSpacing.x2,
                  FotgSpacing.x2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  // A non-lazy Column inside a scroll view, not a ListView.
                  // A ListView builds lazily, so scrolling the city field out of
                  // view would unregister it from the Form and validate() would
                  // skip it in silence — the Module 04 defect, in a sheet.
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(
                      FotgSpacing.x5,
                      FotgSpacing.x4,
                      FotgSpacing.x5,
                      FotgSpacing.x6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          strings.placePickerSaved,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: FotgSpacing.x2),
                        if (saved.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: FotgSpacing.x2,
                            ),
                            child: Text(
                              strings.placePickerNoSaved,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          ...saved.map(
                            (SavedAddress address) => _SavedAddressTile(
                              address: address,
                              onTap: () => Navigator.of(context)
                                  .pop(PlaceChoice.fromSavedAddress(address)),
                            ),
                          ),
                        const SizedBox(height: FotgSpacing.x6),
                        Text(
                          strings.placePickerTypeOne,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: FotgSpacing.x3),
                        TextFormField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: strings.placeFormCity,
                            hintText: strings.placeFormCityHint,
                          ),
                          validator: (String? value) =>
                              (value ?? '').trim().isEmpty
                              ? strings.tripErrorCityRequired
                              : null,
                        ),
                        const SizedBox(height: FotgSpacing.x4),
                        TextFormField(
                          controller: _area,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: strings.placeFormArea,
                          ),
                        ),
                        const SizedBox(height: FotgSpacing.x4),
                        TextFormField(
                          controller: _state,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: strings.placeFormState,
                          ),
                        ),
                        const SizedBox(height: FotgSpacing.x4),
                        TextFormField(
                          controller: _label,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: strings.placeFormLabel,
                          ),
                        ),
                        const SizedBox(height: FotgSpacing.x4),
                        TextFormField(
                          controller: _country,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: InputDecoration(
                            labelText: strings.placeFormCountry,
                            counterText: '',
                          ),
                          validator: (String? value) =>
                              (value ?? '').trim().length == 2
                              ? null
                              : strings.tripErrorCountry,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Pinned, so the action is reachable without scrolling past the
              // saved addresses on a short screen.
              Container(
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
                  label: strings.placeUse,
                  onPressed: _useTyped,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SavedAddressTile extends StatelessWidget {
  const _SavedAddressTile({required this.address, required this.onTap});

  final SavedAddress address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final IconData icon = switch (address.type) {
      AddressType.home => Icons.home_rounded,
      AddressType.work => Icons.work_rounded,
      AddressType.other => Icons.place_rounded,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(address.label),
      subtitle: Text(
        address.formattedAddress,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
