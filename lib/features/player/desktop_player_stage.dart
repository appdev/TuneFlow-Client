import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';
import 'desktop_orbit_vinyl.dart';
import 'lyrics_view.dart';
import 'player_state.dart';

final class DesktopPlayerStage extends StatelessWidget {
  const DesktopPlayerStage({
    super.key,
    required this.state,
    required this.artworkSource,
    required this.palette,
    required this.onRetryLyrics,
  });

  final PlayerState state;
  final AppArtworkSource artworkSource;
  final ArtworkPalette palette;
  final VoidCallback onRetryLyrics;

  @override
  Widget build(BuildContext context) {
    final track = state.current!;
    final album = switch (track.raw['albumName'] ?? track.raw['album']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final artist = track.artist.trim();
    final metadata = [
      if (artist.isNotEmpty) artist,
      if (album != null) album,
    ].join(' · ');

    return LayoutBuilder(
      builder: (context, stageConstraints) {
        const legacyHorizontalInset = 48.0;
        final horizontalInset = (stageConstraints.maxWidth * .10)
            .clamp(72.0, 160.0)
            .toDouble();
        final recordSizingWidth =
            stageConstraints.maxWidth - legacyHorizontalInset * 2;

        return Padding(
          key: const Key('player-desktop-stage'),
          padding: EdgeInsets.fromLTRB(
            horizontalInset,
            48,
            horizontalInset,
            142,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = recordSizingWidth >= 1100;
              final recordDiameter = math.min(
                constraints.maxHeight * 1.12,
                recordSizingWidth * (wide ? .66 : .72),
              );
              final rightOverflow =
                  recordDiameter * (wide ? .26 : .38) +
                  horizontalInset -
                  legacyHorizontalInset;
              final recordLeft =
                  constraints.maxWidth - recordDiameter + rightOverflow;
              final readingWidth = math.min(
                560.0,
                math.max(280.0, recordLeft - AppSpacing.xl),
              );
              final readingHeight = math.min(520.0, constraints.maxHeight);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: -rightOverflow,
                    top: -recordDiameter * .32,
                    width: recordDiameter,
                    height: recordDiameter,
                    child: DesktopOrbitVinyl(
                      source: artworkSource,
                      palette: palette,
                      seed: '${track.source}:${track.id}',
                      semanticLabel: '${track.title}封面',
                      rotating:
                          state.isPlaybackActive &&
                          state.processing == PlayerProcessing.ready,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: (constraints.maxHeight - readingHeight) / 2,
                    width: readingWidth,
                    height: readingHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title.isEmpty ? track.id : track.title,
                          key: const Key('player-desktop-track-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.display.copyWith(
                            color: palette.foreground,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          metadata,
                          key: const Key('player-desktop-metadata'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            color: palette.foreground.withValues(alpha: .62),
                          ),
                        ),
                        const SizedBox(height: 52),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, lyricsConstraints) => Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                key: const Key('desktop-lyrics-viewport'),
                                width: double.infinity,
                                height: math.min(
                                  360.0,
                                  lyricsConstraints.maxHeight,
                                ),
                                child: _DesktopLyrics(
                                  state: state,
                                  onRetry: onRetryLyrics,
                                  foreground: palette.foreground,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

final class _DesktopLyrics extends StatelessWidget {
  const _DesktopLyrics({
    required this.state,
    required this.onRetry,
    required this.foreground,
  });

  final PlayerState state;
  final VoidCallback onRetry;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    if (state.lyricsError != null) {
      return Center(
        key: const Key('player-desktop-lyrics-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '歌词暂不可用',
              style: AppTypography.body.copyWith(
                color: foreground.withValues(alpha: .52),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    final lyrics = state.lyrics;
    if (lyrics == null ||
        (lyrics.original.isEmpty && (lyrics.translation?.isEmpty ?? true))) {
      return Center(
        child: Text(
          '暂无歌词',
          style: AppTypography.body.copyWith(
            color: foreground.withValues(alpha: .52),
          ),
        ),
      );
    }
    return LyricsView(
      state: state,
      verticalPadding: 48,
      edgeFade: true,
      horizontalPadding: 0,
      textAlign: TextAlign.left,
      foreground: foreground,
      mutedForeground: foreground.withValues(alpha: .44),
    );
  }
}
