import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A reusable glassmorphism container.
///
/// Applies a [BackdropFilter] blur behind a semi-transparent gradient surface
/// with a subtle white border — the classic glass-card look.
///
/// ```dart
/// GlassCard(
///   child: Text('Hello'),
/// )
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = AppTheme.radiusXL,
    this.sigmaBlur = 24.0,
    this.gradient,
    this.border,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double sigmaBlur;
  final Gradient? gradient;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigmaBlur, sigmaY: sigmaBlur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.glassGradient,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ??
                Border.all(
                  color: AppTheme.glassBorder,
                  width: 1.5,
                ),
            boxShadow: boxShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
