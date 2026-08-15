import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/current_track_actions_controller.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/playlists/favorite_playlist.dart';

void main() {
  test('loads favorite state for the current track', () async {
    final player = await _playerWithTracks([_track('a')]);
    addTearDown(player.dispose);
    final favorites = _FakeFavorites()..containsResult = true;
    final actions = CurrentTrackActionsController(
      player: player,
      favorites: favorites,
      download: (_, _) async {},
    );
    addTearDown(actions.dispose);

    await _flushAsyncWork();

    expect(actions.track?.id, 'a');
    expect(actions.favoriteKnown, isTrue);
    expect(actions.favorite, isTrue);
    expect(actions.canToggleFavorite, isTrue);
  });

  test('ignores a stale favorite lookup after track changes', () async {
    final player = await _playerWithTracks([_track('a'), _track('b')]);
    addTearDown(player.dispose);
    final favorites = _DeferredFavorites();
    final actions = CurrentTrackActionsController(
      player: player,
      favorites: favorites,
      download: (_, _) async {},
    );
    addTearDown(actions.dispose);

    await player.next();
    favorites.complete('kw:b', true);
    favorites.complete('kw:a', false);
    await _flushAsyncWork();

    expect(actions.track?.id, 'b');
    expect(actions.favoriteKnown, isTrue);
    expect(actions.favorite, isTrue);
  });

  test('optimistically toggles favorite and rolls back on failure', () async {
    final player = await _playerWithTracks([_track('a')]);
    addTearDown(player.dispose);
    final favorites = _FakeFavorites()
      ..containsResult = false
      ..setError = StateError('favorite failed');
    final actions = CurrentTrackActionsController(
      player: player,
      favorites: favorites,
      download: (_, _) async {},
    );
    addTearDown(actions.dispose);
    await _flushAsyncWork();

    final pending = actions.toggleFavorite();
    expect(actions.favorite, isTrue);
    expect(actions.favoritePending, isTrue);
    await expectLater(pending, throwsStateError);

    expect(actions.favorite, isFalse);
    expect(actions.favoritePending, isFalse);
    expect(favorites.setCalls, ['kw:a:true']);
  });

  test('keeps a successful favorite toggle selected', () async {
    final player = await _playerWithTracks([_track('a')]);
    addTearDown(player.dispose);
    final favorites = _FakeFavorites()..containsResult = false;
    final actions = CurrentTrackActionsController(
      player: player,
      favorites: favorites,
      download: (_, _) async {},
    );
    addTearDown(actions.dispose);
    await _flushAsyncWork();

    await actions.toggleFavorite();

    expect(actions.favorite, isTrue);
    expect(actions.favoritePending, isFalse);
    expect(favorites.setCalls, ['kw:a:true']);
  });

  test('downloads once with the current player quality', () async {
    final player = await _playerWithTracks([_track('a')], quality: 'flac');
    addTearDown(player.dispose);
    final favorites = _FakeFavorites()..containsResult = false;
    final gate = Completer<void>();
    final calls = <String>[];
    final actions = CurrentTrackActionsController(
      player: player,
      favorites: favorites,
      download: (value, quality) async {
        calls.add('${value.source}:${value.id}:$quality');
        await gate.future;
      },
    );
    addTearDown(actions.dispose);

    final first = actions.downloadCurrent();
    final second = actions.downloadCurrent();
    expect(actions.downloadPending, isTrue);
    expect(calls, ['kw:a:flac']);

    gate.complete();
    await Future.wait([first, second]);

    expect(actions.downloadPending, isFalse);
    expect(actions.canDownload, isTrue);
  });
}

Track _track(String id) =>
    Track.fromJson({'id': id, 'name': id, 'source': 'kw'});

Future<PlayerController> _playerWithTracks(
  List<Track> tracks, {
  String quality = '128k',
}) async {
  final player = PlayerController(
    resolver: _FakeResolver(),
    audio: _FakeAudio(),
    quality: quality,
  );
  await player.playTracks(tracks);
  return player;
}

Future<void> _flushAsyncWork() => Future<void>.delayed(Duration.zero);

final class _FakeResolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: ResolvedTrack(
          url: '/api/v1/streams/${track.id}',
          quality: quality,
          expiresAt: 1,
        ),
        streamUri: Uri.parse('http://service.local/api/v1/streams/${track.id}'),
      );
}

final class _FakeAudio implements AudioPort {
  @override
  Stream<AudioSnapshot> get snapshots => Stream.value(
    const AudioSnapshot(
      playing: true,
      processing: PlayerProcessing.ready,
      duration: Duration(minutes: 3),
    ),
  );

  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}

  @override
  Future<void> pause() async {}

  @override
  Future<bool> playCachedTrack(Track track, String quality) async => false;

  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stopPlayback() async {}
}

final class _FakeFavorites implements FavoritePlaylistPort {
  bool containsResult = false;
  Object? setError;
  final setCalls = <String>[];

  @override
  Future<bool> contains(Track track) async => containsResult;

  @override
  Future<void> setFavorite(Track track, bool favorite) async {
    setCalls.add('${track.source}:${track.id}:$favorite');
    if (setError case final error?) throw error;
  }
}

final class _DeferredFavorites implements FavoritePlaylistPort {
  final _requests = <String, Completer<bool>>{};

  @override
  Future<bool> contains(Track track) {
    final identity = '${track.source}:${track.id}';
    return (_requests[identity] ??= Completer<bool>()).future;
  }

  void complete(String identity, bool value) =>
      _requests[identity]!.complete(value);

  @override
  Future<void> setFavorite(Track track, bool favorite) async {}
}
