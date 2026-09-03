import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';

/// Trips. Module 02 delivers the destination and its empty state; Module 05
/// fills it with journeys.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.navTrips)),
      body: SafeArea(
        top: false,
        child: EmptyStateView(
          icon: Icons.route_rounded,
          title: strings.tripsEmptyTitle,
          body: strings.tripsEmptyBody,
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
