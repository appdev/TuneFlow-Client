import 'package:flutter/material.dart' hide SearchController;

import '../../api/models.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import 'search_controller.dart';

typedef TrackCallback = void Function(Track track);

final class SearchMobileResults extends StatelessWidget {
  const SearchMobileResults({
    super.key,
    required this.state,
    required this.scrollController,
    required this.loadPicture,
    required this.onPlay,
    required this.onFavorite,
    required this.onMore,
    required this.onViewAll,
    required this.onRetry,
    this.onOpenCollection,
    this.embedded = false,
  });

  final SearchState state;
  final ScrollController scrollController;
  final Future<Uri?> Function(Track) loadPicture;
  final TrackCallback onPlay;
  final TrackCallback onFavorite;
  final TrackCallback onMore;
  final ValueChanged<SearchView> onViewAll;
  final ValueChanged<CatalogSearchKind> onRetry;
  final ValueChanged<CatalogCollection>? onOpenCollection;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (state.query.isEmpty) {
      return const AppEmptyState(message: '输入关键词搜索音乐');
    }
    if (state.view == SearchView.overview || state.view == SearchView.tracks) {
      return _trackList(context, state.trackSection);
    }
    final section = state.view == SearchView.albums
        ? state.albumSection
        : state.playlistSection;
    return _collectionGrid(context, section);
  }

  Widget _trackList(BuildContext context, SearchSection<Track> section) {
    if (section.phase == SearchPhase.loading && section.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (section.phase == SearchPhase.empty) {
      return const AppEmptyState(message: '没有找到匹配单曲');
    }
    return KeyedSubtree(
      key: const Key('search-view-tracks'),
      child: CatalogTrackList(
        tracks: section.items,
        page: section.page,
        pageSize: SearchController.pageSize,
        total: section.total,
        providers: state.providers,
        aggregate: state.source == SearchController.aggregateSource,
        mobile: true,
        loadPicture: loadPicture,
        onPlay: onPlay,
        onFavorite: onFavorite,
        actionsFor: (_) => const [],
        onMore: onMore,
        scrollController: scrollController,
        loadingMore: section.phase == SearchPhase.loadingMore,
        loadMoreError: section.phase == SearchPhase.failure
            ? section.error ?? const Object()
            : null,
        onRetry: () => onRetry(CatalogSearchKind.track),
        embedded: embedded,
      ),
    );
  }

  Widget _collectionGrid(
    BuildContext context,
    SearchSection<CatalogCollection> section,
  ) {
    if (section.phase == SearchPhase.loading && section.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (section.items.isEmpty) {
      return const AppEmptyState(message: '没有找到匹配内容');
    }
    return GridView.builder(
      controller: embedded ? null : scrollController,
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: .78,
      ),
      itemCount: section.items.length,
      itemBuilder: (_, index) => _CollectionCard(
        item: section.items[index],
        onPressed: onOpenCollection == null
            ? null
            : () => onOpenCollection!(section.items[index]),
      ),
    );
  }
}

final class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.item, this.onPressed});
  final CatalogCollection item;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '打开${item.name}',
    child: Material(
      key: Key('search-collection-${item.source}-${item.id}'),
      color: AppTokens.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.compactCard),
        side: BorderSide(color: AppTokens.of(context).borderSoft),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.compactCard),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => AppArtwork(
                    imageUrl: item.imageUrl?.toString(),
                    seed: '${item.source}:${item.id}',
                    semanticLabel: '${item.name}封面',
                    size: constraints.maxWidth,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (item.author.isNotEmpty)
                Text(
                  item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
