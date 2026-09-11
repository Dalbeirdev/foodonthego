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
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints available) {
            // Below ~360dp there is not enough width for an icon *and* a label
            // in each of three segments, and Material wraps the label rather
            // than shrinking it — "Othe / r" on a 320dp phone. The label is the
            // part that carries the meaning, so the icon is what goes.
            final bool roomForIcons = available.maxWidth >= 320;

            return SegmentedButton<AddressType>(
              segments: <ButtonSegment<AddressType>>[
                ButtonSegment<AddressType>(
                  value: AddressType.home,
                  label: Text(strings.addressTypeHome),
                  icon: roomForIcons ? const Icon(Icons.home_outlined) : null,
                ),
                ButtonSegment<AddressType>(
                  value: AddressType.work,
                  label: Text(strings.addressTypeWork),
                  icon: roomForIcons
                      ? const Icon(Icons.work_outline_rounded)
                      : null,
                ),
                ButtonSegment<AddressType>(
                  value: AddressType.other,
                  label: Text(strings.addressTypeOther),
                  icon: roomForIcons ? const Icon(Icons.place_outlined) : null,
                ),
              ],
              selected: <AddressType>{selected},
              showSelectedIcon: false,
              onSelectionChanged: (Set<AddressType> selection) =>
                  onChanged(selection.first),
            );
          },
        ),
      ],
    );
  }
}
