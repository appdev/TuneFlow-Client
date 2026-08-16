import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/app_theme_definition.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/components/queue_panel.dart';
import '../../design/design_tokens.dart';
import '../../storage/app_image_cache_scope.dart';
import '../downloads/redownload_confirmation.dart';
import '../playlists/playlist_repository.dart';
import 'artwork_palette.dart';
import 'artwork_palette_controller.dart';
import 'current_track_actions_controller.dart';
import 'desktop_dynamic_player_backdrop.dart';
import 'desktop_player_controls.dart';
import 'desktop_player_stage.dart';
import 'lyrics_view.dart';
import 'mobile_player_controls.dart';
import 'mobile_queue_sheet.dart';
import 'mobile_vinyl_record.dart';
import 'player_backdrop.dart';
import 'player_controller.dart';
import 'player_state.dart';
import 'wake_lock_port.dart';

enum _PlayerAction { favorite, playlist, download }

final class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.lyricsLoader,
    required this.wakeLock,
    required this.keepAwake,
    this.playlists,
    this.actions,
    this.onBack,
    this.topChromeInset = 0,
    this.paletteController,
    this.onAccentChanged,
  });

  final PlayerController controller;
  final Future<Lyrics> Function(Track track) lyricsLoader;
  final WakeLockPort wakeLock;
  final bool keepAwake;
  final PlaylistRepository? playlists;
  final CurrentTrackActionsController? actions;
  final VoidCallback? onBack;
  final double topChromeInset;
  final ArtworkPaletteController? paletteController;
  final ValueChanged<Color>? onAccentChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

final class _PlayerScreenState extends State<PlayerScreen> {
  late final PageController pages = PageController(initialPage: 0);
  String? _artworkKey;
  AppArtworkSource? _artworkSource;
  ArtworkPaletteController? _paletteController;
  var _ownsPaletteController = false;
  String? _paletteRequestKey;
  Color? _reportedAccent;

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
    _paletteController = widget.paletteController;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePaletteController();
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onAccentChanged != widget.onAccentChanged) {
      _reportedAccent = null;
    }
    if (oldWidget.paletteController == widget.paletteController) return;
    if (_ownsPaletteController) _paletteController?.dispose();
    _paletteController = widget.paletteController;
    _ownsPaletteController = false;
    _paletteRequestKey = null;
    _ensurePaletteController();
  }

  void _ensurePaletteController() {
    if (_paletteController != null) return;
    final manager = AppImageCacheScope.maybeOf(context)?.manager;
    _paletteController = ArtworkPaletteController(
      loadBytes: manager == null
          ? (_) async => null
          : (source) => loadArtworkBytes(manager, source),
    );
    _ownsPaletteController = true;
  }

  void _selectPalette(AppArtworkSource source, Brightness brightness) {
    final key = '${source.url ?? source.fallbackSeed}:${brightness.name}';
    if (_paletteRequestKey == key) return;
    _paletteRequestKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paletteRequestKey != key) return;
      unawaited(_paletteController!.select(source, brightness: brightness));
    });
  }

  void _reportAccent(Color accent) {
    final callback = widget.onAccentChanged;
    if (callback == null || _reportedAccent == accent) return;
    _reportedAccent = accent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedAccent != accent) return;
      callback(accent);
    });
  }

  @override
  void dispose() {
    pages.dispose();
    if (_ownsPaletteController) _paletteController?.dispose();
    unawaited(widget.wakeLock.setEnabled(false));
    super.dispose();
  }

  Future<void> _queue() {
    final mobile =
        classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
    if (mobile) {
      return AppBottomSheet.showDraggable<void>(
        context,
        title: '播放队列',
        initialChildSize: .64,
        minChildSize: .48,
        maxChildSize: .90,
        child: MobileQueueSheet(controller: widget.controller),
      );
    }
    return AppBottomSheet.showContent<void>(
      context,
      title: '播放队列',
      child: ListenableBuilder(
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

  Future<void> _run(
    Future<void> Function() operation, {
    String? success,
    String? successTitle,
    String errorTitle = '操作失败',
  }) async {
    try {
      await operation();
      if (mounted && successTitle != null) {
        showAppMessage(context, title: successTitle);
      } else if (mounted && success != null) {
        showAppMessage(context, title: '完成', message: success);
      }
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: errorTitle,
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<void> _choosePlaylist(Track track) async {
    final playlists = await widget.playlists!.list();
    if (!mounted) return;
    await AppBottomSheet.showContent<void>(
      context,
      title: '添加到歌单',
      child: playlists.isEmpty
          ? const AppEmptyState(message: '还没有歌单')
          : ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return AppButton(
                  key: Key('player-playlist-${playlist.id}'),
                  variant: ShadButtonVariant.ghost,
                  onPressed: () => _run(
                    () => widget.playlists!.addTracks(playlist.id, [track]),
                    success: '已添加到 ${playlist.name}',
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(playlist.name),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _more(Track track) async {
    final playlists = widget.playlists;
    final actions = widget.actions;
    if (playlists == null || actions == null) return;
    final quality = switch (widget.controller.state.quality) {
      'flac24bit' => 'Hi-Res',
      'flac' => '无损',
      final value => value,
    };
    final message = [
      track.artist.trim(),
      quality.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    final selected = await AppBottomSheet.showActions<_PlayerAction>(
      context,
      title: track.title.isEmpty ? track.id : track.title,
      message: message.isEmpty ? null : message,
      actions: [
        AppBottomSheetAction(
          key: const Key('track-action-favorite'),
          value: _PlayerAction.favorite,
          label: actions.favorite ? '取消收藏' : '收藏歌曲',
          enabled: actions.canToggleFavorite,
        ),
        const AppBottomSheetAction(
          key: Key('track-action-addToPlaylist'),
          value: _PlayerAction.playlist,
          label: '添加到歌单',
        ),
        AppBottomSheetAction(
          key: const Key('track-action-download'),
          value: _PlayerAction.download,
          label: '下载当前歌曲',
          enabled: actions.canDownload,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _PlayerAction.favorite:
        await _run(actions.toggleFavorite, errorTitle: '收藏失败');
      case _PlayerAction.playlist:
        await _run(() => _choosePlaylist(track));
      case _PlayerAction.download:
        await _downloadCurrent(actions);
    }
  }

  Future<void> _downloadCurrent(CurrentTrackActionsController actions) async {
    try {
      final result = await actions.downloadCurrent(
        confirmReplacement: (message) =>
            const AppRedownloadConfirmation().confirm(context, message),
      );
      if (!mounted || result?.job == null) return;
      showAppMessage(
        context,
        title: result!.replaced ? '已加入重新下载队列' : '已加入下载队列',
      );
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '下载失败',
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ListenableBuilder(
      listenable: _paletteController!,
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
                classifyLayout(MediaQuery.sizeOf(context)) ==
                AppLayoutClass.mobile;
            final brightness = Theme.of(context).brightness;
            if (!mobile) _selectPalette(artworkSource, brightness);
            final palette =
                _paletteController?.palette ??
                fallbackArtworkPalette(
                  artworkSource.fallbackSeed,
                  brightness: brightness,
                );
            if (!mobile) _reportAccent(palette.vinylAccent);
            final content = mobile
                ? _MobilePlayer(
                    key: const Key('player-mobile-layout'),
                    controller: widget.controller,
                    artworkSource: artworkSource,
                    pages: pages,
                    onQueue: _queue,
                    onMore: () => unawaited(_more(track)),
                    onLyrics: () =>
                        widget.controller.loadLyrics(widget.lyricsLoader),
                    onBack:
                        widget.onBack ??
                        () => unawaited(Navigator.of(context).maybePop()),
                    topChromeInset: widget.topChromeInset,
                    actions: widget.actions,
                  )
                : Stack(
                    key: const Key('player-wide-layout'),
                    fit: StackFit.expand,
                    children: [
                      DesktopPlayerStage(
                        state: state,
                        artworkSource: artworkSource,
                        palette: palette,
                        onRetryLyrics: () =>
                            widget.controller.loadLyrics(widget.lyricsLoader),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: DesktopPlayerControls(
                          controller: widget.controller,
                          palette: palette,
                          actions: widget.actions,
                        ),
                      ),
                    ],
                  );
            final themedContent = mobile
                ? content
                : _DesktopPlayerTheme(palette: palette, child: content);
            return Stack(
              key: const Key('player-screen-root'),
              fit: StackFit.expand,
              children: [
                if (mobile)
                  PlayerBackdrop(
                    source: artworkSource,
                    transitionKey: '${track.source}:${track.id}',
                  )
                else
                  DesktopDynamicPlayerBackdrop(
                    palette: palette,
                    transitionKey: '${track.source}:${track.id}',
                  ),
                SafeArea(child: themedContent),
                if (!mobile && state.error != null)
                  Positioned(
                    top: 46,
                    left: 24,
                    right: 24,
                    child: AppNotice.error(
                      title: '播放失败',
                      message: appErrorMessage(
                        state.error!,
                        fallback: '歌曲暂时无法播放，请重试或切换音源。',
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

final class _DesktopPlayerTheme extends StatefulWidget {
  const _DesktopPlayerTheme({required this.palette, required this.child});

  final ArtworkPalette palette;
  final Widget child;

  @override
  State<_DesktopPlayerTheme> createState() => _DesktopPlayerThemeState();
}

final class _DesktopPlayerThemeState extends State<_DesktopPlayerTheme> {
  ShadThemeData? _baseShad;
  ShadThemeData? _localShad;
  ThemeData? _baseMaterial;
  ThemeData? _localMaterial;
  Color? _accent;

  @override
  Widget build(BuildContext context) {
    final accent = widget.palette.vinylAccent;
    final onAccent = contrastRatio(Colors.black, accent) >= 4.5
        ? Colors.black
        : Colors.white;
    final shad = ShadTheme.of(context);
    final material = Theme.of(context);
    if (_accent != accent || !identical(_baseShad, shad)) {
      _baseShad = shad;
      _localShad = shad.copyWith(
        colorScheme: shad.colorScheme.copyWith(
          primary: accent,
          primaryForeground: onAccent,
          ring: accent,
        ),
        ghostButtonTheme: shad.ghostButtonTheme.copyWith(
          foregroundColor: accent,
          hoverForegroundColor: accent,
          pressedForegroundColor: accent,
        ),
        sliderTheme: shad.sliderTheme.copyWith(
          activeTrackColor: accent,
          thumbBorderColor: accent,
        ),
      );
    }
    if (_accent != accent || !identical(_baseMaterial, material)) {
      _baseMaterial = material;
      _localMaterial = material.copyWith(
        colorScheme: material.colorScheme.copyWith(
          primary: accent,
          onPrimary: onAccent,
        ),
      );
    }
    _accent = accent;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? AppDurations.reducedMotion
        : const Duration(milliseconds: 560);
    return ShadAnimatedTheme(
      key: const Key('player-local-shad-theme'),
      data: _localShad!,
      duration: duration,
      curve: AppCurves.out,
      child: AnimatedTheme(
        data: _localMaterial!,
        duration: duration,
        curve: AppCurves.out,
        child: widget.child,
      ),
    );
  }
}

final class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({
    super.key,
    required this.controller,
    required this.artworkSource,
    required this.pages,
    required this.onQueue,
    required this.onMore,
    required this.onLyrics,
    required this.onBack,
    required this.topChromeInset,
    required this.actions,
  });

  final PlayerController controller;
  final AppArtworkSource artworkSource;
  final PageController pages;
  final VoidCallback onQueue;
  final VoidCallback onMore;
  final VoidCallback onLyrics;
  final VoidCallback onBack;
  final double topChromeInset;
  final CurrentTrackActionsController? actions;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

final class _MobilePlayerState extends State<_MobilePlayer> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state.view != PlayerView.artwork) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller.setView(PlayerView.artwork);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final artworkSource = widget.artworkSource;
    final pages = widget.pages;
    final onQueue = widget.onQueue;
    final onMore = widget.onMore;
    final onLyrics = widget.onLyrics;
    final onBack = widget.onBack;
    final state = controller.state;
    final track = state.current!;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12 + widget.topChromeInset, 16, 16),
      child: Column(
        children: [
          Row(
            key: const Key('player-mobile-topbar'),
            children: [
              _MobileGlassIconButton(
                label: '返回',
                icon: LucideIcons.chevronDown,
                onPressed: onBack,
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
                key: const Key('player-mobile-more'),
                label: '更多操作',
                icon: LucideIcons.ellipsis,
                onPressed: onMore,
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
                  Expanded(
                    child: Text(
                      appErrorMessage(state.error!, fallback: '当前音频暂时无法播放'),
                    ),
                  ),
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
              key: const Key('player-mobile-pages'),
              controller: pages,
              onPageChanged: (index) => controller.setView(
                index == 0 ? PlayerView.artwork : PlayerView.lyrics,
              ),
              children: [
                _MobileNowPlaying(
                  track: track,
                  artworkSource: artworkSource,
                  rotating:
                      state.view == PlayerView.artwork &&
                      state.isPlaybackActive &&
                      state.processing == PlayerProcessing.ready,
                ),
                SizedBox.expand(
                  key: const Key('player-mobile-lyrics-page'),
                  child: state.lyricsError != null
                      ? AppRetryState(
                          key: const Key('player-mobile-lyric-error'),
                          message: '歌词暂不可用',
                          retryLabel: '重试',
                          onRetry: onLyrics,
                        )
                      : LyricsView(
                          state: state,
                          verticalPadding: 28,
                          edgeFade: true,
                        ),
                ),
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
    super.key,
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
    required this.rotating,
  });
  final Track track;
  final AppArtworkSource artworkSource;
  final bool rotating;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final recordSize = math
          .min(constraints.maxWidth * .78, constraints.maxHeight * .62)
          .clamp(148.0, 264.0);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: recordSize,
                  child: MobileVinylRecord(
                    source: artworkSource,
                    seed: '${track.source}:${track.id}',
                    semanticLabel: '${track.title}封面',
                    rotating: rotating,
                  ),
                ),
                const SizedBox(height: 18),
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
              ],
            ),
          ),
        ),
      );
    },
  );
}
