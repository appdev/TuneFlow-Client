/* Hallmark · pre-emit critique: P5 H4 E5 S5 R5 V5 */

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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

    if (blurEnabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: style.shadows,
        ),
        child: AdaptiveGlass(
          key: Key('app-liquid-glass-${role.name}'),
          shape: _liquidShape(radius, style.border),
          settings: LiquidGlassSettings(
            glassColor: style.fill.withValues(alpha: style.fill.a * .24),
            backerColor: style.fill.withValues(alpha: style.fill.a * .38),
            platformViewFallbackColor: style.fallbackFill,
            thickness: style.blurSigma,
            blur: (style.blurSigma / 5).clamp(3.5, 6).toDouble(),
            chromaticAberration: .003,
            lightIntensity: .28 + style.highlight.a * .18,
            refractiveIndex: 1.15,
            saturation: style.saturation,
            glowIntensity: .18,
            shadowElevation: 0,
          ),
          quality: GlassQuality.standard,
          useOwnLayer: true,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      );
    }

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

LiquidShape _liquidShape(BorderRadius radius, Color border) {
  final top = radius.topLeft.x;
  final bottom = radius.bottomLeft.x;
  final vertical =
      radius.topLeft == radius.topRight &&
      radius.bottomLeft == radius.bottomRight;
  assert(vertical, 'Liquid glass supports uniform or vertical corner radii.');
  final side = BorderSide(color: border);
  if (top == bottom) {
    return LiquidRoundedRectangle(borderRadius: top, side: side);
  }
  return LiquidVerticalRoundedRectangle(
    topRadius: top,
    bottomRadius: bottom,
    side: side,
  );
}
