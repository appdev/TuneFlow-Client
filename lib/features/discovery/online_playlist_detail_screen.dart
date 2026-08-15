import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import '../downloads/download_repository.dart';
import '../player/player_controller.dart';
import '../search/adaptive_track_actions.dart';
import '../search/search_track_metadata.dart';
import '../search/track_action.dart';
import 'online_playlist_detail_controller.dart';

final class OnlinePlaylistDetailScreen extends StatefulWidget {
  const OnlinePlaylistDetailScreen({
    super.key,
    required this.controller,
    required this.player,
    required this.downloads,
  });

  final OnlinePlaylistDetailController controller;
  final PlayerController player;
  final DownloadRepository downloads;

  @override
  State<OnlinePlaylistDetailScreen> createState() =>
      _OnlinePlaylistDetailScreenState();
}

final class _OnlinePlaylistDetailScreenState
    extends State<OnlinePlaylistDetailScreen> {
  final Map<(String, String), Future<Uri?>> _pictures = {};
  final ScrollController _scrollController = ScrollController();
  late OnlinePlaylistDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _scrollController.addListener(_loadMore);
    if (_controller.state.pages.isEmpty) {
      unawaited(_controller.load());
    }
  }

  void _loadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 240) {
      return;
    }
    final state = _controller.state;
    if (!state.hasMore ||
        state.loadingPage != null ||
        state.failedPage != null) {
      return;
    }
    final nextPage = state.pages.keys.reduce((a, b) => a > b ? a : b) + 1;
    unawaited(_controller.loadPage(nextPage));
  }

  @override
  void didUpdateWidget(covariant OnlinePlaylistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final replacement = widget.controller;
    if (identical(replacement, _controller)) return;
    if (replacement.source == _controller.source &&
        replacement.playlistId == _controller.playlistId) {
      replacement.dispose();
      return;
    }
    _controller.dispose();
    _pictures.clear();
    _controller = replacement;
    if (_controller.state.pages.isEmpty) {
      unawaited(_controller.load());
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    String? successTitle,
  }) async {
    try {
      await action();
      if (mounted && successTitle != null) {
        showAppMessage(context, title: successTitle);
      } else if (mounted && success != null) {
        showAppMessage(context, title: '完成', message: success);
      }
    } on Object catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          title: '操作失败',
          message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
          destructive: true,
        );
      }
    }
  }

  Future<void> _playAll() async {
    await _controller.loadAllPages();
    if (!mounted) return;
    if (_controller.state.failedPage != null) {
      showAppMessage(
        context,
        title: '无法播放全部',
        message: '歌单仍有页面加载失败，请重试后再播放。',
        destructive: true,
      );
      return;
    }
    final tracks = _controller.state.tracks.toList(growable: false);
    if (tracks.isEmpty) return;
    final first = await _withPicture(tracks.first);
    if (!mounted) return;
    await widget.player.playTracks([first, ...tracks.skip(1)]);
  }

  Future<Uri?> _loadPicture(Track track) =>
      _pictures.putIfAbsent((track.source, track.id), () async {
        final embedded = track.raw['pic'];
        Uri? picture;
        if (embedded is String && embedded.isNotEmpty) {
          picture = Uri.tryParse(embedded);
        } else {
          try {
            picture = Uri.tryParse(await _controller.catalog.picture(track));
          } on Object {
            picture = null;
          }
        }
        if (picture == null ||
            (picture.scheme != 'http' && picture.scheme != 'https')) {
          return null;
        }
        widget.player.updateTrackArtwork(track, picture);
        return picture;
      });

  Future<Track> _withPicture(Track track) async {
    final embedded = track.raw['pic'];
    if (embedded is String && embedded.isNotEmpty) return track;
    final picture = await _loadPicture(track);
    return picture == null
        ? track
        : Track.fromJson({...track.toJson(), 'pic': picture.toString()});
  }

  Future<void> _play(Track track) async {
    final tracks = [..._controller.state.tracks];
    final index = tracks.indexWhere(
      (item) => item.source == track.source && item.id == track.id,
    );
    final playable = await _withPicture(track);
    if (index < 0) {
      await widget.player.play(playable);
      return;
    }
    tracks[index] = playable;
    await widget.player.playTracks(tracks, startIndex: index);
  }

  Future<void> _lyrics(Track track) async {
    final lyrics = await _controller.catalog.lyrics(track);
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: track.title.isEmpty ? '歌词' : track.title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 430),
        child: SingleChildScrollView(
          child: SelectableText(
            [
              lyrics.original,
              if (lyrics.translation case final value?) value,
            ].join('\n\n'),
          ),
        ),
      ),
    );
  }

  Future<void> _choosePlaylist({Track? track, bool importAll = false}) async {
    final playlists = await _controller.playlists.list();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: importAll ? '导入到本地歌单' : '添加到歌单',
      child: playlists.isEmpty
          ? const AppEmptyState(message: '还没有歌单')
          : ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return AppButton(
                  variant: ShadButtonVariant.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (importAll) {
                      unawaited(_controller.importAll(playlist.id));
                    } else if (track != null) {
                      unawaited(
                        _run(
                          () => _controller.playlists.addTracks(playlist.id, [
                            track,
                          ]),
                          success: '已添加到 ${playlist.name}',
                        ),
                      );
                    }
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(playlist.name),
                  ),
                );
              },
            ),
    );
  }

  List<TrackAction> _actionsFor(Track track) {
    final standard = buildTrackActions(
      track: track,
      player: widget.player,
      showLyrics: (value) => _run(() => _lyrics(value)),
      addToPlaylist: (value) => _run(() => _choosePlaylist(track: value)),
      download: (value, quality) => _run(
        () => widget.downloads.create(value, quality),
        successTitle: '已加入下载队列',
      ),
    );
    return [
      TrackAction(
        id: TrackActionId.playNow,
        label: '立即播放',
        icon: AppPlaybackIcons.play,
        invoke: () => _play(track),
      ),
      TrackAction(
        id: TrackActionId.playNext,
        label: '下一首播放',
        icon: LucideIcons.listStart,
        invoke: () async => widget.player.playNext(await _withPicture(track)),
      ),
      TrackAction(
        id: TrackActionId.enqueue,
        label: '添加到播放队列',
        icon: LucideIcons.listPlus,
        invoke: () async => widget.player.enqueue(await _withPicture(track)),
      ),
      ...standard.where(
        (action) =>
            action.id != TrackActionId.playNow &&
            action.id != TrackActionId.playNext &&
            action.id != TrackActionId.enqueue,
      ),
    ];
  }

  void _more(Track track) {
    unawaited(
      showMobileTrackActions(
        context,
        track: track,
        metadata: SearchTrackMetadata.fromTrack(track),
        actions: _actionsFor(track),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMore)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      final playlist = state.playlist;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      if (playlist == null && state.loadingPage != null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (playlist == null) {
        return _InitialError(error: state.error, retry: _controller.load);
      }
      return ColoredBox(
        color: AppTokens.of(context).background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            mobile ? 18 : 30,
            mobile ? 16 : 38,
            16,
          ),
          child: Builder(
            builder: (context) {
              final contents = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetadataHero(
                    playlist: playlist,
                    mobile: mobile,
                    onPlayAll: _playAll,
                    onImportAll: () => _choosePlaylist(importAll: true),
                    busy: state.importing,
                  ),
                  if (state.importProgress case final progress?) ...[
                    const SizedBox(height: 10),
                    _ImportStatus(
                      progress: progress,
                      importing: state.importing,
                      onCancel: _controller.cancelImport,
                    ),
                  ],
                  if (state.error != null && state.stale) ...[
                    const SizedBox(height: 10),
                    AppNotice.error(
                      title: '部分歌曲加载失败',
                      message: appErrorMessage(
                        state.error!,
                        fallback: '部分歌曲暂时无法加载，请稍后重试。',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  mobile
                      ? CatalogTrackList(
                          embedded: true,
                          tracks: state.tracks,
                          page: 1,
                          pageSize: state.tracks.isEmpty
                              ? 1
                              : state.tracks.length,
                          total: playlist.total?.toInt(),
                          providers: const [],
                          aggregate: false,
                          mobile: true,
                          loadPicture: _loadPicture,
                          onPlay: (track) => unawaited(_play(track)),
                          onFavorite: (track) =>
                              unawaited(_choosePlaylist(track: track)),
                          actionsFor: _actionsFor,
                          onMore: _more,
                          loadingMore:
                              state.loadingPage != null &&
                              state.pages.isNotEmpty,
                          loadMoreError: state.failedPage == null
                              ? null
                              : state.error,
                          onRetry: () =>
                              unawaited(_controller.retryFailedPage()),
                        )
                      : Expanded(
                          child: CatalogTrackList(
                            tracks: state.tracks,
                            page: 1,
                            pageSize: state.tracks.isEmpty
                                ? 1
                                : state.tracks.length,
                            total: playlist.total?.toInt(),
                            providers: const [],
                            aggregate: false,
                            mobile: mobile,
                            loadPicture: _loadPicture,
                            onPlay: (track) => unawaited(_play(track)),
                            onFavorite: (track) =>
                                unawaited(_choosePlaylist(track: track)),
                            actionsFor: _actionsFor,
                            onMore: _more,
                            scrollController: _scrollController,
                            loadingMore:
                                state.loadingPage != null &&
                                state.pages.isNotEmpty,
                            loadMoreError: state.failedPage == null
                                ? null
                                : state.error,
                            onRetry: () =>
                                unawaited(_controller.retryFailedPage()),
                          ),
                        ),
                  if (!mobile && state.failedPage != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        variant: ShadButtonVariant.outline,
                        onPressed: state.loadingPage != null
                            ? null
                            : () => unawaited(_controller.retryFailedPage()),
                        child: const Text('重试加载'),
                      ),
                    ),
                ],
              );
              return mobile
                  ? SingleChildScrollView(
                      key: const Key('online-playlist-mobile-scroll'),
                      controller: _scrollController,
                      child: contents,
                    )
                  : contents;
            },
          ),
        ),
      );
    },
  );
}

final class _MetadataHero extends StatelessWidget {
  const _MetadataHero({
    required this.playlist,
    required this.mobile,
    required this.onPlayAll,
    required this.onImportAll,
    required this.busy,
  });

  final CatalogCollection playlist;
  final bool mobile;
  final Future<void> Function() onPlayAll;
  final Future<void> Function() onImportAll;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (playlist.author.isNotEmpty) playlist.author,
      if (playlist.total != null) '${playlist.total} 首',
      if (playlist.playCount case final value?) '$value 播放',
    ];
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          playlist.name,
          maxLines: mobile ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display.copyWith(fontSize: mobile ? 25 : 34),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(metadata.join(' · '), style: AppTypography.metadata),
        ],
        if (playlist.description case final description?)
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            AppButton.playback(
              key: const Key('online-playlist-play-all'),
              onPressed: busy ? null : () => unawaited(onPlayAll()),
              leading: const AppPlaybackGlyph.play(size: 16),
              child: const Text('播放全部'),
            ),
            AppButton(
              key: const Key('online-playlist-import-all'),
              variant: ShadButtonVariant.outline,
              onPressed: busy ? null : () => unawaited(onImportAll()),
              leading: const Icon(LucideIcons.listPlus, size: 16),
              child: const Text('添加全部到歌单'),
            ),
          ],
        ),
      ],
    );
    if (mobile) return details;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Row(
        children: [
          AppArtwork(
            imageUrl: playlist.imageUrl?.toString(),
            seed: '${playlist.source}:${playlist.id}',
            semanticLabel: '${playlist.name}封面',
            size: 176,
            icon: LucideIcons.listMusic,
          ),
          const SizedBox(width: 24),
          Expanded(child: details),
        ],
      ),
    );
  }
}

final class _ImportStatus extends StatelessWidget {
  const _ImportStatus({
    required this.progress,
    required this.importing,
    required this.onCancel,
  });

  final PlaylistImportProgress progress;
  final bool importing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '已获取 ${progress.fetched} · 已添加 ${progress.added} · '
          '跳过 ${progress.skipped} · 失败 ${progress.failed}',
          style: AppTypography.metadata,
        ),
      ),
      if (importing)
        AppButton(
          variant: ShadButtonVariant.ghost,
          onPressed: onCancel,
          child: const Text('取消'),
        ),
    ],
  );
}

final class _InitialError extends StatelessWidget {
  const _InitialError({required this.error, required this.retry});
  final Object? error;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppNotice.error(
            title: '歌单详情加载失败',
            message: error == null
                ? 'Service 未返回歌单详情。'
                : appErrorMessage(error!, fallback: '歌单详情暂时无法加载，请稍后重试。'),
          ),
          const SizedBox(height: 12),
          AppButton(
            variant: ShadButtonVariant.outline,
            onPressed: () => unawaited(retry()),
            child: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}
