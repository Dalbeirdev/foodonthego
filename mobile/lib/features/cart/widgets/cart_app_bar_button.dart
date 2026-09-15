import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/cart.dart';
import '../../../shared/state/cart_controller.dart';

/// The way to the cart, from wherever the customer is adding to it.
///
/// A cart the customer cannot reach is not a cart. Module 11 could add to one
/// and had nowhere to send anybody afterwards; this is the missing door, and it
/// sits in the app bar of every screen a dish can be added from.
///
/// The count is a **badge, not a promise**. It is the server's figure from the
/// last read, and it is deliberately absent rather than zero while that read is
/// in flight or has failed: a "0" the app invented would be indistinguishable
/// from an empty cart, and a traveller in a dead zone would be told they have
/// nothing.
class CartAppBarButton extends ConsumerWidget {
  const CartAppBarButton({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);

    final int? count = ref
        .watch(cartBadgeProvider(tripId))
        .maybeWhen(
          data: (CartView view) => view.itemCount > 0 ? view.itemCount : null,
          orElse: () => null,
        );

    return IconButton(
      onPressed: () => context.push(Routes.tripCartPath(tripId)),
      tooltip: strings.cartOpen,
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.shopping_basket_outlined),
          if (count != null)
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: const BoxDecoration(
                  color: FotgColors.primary600,
                  borderRadius: FotgRadius.pill,
                ),
                child: Text(
                  // Above ninety-nine the badge would grow wider than the icon
                  // it sits on. The exact figure is on the cart screen; here it
                  // only has to say "a lot".
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: FotgColors.neutral0,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
