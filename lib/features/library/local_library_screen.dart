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
import '../../design/components/track_actions.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import '../playlists/playlist_repository.dart';
import 'local_library_controller.dart';

final class LocalLibraryScreen extends StatefulWidget {
  const LocalLibraryScreen({
    super.key,
    required this.controller,
    required this.playlists,
    required this.playTracks,
  });

  final LocalLibraryController controller;
  final PlaylistRepository playlists;
  final PlayTracks playTracks;

  @override
  State<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

final class _LocalLibraryScreenState extends State<LocalLibraryScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state.items.isEmpty) widget.controller.refresh();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _choosePlaylist(Track track) async {
    try {
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
                    key: Key('local-library-playlist-${playlist.id}'),
                    variant: ShadButtonVariant.ghost,
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(_addTrack(playlist, track));
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(playlist.name),
                    ),
                  );
                },
              ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '歌单加载失败',
        message: appErrorMessage(error, fallback: '暂时无法加载歌单，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<void> _addTrack(PlaylistSummary playlist, Track track) async {
    try {
      await widget.playlists.addTracks(playlist.id, [track]);
      if (!mounted) return;
      showAppMessage(context, title: '完成', message: '已添加到 ${playlist.name}');
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '添加失败',
        message: appErrorMessage(error, fallback: '暂时无法添加到该歌单，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<void> _delete(LibraryTrack item) async {
    final accepted = await showAppDestructiveDialog(
      context,
      title: '从 Service 删除这首音乐？',
      message:
          '将永久删除“${item.track.title.isEmpty ? item.track.id : item.track.title}”及其歌词、封面等相关资源。',
      cancelLabel: '取消',
      confirmLabel: '删除',
    );
    if (!accepted || !mounted) return;
    try {
      await widget.controller.delete(item.id);
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '音乐删除失败',
        message: appErrorMessage(error, fallback: '未能从当前 Service 删除音乐，请稍后重试。'),
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final tracks = state.tracks;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      return ColoredBox(
        key: const Key('local-library-route'),
        color: AppTokens.of(context).background,
        child: mobile
            ? ListView(
                key: const Key('local-library-mobile-scroll'),
                children: [
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: AppNotice.error(
                        title: state.stale && tracks.isNotEmpty
                            ? '显示的是上次数据'
                            : '本地音乐加载失败',
                        message: appErrorMessage(
                          state.error!,
                          fallback: '本地音乐暂时无法加载，请稍后重试。',
                        ),
                      ),
                    ),
                  _LocalLibraryHero(
                    items: state.items,
                    mobile: true,
                    loading: state.loading,
                    onPlayAll: tracks.isEmpty
                        ? null
                        : () => widget.controller.playAll(widget.playTracks),
                    onRefresh: widget.controller.refresh,
                  ),
                  if (tracks.isEmpty)
                    SizedBox(
                      height: 220,
                      child: state.loading
                          ? const Center(child: CircularProgressIndicator())
                          : const AppEmptyState(message: '暂无本地音乐'),
                    )
                  else
                    _MobileLocalTrackList(
                      items: state.items,
                      deletingIds: state.deletingIds,
                      onPlay: (index) =>
                          widget.controller.playOne(widget.playTracks, index),
                      onFavorite: (item) => _choosePlaylist(item.track),
                      onDelete: _delete,
                    ),
                ],
              )
            : Column(
                children: [
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: AppNotice.error(
                        title: state.stale && tracks.isNotEmpty
                            ? '显示的是上次数据'
                            : '本地音乐加载失败',
                        message: appErrorMessage(
                          state.error!,
                          fallback: '本地音乐暂时无法加载，请稍后重试。',
                        ),
                      ),
                    ),
                  _LocalLibraryHero(
                    items: state.items,
                    mobile: mobile,
                    loading: state.loading,
                    onPlayAll: tracks.isEmpty
                        ? null
                        : () => widget.controller.playAll(widget.playTracks),
                    onRefresh: widget.controller.refresh,
                  ),
                  Expanded(
                    child: tracks.isEmpty
                        ? state.loading
                              ? const Center(child: CircularProgressIndicator())
                              : const AppEmptyState(message: '暂无本地音乐')
                        : _DesktopLocalTrackList(
                            items: state.items,
                            deletingIds: state.deletingIds,
                            loadPicture: widget.controller.loadPicture,
                            onPlay: (index) => widget.controller.playOne(
                              widget.playTracks,
                              index,
                            ),
                            onFavorite: (item) => _choosePlaylist(item.track),
                            onDelete: _delete,
                          ),
                  ),
                ],
              ),
      );
    },
  );
}

final class _LocalLibraryHero extends StatelessWidget {
  const _LocalLibraryHero({
    required this.items,
    required this.mobile,
    required this.loading,
    required this.onPlayAll,
    required this.onRefresh,
  });

  final List<LibraryTrack> items;
  final bool mobile;
  final bool loading;
  final VoidCallback? onPlayAll;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tracks = items.map((item) => item.track).toList(growable: false);
    final imageUrl = firstAvailableLibraryArtwork(items)?.toString();
    final actions = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        AppButton.playback(
          key: const Key('local-library-play-all'),
          onPressed: onPlayAll,
          leading: const AppPlaybackGlyph.play(size: 18),
          child: const Text('播放全部'),
        ),
        AppButton(
          variant: ShadButtonVariant.outline,
          loading: loading,
          onPressed: onRefresh,
          leading: const Icon(LucideIcons.refreshCw, size: 18),
          child: const Text('刷新'),
        ),
      ],
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${tracks.length} 首',
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '本地音乐',
          style: mobile ? AppTypography.mobilePageTitle : AppTypography.display,
        ),
        if (!mobile) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '已下载到当前 Service 的音乐',
            style: AppTypography.body.copyWith(
              color: AppTokens.of(context).foregroundSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        actions,
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? 16 : 38,
        mobile ? 20 : 28,
        mobile ? 16 : 38,
        20,
      ),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tracks.length} 首',
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
                const SizedBox(height: 3),
                const Text('本地音乐', style: AppTypography.mobilePageTitle),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) => AppArtwork(
                    key: const Key('local-library-hero-artwork'),
                    imageUrl: imageUrl,
                    seed: 'local-library',
                    semanticLabel: '本地音乐封面',
                    size: constraints.maxWidth / 1.8,
                    width: constraints.maxWidth,
                    height: constraints.maxWidth / 1.8,
                    icon: LucideIcons.library,
                  ),
                ),
                const SizedBox(height: 14),
                actions,
              ],
            )
          : SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    flex: 58,
                    child: LayoutBuilder(
                      builder: (context, constraints) => AppArtwork(
                        key: const Key('local-library-hero-artwork'),
                        imageUrl: imageUrl,
                        seed: 'local-library',
                        semanticLabel: '本地音乐封面',
                        size: 220,
                        width: constraints.maxWidth,
                        height: 220,
                        icon: LucideIcons.library,
                      ),
                    ),
                  ),
                  const SizedBox(width: 34),
                  Expanded(flex: 42, child: copy),
                ],
              ),
            ),
    );
  }
}

final class _DesktopLocalTrackList extends StatelessWidget {
  const _DesktopLocalTrackList({
    required this.items,
    required this.deletingIds,
    required this.loadPicture,
    required this.onPlay,
    required this.onFavorite,
    required this.onDelete,
  });

  final List<LibraryTrack> items;
  final Set<String> deletingIds;
  final Future<Uri?> Function(Track) loadPicture;
  final ValueChanged<int> onPlay;
  final ValueChanged<LibraryTrack> onFavorite;
  final ValueChanged<LibraryTrack> onDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final showAlbum = constraints.maxWidth >= 1080;
      final showDuration = constraints.maxWidth >= 720;
      return Padding(
        padding: const EdgeInsets.fromLTRB(38, 0, 38, 30),
        child: Column(
          children: [
            CatalogTrackTableHeader(
              showAlbum: showAlbum,
              showDuration: showDuration,
              compact: compact,
              showFavorite: true,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return CatalogTrackRow(
                    index: index + 1,
                    track: item.track,
                    providers: const [],
                    aggregate: false,
                    showAlbum: showAlbum,
                    showDuration: showDuration,
                    compact: compact,
                    loadPicture: loadPicture,
                    onPlay: () => onPlay(index),
                    onFavorite: () => onFavorite(item),
                    actions: const [],
                    trailing: _LocalTrackDeleteButton(
                      item: item,
                      deleting: deletingIds.contains(item.id),
                      onDelete: onDelete,
                    ),
                    rowKeyPrefix: 'local-library',
                    singleTap: true,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _MobileLocalTrackList extends StatelessWidget {
  const _MobileLocalTrackList({
    required this.items,
    required this.deletingIds,
    required this.onPlay,
    required this.onFavorite,
    required this.onDelete,
  });

  final List<LibraryTrack> items;
  final Set<String> deletingIds;
  final ValueChanged<int> onPlay;
  final ValueChanged<LibraryTrack> onFavorite;
  final ValueChanged<LibraryTrack> onDelete;

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      final track = item.track;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('local-library-mobile-track-${track.source}-${track.id}'),
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: () => onPlay(index),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTokens.of(context).borderSoft),
              ),
            ),
            child: Row(
              children: [
                AppArtwork(
                  imageUrl: track.raw['pic'] as String?,
                  seed: '${track.source}:${track.id}',
                  semanticLabel: '${track.title}封面',
                  size: 38,
                  borderRadius: 9,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title.isEmpty ? track.id : track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.title,
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                          color: AppTokens.of(context).foregroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key(
                    'local-library-favorite-${track.source}-${track.id}',
                  ),
                  tooltip: '收藏到歌单',
                  onPressed: () => onFavorite(item),
                  icon: const Icon(LucideIcons.heartPlus, size: 19),
                ),
                _LocalTrackDeleteButton(
                  item: item,
                  deleting: deletingIds.contains(item.id),
                  onDelete: onDelete,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Uri? firstAvailableLibraryArtwork(List<LibraryTrack> items) => items
    .map((item) => item.pictureUrl)
    .whereType<Uri>()
    .where(
      (uri) =>
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty,
    )
    .firstOrNull;

final class _LocalTrackDeleteButton extends StatelessWidget {
  const _LocalTrackDeleteButton({
    required this.item,
    required this.deleting,
    required this.onDelete,
  });

  final LibraryTrack item;
  final bool deleting;
  final ValueChanged<LibraryTrack> onDelete;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('local-library-delete-${item.id}'),
    tooltip: '从服务端删除',
    onPressed: deleting ? null : () => onDelete(item),
    icon: deleting
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            LucideIcons.trash2,
            size: 19,
            color: ShadTheme.of(context).colorScheme.destructive,
          ),
  );
}
