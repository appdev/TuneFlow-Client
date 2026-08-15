import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../library/library_repository.dart';
import 'playlist_repository.dart';

final class PlaylistsState {
  const PlaylistsState({
    this.items = const [],
    this.library = const [],
    this.loading = false,
    this.stale = false,
    this.playlistError,
    this.libraryError,
  });

  final List<PlaylistDetail> items;
  final List<LibraryTrack> library;
  final bool loading;
  final bool stale;
  final Object? playlistError;
  final Object? libraryError;
  Object? get error => playlistError ?? libraryError;
}

final class PlaylistsController extends ChangeNotifier {
  PlaylistsController(
    this.repository, {
    required this.library,
    String Function()? idFactory,
  }) : _idFactory =
           idFactory ??
           (() => 'flutter_${DateTime.now().microsecondsSinceEpoch}');

  final PlaylistRepository repository;
  final LibraryRepository library;
  final String Function() _idFactory;
  bool _disposed = false;
  PlaylistsState state = const PlaylistsState();

  Future<void> refresh() async {
    if (_disposed) return;
    state = PlaylistsState(
      items: state.items,
      library: state.library,
      loading: true,
      stale: state.stale,
      playlistError: state.playlistError,
      libraryError: state.libraryError,
    );
    notifyListeners();

    List<PlaylistDetail>? nextItems;
    List<LibraryTrack>? nextLibrary;
    Object? playlistError;
    Object? libraryError;
    await Future.wait([
      () async {
        try {
          nextItems = await repository.listDetails();
        } on Object catch (error) {
          playlistError = error;
        }
      }(),
      () async {
        try {
          nextLibrary = await library.list();
        } on Object catch (error) {
          libraryError = error;
        }
      }(),
    ]);
    if (_disposed) return;

    state = PlaylistsState(
      items: nextItems ?? state.items,
      library: nextLibrary ?? state.library,
      stale: playlistError != null || libraryError != null,
      playlistError: playlistError,
      libraryError: libraryError,
    );
    notifyListeners();
  }

  Future<void> create({required String name}) async {
    await repository.create(id: _idFactory(), name: name);
    await refresh();
  }

  Future<void> delete(String id) async {
    await repository.delete(id);
    await refresh();
  }

  void invalidate() {
    state = PlaylistsState(
      items: state.items,
      library: state.library,
      stale: true,
      playlistError: state.playlistError,
      libraryError: state.libraryError,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
