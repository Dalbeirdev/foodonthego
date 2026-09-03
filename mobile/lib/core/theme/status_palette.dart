import 'package:flutter/material.dart';

import '../../domain/models/order_status.dart';
import 'tokens.dart';

/// How each order state looks.
///
/// Three things vary per state, not one: **colour, icon and label**. Colour alone
/// is not a usable signal — roughly one man in twelve cannot reliably separate
/// the amber "cooking" from the green "ready", and both are the moment that
/// matters most to someone deciding whether to pull over.
class OrderStatusStyle {
  const OrderStatusStyle({
    required this.foreground,
    required this.background,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final IconData icon;

  static OrderStatusStyle of(OrderStatus status, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    return switch (status) {
      OrderStatus.placed => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkInfo : FotgColors.info,
        background: isDark ? const Color(0xFF0F1E38) : FotgColors.infoSurface,
        icon: Icons.receipt_long_outlined,
      ),
      OrderStatus.accepted => OrderStatusStyle(
        foreground: isDark ? FotgColors.secondary500 : FotgColors.secondary700,
        background: isDark ? const Color(0xFF0C2F2B) : FotgColors.secondary100,
        icon: Icons.check_circle_outline,
      ),
      OrderStatus.cooking => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkWarning : FotgColors.warning,
        background: isDark
            ? const Color(0xFF241A06)
            : FotgColors.warningSurface,
        icon: Icons.local_fire_department_outlined,
      ),
      OrderStatus.ready => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkSuccess : FotgColors.success,
        background: isDark
            ? const Color(0xFF0F2417)
            : FotgColors.successSurface,
        icon: Icons.takeout_dining_outlined,
      ),
      OrderStatus.pickedUp => OrderStatusStyle(
        foreground: isDark ? FotgColors.neutral400 : FotgColors.neutral600,
        background: isDark ? FotgColors.neutral800 : FotgColors.neutral100,
        icon: Icons.task_alt_outlined,
      ),
      OrderStatus.cancelled => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkError : FotgColors.error,
        background: isDark ? const Color(0xFF2A1414) : FotgColors.errorSurface,
        icon: Icons.cancel_outlined,
      ),
    };
  }
}
