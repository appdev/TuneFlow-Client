import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/platform/macos_menu_bar.dart';
import 'package:musicfree_service_client/platform/macos_menu_bar_coordinator.dart';

void main() {
  test('publishes idle state without a player', () async {
    final menuBar = _FakeMenuBarPort();
    final coordinator = MacOSMenuBarCoordinator(
      player: null,
      favorites: null,
      menuBar: menuBar,
      reportFailure: (_, _) {},
      revealPendingMessages: () {},
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();

    expect(menuBar.states, [MacOSMenuBarSnapshot.idle]);
  });

  test('publishes track controls and ignores position-only changes', () async {
    final fixture = _PlayerFixture();
    final menuBar = _FakeMenuBarPort();
    final favorites = _FakeFavorites()..containsResult = false;
    final coordinator = MacOSMenuBarCoordinator(
      player: fixture.player,
      favorites: favorites,
      menuBar: menuBar,
      reportFailure: (_, _) {},
      revealPendingMessages: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(fixture.dispose);
    await coordinator.start();

    await fixture.player.playTracks([_track('a'), _track('b')]);
    fixture.audio.emit(
      const AudioSnapshot(
        playing: true,
        processing: PlayerProcessing.ready,
        duration: Duration(minutes: 3),
      ),
    );
    await _flush();
    final ready = menuBar.states.last;

    expect(ready.trackId, 'a');
    expect(ready.source, 'kw');
    expect(ready.playing, isTrue);
    expect(ready.canGoPrevious, isFalse);
    expect(ready.canGoNext, isTrue);
    expect(ready.canPlayPause, isTrue);

    final count = menuBar.states.length;
    fixture.audio.emit(
      const AudioSnapshot(
        playing: true,
        processing: PlayerProcessing.ready,
        position: Duration(seconds: 10),
        duration: Duration(minutes: 3),
      ),
    );
    await _flush();

    expect(menuBar.states, hasLength(count));
  });

  test('routes play pause and lifecycle commands', () async {
    final fixture = _PlayerFixture();
    final menuBar = _FakeMenuBarPort();
    var revealed = 0;
    var hidden = 0;
    final coordinator = MacOSMenuBarCoordinator(
      player: fixture.player,
      favorites: _FakeFavorites()..containsResult = false,
      menuBar: menuBar,
      reportFailure: (_, _) {},
      revealPendingMessages: () => revealed++,
      hidePendingMessages: () => hidden++,
    );
    addTearDown(coordinator.dispose);
    addTearDown(fixture.dispose);
    await coordinator.start();
    await fixture.player.play(_track('a'));
    fixture.audio.emit(
      const AudioSnapshot(playing: true, processing: PlayerProcessing.ready),
    );
    await _flush();

    menuBar.emitCommand(MacOSMenuBarCommand.playPause);
    menuBar.emitCommand(MacOSMenuBarCommand.showWindow);
    menuBar.emitCommand(MacOSMenuBarCommand.applicationActivated);
    menuBar.emitCommand(MacOSMenuBarCommand.windowHidden);
    menuBar.emitCommand(MacOSMenuBarCommand.quit);
    await _flush();

    expect(fixture.audio.pauseCalls, 1);
    expect(menuBar.showWindowCalls, 1);
    expect(menuBar.terminateCalls, 1);
    expect(revealed, 1);
    expect(hidden, 1);
  });

  test('favorite update is optimistic and rolls back after failure', () async {
    final fixture = _PlayerFixture();
    final menuBar = _FakeMenuBarPort();
    final favorites = _FakeFavorites()
      ..containsResult = false
      ..setError = StateError('offline');
    final failures = <String>[];
    final coordinator = MacOSMenuBarCoordinator(
      player: fixture.player,
      favorites: favorites,
      menuBar: menuBar,
      reportFailure: (title, message) => failures.add('$title:$message'),
      revealPendingMessages: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(fixture.dispose);
    await coordinator.start();
    await fixture.player.play(_track('a'));
    fixture.audio.emit(const AudioSnapshot(processing: PlayerProcessing.ready));
    await _flush();

    menuBar.emitCommand(MacOSMenuBarCommand.toggleFavorite);
    await _flush();

    expect(favorites.setCalls, ['kw:a:true']);
    expect(menuBar.states.any((state) => state.favoritePending), isTrue);
    expect(menuBar.states.last.favorite, isFalse);
    expect(menuBar.states.last.favoritePending, isFalse);
    expect(failures.single, contains('收藏失败'));
  });

  test('stale favorite lookup cannot overwrite a newer track', () async {
    final fixture = _PlayerFixture();
    final menuBar = _FakeMenuBarPort();
    final favorites = _DeferredFavorites();
    final coordinator = MacOSMenuBarCoordinator(
      player: fixture.player,
      favorites: favorites,
      menuBar: menuBar,
      reportFailure: (_, _) {},
      revealPendingMessages: () {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(fixture.dispose);
    await coordinator.start();
    await fixture.player.playTracks([_track('a'), _track('b')]);
    await _flush();
    await fixture.player.playIndex(1);
    await _flush();

    favorites.requests[1].complete(false);
    await _flush();
    favorites.requests[0].complete(true);
    await _flush();

    expect(menuBar.states.last.trackId, 'b');
    expect(menuBar.states.last.favorite, isFalse);
  });

  test('love playlist adapter matches source and id and writes love', () async {
    final requests = <http.Request>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _data({
            'id': 'love',
            'name': 'love',
            'tracks': [
              {'id': 'same', 'source': 'wy', 'name': 'WY'},
            ],
          });
        }
        return _data(<Object?>[]);
      }),
    );
    final favorites = LovePlaylistFavorites(PlaylistRepository(api));
    final kw = _track('same');

    expect(await favorites.contains(kw), isFalse);
    await favorites.setFavorite(kw, true);
    await favorites.setFavorite(kw, false);

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/v1/playlists/love',
      'POST /api/v1/playlists/love/tracks',
      'POST /api/v1/playlists/love/tracks/remove',
    ]);
  });
}

Track _track(String id) =>
    Track.fromJson({'id': id, 'source': 'kw', 'name': 'Song $id'});

http.Response _data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _PlayerFixture {
  _PlayerFixture()
    : player = PlayerController(resolver: _Resolver(), audio: _Audio());

  late final PlayerController player;
  _Audio get audio => player.audio as _Audio;

  Future<void> dispose() async {
    player.dispose();
    await audio.controller.close();
  }
}

final class _Resolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: const ResolvedTrack(
          url: '/stream',
          quality: '128k',
          expiresAt: 1000,
        ),
        streamUri: Uri.parse('http://service.local/${track.id}'),
      );
}

final class _Audio implements AudioPort {
  final controller = StreamController<AudioSnapshot>.broadcast();
  int pauseCalls = 0;
  int resumeCalls = 0;

  void emit(AudioSnapshot snapshot) => controller.add(snapshot);

  @override
  Stream<AudioSnapshot> get snapshots => controller.stream;

  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<bool> playCachedTrack(Track track, String quality) async => false;

  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {}

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stopPlayback() async {}
}

final class _FakeMenuBarPort implements MacOSMenuBarPort {
  final controller = StreamController<MacOSMenuBarCommand>.broadcast();
  final states = <MacOSMenuBarSnapshot>[];
  int showWindowCalls = 0;
  int terminateCalls = 0;

  void emitCommand(MacOSMenuBarCommand command) => controller.add(command);

  @override
  Stream<MacOSMenuBarCommand> get commands => controller.stream;

  @override
  Future<void> dispose() => controller.close();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showWindow() async => showWindowCalls++;

  @override
  Future<void> terminate() async => terminateCalls++;

  @override
  Future<void> updateState(MacOSMenuBarSnapshot state) async =>
      states.add(state);
}

class _FakeFavorites implements FavoritePlaylistPort {
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

final class _DeferredFavorites extends _FakeFavorites {
  final requests = <Completer<bool>>[];

  @override
  Future<bool> contains(Track track) {
    final request = Completer<bool>();
    requests.add(request);
    return request.future;
  }
}
