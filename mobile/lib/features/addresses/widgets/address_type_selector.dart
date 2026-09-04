import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/saved_address.dart';

/// Home / Work / Other, as three segments.
///
/// A segmented control rather than a dropdown: three options that all fit on
/// screen should not need a tap to reveal, and the choice changes the form
/// below it, so it belongs at the top where it is visible.
class AddressTypeSelector extends StatelessWidget {
  const AddressTypeSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final AddressType selected;
  final ValueChanged<AddressType> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.addressTypeLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: FotgSpacing.x3),
        SegmentedButton<AddressType>(
          segments: <ButtonSegment<AddressType>>[
            ButtonSegment<AddressType>(
              value: AddressType.home,
              label: Text(strings.addressTypeHome),
              icon: const Icon(Icons.home_outlined),
            ),
            ButtonSegment<AddressType>(
              value: AddressType.work,
              label: Text(strings.addressTypeWork),
              icon: const Icon(Icons.work_outline_rounded),
            ),
            ButtonSegment<AddressType>(
              value: AddressType.other,
              label: Text(strings.addressTypeOther),
              icon: const Icon(Icons.place_outlined),
            ),
          ],
          selected: <AddressType>{selected},
          showSelectedIcon: false,
          onSelectionChanged: (Set<AddressType> selection) =>
              onChanged(selection.first),
        ),
      ],
    );
  }
}
