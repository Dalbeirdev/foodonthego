import 'package:flutter/material.dart';

import '../../domain/models/placed_order.dart';
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

  static OrderStatusStyle of(PlacedOrderStatus status, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    return switch (status) {
      PlacedOrderStatus.placed => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkInfo : FotgColors.info,
        background: isDark ? const Color(0xFF0F1E38) : FotgColors.infoSurface,
        icon: Icons.receipt_long_outlined,
      ),
      PlacedOrderStatus.accepted => OrderStatusStyle(
        foreground: isDark ? FotgColors.secondary500 : FotgColors.secondary700,
        background: isDark ? const Color(0xFF0C2F2B) : FotgColors.secondary100,
        icon: Icons.check_circle_outline,
      ),
      PlacedOrderStatus.cooking => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkWarning : FotgColors.warning,
        background: isDark
            ? const Color(0xFF241A06)
            : FotgColors.warningSurface,
        icon: Icons.local_fire_department_outlined,
      ),
      PlacedOrderStatus.ready => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkSuccess : FotgColors.success,
        background: isDark
            ? const Color(0xFF0F2417)
            : FotgColors.successSurface,
        icon: Icons.takeout_dining_outlined,
      ),
      PlacedOrderStatus.pickedUp => OrderStatusStyle(
        foreground: isDark ? FotgColors.neutral400 : FotgColors.neutral600,
        background: isDark ? FotgColors.neutral800 : FotgColors.neutral100,
        icon: Icons.task_alt_outlined,
      ),
      // Three ways an order ends badly, and they read alike on purpose: a
      // customer needs to know it is not coming, and the difference between
      // "you cancelled" and "they declined" is in the copy beside this, not in
      // the colour of a chip.
      PlacedOrderStatus.cancelled ||
      PlacedOrderStatus.rejected ||
      PlacedOrderStatus.paymentFailed => OrderStatusStyle(
        foreground: isDark ? FotgColors.darkError : FotgColors.error,
        background: isDark ? const Color(0xFF2A1414) : FotgColors.errorSurface,
        icon: Icons.cancel_outlined,
      ),

      // Not an order yet, and a refund is money moving rather than food. Both
      // are deliberately quiet: neither is a step towards collecting anything.
      PlacedOrderStatus.awaitingPayment ||
      PlacedOrderStatus.refunded => OrderStatusStyle(
        foreground: isDark ? FotgColors.neutral400 : FotgColors.neutral600,
        background: isDark ? FotgColors.neutral800 : FotgColors.neutral100,
        icon: Icons.hourglass_empty_outlined,
      ),
    };
  }
}
