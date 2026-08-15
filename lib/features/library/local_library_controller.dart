import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../design/components/track_actions.dart';
import 'library_repository.dart';

final class LocalLibraryState {
  const LocalLibraryState({
    this.items = const [],
    this.loading = false,
    this.stale = false,
    this.error,
    this.deletingIds = const {},
  });

  final List<LibraryTrack> items;
  final bool loading;
  final bool stale;
  final Object? error;
  final Set<String> deletingIds;

  List<Track> get tracks =>
      items.map((item) => item.track).toList(growable: false);
}

final class LocalLibraryController extends ChangeNotifier {
  LocalLibraryController(this.repository);

  final LibraryRepository repository;
  bool _disposed = false;
  LocalLibraryState state = const LocalLibraryState();

  Future<void> refresh() async {
    if (_disposed) return;
    state = LocalLibraryState(
      items: state.items,
      loading: true,
      stale: state.stale,
      error: state.error,
      deletingIds: state.deletingIds,
    );
    notifyListeners();
    try {
      final items = await repository.list();
      if (_disposed) return;
      state = LocalLibraryState(items: items, deletingIds: state.deletingIds);
    } on Object catch (error) {
      if (_disposed) return;
      state = LocalLibraryState(
        items: state.items,
        stale: true,
        error: error,
        deletingIds: state.deletingIds,
      );
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    if (state.deletingIds.contains(id)) return;
    state = LocalLibraryState(
      items: state.items,
      loading: state.loading,
      stale: state.stale,
      error: state.error,
      deletingIds: {...state.deletingIds, id},
    );
    notifyListeners();
    try {
      await repository.delete(id);
      state = LocalLibraryState(
        items: state.items
            .where((item) => item.id != id)
            .toList(growable: false),
        loading: state.loading,
        stale: state.stale,
        error: state.error,
        deletingIds: {...state.deletingIds}..remove(id),
      );
      notifyListeners();
    } on Object {
      state = LocalLibraryState(
        items: state.items,
        loading: state.loading,
        stale: state.stale,
        error: state.error,
        deletingIds: {...state.deletingIds}..remove(id),
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playOne(PlayTracks play, int index) async {
    final tracks = state.tracks;
    if (index < 0 || index >= tracks.length) return;
    await play(tracks, startIndex: index);
  }

  Future<void> playAll(PlayTracks play) async {
    final tracks = state.tracks;
    if (tracks.isNotEmpty) await play(tracks);
  }

  Future<Uri?> loadPicture(Track track) async {
    final uri = Uri.tryParse(track.raw['pic'] as String? ?? '');
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? uri
        : null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
