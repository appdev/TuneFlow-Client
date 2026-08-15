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
            child: DecoratedBox(
              key: const Key('player-desktop-backdrop-gradient-base'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      colors.backgroundBase.withValues(alpha: .88),
                      neutral,
                    ),
                    Color.alphaBlend(
                      colors.backgroundCompanion.withValues(alpha: .72),
                      neutral,
                    ),
                  ],
                ),
              ),
              child: DecoratedBox(
                key: const Key('player-desktop-backdrop-gradient-companion'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.72, -.82),
                    radius: 1.12,
                    colors: [
                      colors.backgroundCompanion.withValues(alpha: .38),
                      colors.backgroundBase.withValues(alpha: 0),
                    ],
                  ),
                ),
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
