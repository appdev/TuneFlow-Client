import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../downloads/download_repository.dart';
import '../library/library_repository.dart';
import '../playback_history/playback_history_repository.dart';
import '../playlists/playlist_repository.dart';

List<Track> _uniqueTracks(Iterable<Track> tracks) {
  final seen = <String>{};
  return List.unmodifiable(
    tracks.where((track) => seen.add('${track.source}:${track.id}')),
  );
}

Iterable<Track> _withCurrentLibraryTracks(
  Iterable<Track> tracks,
  Iterable<LibraryTrack> library,
) {
  final libraryByTrack = {
    for (final item in library)
      '${item.track.source}:${item.track.id}': item.track,
  };
  return tracks.map(
    (track) => libraryByTrack['${track.source}:${track.id}'] ?? track,
  );
}

final class HomeState {
  const HomeState({
    this.playlists = const [],
    this.downloads = const [],
    this.loading = false,
    this.stale = false,
    this.error,
    this.library = const [],
    this.continueListening = const [],
    this.lastSyncedAt,
  });

  final List<PlaylistSummary> playlists;
  final List<DownloadJob> downloads;
  final bool loading;
  final bool stale;
  final Object? error;
  final List<LibraryTrack> library;
  final List<Track> continueListening;
  final DateTime? lastSyncedAt;
  List<Track> get recentlyArrived {
    final completed =
        downloads
            .where((job) => job.status == DownloadStatus.completed)
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return completed.map((job) => job.musicInfo).toList(growable: false);
  }

  List<Track> get featured {
    final seen = <String>{};
    final tracks = <Track>[];
    for (final track in [
      ...continueListening,
      ...recentlyArrived,
      ...library.map((item) => item.track),
    ]) {
      if (seen.add('${track.source}:${track.id}')) tracks.add(track);
      if (tracks.length == 6) break;
    }
    return tracks;
  }

  num get libraryBytes =>
      library.fold<num>(0, (total, track) => total + track.size);
}

final class HomeController extends ChangeNotifier {
  HomeController({
    required this.playlists,
    required this.downloads,
    required this.library,
    this.history,
  });

  final PlaylistRepository playlists;
  final DownloadRepository downloads;
  final LibraryRepository library;
  final PlaybackHistoryRepository? history;
  HomeState state = const HomeState();

  Future<void> refresh() async {
    state = HomeState(
      playlists: state.playlists,
      downloads: state.downloads,
      loading: true,
      stale: state.stale,
      error: state.error,
      library: state.library,
      continueListening: state.continueListening,
      lastSyncedAt: state.lastSyncedAt,
    );
    notifyListeners();

    List<PlaylistSummary>? nextPlaylists;
    List<DownloadJob>? nextDownloads;
    List<LibraryTrack>? nextLibrary;
    List<PlaybackHistoryEntry>? nextHistory;
    Object? firstError;
    Future<void> loadPlaylists() async {
      try {
        final summaries = await playlists.list();
        nextPlaylists = await Future.wait(
          summaries.map<Future<PlaylistSummary>>((summary) async {
            try {
              return await playlists.get(summary.id);
            } on Object {
              return summary;
            }
          }),
        );
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    Future<void> loadDownloads() async {
      try {
        nextDownloads = await downloads.list();
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    Future<void> loadLibrary() async {
      try {
        nextLibrary = await library.list();
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    Future<void> loadHistory() async {
      final repository = history;
      if (repository == null) return;
      try {
        nextHistory = await repository.readPlaybackHistory();
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    await Future.wait([
      loadPlaylists(),
      loadDownloads(),
      loadLibrary(),
      loadHistory(),
    ]);

    final currentLibrary = nextLibrary ?? state.library;
    state = HomeState(
      playlists: nextPlaylists ?? state.playlists,
      downloads: nextDownloads ?? state.downloads,
      library: currentLibrary,
      continueListening: nextHistory == null
          ? state.continueListening
          : _uniqueTracks(
              _withCurrentLibraryTracks(
                nextHistory!.map((item) => item.track),
                currentLibrary,
              ),
            ),
      lastSyncedAt: firstError == null ? DateTime.now() : state.lastSyncedAt,
      stale: firstError != null,
      error: firstError,
    );
    notifyListeners();
  }
}
