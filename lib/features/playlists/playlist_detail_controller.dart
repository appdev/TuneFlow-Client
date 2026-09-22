import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../design/components/track_actions.dart';
import 'playlist_repository.dart';

enum PlaylistSort { original, title, artist, album }

final class PlaylistDetailState {
  const PlaylistDetailState({
    this.detail,
    this.loading = false,
    this.stale = false,
    this.error,
  });

  final PlaylistDetail? detail;
  final bool loading;
  final bool stale;
  final Object? error;
}

final class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController(this.repository, this.playlistId);

  final PlaylistRepository repository;
  final String playlistId;
  PlaylistDetailState state = const PlaylistDetailState();
  String query = '';
  PlaylistSort sort = PlaylistSort.original;
  bool selecting = false;
  final Set<(String, String)> selected = {};
  int? _selectionAnchor;

  bool get filtered => query.isNotEmpty || sort != PlaylistSort.original;
  List<Track> get visibleTracks {
    final needle = query.trim().toLowerCase();
    final tracks = [...?state.detail?.tracks]
        .where(
          (track) =>
              '${track.title} ${track.artist} ${track.raw['albumName'] ?? ''}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
    if (sort != PlaylistSort.original) {
      String field(Track t) => switch (sort) {
        PlaylistSort.title => t.title,
        PlaylistSort.artist => t.artist,
        PlaylistSort.album => t.raw['albumName']?.toString() ?? '',
        PlaylistSort.original => '',
      };
      final original = {for (var i = 0; i < tracks.length; i++) tracks[i]: i};
      tracks.sort((a, b) {
        final order = naturalTrackCompare(field(a), field(b));
        return order == 0 ? original[a]!.compareTo(original[b]!) : order;
      });
    }
    return tracks;
  }

  void setQuery(String value) {
    query = value;
    _selectionAnchor = null;
    notifyListeners();
  }

  void setSort(PlaylistSort value) {
    sort = value;
    _selectionAnchor = null;
    notifyListeners();
  }

  void setSelecting(bool value) {
    selecting = value;
    if (!value) selected.clear();
    _selectionAnchor = null;
    notifyListeners();
  }

  void toggleSelection(Track track, {bool range = false}) {
    final visible = visibleTracks;
    final index = visible.indexWhere(
      (t) => t.id == track.id && t.source == track.source,
    );
    if (range && _selectionAnchor != null && index >= 0) {
      final first = index < _selectionAnchor! ? index : _selectionAnchor!;
      final last = index > _selectionAnchor! ? index : _selectionAnchor!;
      for (final item in visible.skip(first).take(last - first + 1)) {
        selected.add((item.source, item.id));
      }
    } else if (!selected.add((track.source, track.id))) {
      selected.remove((track.source, track.id));
    }
    _selectionAnchor = index < 0 ? null : index;
    notifyListeners();
  }

  void selectAllVisible() {
    final keys = visibleTracks.map((t) => (t.source, t.id)).toSet();
    if (keys.every(selected.contains)) {
      selected.removeAll(keys);
    } else {
      selected.addAll(keys);
    }
    notifyListeners();
  }

  List<Track> get selectedTracks => [
    for (final t in state.detail?.tracks ?? <Track>[])
      if (selected.contains((t.source, t.id))) t,
  ];

  Future<void> removeSelected() async {
    final tracks = selectedTracks;
    if (tracks.isEmpty) return;
    final ids = tracks.map((t) => t.id).toSet();
    if (state.detail!.tracks.any(
      (t) => ids.contains(t.id) && !selected.contains((t.source, t.id)),
    )) {
      throw StateError('当前接口无法区分同 ID 的不同音源，请同时选择后再移除。');
    }
    await repository.removeTracks(playlistId, ids.toList());
    selected.removeAll(tracks.map((t) => (t.source, t.id)));
    await refresh();
  }

  Future<void> addSelectedTo(String targetId) async {
    final tracks = selectedTracks;
    if (tracks.isEmpty) return;
    await repository.addTracks(targetId, tracks);
    selected.removeAll(tracks.map((t) => (t.source, t.id)));
    notifyListeners();
  }

  Future<void> refresh() async {
    state = PlaylistDetailState(
      detail: state.detail,
      loading: true,
      stale: state.stale,
      error: state.error,
    );
    notifyListeners();
    try {
      final detail = await repository.get(playlistId);
      state = PlaylistDetailState(detail: detail);
      final keys = detail.tracks.map((t) => (t.source, t.id)).toSet();
      selected.removeWhere((key) => !keys.contains(key));
      _selectionAnchor = null;
    } on Object catch (error) {
      state = PlaylistDetailState(
        detail: state.detail,
        stale: true,
        error: error,
      );
    }
    notifyListeners();
  }

  Future<void> remove(String trackId) async {
    await repository.removeTracks(playlistId, [trackId]);
    await refresh();
  }

  Future<void> rename(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    await repository.update(playlistId, normalized);
    await refresh();
  }

  Future<void> delete() => repository.delete(playlistId);

  Future<List<PlaylistSummary>> moveTargets() async => (await repository.list())
      .where((playlist) => playlist.id != playlistId)
      .toList(growable: false);

  Future<void> move(Track track, String targetId) async {
    await repository.moveTracks(
      fromId: playlistId,
      toId: targetId,
      tracks: [track],
    );
    await refresh();
  }

  Future<void> clear() async {
    await repository.clearTracks(playlistId);
    await refresh();
  }

  Future<void> reorder({
    required int position,
    required List<String> trackIds,
  }) async {
    await repository.reorderTracks(playlistId, position, trackIds);
    await refresh();
  }

  Future<void> playOne(PlayTracks play, int index) async {
    final detail = state.detail;
    if (detail == null || index < 0 || index >= detail.tracks.length) return;
    await play(detail.tracks, startIndex: index);
  }

  Future<void> playAll(PlayTracks play) async {
    final tracks = state.detail?.tracks ?? const <Track>[];
    if (tracks.isNotEmpty) await play(tracks);
  }

  void invalidate() {
    state = PlaylistDetailState(
      detail: state.detail,
      stale: true,
      error: state.error,
    );
    notifyListeners();
  }
}

int naturalTrackCompare(String a, String b) {
  final pattern = RegExp(r'\d+|\D+');
  final left = pattern.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = pattern.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final numberA = BigInt.tryParse(left[i]);
    final numberB = BigInt.tryParse(right[i]);
    final order = numberA != null && numberB != null
        ? numberA.compareTo(numberB)
        : left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}
