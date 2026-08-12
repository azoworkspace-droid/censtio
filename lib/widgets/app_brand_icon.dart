import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared Centsio branding used by the startup screen and Pro surfaces.
class AppBrandIcon extends StatelessWidget {
  const AppBrandIcon({
    super.key,
    this.size = 72,
    this.borderRadius = 22,
    this.showGlow = true,
  });

  final double size;
  final double borderRadius;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return Semantics(
      image: true,
      label: 'Centsio AI app icon',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: radius,
          border: Border.all(
            color: AppTheme.emerald.withAlpha(showGlow ? 170 : 90),
            width: showGlow ? 1.5 : 1,
          ),
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: AppTheme.emerald.withAlpha(60),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular((borderRadius - 2).clamp(0, 80)),
          child: Image.asset(
            'assets/app_icon.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
