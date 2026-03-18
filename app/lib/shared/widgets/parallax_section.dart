import 'package:flutter/material.dart';

/// A section that reacts to scroll with parallax and fade.
/// Wrap [child] in a scrollable and pass the same [scrollController].
class ParallaxSection extends StatelessWidget {
  const ParallaxSection({
    super.key,
    required this.scrollController,
    required this.child,
    this.parallaxOffset = 0.3,
    this.fadeStart = 0.0,
    this.fadeEnd = 0.5,
  });

  final ScrollController scrollController;
  final Widget child;
  final double parallaxOffset;
  final double fadeStart;
  final double fadeEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, child) {
        final offset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;
        final opacity = 1.0 -
            ((offset - fadeStart * 200) / (200 * (fadeEnd - fadeStart)))
                .clamp(0.0, 1.0);
        final translateY = scrollController.hasClients
            ? offset * parallaxOffset * 0.5
            : 0.0;
        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
