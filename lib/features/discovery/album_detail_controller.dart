import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../search/search_repository.dart';

const _unchanged = Object();

final class AlbumDetailRouteArgs {
  const AlbumDetailRouteArgs({required this.album, required this.supported});

  final CatalogCollection album;
  final bool supported;
}

final class AlbumDetailState {
  const AlbumDetailState({
    this.album,
    this.pages = const {},
    this.tracks = const [],
    this.loadingPage,
    this.failedPage,
    this.error,
    this.stale = false,
    this.unsupported = false,
  });

  final CatalogCollection? album;
  final Map<int, AlbumDetailPage> pages;
  final List<Track> tracks;
  final int? loadingPage;
  final int? failedPage;
  final Object? error;
  final bool stale;
  final bool unsupported;

  bool get hasMore {
    if (pages.isEmpty) return false;
    final lastPage = pages.keys.reduce((a, b) => a > b ? a : b);
    return pages[lastPage]!.hasMore;
  }

  AlbumDetailState copyWith({
    Object? album = _unchanged,
    Map<int, AlbumDetailPage>? pages,
    List<Track>? tracks,
    Object? loadingPage = _unchanged,
    Object? failedPage = _unchanged,
    Object? error = _unchanged,
    bool? stale,
    bool? unsupported,
  }) => AlbumDetailState(
    album: identical(album, _unchanged)
        ? this.album
        : album as CatalogCollection?,
    pages: pages ?? this.pages,
    tracks: tracks ?? this.tracks,
    loadingPage: identical(loadingPage, _unchanged)
        ? this.loadingPage
        : loadingPage as int?,
    failedPage: identical(failedPage, _unchanged)
        ? this.failedPage
        : failedPage as int?,
    error: identical(error, _unchanged) ? this.error : error,
    stale: stale ?? this.stale,
    unsupported: unsupported ?? this.unsupported,
  );
}

final class AlbumDetailController extends ChangeNotifier {
  AlbumDetailController({
    required this.catalog,
    required this.source,
    required this.albumId,
    required this.supported,
    this.initialAlbum,
  }) : state = AlbumDetailState(album: initialAlbum, unsupported: !supported);

  final SearchRepository catalog;
  final String source;
  final String albumId;
  final bool supported;
  final CatalogCollection? initialAlbum;
  AlbumDetailState state;
  var _generation = 0;

  Future<void> load() async {
    if (!supported) return;
    final generation = ++_generation;
    state = AlbumDetailState(album: initialAlbum, loadingPage: 1);
    notifyListeners();
    await _loadPage(1, generation);
  }

  Future<void> loadPage(int page) async {
    if (!supported || page < 1 || state.loadingPage != null) return;
    await _loadPage(page, ++_generation);
  }

  Future<void> retryFailedPage() async {
    final page = state.failedPage;
    if (page != null) await loadPage(page);
  }

  Future<void> _loadPage(int page, int generation) async {
    state = state.copyWith(
      loadingPage: page,
      failedPage: null,
      error: null,
      stale: false,
    );
    notifyListeners();
    try {
      final result = await catalog.album(
        source: source,
        albumId: albumId,
        page: page,
      );
      if (generation != _generation) return;
      final pages = Map<int, AlbumDetailPage>.from(state.pages)
        ..[result.page] = result;
      state = state.copyWith(
        album: _mergeAlbum(result.album),
        pages: Map.unmodifiable(pages),
        tracks: List.unmodifiable(_orderedTracks(pages)),
        loadingPage: null,
        failedPage: null,
        error: null,
        stale: false,
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        loadingPage: null,
        failedPage: page,
        error: error,
        stale: state.tracks.isNotEmpty,
      );
    }
    notifyListeners();
  }

  CatalogCollection _mergeAlbum(CatalogCollection details) {
    final seed = state.album ?? initialAlbum;
    if (seed == null) return details;
    return CatalogCollection(
      id: details.id,
      kind: details.kind,
      name: details.name.isNotEmpty ? details.name : seed.name,
      source: details.source,
      author: details.author.isNotEmpty ? details.author : seed.author,
      total: details.total ?? seed.total,
      imageUrl: details.imageUrl ?? seed.imageUrl,
      description: details.description ?? seed.description,
      playCount: details.playCount ?? seed.playCount,
    );
  }

  List<Track> _orderedTracks(Map<int, AlbumDetailPage> pages) {
    final seen = <(String, String)>{};
    final tracks = <Track>[];
    final pageNumbers = pages.keys.toList()..sort();
    for (final page in pageNumbers) {
      for (final track in pages[page]!.tracks) {
        if (seen.add((track.source, track.id))) tracks.add(track);
      }
    }
    return tracks;
  }

  Future<void> loadAllPages() async {
    if (!supported) return;
    if (state.pages.isEmpty) await load();
    while (state.hasMore && state.failedPage == null) {
      final nextPage = state.pages.keys.reduce((a, b) => a > b ? a : b) + 1;
      await loadPage(nextPage);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
