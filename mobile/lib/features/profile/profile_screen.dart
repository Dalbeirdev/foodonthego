import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_environment.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/home_dashboard.dart';
import '../../shared/state/providers.dart';

/// The customer profile shell.
///
/// Every row routes to a controlled placeholder naming its module — none edits
/// anything, because there is no account to edit until Module 03. Sign out is
/// present but disabled for the same reason: showing it enabled would imply a
/// session exists.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppStrings strings = AppStrings.of(context);
    final AsyncValue<HomeDashboard> dashboard = ref.watch(
      homeDashboardProvider,
    );

    final String name = dashboard.maybeWhen(
      data: (HomeDashboard value) => value.customer.fullName,
      orElse: () => '—',
    );
    final String initials = dashboard.maybeWhen(
      data: (HomeDashboard value) => value.customer.initials,
      orElse: () => '?',
    );

    void open(String feature, String module) =>
        context.push(Routes.comingSoonFor(feature: feature, module: module));

    return Scaffold(
      appBar: AppBar(title: Text(strings.navProfile)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: FotgSpacing.x10),
          children: <Widget>[
            _ProfileHeader(name: name, initials: initials),
            const SizedBox(height: FotgSpacing.x4),

            _Section(title: strings.profileAccountSection),
            _Row(
              icon: Icons.person_outline_rounded,
              label: strings.profilePersonalInformation,
              onTap: () => open(
                strings.profilePersonalInformation,
                'Module 03 — Authentication',
              ),
            ),
            _Row(
              icon: Icons.bookmark_border_rounded,
              label: strings.profileSavedAddresses,
              onTap: () => open(
                strings.profileSavedAddresses,
                'Module 04 — Saved Addresses',
              ),
            ),
            _Row(
              icon: Icons.credit_card_outlined,
              label: strings.profilePaymentMethods,
              onTap: () =>
                  open(strings.profilePaymentMethods, 'Module 11 — Payments'),
            ),
            _Row(
              icon: Icons.history_rounded,
              label: strings.profileOrderHistory,
              onTap: () => open(
                strings.profileOrderHistory,
                'Module 08 — Order Lifecycle',
              ),
            ),

            _Section(title: strings.profilePreferencesSection),
            _Row(
              icon: Icons.notifications_none_rounded,
              label: strings.profileNotifications,
              onTap: () => open(
                strings.profileNotifications,
                'Module 10 — Notifications',
              ),
            ),

            _Section(title: strings.profileSupportSection),
            _Row(
              icon: Icons.support_agent_rounded,
              label: strings.profileHelp,
              onTap: () => open(strings.profileHelp, 'Module 14 — Support'),
            ),
            _Row(
              icon: Icons.gavel_rounded,
              label: strings.profileLegal,
              onTap: () =>
                  open(strings.profileLegal, 'Module 17 — Legal & Policy'),
            ),
            _Row(
              icon: Icons.privacy_tip_outlined,
              label: strings.profilePrivacy,
              onTap: () =>
                  open(strings.profilePrivacy, 'Module 17 — Legal & Policy'),
            ),
            _Row(
              icon: Icons.info_outline_rounded,
              label: strings.profileAbout,
              onTap: () =>
                  open(strings.profileAbout, 'Module 17 — Legal & Policy'),
            ),

            const SizedBox(height: FotgSpacing.x6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FotgSpacing.x5),
              child: OutlinedButton.icon(
                // Disabled, not hidden: the row belongs in the information
                // architecture, and an enabled control would imply a session.
                onPressed: null,
                icon: const Icon(Icons.logout_rounded, size: FotgSizing.iconSm),
                label: Text(strings.profileSignOut),
                style: OutlinedButton.styleFrom(
                  // Full width is deliberate here: this row spans the settings
                  // list it belongs to. Stated explicitly rather than relying on
                  // Size.fromHeight, whose infinite width is easy to miss.
                  minimumSize: const Size(
                    double.infinity,
                    FotgSizing.controlHeightMd,
                  ),
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: FotgSpacing.x3),
            Center(
              child: Text(
                '${strings.appName} · ${AppEnvironment.current.label}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.initials});

  final String name;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x4,
        FotgSpacing.x5,
        FotgSpacing.x2,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.outline),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: FotgSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.of(context).tagline,
                  style: theme.textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x5,
        FotgSpacing.x5,
        FotgSpacing.x2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      minVerticalPadding: FotgSpacing.x3,
      leading: Icon(
        icon,
        size: FotgSizing.iconMd,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
