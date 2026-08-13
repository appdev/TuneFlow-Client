/* Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4 */

import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'lyrics_view.dart';
import 'player_state.dart';

final class DesktopPlayerStage extends StatelessWidget {
  const DesktopPlayerStage({
    super.key,
    required this.state,
    required this.artworkSource,
    required this.onRetryLyrics,
  });

  final PlayerState state;
  final AppArtworkSource artworkSource;
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

    return Padding(
      key: const Key('player-desktop-stage'),
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 142),
      child: Row(
        children: [
          Expanded(
            flex: 42,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: LayoutBuilder(
                        builder: (context, constraints) => AppArtwork(
                          key: const Key('player-desktop-artwork'),
                          source: artworkSource,
                          seed: '${track.source}:${track.id}',
                          semanticLabel: '${track.title}封面',
                          size: constraints.maxWidth,
                          borderRadius: AppRadii.panel,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      track.title.isEmpty ? track.id : track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.display,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      metadata,
                      key: const Key('player-desktop-metadata'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: AppTokens.of(context).foregroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            flex: 58,
            child: Center(
              child: SizedBox(
                key: const Key('desktop-lyrics-viewport'),
                height: 360,
                child: _DesktopLyrics(state: state, onRetry: onRetryLyrics),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DesktopLyrics extends StatelessWidget {
  const _DesktopLyrics({required this.state, required this.onRetry});

  final PlayerState state;
  final VoidCallback onRetry;

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
                color: AppTokens.of(context).muted,
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
            color: AppTokens.of(context).muted,
          ),
        ),
      );
    }
    return LyricsView(state: state, verticalPadding: 48, edgeFade: true);
  }
}
