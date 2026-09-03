import 'package:flutter/material.dart';

import '../../shared/widgets/module_placeholder.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: const SafeArea(
        child: ModulePlaceholder(
          icon: Icons.receipt_long_outlined,
          title: 'Orders',
          module: 'Module 08 — Order Lifecycle',
          description: 'Orders you have placed, each with the time it will be ready and how far you still are from the restaurant.',
        ),
      ),
    );
  }
}
