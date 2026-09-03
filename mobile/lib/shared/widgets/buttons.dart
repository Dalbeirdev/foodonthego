import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The primary call to action.
///
/// Carries its own loading state so a caller never has to swap the button for a
/// spinner — swapping changes the layout and moves everything below it, and the
/// label disappearing is exactly when a user taps again.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool disabled = isLoading || onPressed == null;

    final Widget child = isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: FotgSpacing.x3),
              // The label stays while loading, so the button keeps its width and
              // the user keeps their context.
              Text(label),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: FotgSizing.iconSm),
                const SizedBox(width: FotgSpacing.x2),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final Widget button = FilledButton(
      onPressed: disabled ? null : onPressed,
      child: child,
    );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: isLoading ? '$label, loading' : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// A lower-emphasis action that still reads as a control.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget button = OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: FotgSizing.iconSm),
            const SizedBox(width: FotgSpacing.x2),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A text link that keeps a full touch target.
///
/// A bare `TextButton` shrinks to its text, which on "View order" is about 70x20 —
/// well under the 48dp floor.
class LinkAction extends StatelessWidget {
  const LinkAction({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, FotgSizing.touchTargetMin),
        padding: const EdgeInsets.symmetric(horizontal: FotgSpacing.x3),
        foregroundColor: theme.colorScheme.primary,
        textStyle: theme.textTheme.labelLarge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (icon != null) ...<Widget>[
            const SizedBox(width: FotgSpacing.x1),
            Icon(icon, size: 18),
          ],
        ],
      ),
    );
  }
}
