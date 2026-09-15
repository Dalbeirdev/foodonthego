import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/phone/supported_country.dart';
import '../../../core/theme/tokens.dart';

/// The country selector attached to the phone field.
///
/// A bottom sheet rather than a dropdown: at four entries a dropdown would do,
/// but the list grows with each market and a sheet stays usable at twenty
/// entries and at large text sizes, where a dropdown menu runs off the screen.
class CountryPickerButton extends StatelessWidget {
  const CountryPickerButton({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final SupportedCountry selected;
  final ValueChanged<SupportedCountry> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      label:
          '${AppStrings.of(context).authCountryPickerTitle}, '
          '${selected.name} ${selected.dialCode}',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: FotgRadius.control,
        child: Padding(
          // No Container with an alignment here, and no height: a Container that
          // is told to align its child expands to every pixel its constraints
          // allow. As a field prefix that means it swallows the whole field and
          // the number being typed becomes invisible — which is exactly what it
          // did before this was written as a shrink-wrapping Padding.
          padding: const EdgeInsets.only(right: FotgSpacing.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(selected.flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: FotgSpacing.x2),
              Text(selected.dialCode, style: theme.textTheme.bodyLarge),
              Icon(
                Icons.arrow_drop_down,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final SupportedCountry? picked =
        await showModalBottomSheet<SupportedCountry>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) =>
              _CountrySheet(selected: selected),
        );

    if (picked != null) onChanged(picked);
  }
}

class _CountrySheet extends StatelessWidget {
  const _CountrySheet({required this.selected});

  final SupportedCountry selected;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FotgSpacing.x6,
              0,
              FotgSpacing.x6,
              FotgSpacing.x4,
            ),
            child: Text(
              strings.authCountryPickerTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          for (final SupportedCountry country in SupportedCountry.all)
            ListTile(
              leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
              title: Text(country.name),
              trailing: Text(
                country.dialCode,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              selected: country.callingCode == selected.callingCode,
              onTap: () => Navigator.of(context).pop(country),
            ),
          const SizedBox(height: FotgSpacing.x4),
        ],
      ),
    );
  }
}
