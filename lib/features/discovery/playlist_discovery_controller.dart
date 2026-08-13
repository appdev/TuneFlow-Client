import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../search/search_repository.dart';

enum DiscoveryPhase { idle, loading, ready, empty, failure }

const _unchanged = Object();

final class PlaylistDiscoveryState {
  const PlaylistDiscoveryState({
    this.providers = const [],
    this.source = '',
    this.filters,
    this.sortId = '',
    this.tagId = '',
    this.page = 1,
    this.items = const [],
    this.limit = 0,
    this.total,
    this.hasMore = false,
    this.phase = DiscoveryPhase.idle,
    this.filtersError,
    this.browseError,
    this.stale = false,
  });

  final List<CatalogProvider> providers;
  final String source;
  final PlaylistDiscoveryFilters? filters;
  final String sortId;
  final String tagId;
  final int page;
  final List<CatalogCollection> items;
  final int limit;
  final int? total;
  final bool hasMore;
  final DiscoveryPhase phase;
  final Object? filtersError;
  final Object? browseError;
  final bool stale;

  PlaylistDiscoveryState copyWith({
    List<CatalogProvider>? providers,
    String? source,
    Object? filters = _unchanged,
    String? sortId,
    String? tagId,
    int? page,
    List<CatalogCollection>? items,
    int? limit,
    Object? total = _unchanged,
    bool? hasMore,
    DiscoveryPhase? phase,
    Object? filtersError = _unchanged,
    Object? browseError = _unchanged,
    bool? stale,
  }) => PlaylistDiscoveryState(
    providers: providers ?? this.providers,
    source: source ?? this.source,
    filters: identical(filters, _unchanged)
        ? this.filters
        : filters as PlaylistDiscoveryFilters?,
    sortId: sortId ?? this.sortId,
    tagId: tagId ?? this.tagId,
    page: page ?? this.page,
    items: items ?? this.items,
    limit: limit ?? this.limit,
    total: identical(total, _unchanged) ? this.total : total as int?,
    hasMore: hasMore ?? this.hasMore,
    phase: phase ?? this.phase,
    filtersError: identical(filtersError, _unchanged)
        ? this.filtersError
        : filtersError,
    browseError: identical(browseError, _unchanged)
        ? this.browseError
        : browseError,
    stale: stale ?? this.stale,
  );
}

final class PlaylistDiscoveryController extends ChangeNotifier {
  PlaylistDiscoveryController(this.repository);

  final SearchRepository repository;
  PlaylistDiscoveryState state = const PlaylistDiscoveryState();
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      phase: DiscoveryPhase.loading,
      filtersError: null,
      browseError: null,
      stale: false,
    );
    notifyListeners();
    try {
      final capabilities = await repository.capabilities();
      if (generation != _generation) return;
      final providers = capabilities.providers
          .where(
            (provider) =>
                provider.playlistDiscovery?.tags == true &&
                provider.playlistDiscovery?.browse == true &&
                provider.playlistDiscovery?.detail == true,
          )
          .toList(growable: false);
      if (providers.isEmpty) {
        state = state.copyWith(
          providers: const [],
          phase: DiscoveryPhase.failure,
          filtersError: StateError('当前 Service 没有可用的歌单发现平台。'),
        );
        notifyListeners();
        return;
      }
      final source = providers.any((provider) => provider.id == state.source)
          ? state.source
          : providers.first.id;
      state = state.copyWith(
        providers: List.unmodifiable(providers),
        source: source,
      );
      await _loadFilters(source: source, generation: generation);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        phase: DiscoveryPhase.failure,
        filtersError: error,
      );
      notifyListeners();
    }
  }

  Future<void> selectProvider(String source) async {
    if (source == state.source ||
        !state.providers.any((provider) => provider.id == source)) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      source: source,
      filters: null,
      sortId: '',
      tagId: '',
      page: 1,
      items: const [],
      limit: 0,
      total: null,
      hasMore: false,
      phase: DiscoveryPhase.loading,
      filtersError: null,
      browseError: null,
      stale: false,
    );
    notifyListeners();
    await _loadFilters(source: source, generation: generation);
  }

  Future<void> selectSort(String sortId) async {
    if (sortId == state.sortId || state.filters == null) return;
    final generation = ++_generation;
    state = state.copyWith(
      sortId: sortId,
      page: 1,
      browseError: null,
      stale: false,
    );
    await _loadBrowse(page: 1, generation: generation);
  }

  Future<void> selectTag(String tagId) async {
    if (tagId == state.tagId || state.filters == null) return;
    final generation = ++_generation;
    state = state.copyWith(
      tagId: tagId,
      page: 1,
      browseError: null,
      stale: false,
    );
    await _loadBrowse(page: 1, generation: generation);
  }

  Future<void> goToPage(int page) async {
    if (page < 1 || page == state.page || state.filters == null) return;
    final generation = ++_generation;
    await _loadBrowse(page: page, generation: generation);
  }

  Future<void> retryFilters() async {
    if (state.source.isEmpty) return load();
    final generation = ++_generation;
    await _loadFilters(source: state.source, generation: generation);
  }

  Future<void> retryBrowse() async {
    if (state.filters == null) return retryFilters();
    final generation = ++_generation;
    await _loadBrowse(page: state.page, generation: generation);
  }

  Future<void> _loadFilters({
    required String source,
    required int generation,
  }) async {
    state = state.copyWith(
      phase: DiscoveryPhase.loading,
      filtersError: null,
      browseError: null,
      stale: false,
    );
    notifyListeners();
    try {
      final filters = await repository.playlistTags(source: source);
      if (generation != _generation) return;
      final sortId =
          filters.sorts
              .where((sort) => sort.id.toLowerCase() == 'hot')
              .firstOrNull
              ?.id ??
          filters.sorts
              .where((sort) => sort.name.contains('最热'))
              .firstOrNull
              ?.id ??
          filters.sorts.firstOrNull?.id ??
          '';
      state = state.copyWith(
        filters: filters,
        sortId: sortId,
        tagId: '',
        page: 1,
        filtersError: null,
      );
      await _loadBrowse(page: 1, generation: generation);
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        filters: null,
        phase: DiscoveryPhase.failure,
        filtersError: error,
        browseError: null,
        stale: false,
      );
      notifyListeners();
    }
  }

  Future<void> _loadBrowse({required int page, required int generation}) async {
    final previousItems = state.items;
    final previousPage = state.page;
    final previousTotal = state.total;
    state = state.copyWith(
      phase: DiscoveryPhase.loading,
      browseError: null,
      stale: false,
    );
    notifyListeners();
    try {
      final result = await repository.browsePlaylists(
        source: state.source,
        sortId: state.sortId,
        tagId: state.tagId,
        page: page,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        page: result.page,
        items: List.unmodifiable(result.items),
        limit: result.limit,
        total: result.total,
        hasMore: result.hasMore,
        phase: result.items.isEmpty
            ? DiscoveryPhase.empty
            : DiscoveryPhase.ready,
        browseError: null,
        stale: false,
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        page: previousPage,
        items: previousItems,
        total: previousTotal,
        phase: DiscoveryPhase.failure,
        browseError: error,
        stale: previousItems.isNotEmpty,
      );
    }
    notifyListeners();
  }
}
