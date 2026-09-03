import 'package:flutter/material.dart';

import '../../shared/widgets/module_placeholder.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: const SafeArea(
        child: ModulePlaceholder(
          icon: Icons.route_outlined,
          title: 'Trips',
          module: 'Module 09 — Route & Corridor Management',
          description: 'Your saved and active journeys. Pick an origin and destination, and FoodOnTheGo finds kitchens a short detour from the route.',
        ),
      ),
    );
  }
}
