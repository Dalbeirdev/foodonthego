import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/saved_address.dart';

/// One saved address in the list.
///
/// A list row rather than a card: three cards on a phone leaves less room for
/// the address than for the padding around it, and the whole point of this
/// screen is reading addresses.
class AddressListItem extends StatelessWidget {
  const AddressListItem({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onMakeDefault,
    this.busy = false,
    super.key,
  });

  final SavedAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMakeDefault;

  /// True while a row-level action is in flight. The row stays in place and
  /// shows its own progress rather than the list blanking out.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Semantics(
      // Read as one thing, in the order somebody needs it: what it is called,
      // whether it is the default, then where it is.
      label: <String>[
        address.label,
        if (address.isDefault) strings.addressDefault,
        address.formattedAddress,
      ].join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FotgSpacing.x5,
            vertical: FotgSpacing.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _TypeIcon(type: address.type, isDefault: address.isDefault),
              const SizedBox(width: FotgSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            address.label,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (address.isDefault) ...<Widget>[
                          const SizedBox(width: FotgSpacing.x2),
                          _DefaultBadge(label: strings.addressDefault),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address.shortAddress,
                      style: theme.textTheme.bodyMedium,
                      // Two lines, not one: a long Indian address is routinely
                      // "Flat 204, Shree Krishna Residency, MG Extension Road",
                      // and truncating it at one line loses the building.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      address.localityLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (address.landmark != null &&
                        address.landmark!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        address.landmark!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FotgSpacing.x2),
              _RowActions(
                address: address,
                busy: busy,
                onEdit: onEdit,
                onDelete: onDelete,
                onMakeDefault: onMakeDefault,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, required this.isDefault});

  final AddressType type;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final IconData icon = switch (type) {
      AddressType.home => Icons.home_outlined,
      AddressType.work => Icons.work_outline_rounded,
      AddressType.other => Icons.place_outlined,
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDefault
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: FotgRadius.control,
      ),
      child: Icon(
        icon,
        size: FotgSizing.iconMd,
        color: isDefault
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The default marker.
///
/// A word inside a pill, not a coloured dot or a star. "Default" is a state
/// somebody needs to read, and shape or colour alone excludes anybody who cannot
/// see the difference.
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FotgSpacing.x2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: FotgRadius.pill,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Edit, remove and set-default, behind one overflow control.
///
/// Not swipe-to-delete. A swipe that removes an address is one accidental
/// gesture away from destroying something, and this list is scrolled.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.address,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onMakeDefault,
  });

  final SavedAddress address;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMakeDefault;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    if (busy) {
      return const SizedBox(
        width: FotgSizing.touchTargetMin,
        height: FotgSizing.touchTargetMin,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: strings.addressEdit,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (String action) => switch (action) {
        'edit' => onEdit(),
        'default' => onMakeDefault(),
        'delete' => onDelete(),
        _ => null,
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: _MenuRow(
            icon: Icons.edit_outlined,
            label: strings.addressEdit,
          ),
        ),
        if (!address.isDefault)
          PopupMenuItem<String>(
            value: 'default',
            child: _MenuRow(
              icon: Icons.star_outline_rounded,
              label: strings.addressSetDefault,
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: strings.addressDelete,
            destructive: true,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? color = destructive ? theme.colorScheme.error : null;

    return Row(
      children: <Widget>[
        Icon(icon, size: FotgSizing.iconSm, color: color),
        const SizedBox(width: FotgSpacing.x3),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
