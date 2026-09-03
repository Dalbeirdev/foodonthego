import 'package:flutter/material.dart';

import '../../shared/widgets/module_placeholder.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const SafeArea(
        child: ModulePlaceholder(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          module: 'Module 10 — Notifications',
          description: 'When the kitchen accepts, when it starts cooking, and when the food is ready for you to collect.',
        ),
      ),
    );
  }
}
