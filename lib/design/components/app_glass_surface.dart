import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_glass_policy.dart';
import '../app_theme_definition.dart';
import '../app_theme_scope.dart';
import '../design_tokens.dart';

final class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    required this.role,
    required this.child,
    this.borderRadius,
    this.padding,
    super.key,
  });

  final AppGlassRole role;
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final style = AppThemeScope.variantOf(context).glass[role]!;
    final policy = AppGlassPolicyScope.policyOf(context);
    final blurEnabled = policy.blurEnabled && style.blurSigma > 0;
    final radius =
        borderRadius ??
        BorderRadius.circular(switch (role) {
          AppGlassRole.nav => 22,
          AppGlassRole.sheet => AppRadii.sheet,
          AppGlassRole.clear || AppGlassRole.control => 16,
          AppGlassRole.fallback => AppRadii.panel,
        });
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter.grouped(
        enabled: blurEnabled,
        filter: ImageFilter.blur(
          sigmaX: style.blurSigma,
          sigmaY: style.blurSigma,
          tileMode: TileMode.mirror,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: blurEnabled ? style.fill : style.fallbackFill,
            border: Border.all(color: style.border),
            borderRadius: radius,
            boxShadow: style.shadows,
          ),
          child: content,
        ),
      ),
    );
  }
}
