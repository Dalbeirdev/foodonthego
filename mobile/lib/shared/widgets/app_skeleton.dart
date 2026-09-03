import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A shimmering placeholder block.
///
/// The shimmer stops when the OS asks for reduced motion — a looping animation is
/// exactly the kind that causes discomfort, and it runs for the whole load.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    this.height = 16,
    this.width,
    this.radius = FotgRadius.sm,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = theme.colorScheme.surfaceContainerHighest;
    final Color highlight = theme.colorScheme.outline;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            colors: <Color>[base, highlight, base],
            stops: <double>[
              (_controller.value - 0.3).clamp(0.0, 1.0),
              _controller.value.clamp(0.0, 1.0),
              (_controller.value + 0.3).clamp(0.0, 1.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The home screen's loading state.
///
/// Shaped like the content it is replacing — a greeting line, a planner card, a
/// journey card — so the page does not visibly reflow when the data lands. A
/// centred spinner tells the user nothing about what is coming.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your home screen',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          FotgSpacing.x5,
          FotgSpacing.x6,
          FotgSpacing.x5,
          FotgSpacing.x10,
        ),
        children: const <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppSkeleton(height: 30, width: 220),
                    SizedBox(height: FotgSpacing.x2),
                    AppSkeleton(height: 18, width: 160),
                  ],
                ),
              ),
              SizedBox(width: FotgSpacing.x4),
              AppSkeleton(height: 48, width: 48, radius: FotgRadius.full),
            ],
          ),
          SizedBox(height: FotgSpacing.x6),
          AppSkeleton(height: 210, radius: FotgRadius.lg),
          SizedBox(height: FotgSpacing.x6),
          AppSkeleton(height: 20, width: 140),
          SizedBox(height: FotgSpacing.x3),
          AppSkeleton(height: 148, radius: FotgRadius.lg),
          SizedBox(height: FotgSpacing.x6),
          AppSkeleton(height: 20, width: 120),
          SizedBox(height: FotgSpacing.x3),
          AppSkeleton(height: 132, radius: FotgRadius.lg),
        ],
      ),
    );
  }
}
