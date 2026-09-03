import 'package:flutter/material.dart';

import '../../shared/widgets/module_placeholder.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const SafeArea(
        child: ModulePlaceholder(
          icon: Icons.person_outline,
          title: 'Profile',
          module: 'Module 03 — Account Settings',
          description:
              'Your account, saved addresses, payment methods and preferences.',
        ),
      ),
    );
  }
}
