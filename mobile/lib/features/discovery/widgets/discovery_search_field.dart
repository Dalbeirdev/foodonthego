import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';

/// The search field above the route's stops.
///
/// Stateful only in that it owns a [TextEditingController]. What was typed
/// lives in the discovery controller; this widget's own controller exists
/// because a `TextField` needs one to place a cursor, and rebuilding it from
/// state on every keystroke would move the caret to the end of the line each
/// time somebody edited the middle of a word.
class DiscoverySearchField extends StatefulWidget {
  const DiscoverySearchField({
    required this.text,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCleared,
    this.enabled = true,
    super.key,
  });

  /// What the controller believes is typed. Written into the field only when it
  /// differs — a clear button, or a restored screen — never on every rebuild.
  final String text;

  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onCleared;
  final bool enabled;

  @override
  State<DiscoverySearchField> createState() => _DiscoverySearchFieldState();
}

class _DiscoverySearchFieldState extends State<DiscoverySearchField> {
  late final TextEditingController _field = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(DiscoverySearchField old) {
    super.didUpdateWidget(old);

    // Only when the state and the field have genuinely diverged, which happens
    // when something other than typing changed the term.
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

    return TextField(
      controller: _field,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted(),
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      decoration: InputDecoration(
        isDense: true,
        hintText: strings.discoverySearchHint,
        labelText: strings.discoverySearchLabel,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        // Offered only when there is something to clear, so the field does not
        // carry a permanently inert button.
        suffixIcon: widget.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: strings.discoverySearchClear,
                onPressed: () {
                  _field.clear();
                  widget.onCleared();
                },
              ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(FotgRadius.lg)),
        ),
      ),
    );
  }
}
