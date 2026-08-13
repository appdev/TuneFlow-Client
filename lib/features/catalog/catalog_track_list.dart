import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/design_tokens.dart';
import '../search/adaptive_track_actions.dart';
import '../search/search_track_artwork.dart';
import '../search/search_track_metadata.dart';
import '../search/track_action.dart';

typedef CatalogTrackActionsBuilder = List<TrackAction> Function(Track track);

final class CatalogTrackList extends StatelessWidget {
  const CatalogTrackList({
    super.key,
    required this.tracks,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.providers,
    required this.aggregate,
    required this.mobile,
    required this.loadPicture,
    required this.onPlay,
    required this.onFavorite,
    required this.actionsFor,
    this.onMore,
    this.onPage,
    this.scrollController,
    this.loadingMore = false,
    this.loadMoreError,
    this.onRetry,
  });

  final List<Track> tracks;
  final int page;
  final int pageSize;
  final int? total;
  final List<CatalogProvider> providers;
  final bool aggregate;
  final bool mobile;
  final Future<Uri?> Function(Track) loadPicture;
  final ValueChanged<Track> onPlay;
  final ValueChanged<Track> onFavorite;
  final CatalogTrackActionsBuilder actionsFor;
  final ValueChanged<Track>? onMore;
  final ValueChanged<int>? onPage;
  final ScrollController? scrollController;
  final bool loadingMore;
  final Object? loadMoreError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => mobile
      ? _MobileCatalogTrackList(
          tracks: tracks,
          scrollController: scrollController,
          onPlay: onPlay,
          onFavorite: onFavorite,
          onMore: onMore,
          loadingMore: loadingMore,
          loadMoreError: loadMoreError,
          onRetry: onRetry,
        )
      : LayoutBuilder(
          builder: (context, constraints) {
            final showAlbum = constraints.maxWidth >= 1080;
            final showDuration = constraints.maxWidth >= 900;
            final compact = constraints.maxWidth < 900;
            return Column(
              children: [
                CatalogTrackTableHeader(
                  showAlbum: showAlbum,
                  showDuration: showDuration,
                  compact: compact,
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) => CatalogTrackRow(
                      index: index + 1 + ((page - 1) * pageSize),
                      track: tracks[index],
                      providers: providers,
                      aggregate: aggregate,
                      showAlbum: showAlbum,
                      showDuration: showDuration,
                      compact: compact,
                      loadPicture: loadPicture,
                      onPlay: () => onPlay(tracks[index]),
                      onFavorite: () => onFavorite(tracks[index]),
                      actions: actionsFor(tracks[index]),
                    ),
                  ),
                ),
                if (onPage case final callback?)
                  _CatalogPagination(
                    page: page,
                    pageSize: pageSize,
                    itemCount: tracks.length,
                    total: total,
                    onPage: callback,
                  ),
              ],
            );
          },
        );
}

final class CatalogTrackTableHeader extends StatelessWidget {
  const CatalogTrackTableHeader({
    super.key,
    required this.showAlbum,
    required this.showDuration,
    required this.compact,
    this.showFavorite = true,
  });

  final bool showAlbum;
  final bool showDuration;
  final bool compact;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTokens.of(context).border)),
    ),
    child: Row(
      children: [
        SizedBox(width: compact ? 28 : 30, child: const Text('#')),
        const SizedBox(width: 12),
        SizedBox(width: compact ? 40 : 44, child: const Text('封面')),
        const SizedBox(width: 12),
        const Expanded(child: Text('歌曲名')),
        const SizedBox(width: 12),
        if (showFavorite)
          const SizedBox(
            width: 44,
            child: Center(child: Icon(LucideIcons.heart, size: 16)),
          ),
        if (showAlbum) ...[
          const SizedBox(width: 12),
          const Expanded(child: Text('专辑')),
        ],
        if (showDuration) ...[
          const SizedBox(width: 12),
          const SizedBox(width: 54, child: Text('时长')),
        ],
        const SizedBox(width: 12),
        const SizedBox(width: 44),
      ],
    ),
  );
}

final class CatalogTrackRow extends StatelessWidget {
  const CatalogTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.providers,
    required this.aggregate,
    required this.showAlbum,
    required this.showDuration,
    required this.compact,
    required this.loadPicture,
    required this.onPlay,
    required this.actions,
    this.onFavorite,
    this.favoriteIcon = LucideIcons.heartPlus,
    this.favoriteTooltip = '收藏到歌单',
    this.trailing,
    this.rowKeyPrefix = 'search',
    this.reserveFavoriteSpace = true,
    this.singleTap = false,
  });

  final int index;
  final Track track;
  final List<CatalogProvider> providers;
  final bool aggregate;
  final bool showAlbum;
  final bool showDuration;
  final bool compact;
  final Future<Uri?> Function(Track) loadPicture;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final List<TrackAction> actions;
  final IconData favoriteIcon;
  final String favoriteTooltip;
  final Widget? trailing;
  final String rowKeyPrefix;
  final bool reserveFavoriteSpace;
  final bool singleTap;

  @override
  Widget build(BuildContext context) {
    final metadata = SearchTrackMetadata.fromTrack(track);
    final row = InkWell(
      key: Key('$rowKeyPrefix-track-${track.source}-${track.id}'),
      onTap: singleTap ? onPlay : null,
      onDoubleTap: onPlay,
      child: Container(
        height: compact ? 54 : 58,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTokens.of(context).borderSoft),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 28 : 30,
              child: Text(
                index.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: AppTypography.counter.copyWith(
                  fontSize: 11,
                  color: AppTokens.of(context).muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: compact ? 40 : 44,
              child: Center(
                child: SearchTrackArtwork(
                  track: track,
                  loadPicture: loadPicture,
                  size: compact ? 36 : 38,
                  borderRadius: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title.isEmpty ? track.id : track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _DesktopMetadata(
                    track: track,
                    metadata: metadata,
                    providers: providers,
                    aggregate: aggregate,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (reserveFavoriteSpace || onFavorite != null)
              SizedBox(
                width: 44,
                child: onFavorite == null
                    ? null
                    : KeyedSubtree(
                        key: Key(
                          'catalog-favorite-${track.source}-${track.id}',
                        ),
                        child: IconButton(
                          key: Key(
                            '$rowKeyPrefix-favorite-${track.source}-${track.id}',
                          ),
                          tooltip: favoriteTooltip,
                          onPressed: onFavorite,
                          icon: Icon(favoriteIcon, size: 20),
                        ),
                      ),
              ),
            if (showAlbum) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  metadata.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
              ),
            ],
            if (showDuration) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 54,
                child: Text(
                  metadata.durationLabel ?? '--:--',
                  style: AppTypography.counter,
                ),
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child:
                  trailing ??
                  (actions.isEmpty
                      ? null
                      : KeyedSubtree(
                          key: Key('catalog-more-${track.source}-${track.id}'),
                          child: DesktopTrackActionsButton(
                            actions: actions,
                            child: (open) => IconButton(
                              key: Key(
                                '$rowKeyPrefix-more-${track.source}-${track.id}',
                              ),
                              tooltip: '更多操作',
                              onPressed: open,
                              icon: const Icon(LucideIcons.ellipsis, size: 20),
                            ),
                          ),
                        )),
            ),
          ],
        ),
      ),
    );
    return KeyedSubtree(
      key: key ?? Key('catalog-track-${track.source}-${track.id}'),
      child: actions.isEmpty
          ? row
          : DesktopTrackContextRegion(actions: actions, child: row),
    );
  }
}

final class _DesktopMetadata extends StatelessWidget {
  const _DesktopMetadata({
    required this.track,
    required this.metadata,
    required this.providers,
    required this.aggregate,
  });

  final Track track;
  final SearchTrackMetadata metadata;
  final List<CatalogProvider> providers;
  final bool aggregate;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      children: [
        if (metadata.qualityLabel case final quality?) ...[
          Container(
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.accent.withValues(alpha: .82)),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              quality,
              style: AppTypography.metadata.copyWith(
                color: tokens.accent,
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.metadata.copyWith(color: tokens.muted),
          ),
        ),
        if (aggregate) ...[
          const SizedBox(width: 7),
          Text(
            providerLabel(providers, track.source),
            style: AppTypography.metadata.copyWith(color: tokens.accent),
          ),
        ],
      ],
    );
  }
}

final class _MobileCatalogTrackList extends StatelessWidget {
  const _MobileCatalogTrackList({
    required this.tracks,
    required this.scrollController,
    required this.onPlay,
    required this.onFavorite,
    required this.onMore,
    required this.loadingMore,
    required this.loadMoreError,
    required this.onRetry,
  });

  final List<Track> tracks;
  final ScrollController? scrollController;
  final ValueChanged<Track> onPlay;
  final ValueChanged<Track> onFavorite;
  final ValueChanged<Track>? onMore;
  final bool loadingMore;
  final Object? loadMoreError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: scrollController,
    itemCount: tracks.length + (loadingMore || loadMoreError != null ? 1 : 0),
    itemBuilder: (context, index) {
      if (index < tracks.length) {
        final track = tracks[index];
        final metadata = SearchTrackMetadata.fromTrack(track);
        final tokens = AppTokens.of(context);
        return KeyedSubtree(
          key: Key('catalog-track-${track.source}-${track.id}'),
          child: InkWell(
            key: Key('search-track-${track.source}-${track.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPlay(track),
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).width <= 360 ? 56 : 60,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.borderSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.title.isEmpty ? track.id : track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.title.copyWith(
                            fontSize: 14,
                            height: 1.2,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _MobileMetadataLine(track: track, metadata: metadata),
                      ],
                    ),
                  ),
                  KeyedSubtree(
                    key: Key('catalog-favorite-${track.source}-${track.id}'),
                    child: IconButton(
                      key: Key('search-favorite-${track.source}-${track.id}'),
                      tooltip: '收藏到歌单',
                      onPressed: () => onFavorite(track),
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      padding: const EdgeInsets.all(12),
                      icon: Icon(
                        LucideIcons.heartPlus,
                        size: 20,
                        color: tokens.muted,
                      ),
                    ),
                  ),
                  KeyedSubtree(
                    key: Key('catalog-more-${track.source}-${track.id}'),
                    child: IconButton(
                      key: Key('search-more-${track.source}-${track.id}'),
                      tooltip: '更多操作',
                      onPressed: onMore == null ? null : () => onMore!(track),
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      padding: const EdgeInsets.all(12),
                      icon: Icon(
                        LucideIcons.ellipsisVertical,
                        size: 20,
                        color: tokens.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (loadMoreError != null) {
        return TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('加载失败，点击重试'),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    },
  );
}

final class _MobileMetadataLine extends StatelessWidget {
  const _MobileMetadataLine({required this.track, required this.metadata});

  final Track track;
  final SearchTrackMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final values = <Widget>[
      if (metadata.qualityLabel case final value?)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.success, width: 1.2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            value,
            style: AppTypography.metadata.copyWith(
              color: tokens.success,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (track.artist.isNotEmpty) Text(track.artist),
    ];
    return DefaultTextStyle(
      style: AppTypography.metadata.copyWith(
        color: tokens.muted,
        fontSize: 11,
        height: 1.2,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 3,
        children: values,
      ),
    );
  }
}

final class _CatalogPagination extends StatelessWidget {
  const _CatalogPagination({
    required this.page,
    required this.pageSize,
    required this.itemCount,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int pageSize;
  final int itemCount;
  final int? total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = total == null
        ? null
        : (total! / pageSize).ceil().clamp(1, 999999);
    return SizedBox(
      height: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(total == null ? '$itemCount 首' : '共 $total 首'),
          const SizedBox(width: 18),
          IconButton(
            tooltip: '上一页',
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(LucideIcons.chevronLeft),
          ),
          Text(pages == null ? '第 $page 页' : '$page / $pages'),
          IconButton(
            tooltip: '下一页',
            onPressed: pages == null || page < pages
                ? () => onPage(page + 1)
                : null,
            icon: const Icon(LucideIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}
