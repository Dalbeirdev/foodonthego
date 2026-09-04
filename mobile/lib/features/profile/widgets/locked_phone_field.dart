import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';

/// The verified mobile number, shown and not editable.
///
/// Drawn as a panel rather than a disabled `TextField`: a greyed-out input
/// invites tapping and then does nothing, which reads as a bug. This says what
/// the number is, that it is verified, and why it cannot be changed here — in
/// that order, because that is the order somebody asks.
///
/// Masked even on the account's own screen. A phone is read over shoulders and
/// screenshotted into support tickets; the last four digits confirm which number
/// it is without putting the whole thing on display.
class LockedPhoneField extends StatelessWidget {
  const LockedPhoneField({required this.maskedPhone, super.key});

  final String maskedPhone;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label:
          '${strings.profileMobileLabel}, $maskedPhone, ${strings.profileVerified}',
      readOnly: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(FotgSpacing.x4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: FotgRadius.control,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: FotgSizing.iconSm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: FotgSpacing.x2),
                  Text(
                    strings.profileMobileLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FotgSpacing.x2),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      maskedPhone,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  // Text as well as a tick. "Verified" communicated by a green
                  // check alone is invisible to anybody who cannot see colour or
                  // is using a screen reader.
                  Icon(
                    Icons.verified_rounded,
                    size: FotgSizing.iconSm,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: FotgSpacing.x1),
                  Text(
                    strings.profileVerified,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FotgSpacing.x2),
              Text(
                strings.profilePhoneLocked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
