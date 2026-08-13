import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../playlists/playlist_repository.dart';
import '../search/search_repository.dart';

const _unchanged = Object();

final class PlaylistImportProgress {
  const PlaylistImportProgress({
    required this.fetched,
    required this.added,
    required this.skipped,
    required this.failed,
    required this.completed,
    required this.cancelled,
  });

  final int fetched;
  final int added;
  final int skipped;
  final int failed;
  final bool completed;
  final bool cancelled;
}

final class OnlinePlaylistDetailState {
  const OnlinePlaylistDetailState({
    this.playlist,
    this.pages = const {},
    this.tracks = const [],
    this.loadingPage,
    this.failedPage,
    this.error,
    this.stale = false,
    this.importProgress,
    this.importing = false,
  });

  final CatalogCollection? playlist;
  final Map<int, OnlinePlaylistPage> pages;
  final List<Track> tracks;
  final int? loadingPage;
  final int? failedPage;
  final Object? error;
  final bool stale;
  final PlaylistImportProgress? importProgress;
  final bool importing;

  bool get hasMore =>
      pages.isNotEmpty &&
      pages[pages.keys.reduce((a, b) => a > b ? a : b)]!.hasMore;

  OnlinePlaylistDetailState copyWith({
    Object? playlist = _unchanged,
    Map<int, OnlinePlaylistPage>? pages,
    List<Track>? tracks,
    Object? loadingPage = _unchanged,
    Object? failedPage = _unchanged,
    Object? error = _unchanged,
    bool? stale,
    Object? importProgress = _unchanged,
    bool? importing,
  }) => OnlinePlaylistDetailState(
    playlist: identical(playlist, _unchanged)
        ? this.playlist
        : playlist as CatalogCollection?,
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
    importProgress: identical(importProgress, _unchanged)
        ? this.importProgress
        : importProgress as PlaylistImportProgress?,
    importing: importing ?? this.importing,
  );
}

final class OnlinePlaylistDetailController extends ChangeNotifier {
  OnlinePlaylistDetailController({
    required this.catalog,
    required this.playlists,
    required this.source,
    required this.playlistId,
    this.initialPlaylist,
  }) : state = OnlinePlaylistDetailState(playlist: initialPlaylist);

  final SearchRepository catalog;
  final PlaylistRepository playlists;
  final String source;
  final String playlistId;
  final CatalogCollection? initialPlaylist;
  OnlinePlaylistDetailState state;
  var _generation = 0;
  var _cancelImport = false;
  String? _importTarget;
  final Set<(String, String)> _confirmedImports = {};

  Future<void> load() async {
    final generation = ++_generation;
    state = OnlinePlaylistDetailState(
      playlist: initialPlaylist,
      loadingPage: 1,
    );
    notifyListeners();
    await _loadPage(1, generation);
  }

  Future<void> loadPage(int page) async {
    if (page < 1 || state.loadingPage != null) return;
    await _loadPage(page, ++_generation);
  }

  Future<void> retryFailedPage() async {
    final page = state.failedPage;
    if (page == null) return;
    await loadPage(page);
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
      final result = await catalog.onlinePlaylist(
        source: source,
        playlistId: playlistId,
        page: page,
      );
      if (generation != _generation) return;
      final pages = Map<int, OnlinePlaylistPage>.from(state.pages)
        ..[result.page] = result;
      state = state.copyWith(
        playlist: _mergePlaylist(result.playlist),
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

  CatalogCollection _mergePlaylist(CatalogCollection details) {
    final seed = state.playlist ?? initialPlaylist;
    if (seed == null) return details;
    return CatalogCollection(
      id: details.id,
      kind: details.kind,
      name: details.name.isNotEmpty ? details.name : seed.name,
      source: details.source,
      author: seed.author.isNotEmpty ? seed.author : details.author,
      total: details.total ?? seed.total,
      imageUrl: details.imageUrl ?? seed.imageUrl,
      description: details.description ?? seed.description,
      playCount: details.playCount ?? seed.playCount,
    );
  }

  List<Track> _orderedTracks(Map<int, OnlinePlaylistPage> pages) {
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
    if (state.pages.isEmpty) await load();
    while (state.hasMore && !_cancelImport) {
      final nextPage = state.pages.keys.reduce((a, b) => a > b ? a : b) + 1;
      await loadPage(nextPage);
      if (state.failedPage == nextPage) return;
    }
  }

  Future<void> importAll(String targetPlaylistId) async {
    if (state.importing) return;
    if (_importTarget != targetPlaylistId) {
      _importTarget = targetPlaylistId;
      _confirmedImports.clear();
    }
    _cancelImport = false;
    state = state.copyWith(
      importing: true,
      importProgress: PlaylistImportProgress(
        fetched: state.tracks.length,
        added: _confirmedImports.length,
        skipped: 0,
        failed: 0,
        completed: false,
        cancelled: false,
      ),
    );
    notifyListeners();

    await loadAllPages();
    if (_cancelImport) {
      _finishCancelled();
      return;
    }
    if (state.failedPage != null) {
      state = state.copyWith(
        importing: false,
        importProgress: PlaylistImportProgress(
          fetched: state.tracks.length,
          added: _confirmedImports.length,
          skipped: 0,
          failed: state.tracks.length - _confirmedImports.length,
          completed: false,
          cancelled: false,
        ),
      );
      notifyListeners();
      return;
    }

    final pending = state.tracks
        .where((track) => !_confirmedImports.contains((track.source, track.id)))
        .toList(growable: false);
    var offset = 0;
    try {
      while (offset < pending.length) {
        if (_cancelImport) {
          _finishCancelled();
          return;
        }
        final end = (offset + 100).clamp(0, pending.length);
        final batch = pending.sublist(offset, end);
        await playlists.addTracks(targetPlaylistId, batch);
        for (final track in batch) {
          _confirmedImports.add((track.source, track.id));
        }
        offset = end;
        state = state.copyWith(
          importProgress: PlaylistImportProgress(
            fetched: state.tracks.length,
            added: _confirmedImports.length,
            skipped: 0,
            failed: 0,
            completed: false,
            cancelled: false,
          ),
        );
        notifyListeners();
      }
      state = state.copyWith(
        importing: false,
        importProgress: PlaylistImportProgress(
          fetched: state.tracks.length,
          added: _confirmedImports.length,
          skipped: state.tracks.length - _confirmedImports.length,
          failed: 0,
          completed: true,
          cancelled: false,
        ),
      );
    } on Object catch (error) {
      state = state.copyWith(
        importing: false,
        error: error,
        importProgress: PlaylistImportProgress(
          fetched: state.tracks.length,
          added: _confirmedImports.length,
          skipped: 0,
          failed: state.tracks.length - _confirmedImports.length,
          completed: false,
          cancelled: false,
        ),
      );
    }
    notifyListeners();
  }

  void cancelImport() {
    _cancelImport = true;
  }

  void _finishCancelled() {
    state = state.copyWith(
      importing: false,
      importProgress: PlaylistImportProgress(
        fetched: state.tracks.length,
        added: _confirmedImports.length,
        skipped: 0,
        failed: 0,
        completed: false,
        cancelled: true,
      ),
    );
    notifyListeners();
  }
}
