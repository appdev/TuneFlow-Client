import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'desktop_vinyl_record.dart';

double normalizedPlaybackProgress({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return 0;
  return (position.inMicroseconds / duration.inMicroseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

final class DesktopVinylPortal extends StatelessWidget {
  const DesktopVinylPortal({
    super.key,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
    required this.position,
    required this.duration,
  });

  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const axisWidth = 24.0;
      const axisInset = 32.0;
      const markerSize = 8.0;
      final portalWidth = math.max(0.0, constraints.maxWidth - axisWidth);
      final portalHeight = constraints.maxHeight;
      final discDiameter = math.min(portalHeight * 1.08, portalWidth * 1.22);
      final discLeft = -discDiameter * .16;
      final progress = normalizedPlaybackProgress(
        position: position,
        duration: duration,
      );
      final tokens = AppTokens.of(context);

      return SizedBox.expand(
        key: const Key('player-desktop-vinyl-portal'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: portalWidth,
              child: ClipRRect(
                key: const Key('player-desktop-vinyl-portal-clip'),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(portalHeight / 2),
                  bottomLeft: Radius.circular(portalHeight / 2),
                  topRight: const Radius.circular(AppRadii.panel),
                  bottomRight: const Radius.circular(AppRadii.panel),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface.withValues(alpha: .16),
                    border: Border.all(
                      color: tokens.foreground.withValues(alpha: .10),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: discLeft,
                        top: (portalHeight - discDiameter) / 2,
                        width: discDiameter,
                        height: discDiameter,
                        child: DesktopVinylRecord(
                          source: source,
                          seed: seed,
                          semanticLabel: semanticLabel,
                          rotating: rotating,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: axisInset,
              bottom: axisInset,
              width: axisWidth,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: _PlaybackAxis(
                    progress: progress,
                    markerSize: markerSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _PlaybackAxis extends StatelessWidget {
  const _PlaybackAxis({required this.progress, required this.markerSize});

  final double progress;
  final double markerSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final travel = math.max(0.0, constraints.maxHeight - markerSize);
      final tokens = AppTokens.of(context);
      final accent = tokens.accent;
      return Stack(
        key: const Key('player-desktop-vinyl-progress-axis'),
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: (constraints.maxWidth - 1) / 2,
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: accent.withValues(alpha: .5)),
          ),
          Transform.translate(
            offset: Offset(0, travel * progress),
            child: Container(
              key: const Key('player-desktop-vinyl-progress-marker'),
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
          ),
          Positioned(
            right: 0,
            top: 16,
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                'NOW PLAYING',
                style: AppTypography.metadata.copyWith(
                  color: tokens.foregroundSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
