import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';

final class DesktopDynamicPlayerBackdrop extends StatelessWidget {
  const DesktopDynamicPlayerBackdrop({
    required this.palette,
    required this.transitionKey,
    super.key,
  });

  final ArtworkPalette palette;
  final Object transitionKey;

  @override
  Widget build(BuildContext context) {
    final policy = AppGlassPolicyScope.policyOf(context);
    final duration = policy.reduceMotion
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 560);
    final neutral = AppTokens.of(context).background;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: TweenAnimationBuilder<ArtworkPalette>(
          key: const Key('player-desktop-backdrop'),
          tween: _ArtworkPaletteTween(end: palette),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, colors, _) => SizedBox.expand(
            key: ValueKey(transitionKey),
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    key: const Key('player-desktop-backdrop-canvas'),
                    color: neutral,
                  ),
                  _diffuseLayer(
                    key: const Key('player-desktop-backdrop-diffuse-base'),
                    center: const Alignment(.54, -.92),
                    radius: 1.28,
                    color: colors.backgroundBase,
                    opacity: .72,
                  ),
                  _diffuseLayer(
                    key: const Key('player-desktop-backdrop-diffuse-companion'),
                    center: const Alignment(-.88, .96),
                    radius: 1.34,
                    color: colors.backgroundCompanion,
                    opacity: .62,
                  ),
                  _diffuseLayer(
                    key: const Key('player-desktop-backdrop-diffuse-accent'),
                    center: const Alignment(1.08, .84),
                    radius: 1.12,
                    color: colors.vinylAccent,
                    opacity: .14,
                  ),
                  _diffuseLayer(
                    key: const Key('player-desktop-backdrop-reading-wash'),
                    center: const Alignment(-.16, -.10),
                    radius: .96,
                    color: neutral,
                    opacity: .52,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ArtworkPaletteTween extends Tween<ArtworkPalette> {
  _ArtworkPaletteTween({required super.end});

  @override
  ArtworkPalette lerp(double t) => ArtworkPalette.lerp(begin ?? end!, end!, t);
}

DecoratedBox _diffuseLayer({
  required Key key,
  required Alignment center,
  required double radius,
  required Color color,
  required double opacity,
}) => DecoratedBox(
  key: key,
  decoration: BoxDecoration(
    gradient: RadialGradient(
      center: center,
      radius: radius,
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * .42),
        color.withValues(alpha: 0),
      ],
      stops: const [0, .48, 1],
    ),
  ),
);
