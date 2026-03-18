import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:spark/core/constants/app_constants.dart';

/// Crossed app logo — use everywhere for consistent branding.
class CrossedLogo extends StatelessWidget {
  const CrossedLogo({
    super.key,
    this.size = 80,
    this.colorFilter,
    this.fit = BoxFit.contain,
  });

  final double size;
  final ColorFilter? colorFilter;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AppConstants.logoAsset,
      width: size,
      height: size,
      fit: fit,
      colorFilter: colorFilter,
    );
  }
}
