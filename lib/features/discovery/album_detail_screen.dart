import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import '../downloads/download_repository.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_repository.dart';
import '../search/adaptive_track_actions.dart';
import '../search/search_track_metadata.dart';
import '../search/track_action.dart';
import 'album_detail_controller.dart';

final class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.controller,
    required this.player,
    required this.playlists,
    required this.downloads,
  });

  final AlbumDetailController controller;
  final PlayerController player;
  final PlaylistRepository playlists;
  final DownloadRepository downloads;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

final class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final _scrollController = ScrollController();
  final Map<(String, String), Future<Uri?>> _pictures = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMore);
    if (widget.controller.state.pages.isEmpty &&
        !widget.controller.state.unsupported) {
      unawaited(widget.controller.load());
    }
  }

  void _loadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 240) {
      return;
    }
    final state = widget.controller.state;
    if (!state.hasMore ||
        state.loadingPage != null ||
        state.failedPage != null) {
      return;
    }
    final page = state.pages.keys.reduce((a, b) => a > b ? a : b) + 1;
    unawaited(widget.controller.loadPage(page));
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    String? successTitle,
  }) async {
    try {
      await action();
      if (!mounted) return;
      if (successTitle != null) {
        showAppMessage(context, title: successTitle);
      } else if (success != null) {
        showAppMessage(context, title: '完成', message: success);
      }
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '操作失败',
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<Uri?> _loadPicture(Track track) =>
      _pictures.putIfAbsent((track.source, track.id), () async {
        final embedded = track.raw['pic'];
        if (embedded is String && embedded.isNotEmpty) {
          return Uri.tryParse(embedded);
        }
        try {
          return Uri.tryParse(await widget.controller.catalog.picture(track));
        } on Object {
          return null;
        }
      });

  Future<Track> _withPicture(Track track) async {
    if (track.raw['pic'] case final String value when value.isNotEmpty) {
      return track;
    }
    final picture = await _loadPicture(track);
    return picture == null
        ? track
        : Track.fromJson({...track.toJson(), 'pic': picture.toString()});
  }

  Future<void> _play(Track track) async {
    final tracks = [...widget.controller.state.tracks];
    final index = tracks.indexWhere(
      (item) => item.source == track.source && item.id == track.id,
    );
    if (index < 0) return;
    tracks[index] = await _withPicture(track);
    await widget.player.playTracks(tracks, startIndex: index);
  }

  Future<void> _playAll() async {
    await widget.controller.loadAllPages();
    if (!mounted) return;
    if (widget.controller.state.failedPage != null) {
      showAppMessage(
        context,
        title: '无法播放全部',
        message: '专辑仍有歌曲加载失败，请重试后再播放。',
        destructive: true,
      );
      return;
    }
    final tracks = widget.controller.state.tracks.toList(growable: false);
    if (tracks.isNotEmpty) await widget.player.playTracks(tracks);
  }

  Future<void> _choosePlaylist(Track track) async {
    final playlists = await widget.playlists.list();
    if (!mounted) return;
    await showAppSheet<void>(
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
                  variant: ShadButtonVariant.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(
                      _run(
                        () => widget.playlists.addTracks(playlist.id, [track]),
                        success: '已添加到 ${playlist.name}',
                      ),
                    );
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

  Future<void> _showLyrics(Track track) async {
    final lyrics = await widget.controller.catalog.lyrics(track);
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: track.title.isEmpty ? '歌词' : track.title,
      child: SingleChildScrollView(
        child: SelectableText(
          [
            lyrics.original,
            if (lyrics.translation case final value?) value,
          ].join('\n\n'),
        ),
      ),
    );
  }

  List<TrackAction> _actionsFor(Track track) => buildTrackActions(
    track: track,
    player: widget.player,
    showLyrics: (value) => _run(() => _showLyrics(value)),
    addToPlaylist: (value) => _run(() => _choosePlaylist(value)),
    download: (value, quality) => _run(
      () => widget.downloads.create(value, quality),
      successTitle: '已加入下载队列',
    ),
  );

  void _more(Track track) => unawaited(
    showMobileTrackActions(
      context,
      track: track,
      metadata: SearchTrackMetadata.fromTrack(track),
      actions: _actionsFor(track),
    ),
  );

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMore)
      ..dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final album = state.album;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      if (album == null && state.loadingPage != null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (album == null) {
        return Center(
          child: AppNotice.error(
            title: '专辑加载失败',
            message: appErrorMessage(
              state.error ?? const FormatException('missing album'),
              fallback: '专辑详情暂时无法加载，请稍后重试。',
            ),
          ),
        );
      }
      final contents = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AlbumHero(album: album, mobile: mobile, onPlayAll: _playAll),
          if (state.unsupported) ...[
            const SizedBox(height: 14),
            const AppNotice.error(
              title: '当前音源不支持专辑详情',
              message: '仍可查看搜索结果中的专辑信息，请返回选择其他内容。',
            ),
          ] else ...[
            if (state.error != null) ...[
              const SizedBox(height: 14),
              AppNotice.error(
                title: state.stale ? '部分歌曲加载失败' : '专辑加载失败',
                message: appErrorMessage(
                  state.error!,
                  fallback: '专辑歌曲暂时无法加载，请稍后重试。',
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (state.tracks.isEmpty && state.loadingPage == null)
              const AppEmptyState(message: '该专辑暂无歌曲')
            else if (mobile)
              CatalogTrackList(
                embedded: true,
                tracks: state.tracks,
                page: 1,
                pageSize: state.tracks.isEmpty ? 1 : state.tracks.length,
                total: album.total?.toInt(),
                providers: const [],
                aggregate: false,
                mobile: true,
                loadPicture: _loadPicture,
                onPlay: (track) => unawaited(_play(track)),
                onFavorite: (track) => unawaited(_choosePlaylist(track)),
                actionsFor: _actionsFor,
                onMore: _more,
                loadingMore:
                    state.loadingPage != null && state.pages.isNotEmpty,
                loadMoreError: state.failedPage == null ? null : state.error,
                onRetry: () => unawaited(widget.controller.retryFailedPage()),
              )
            else
              Expanded(
                child: CatalogTrackList(
                  tracks: state.tracks,
                  page: 1,
                  pageSize: state.tracks.isEmpty ? 1 : state.tracks.length,
                  total: album.total?.toInt(),
                  providers: const [],
                  aggregate: false,
                  mobile: false,
                  loadPicture: _loadPicture,
                  onPlay: (track) => unawaited(_play(track)),
                  onFavorite: (track) => unawaited(_choosePlaylist(track)),
                  actionsFor: _actionsFor,
                  onMore: _more,
                  scrollController: _scrollController,
                  loadingMore:
                      state.loadingPage != null && state.pages.isNotEmpty,
                  loadMoreError: state.failedPage == null ? null : state.error,
                  onRetry: () => unawaited(widget.controller.retryFailedPage()),
                ),
              ),
          ],
        ],
      );
      return ColoredBox(
        key: const Key('album-detail-route'),
        color: AppTokens.of(context).background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            mobile ? 18 : 30,
            mobile ? 16 : 38,
            16,
          ),
          child: mobile
              ? SingleChildScrollView(
                  key: const PageStorageKey('album-detail-mobile-scroll'),
                  controller: _scrollController,
                  child: contents,
                )
              : contents,
        ),
      );
    },
  );
}

final class _AlbumHero extends StatelessWidget {
  const _AlbumHero({
    required this.album,
    required this.mobile,
    required this.onPlayAll,
  });

  final CatalogCollection album;
  final bool mobile;
  final Future<void> Function() onPlayAll;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album.name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display.copyWith(fontSize: mobile ? 25 : 34),
        ),
        if (album.author.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(album.author, style: AppTypography.metadata),
        ],
        if (album.description case final description?
            when description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 12),
        AppButton.playback(
          key: const Key('album-play-all'),
          onPressed: () => unawaited(onPlayAll()),
          child: const Text('播放全部'),
        ),
      ],
    );
    if (mobile) return details;
    return Row(
      children: [
        AppArtwork(
          imageUrl: album.imageUrl?.toString(),
          seed: '${album.source}:${album.id}',
          semanticLabel: '${album.name}封面',
          size: 176,
          icon: LucideIcons.disc3,
        ),
        const SizedBox(width: 24),
        Expanded(child: details),
      ],
    );
  }
}
