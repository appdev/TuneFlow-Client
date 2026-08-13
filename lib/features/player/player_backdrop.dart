import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';

final class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({
    required this.source,
    required this.transitionKey,
    super.key,
  });

  final AppArtworkSource source;
  final Object transitionKey;

  @override
  Widget build(BuildContext context) {
    final policy = AppGlassPolicyScope.policyOf(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedSwitcher(
          key: const Key('player-backdrop'),
          duration: Duration(milliseconds: policy.reduceMotion ? 150 : 280),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: SizedBox.expand(
            key: ValueKey(transitionKey),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 36,
                    sigmaY: 36,
                    tileMode: TileMode.mirror,
                  ),
                  child: Transform.scale(
                    scale: 1.16,
                    child: LayoutBuilder(
                      builder: (context, constraints) => AppArtwork(
                        source: source,
                        seed: source.fallbackSeed,
                        semanticLabel: '封面背景',
                        size: constraints.maxWidth,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        borderRadius: 0,
                      ),
                    ),
                  ),
                ),
                ColoredBox(color: AppTokens.of(context).playerVeil),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
