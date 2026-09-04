import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/config/app_environment.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/models/trip.dart';
import '../../domain/repositories/home_repository.dart';
import '../../shared/state/providers.dart';
import '../../shared/widgets/app_error_view.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/active_order_card.dart';
import 'widgets/greeting_header.dart';
import 'widgets/how_it_works.dart';
import 'widgets/journey_planner_card.dart';
import 'widgets/quick_actions.dart';
import '../../shared/state/trips_controller.dart';
import '../trips/trip_detail_screen.dart';
import '../trips/trip_form_screen.dart';
import 'widgets/next_journey_card.dart';

/// The customer home screen.
///
/// It has exactly three branches — loading, error, data — because the dashboard
/// arrives as one value. Within the data branch the layout is *conditional, not
/// padded*: a customer with no journey sees no journey section at all, rather
/// than an empty container captioned "no journey".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.now});

  /// Injectable so greetings and countdowns can be tested at a known instant.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HomeDashboard> dashboard = ref.watch(
      homeDashboardProvider,
    );

    return Scaffold(
      body: SafeArea(
        // The shell already consumed the top inset for the offline banner.
        top: false,
        child: dashboard.when(
          loading: () => const HomeSkeleton(),
          error: (Object error, StackTrace _) => AppErrorView(
            kind: error is HomeLoadFailure
                ? error.kind
                : HomeFailureKind.unknown,
            onRetry: () => ref.invalidate(homeDashboardProvider),
          ),
          data: (HomeDashboard data) => _HomeContent(dashboard: data, now: now),
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.dashboard, this.now});

  final HomeDashboard dashboard;
  final DateTime? now;

  void _openUnbuilt(
    BuildContext context,
    WidgetRef ref, {
    required String feature,
    required String module,
    required String analyticsEvent,
  }) {
    ref
        .read(analyticsProvider)
        .log(analyticsEvent, properties: <String, Object?>{'feature': feature});
    context.push(Routes.comingSoonFor(feature: feature, module: module));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);
    final Analytics analytics = ref.watch(analyticsProvider);

    // The journey section is its own async value rather than part of the
    // dashboard, because it comes from a different endpoint. It renders nothing
    // while loading and nothing on failure: home is not the place to report that
    // one card could not be fetched, and the Trips tab says so properly.
    final Trip? nextTrip = ref.watch(nextTripControllerProvider).value;

    return RefreshIndicator(
      // A real refresh: it invalidates the provider and waits for the next value,
      // so the spinner reflects an actual reload rather than a fixed delay.
      onRefresh: () async {
        analytics.log(AnalyticsEvents.homeRefreshed);
        ref.invalidate(homeDashboardProvider);
        await ref.read(homeDashboardProvider.future);
      },
      child: ListView(
        // Always scrollable, or pull-to-refresh does nothing on a short screen.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          FotgSpacing.x5,
          FotgSpacing.x5,
          FotgSpacing.x5,
          FotgSpacing.x10,
        ),
        children: <Widget>[
          GreetingHeader(
            customer: dashboard.customer,
            now: now,
            onAvatarTap: () => _openUnbuilt(
              context,
              ref,
              feature: strings.profilePersonalInformation,
              module: 'Module 03 — Authentication',
              analyticsEvent: AnalyticsEvents.unbuiltFeatureOpened,
            ),
          ),
          const SizedBox(height: FotgSpacing.x6),

          JourneyPlannerCard(
            onPlanJourney: () {
              analytics.log(AnalyticsEvents.planJourneyTapped);
              // Real from Module 05 onwards. The planner is a screen now, not a
              // placeholder naming the module that will build it.
              Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (BuildContext context) => const TripFormScreen(),
                ),
              );
            },
            isEnabled: true,
          ),

          // The customer's real next journey, from the API. Rendered only when
          // there is one — an empty "Your next journey" card is worse than no
          // card, which is why this is a null check rather than an empty state.
          if (nextTrip != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x8),
            SectionHeader(
              title: strings.homeNextJourney,
              action: TextButton(
                onPressed: () {
                  analytics.log(AnalyticsEvents.tripsTabOpened);
                  context.go(Routes.trips);
                },
                child: Text(strings.homeJourneyViewAll),
              ),
            ),
            NextJourneyCard(
              trip: nextTrip,
              onTap: () {
                analytics.log(AnalyticsEvents.journeyCardTapped);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        TripDetailScreen(tripId: nextTrip.id),
                  ),
                );
              },
            ),
          ],

          if (dashboard.activeOrder != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x8),
            SectionHeader(title: strings.orderSectionTitle),
            ActiveOrderCard(
              order: dashboard.activeOrder!,
              now: now,
              onTap: () => _openUnbuilt(
                context,
                ref,
                feature: 'Order detail',
                module: 'Module 08 — Order Lifecycle',
                analyticsEvent: AnalyticsEvents.orderCardTapped,
              ),
            ),
          ],

          // For a customer with nothing on, the screen explains the product
          // instead of showing blank space where cards would be.
          if (nextTrip == null && !dashboard.hasActiveOrder) ...<Widget>[
            const SizedBox(height: FotgSpacing.x8),
            SectionHeader(title: strings.howItWorksTitle),
            const HowItWorks(),
          ],

          const SizedBox(height: FotgSpacing.x8),
          SectionHeader(title: strings.quickActionsTitle),
          QuickActions(
            actions: <QuickAction>[
              QuickAction(
                icon: Icons.receipt_long_outlined,
                label: strings.quickActionOrders,
                onTap: () {
                  analytics.log(
                    AnalyticsEvents.quickActionTapped,
                    properties: <String, Object?>{'action': 'orders'},
                  );
                  // A real destination: the Orders tab exists in this module.
                  context.go(Routes.orders);
                },
              ),
              QuickAction(
                icon: Icons.bookmark_border_rounded,
                label: strings.quickActionSavedPlaces,
                onTap: () => _openUnbuilt(
                  context,
                  ref,
                  feature: strings.quickActionSavedPlaces,
                  module: 'Module 04 — Saved Addresses',
                  analyticsEvent: AnalyticsEvents.quickActionTapped,
                ),
              ),
              QuickAction(
                icon: Icons.support_agent_rounded,
                label: strings.quickActionSupport,
                onTap: () => _openUnbuilt(
                  context,
                  ref,
                  feature: strings.quickActionSupport,
                  module: 'Module 14 — Support',
                  analyticsEvent: AnalyticsEvents.quickActionTapped,
                ),
              ),
            ],
          ),

          if (AppEnvironment.current.allowsFixtures) ...<Widget>[
            const SizedBox(height: FotgSpacing.x6),
            const _DevelopmentDataNotice(),
          ],
        ],
      ),
    );
  }
}

/// States plainly that the content above is fixture data. Rendered only where
/// the environment allows fixtures, so it cannot reach a customer.
class _DevelopmentDataNotice extends StatelessWidget {
  const _DevelopmentDataNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(FotgSpacing.x4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1E38) : FotgColors.infoSurface,
        borderRadius: FotgRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.science_outlined,
            size: FotgSizing.iconSm,
            color: isDark ? FotgColors.darkInfo : FotgColors.info,
          ),
          const SizedBox(width: FotgSpacing.x3),
          Expanded(
            child: Text(
              strings.developmentDataNotice,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? FotgColors.darkInfo : FotgColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
