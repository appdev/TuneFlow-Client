import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/app_theme_definition.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/components/queue_panel.dart';
import '../../design/design_tokens.dart';
import 'desktop_player_controls.dart';
import 'desktop_player_stage.dart';
import 'lyrics_view.dart';
import 'mobile_player_controls.dart';
import 'mobile_queue_sheet.dart';
import 'player_backdrop.dart';
import 'player_controller.dart';
import 'player_state.dart';
import 'wake_lock_port.dart';

final class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.lyricsLoader,
    required this.wakeLock,
    required this.keepAwake,
  });

  final PlayerController controller;
  final Future<Lyrics> Function(Track track) lyricsLoader;
  final WakeLockPort wakeLock;
  final bool keepAwake;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

final class _PlayerScreenState extends State<PlayerScreen> {
  late final PageController pages = PageController(
    initialPage: widget.controller.state.view == PlayerView.lyrics ? 1 : 0,
  );
  String? _artworkKey;
  AppArtworkSource? _artworkSource;

  AppArtworkSource _sourceFor(Track track) {
    final url = track.raw['pic'] as String?;
    final key = '${track.source}:${track.id}:$url';
    if (_artworkKey != key) {
      _artworkKey = key;
      _artworkSource = AppArtworkSource.fromUrl(
        url,
        fallbackSeed: '${track.source}:${track.id}',
      );
    }
    return _artworkSource!;
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.wakeLock.setEnabled(widget.keepAwake));
    unawaited(widget.controller.loadLyrics(widget.lyricsLoader));
    if (widget.controller.state.view == PlayerView.queue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller.setView(PlayerView.artwork);
        unawaited(_queue());
      });
    }
  }

  @override
  void dispose() {
    pages.dispose();
    unawaited(widget.wakeLock.setEnabled(false));
    super.dispose();
  }

  Future<void> _queue() {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    return showAppSheet<void>(
      context,
      title: '播放队列',
      initialChildSize: mobile ? .64 : null,
      minChildSize: .48,
      maxChildSize: .90,
      child: mobile
          ? MobileQueueSheet(controller: widget.controller)
          : ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final state = widget.controller.state;
                return QueuePanel(
                  compact: true,
                  tracks: state.queue,
                  currentIndex: state.currentIndex,
                  onSelected: widget.controller.playIndex,
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final track = state.current;
      if (track == null) {
        return const ColoredBox(
          color: Colors.transparent,
          child: AppEmptyState(message: '播放队列为空'),
        );
      }
      final artworkSource = _sourceFor(track);
      return LayoutBuilder(
        builder: (context, constraints) {
          final mobile =
              classifyLayout(constraints.maxWidth) == AppLayoutClass.mobile;
          final content = mobile
              ? _MobilePlayer(
                  key: const Key('player-mobile-layout'),
                  controller: widget.controller,
                  artworkSource: artworkSource,
                  pages: pages,
                  onQueue: _queue,
                  onLyrics: () =>
                      widget.controller.loadLyrics(widget.lyricsLoader),
                )
              : Stack(
                  key: const Key('player-wide-layout'),
                  fit: StackFit.expand,
                  children: [
                    DesktopPlayerStage(
                      state: state,
                      artworkSource: artworkSource,
                      onRetryLyrics: () =>
                          widget.controller.loadLyrics(widget.lyricsLoader),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: DesktopPlayerControls(
                        controller: widget.controller,
                      ),
                    ),
                  ],
                );
          return Stack(
            key: const Key('player-screen-root'),
            fit: StackFit.expand,
            children: [
              PlayerBackdrop(
                source: artworkSource,
                transitionKey: '${track.source}:${track.id}',
              ),
              SafeArea(child: content),
              if (!mobile && state.error != null)
                Positioned(
                  top: 46,
                  left: 24,
                  right: 24,
                  child: AppNotice.error(
                    title: '播放失败',
                    message: state.error.toString(),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

final class _MobilePlayer extends StatelessWidget {
  const _MobilePlayer({
    super.key,
    required this.controller,
    required this.artworkSource,
    required this.pages,
    required this.onQueue,
    required this.onLyrics,
  });

  final PlayerController controller;
  final AppArtworkSource artworkSource;
  final PageController pages;
  final VoidCallback onQueue;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final track = state.current!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Row(
            key: const Key('player-mobile-topbar'),
            children: [
              _MobileGlassIconButton(
                label: '返回',
                icon: LucideIcons.chevronDown,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Center(
                  child: AppGlassSurface(
                    role: AppGlassRole.clear,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text('正在播放', style: AppTypography.metadata),
                  ),
                ),
              ),
              _MobileGlassIconButton(
                label: '播放队列',
                icon: LucideIcons.ellipsis,
                onPressed: onQueue,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (state.error != null)
            AppGlassSurface(
              key: const Key('player-mobile-playback-error'),
              role: AppGlassRole.clear,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 18,
                    color: AppTokens.of(context).danger,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('当前音频暂时无法播放')),
                  ShadButton.ghost(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: controller.resume,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: PageView(
              controller: pages,
              onPageChanged: (index) =>
                  controller.setView(PlayerView.values[index]),
              children: [
                _MobileNowPlaying(
                  track: track,
                  artworkSource: artworkSource,
                  state: state,
                  onRetryLyrics: onLyrics,
                ),
                LyricsView(state: state, verticalPadding: 120, edgeFade: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MobilePlayerControls(
            state: state,
            onSeek: controller.seek,
            onPrevious: controller.previous,
            onPlayPause: state.playing ? controller.pause : controller.resume,
            onNext: controller.next,
            onPlaybackMode: controller.cyclePlaybackMode,
            onQualityChanged: (quality) =>
                unawaited(controller.setQuality(quality)),
            onQueue: onQueue,
          ),
        ],
      ),
    );
  }
}

final class _MobileGlassIconButton extends StatelessWidget {
  const _MobileGlassIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppGlassSurface(
    role: AppGlassRole.clear,
    borderRadius: BorderRadius.circular(14),
    child: Semantics(
      button: true,
      label: label,
      child: ShadButton.ghost(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon, size: 20),
      ),
    ),
  );
}

final class _MobileNowPlaying extends StatelessWidget {
  const _MobileNowPlaying({
    required this.track,
    required this.artworkSource,
    required this.state,
    required this.onRetryLyrics,
  });
  final Track track;
  final AppArtworkSource artworkSource;
  final PlayerState state;
  final VoidCallback onRetryLyrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final artworkSize = (constraints.maxHeight * .46).clamp(132.0, 208.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            AppArtwork(
              key: const Key('player-mobile-artwork'),
              source: artworkSource,
              seed: '${track.source}:${track.id}',
              semanticLabel: '${track.title}封面',
              size: artworkSize,
              borderRadius: AppRadii.panel,
            ),
            const SizedBox(height: 14),
            Text(
              track.title.isEmpty ? track.id : track.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.section,
            ),
            const SizedBox(height: 3),
            Text(
              track.artist,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppTokens.of(context).foregroundSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (state.lyricsError != null)
              TextButton.icon(
                key: const Key('player-mobile-lyric-error'),
                onPressed: onRetryLyrics,
                icon: const Icon(LucideIcons.rotateCcw, size: 15),
                label: const Text('歌词暂不可用'),
              )
            else if (state.lyrics == null ||
                (state.lyrics!.original.isEmpty &&
                    (state.lyrics!.translation?.isEmpty ?? true)))
              SizedBox(
                height: 104,
                child: Center(
                  child: Text(
                    '暂无歌词',
                    style: AppTypography.body.copyWith(
                      color: AppTokens.of(context).muted,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 104,
                child: LyricsView(
                  state: state,
                  verticalPadding: 28,
                  edgeFade: true,
                ),
              ),
          ],
        ),
      );
    },
  );
}
