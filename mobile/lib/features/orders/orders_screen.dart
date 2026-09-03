import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';

/// Orders. The empty state deliberately shows no fixture orders: a permanent
/// fake order here would be indistinguishable from a real one. Module 08 fills it.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.navOrders)),
      body: SafeArea(
        top: false,
        child: EmptyStateView(
          icon: Icons.receipt_long_rounded,
          title: strings.ordersEmptyTitle,
          body: strings.ordersEmptyBody,
          action: PrimaryButton(
            label: strings.plannerCta,
            icon: Icons.near_me_rounded,
            expand: false,
            onPressed: () => context.push(
              Routes.comingSoonFor(
                feature: 'Trip planner',
                module: 'Module 05 — Trip Planner',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
