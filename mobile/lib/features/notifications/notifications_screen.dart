import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/empty_state_view.dart';

/// Notifications. The screen architecture only — no push registration, no
/// permission prompt. Module 10 delivers those, and asking for notification
/// permission before there is anything to notify about is the fastest way to be
/// denied it permanently.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.navNotificationsFull)),
      body: SafeArea(
        top: false,
        child: EmptyStateView(
          icon: Icons.notifications_none_rounded,
          title: strings.notificationsEmptyTitle,
          body: strings.notificationsEmptyBody,
        ),
      ),
    );
  }
}
