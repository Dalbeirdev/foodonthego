import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/config/app_environment.dart';
import '../../core/config/feature_flags.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/home_dashboard.dart';
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
import 'widgets/route_summary_card.dart';

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
    final FeatureFlags flags = ref.watch(featureFlagsProvider);
    final Analytics analytics = ref.watch(analyticsProvider);

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
            isTravelling: dashboard.hasActiveTrip,
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
              _openUnbuilt(
                context,
                ref,
                feature: 'Trip planner',
                module: 'Module 05 — Trip Planner',
                analyticsEvent: AnalyticsEvents.unbuiltFeatureOpened,
              );
            },
            isEnabled: flags.tripPlannerEnabled || flags.exposesUnbuiltFeatures,
          ),

          // Rendered only when there is a journey. No empty shells.
          if (dashboard.activeTrip != null) ...<Widget>[
            const SizedBox(height: FotgSpacing.x8),
            SectionHeader(title: strings.journeySectionTitle),
            RouteSummaryCard(
              trip: dashboard.activeTrip!,
              onTap: () => _openUnbuilt(
                context,
                ref,
                feature: 'Journey detail',
                module: 'Module 05 — Trip Planner',
                analyticsEvent: AnalyticsEvents.journeyCardTapped,
              ),
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
          if (dashboard.isNewJourney) ...<Widget>[
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
