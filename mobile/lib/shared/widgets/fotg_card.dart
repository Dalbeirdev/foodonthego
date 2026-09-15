import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A surface with the product's border, radius and padding. Exists so screens do
/// not each re-derive "what a card looks like" from raw values.
class FotgCard extends StatelessWidget {
  const FotgCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(FotgSpacing.x5),
        child: child,
      ),
    );
  }
}
