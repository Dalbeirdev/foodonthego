import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';

/// A note for the kitchen.
///
/// Two things this deliberately does not do. It does not promise the kitchen
/// will comply — the caption says they will see it and do what they can — and
/// it is never presented as a way to declare an allergy. A free-text field is
/// not an allergen control, and treating it as one is how somebody gets hurt.
class SpecialInstructionsField extends StatefulWidget {
  const SpecialInstructionsField({
    required this.text,
    required this.onChanged,
    required this.maxLength,
    required this.remaining,
    super.key,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final int maxLength;
  final int remaining;

  @override
  State<SpecialInstructionsField> createState() =>
      _SpecialInstructionsFieldState();
}

class _SpecialInstructionsFieldState extends State<SpecialInstructionsField> {
  late final TextEditingController _field = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(SpecialInstructionsField old) {
    super.didUpdateWidget(old);

    // Only when the two have genuinely diverged — never on every rebuild, which
    // would move the caret to the end of the line mid-word.
    if (widget.text != _field.text) {
      _field.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Wrap rather than Row: "Special instructions" and "Optional" do not
        // fit on one line at 320 dp with large text, and a heading clipped
        // mid-word is worse than one on two lines.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: FotgSpacing.x2,
          children: <Widget>[
            Text(
              strings.itemNoteLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              strings.itemNoteOptional,
              style: theme.textTheme.labelSmall?.copyWith(
                color: FotgColors.neutral600,
              ),
            ),
          ],
        ),
        const SizedBox(height: FotgSpacing.x2),
        TextField(
          controller: _field,
          onChanged: widget.onChanged,
          // Line breaks kept: "no onion" on its own line is how somebody
          // writes a second request.
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.newline,
          // Stops at what the server accepts, so a customer cannot type their
          // way into an error.
          maxLength: widget.maxLength,
          buildCounter:
              (
                _, {
                required int currentLength,
                required bool isFocused,
                required int? maxLength,
              }) => null,
          decoration: InputDecoration(
            hintText: strings.itemNoteHint,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(FotgRadius.lg)),
            ),
          ),
        ),
        const SizedBox(height: FotgSpacing.x1),
        // Wrap rather than Row: at 320 dp with the counter showing, the two
        // do not fit side by side, and a caveat clipped mid-sentence is worse
        // than one on its own line.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: FotgSpacing.x3,
          runSpacing: FotgSpacing.x1,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                strings.itemNoteCaveat,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: FotgColors.neutral600,
                ),
              ),
            ),
            // Only once the limit is close. A counter that is always on turns
            // a note into a test.
            if (widget.remaining <= 40)
              Text(
                strings.itemNoteRemaining(widget.remaining),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.remaining <= 0
                      ? FotgColors.error
                      : FotgColors.neutral600,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
