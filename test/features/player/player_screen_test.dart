import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/user_download_coordinator.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/artwork_palette_controller.dart';
import 'package:musicfree_service_client/features/player/current_track_actions_controller.dart';
import 'package:musicfree_service_client/features/player/mini_player.dart';
import 'package:musicfree_service_client/features/player/lyrics_view.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_screen.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/player/wake_lock_port.dart';
import 'package:musicfree_service_client/features/playlists/favorite_playlist.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

final class FakeResolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: const ResolvedTrack(
          url: '/api/v1/streams/token',
          quality: '128k',
          expiresAt: 1,
        ),
        streamUri: Uri.parse('http://service.local/api/v1/streams/token'),
      );
}

final class FakeAudio implements AudioPort {
  int stopPlaybackCalls = 0;
  Object? stopPlaybackError;

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
  Future<void> stopPlayback() async {
    stopPlaybackCalls++;
    if (stopPlaybackError case final error?) throw error;
  }
}

final class SnapshotAudio implements AudioPort {
  final snapshotsController = StreamController<AudioSnapshot>.broadcast();
  Object? nextPlayError;
  int pauseCalls = 0;
  int playCalls = 0;
  int resumeCalls = 0;

  void emit(AudioSnapshot snapshot) => snapshotsController.add(snapshot);

  @override
  Stream<AudioSnapshot> get snapshots => snapshotsController.stream;
  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}
  @override
  Future<void> pause() async => pauseCalls += 1;
  @override
  Future<bool> playCachedTrack(Track track, String quality) async => false;
  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {
    playCalls += 1;
    final error = nextPlayError;
    nextPlayError = null;
    if (error != null) throw error;
  }

  @override
  Future<void> resume() async => resumeCalls += 1;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stopPlayback() async {}

  Future<void> close() => snapshotsController.close();
}

final class FakeWakeLock implements WakeLockPort {
  final values = <bool>[];
  @override
  Future<void> setEnabled(bool value) async => values.add(value);
}

final class FakeFavorites implements FavoritePlaylistPort {
  FakeFavorites({this.containsResult = false});

  bool containsResult;
  final setCalls = <String>[];

  @override
  Future<bool> contains(Track track) async => containsResult;

  @override
  Future<void> setFavorite(Track track, bool favorite) async {
    setCalls.add('${track.source}:${track.id}:$favorite');
    containsResult = favorite;
  }
}

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

Future<void> pumpFiniteAnimations(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

({PlaylistRepository playlists, DownloadRepository downloads})
playerActionRepositories(Future<http.Response> Function(http.Request) handler) {
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  );
  return (
    playlists: PlaylistRepository(api),
    downloads: DownloadRepository(api),
  );
}

Future<PlayerController> pumpMobileActionPlayer(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repositories = playerActionRepositories(handler);
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  await controller.playTracks([
    Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
  ]);
  final actions = CurrentTrackActionsController(
    player: controller,
    favorites: FakeFavorites(),
    download: (track, quality, {required confirmReplacement}) =>
        UserDownloadCoordinator(
          repositories.downloads,
        ).create(track, quality, confirmReplacement: confirmReplacement),
  );
  addTearDown(actions.dispose);
  await tester.pumpWidget(
    harness(
      PlayerScreen(
        controller: controller,
        lyricsLoader: (_) async => const Lyrics(original: ''),
        wakeLock: FakeWakeLock(),
        keepAwake: false,
        playlists: repositories.playlists,
        actions: actions,
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('mobile player groups current-track choices in the ActionSheet', (
    tester,
  ) async {
    await pumpMobileActionPlayer(
      tester,
      (_) async => http.Response(jsonEncode({'data': <Object?>[]}), 200),
    );

    expect(find.byKey(const Key('mobile-full-favorite')), findsNothing);
    expect(find.byKey(const Key('mobile-full-download')), findsNothing);
    expect(find.bySemanticsLabel('更多操作'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-mobile-more')));
    await pumpFiniteAnimations(tester);

    expect(find.byKey(const Key('track-action-addToPlaylist')), findsOneWidget);
    expect(find.byKey(const Key('track-action-favorite')), findsOneWidget);
    expect(find.byKey(const Key('track-action-download')), findsOneWidget);
    expect(find.byKey(const Key('track-action-enqueue')), findsNothing);
    expect(find.text('One'), findsWidgets);
    expect(find.text('128k'), findsWidgets);
    expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
  });

  testWidgets('mobile player adds the current track to a selected playlist', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pumpMobileActionPlayer(tester, (request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'daily', 'name': '每日收藏'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'one', 'name': 'One', 'source': 'kw'},
          ],
        }),
        200,
      );
    });

    await tester.tap(find.byKey(const Key('player-mobile-more')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('track-action-addToPlaylist')));
    await pumpFiniteAnimations(tester);
    expect(requests.map((request) => request.method), contains('GET'));
    expect(find.byKey(const Key('track-action-addToPlaylist')), findsNothing);
    expect(find.byKey(const Key('player-mobile-layout')), findsOneWidget);
    expect(find.text('每日收藏'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-playlist-daily')));
    await pumpFiniteAnimations(tester);

    final post = requests.singleWhere((request) => request.method == 'POST');
    expect(post.url.path, '/api/v1/playlists/daily/tracks');
    final body = jsonDecode(post.body) as Map<String, Object?>;
    final tracks = body['tracks']! as List<Object?>;
    expect((tracks.single as Map<String, Object?>)['id'], 'one');
    expect(find.text('已添加到 每日收藏'), findsOneWidget);
  });

  testWidgets('mobile player downloads the current track at default quality', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pumpMobileActionPlayer(tester, (request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'download-one',
            'status': 'waiting',
            'musicInfo': {'id': 'one', 'name': 'One', 'source': 'kw'},
            'quality': '128k',
            'extension': 'mp3',
            'fileName': 'one.mp3',
            'downloaded': 0,
            'total': 0,
            'progress': 0,
            'queuePosition': 1,
            'createdAt': 1000,
            'updatedAt': 1000,
          },
        }),
        201,
      );
    });

    await tester.tap(find.byKey(const Key('player-mobile-more')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('track-action-download')));
    await pumpFiniteAnimations(tester);

    final request = requests.single;
    expect(request.url.path, '/api/v1/downloads');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect((body['musicInfo']! as Map<String, Object?>)['id'], 'one');
    expect(body['quality'], '128k');
    expect(body['existingFilePolicy'], 'error');
    expect(find.text('已加入下载队列'), findsOneWidget);
  });

  testWidgets('mobile player confirms before replacing an existing download', (
    tester,
  ) async {
    final policies = <String?>[];
    await pumpMobileActionPlayer(tester, (request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final policy = body['existingFilePolicy'] as String?;
      policies.add(policy);
      if (policy == 'error') {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'DOWNLOAD_ALREADY_EXISTS',
              'message': 'already exists',
            },
          }),
          409,
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'replacement-one',
            'status': 'waiting',
            'musicInfo': {'id': 'one', 'name': 'One', 'source': 'kw'},
            'quality': '128k',
            'extension': 'mp3',
            'fileName': 'one.mp3',
            'downloaded': 0,
            'total': 0,
            'progress': 0,
            'queuePosition': 1,
            'createdAt': 1000,
            'updatedAt': 1000,
          },
        }),
        201,
      );
    });

    await tester.tap(find.byKey(const Key('player-mobile-more')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('track-action-download')));
    await pumpFiniteAnimations(tester);

    expect(find.text('重新下载成功后将替换现有文件。'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await pumpFiniteAnimations(tester);

    expect(policies, ['error', 'replace']);
    expect(find.text('已加入重新下载队列'), findsOneWidget);
  });

  testWidgets('failed mobile player action preserves the current track', (
    tester,
  ) async {
    final controller = await pumpMobileActionPlayer(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'DOWNLOAD_FAILED', 'message': 'failed'},
        }),
        500,
      ),
    );

    await tester.tap(find.byKey(const Key('player-mobile-more')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('track-action-download')));
    await pumpFiniteAnimations(tester);

    expect(find.text('下载失败'), findsOneWidget);
    expect(controller.state.current?.id, 'one');
  });

  testWidgets('mini player is hidden without a queue and opens when visible', (
    tester,
  ) async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    var opened = false;
    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () => opened = true,
          variant: MiniPlayerVariant.mobile,
        ),
      ),
    );
    expect(find.byKey(const Key('mini-player')), findsNothing);

    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('mobile-mini-player'))).height,
      60,
    );
    expect(find.byKey(const Key('mobile-player-next')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('mobile-player-next'))),
      const Size.square(44),
    );
    expect(find.byKey(const Key('mobile-full-favorite')), findsNothing);
    expect(find.byKey(const Key('mobile-full-download')), findsNothing);
    await tester.tap(find.byKey(const Key('mini-player')));

    expect(opened, isTrue);
  });

  testWidgets('desktop player exposes the persistent transport surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    var opened = false;
    await controller.playTracks([
      Track.fromJson({
        'id': 'desktop',
        'name': 'Desktop track',
        'source': 'kw',
      }),
    ]);
    final favorites = FakeFavorites();
    final actions = CurrentTrackActionsController(
      player: controller,
      favorites: favorites,
      download: (_, _, {required confirmReplacement}) async =>
          const UserDownloadResult(replaced: false),
    );
    addTearDown(actions.dispose);

    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () => opened = true,
          variant: MiniPlayerVariant.desktop,
          actions: actions,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('desktop-persistent-player')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('desktop-persistent-player'))).height,
      96,
    );
    final shell = tester.widget<Material>(
      find.byKey(const Key('desktop-persistent-player')),
    );
    final shellSize = shell.child! as SizedBox;
    expect(shellSize.child, isA<Padding>());
    expect(
      tester.getSize(find.byKey(const Key('desktop-player-artwork'))),
      const Size.square(52),
    );
    expect(
      tester.getSize(find.byKey(const Key('desktop-play-pause'))),
      const Size.square(52),
    );
    for (final key in [
      'player-previous-mini',
      'player-next-mini',
      'desktop-quality',
      'desktop-lyrics',
      'desktop-queue',
      'desktop-mini-favorite',
      'desktop-mini-download',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
    expect(
      tester
          .widget<ShadButton>(find.byKey(const Key('desktop-quality')))
          .variant,
      ShadButtonVariant.ghost,
    );
    final playerRect = tester.getRect(
      find.byKey(const Key('desktop-persistent-player')),
    );
    await tester.tapAt(Offset(playerRect.center.dx, playerRect.top + 4));
    expect(opened, isTrue);

    opened = false;
    await tester.tap(find.byKey(const Key('player-previous-mini')));
    await tester.pump();
    expect(opened, isFalse);
    await tester.tap(find.byKey(const Key('desktop-play-pause')));
    await tester.pump();
    expect(opened, isFalse);
    await tester.tap(find.byKey(const Key('playback-progress-hit-area')));
    await tester.pump();
    expect(opened, isFalse);
    await tester.tap(find.byKey(const Key('desktop-mini-favorite')));
    await tester.pump();
    expect(opened, isFalse);
    expect(favorites.setCalls, ['kw:desktop:true']);

    await tester.tap(find.byKey(const Key('desktop-player-artwork')));
    expect(opened, isTrue);
    await tester.tap(find.byKey(const Key('desktop-lyrics')));
    expect(controller.state.view, PlayerView.lyrics);
    await tester.tap(find.byKey(const Key('desktop-queue')));
    expect(controller.state.view, PlayerView.queue);
    expect(find.byKey(const Key('player-previous-mini')), findsOneWidget);
    expect(find.byKey(const Key('player-next-mini')), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('desktop track surface opens without a pressed ink highlight', (
    tester,
  ) async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'quiet-tap', 'name': 'Quiet tap', 'source': 'kw'}),
    ]);
    var opened = false;

    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () => opened = true,
          variant: MiniPlayerVariant.desktop,
        ),
      ),
    );

    final trackSurface = find.byKey(const Key('desktop-track-surface'));
    expect(tester.widget(trackSurface), isNot(isA<InkWell>()));
    await tester.tap(trackSurface);
    expect(opened, isTrue);
  });

  testWidgets('desktop default artwork omits the fallback outline', (
    tester,
  ) async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({
        'id': 'borderless-cover',
        'name': 'Borderless cover',
        'source': 'kw',
      }),
    ]);

    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () {},
          variant: MiniPlayerVariant.desktop,
        ),
      ),
    );

    final artwork = tester.widget<AppArtwork>(
      find.byKey(const Key('desktop-player-artwork')),
    );
    expect(artwork.showFallbackBorder, isFalse);
  });

  testWidgets('desktop loading transport remains available for pause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = SnapshotAudio();
    addTearDown(audio.close);
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([
      Track.fromJson({'id': 'states', 'name': 'States', 'source': 'kw'}),
    ]);
    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () {},
          variant: MiniPlayerVariant.desktop,
        ),
      ),
    );

    expect(find.byKey(const Key('desktop-player-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-play-pause')));
    expect(audio.pauseCalls, 1);
    expect(audio.resumeCalls, 0);

    audio.emit(
      const AudioSnapshot(
        processing: PlayerProcessing.buffering,
        playing: true,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('desktop-player-loading')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-play-pause')));
    expect(audio.pauseCalls, 2);

    audio.emit(
      const AudioSnapshot(processing: PlayerProcessing.ready, playing: true),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);

    audio.emit(const AudioSnapshot(processing: PlayerProcessing.ready));
    await tester.pump();
    expect(find.bySemanticsLabel('播放'), findsOneWidget);

    audio.emit(const AudioSnapshot(processing: PlayerProcessing.completed));
    await tester.pump();
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
  });

  testWidgets('desktop player presents an error and retries playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = SnapshotAudio()..nextPlayError = StateError('network down');
    addTearDown(audio.close);
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([
      Track.fromJson({'id': 'retry', 'name': 'Retry', 'source': 'kw'}),
    ]);
    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () {},
          variant: MiniPlayerVariant.desktop,
        ),
      ),
    );

    expect(find.byKey(const Key('desktop-player-error')), findsOneWidget);
    expect(find.text('播放失败，点击重试'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('network down'), findsNothing);
    expect(find.bySemanticsLabel('重试播放'), findsOneWidget);
    expect(audio.playCalls, 1);

    await tester.tap(find.byKey(const Key('desktop-play-pause')));
    await tester.pump();

    expect(audio.playCalls, 2);
    expect(find.byKey(const Key('desktop-player-loading')), findsOneWidget);
  });

  testWidgets('full player exposes controls and scopes keep-awake to route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);
    final actions = CurrentTrackActionsController(
      player: controller,
      favorites: FakeFavorites(),
      download: (_, _, {required confirmReplacement}) async =>
          const UserDownloadResult(replaced: false),
    );
    addTearDown(actions.dispose);
    final wakeLock = FakeWakeLock();

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:00]line'),
          wakeLock: wakeLock,
          keepAwake: true,
          actions: actions,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('player-previous')), findsOneWidget);
    expect(find.byKey(const Key('player-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('player-next')), findsOneWidget);
    expect(find.byKey(const Key('player-wide-layout')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
    expect(
      find.byKey(const Key('player-desktop-vinyl-artwork')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-desktop-metadata')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-controls')), findsOneWidget);
    expect(find.byKey(const Key('desktop-full-favorite')), findsOneWidget);
    expect(find.byKey(const Key('desktop-full-download')), findsOneWidget);
    final favoriteRect = tester.getRect(
      find.byKey(const Key('desktop-full-favorite')),
    );
    final coreRect = tester.getRect(
      find.byKey(const Key('player-desktop-core')),
    );
    expect(favoriteRect.center.dx, lessThan(coreRect.left));
    expect(find.byKey(const Key('player-desktop-quality')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-queue')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('player-desktop-track-title'))).dx,
      closeTo(120, .1),
    );
    expect(find.byKey(const Key('player-view-artwork')), findsNothing);
    expect(find.byKey(const Key('player-view-lyrics')), findsNothing);
    expect(find.byKey(const Key('player-view-queue')), findsNothing);
    expect(find.bySemanticsLabel('One封面'), findsWidgets);
    expect(find.text('line'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    final lyricsHeight = tester
        .getSize(find.byKey(const Key('desktop-lyrics-viewport')))
        .height;
    expect(lyricsHeight, greaterThan(200));
    expect(lyricsHeight, lessThanOrEqualTo(360));
    expect(wakeLock.values, [true]);

    await tester.pumpWidget(harness(const SizedBox()));
    await tester.pump();
    expect(wakeLock.values, [true, false]);
  });

  testWidgets(
    'desktop player crops textured vinyl at the top right of the lyrics',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.playTracks([
        Track.fromJson({
          'id': 'evening',
          'name': '晚风',
          'singer': '伍佰 & China Blue',
          'albumName': '泪桥',
          'source': 'kw',
        }),
      ]);

      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async =>
                const Lyrics(original: '[00:00]慢慢吹，轻轻送\n[00:10]人生路，你就走'),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      await tester.pump();

      final orbit = find.byKey(const Key('player-desktop-orbit-vinyl'));
      final artwork = find.byKey(const Key('player-desktop-vinyl-artwork'));
      final spindle = find.byKey(const Key('player-desktop-vinyl-spindle'));
      expect(orbit, findsOneWidget);
      expect(
        find.byKey(const Key('player-desktop-vinyl-portal')),
        findsNothing,
      );
      expect(find.byKey(const Key('player-desktop-artwork')), findsNothing);

      final title = find.byKey(const Key('player-desktop-track-title'));
      final metadata = find.byKey(const Key('player-desktop-metadata'));
      final firstLyric = find.text('慢慢吹，轻轻送');
      expect(title, findsOneWidget);
      expect(metadata, findsOneWidget);
      expect(find.text('晚风'), findsOneWidget);
      expect(tester.getSize(orbit).width, greaterThan(800));
      expect(tester.getRect(orbit).top, lessThan(0));
      expect(tester.getRect(orbit).right, greaterThan(1440));
      expect(
        tester.getRect(orbit).left,
        greaterThan(tester.getRect(title).right),
      );
      expect(tester.getRect(artwork).center.dy, greaterThan(0));
      expect(tester.getRect(spindle).center, tester.getRect(artwork).center);
      expect(tester.getTopLeft(title).dx, closeTo(144, .1));
      expect(
        tester.getTopLeft(firstLyric).dx,
        closeTo(tester.getTopLeft(title).dx, .1),
      );
      expect(
        tester.getTopLeft(title).dy,
        lessThan(tester.getTopLeft(firstLyric).dy),
      );

      final titleBeforeScroll = tester.getTopLeft(title);
      await tester.drag(
        find.byKey(const ValueKey('lyrics-0')),
        const Offset(0, -80),
      );
      await tester.pump();
      expect(tester.getTopLeft(title), titleBeforeScroll);
    },
  );

  testWidgets(
    'desktop player scopes artwork accent and hides lyric scrollbar',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const source = AppArtworkSource.fallback(fallbackSeed: 'kw:themed');
      final paletteController = ArtworkPaletteController(
        loadBytes: (_) async => null,
      );
      addTearDown(paletteController.dispose);
      await paletteController.select(source, brightness: Brightness.light);
      final expected = fallbackArtworkPalette(
        source.fallbackSeed,
        brightness: Brightness.light,
      );
      final reported = <Color>[];
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.playTracks([
        Track.fromJson({'id': 'themed', 'name': 'Themed', 'source': 'kw'}),
      ]);
      final actions = CurrentTrackActionsController(
        player: controller,
        favorites: FakeFavorites(),
        download: (_, _, {required confirmReplacement}) async =>
            const UserDownloadResult(replaced: false),
      );
      addTearDown(actions.dispose);

      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async =>
                const Lyrics(original: '[00:00]first\n[00:10]second'),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
            paletteController: paletteController,
            onAccentChanged: reported.add,
            actions: actions,
          ),
        ),
      );
      await tester.pump();

      final localTheme = tester.widget<ShadAnimatedTheme>(
        find.byKey(const Key('player-local-shad-theme')),
      );
      expect(localTheme.data.colorScheme.primary, expected.vinylAccent);
      final slider = tester.widget<ShadSlider>(
        find.descendant(
          of: find.byKey(const Key('player-desktop-progress')),
          matching: find.byType(ShadSlider),
        ),
      );
      expect(slider.activeTrackColor, expected.vinylAccent);
      expect(slider.inactiveTrackColor, readableArtworkInactiveTrack(expected));
      final playMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const Key('player-play-pause')),
          matching: find.byType(Material),
        ),
      );
      expect(playMaterial.color, expected.vinylAccent);
      final playIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('player-play-pause')),
          matching: find.byType(Icon),
        ),
      );
      expect(playIcon.color, Colors.white);
      for (final key in ['desktop-full-favorite', 'desktop-full-download']) {
        expect(
          tester.widget<ShadButton>(find.byKey(Key(key))).foregroundColor,
          expected.vinylAccent,
        );
      }
      final scrollConfiguration = tester.widget<ScrollConfiguration>(
        find.byKey(const Key('lyrics-scroll-configuration')),
      );
      const scrollbarProbe = SizedBox();
      expect(
        scrollConfiguration.behavior.buildScrollbar(
          tester.element(find.byKey(const Key('lyrics-scroll-configuration'))),
          scrollbarProbe,
          const ScrollableDetails.vertical(),
        ),
        same(scrollbarProbe),
      );
      expect(reported, contains(expected.vinylAccent));
    },
  );

  testWidgets(
    'desktop player reuses its local theme for position-only snapshots',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const source = AppArtworkSource.fallback(fallbackSeed: 'kw:stable-theme');
      final paletteController = ArtworkPaletteController(
        loadBytes: (_) async => null,
      );
      addTearDown(paletteController.dispose);
      await paletteController.select(source, brightness: Brightness.light);
      final audio = SnapshotAudio();
      addTearDown(audio.close);
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
      );
      await controller.playTracks([
        Track.fromJson({
          'id': 'stable-theme',
          'name': 'Stable Theme',
          'source': 'kw',
        }),
      ]);

      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: '[00:00]line'),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
            paletteController: paletteController,
          ),
        ),
      );
      await tester.pump();
      final themeFinder = find.byKey(const Key('player-local-shad-theme'));
      final before = tester.widget<ShadAnimatedTheme>(themeFinder).data;

      audio.emit(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.ready,
          position: Duration(seconds: 1),
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pump();

      final after = tester.widget<ShadAnimatedTheme>(themeFinder).data;
      expect(after, same(before));
    },
  );

  testWidgets('desktop orbit vinyl stays clear of lyrics at 1024x768', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({
        'id': 'compact-portal',
        'name': '紧凑舷窗',
        'singer': '测试歌手',
        'source': 'kw',
      }),
    ]);

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async =>
              const Lyrics(original: '[00:00]第一句\n[00:10]第二句'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    final orbit = find.byKey(const Key('player-desktop-orbit-vinyl'));
    final artwork = find.byKey(const Key('player-desktop-vinyl-artwork'));
    final spindle = find.byKey(const Key('player-desktop-vinyl-spindle'));
    final title = find.byKey(const Key('player-desktop-track-title'));
    final lyrics = find.byKey(const Key('desktop-lyrics-viewport'));
    final controls = find.byKey(const Key('player-desktop-controls'));
    expect(orbit, findsOneWidget);
    expect(tester.getTopLeft(title).dx, closeTo(102.4, .1));
    expect(tester.getSize(orbit).width, greaterThan(600));
    expect(tester.getRect(orbit).top, lessThan(0));
    expect(tester.getRect(orbit).right, greaterThan(1024));
    expect(
      tester.getRect(orbit).left,
      greaterThan(tester.getRect(title).right),
    );
    expect(
      tester.getRect(orbit).left,
      greaterThan(tester.getRect(lyrics).right),
    );
    expect(tester.getRect(orbit).overlaps(tester.getRect(controls)), isFalse);
    expect(tester.getRect(artwork).center.dy, greaterThan(0));
    expect(
      tester.getRect(spindle).center.dx,
      closeTo(tester.getRect(artwork).center.dx, .01),
    );
    expect(
      tester.getRect(spindle).center.dy,
      closeTo(tester.getRect(artwork).center.dy, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lyrics follow playback position to keep the active line visible',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = SnapshotAudio();
      addTearDown(audio.close);
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
      );
      await controller.play(
        Track.fromJson({'id': 'follow', 'name': 'Follow', 'source': 'kw'}),
      );
      final lyrics = List.generate(
        30,
        (index) => '[00:${index.toString().padLeft(2, '0')}]Line $index',
      ).join('\n');

      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => Lyrics(original: lyrics),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      await tester.pump();

      audio.emit(
        const AudioSnapshot(
          processing: PlayerProcessing.ready,
          position: Duration(seconds: 20),
          duration: Duration(seconds: 30),
        ),
      );
      await tester.pump();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final viewport = tester.getRect(
        find.byKey(const Key('desktop-lyrics-viewport')),
      );
      final activeLineFinder = find.text('Line 20');
      expect(activeLineFinder.hitTestable(), findsOneWidget);
      final activeLine = tester.getRect(activeLineFinder);
      expect(
        activeLine.center.dy,
        inInclusiveRange(
          viewport.top + viewport.height * .25,
          viewport.top + viewport.height * .50,
        ),
      );
    },
  );

  testWidgets('desktop vinyl rotates only while playback is ready', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = SnapshotAudio();
    addTearDown(audio.close);
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([
      Track.fromJson({'id': 'vinyl', 'name': 'Vinyl', 'source': 'kw'}),
    ]);
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:00]line'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );

    audio.emit(
      const AudioSnapshot(processing: PlayerProcessing.ready, playing: true),
    );
    await tester.pump();
    await tester.pump();
    final turn = find.byKey(const Key('player-desktop-orbit-turn'));
    double turns() => tester.widget<RotationTransition>(turn).turns.value;
    final initial = turns();
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), greaterThan(initial));

    audio.emit(
      const AudioSnapshot(
        processing: PlayerProcessing.buffering,
        playing: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    final buffered = turns();
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(buffered, 1e-6));

    audio.emit(
      const AudioSnapshot(processing: PlayerProcessing.ready, playing: true),
    );
    await tester.pump();
    await tester.pump();
    expect(turns(), closeTo(buffered, 1e-6));
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), greaterThan(buffered));
  });

  testWidgets('desktop vinyl stays still when reduced motion is enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = SnapshotAudio();
    addTearDown(audio.close);
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([
      Track.fromJson({'id': 'still', 'name': 'Still', 'source': 'kw'}),
    ]);
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: '[00:00]line'),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );

    audio.emit(
      const AudioSnapshot(processing: PlayerProcessing.ready, playing: true),
    );
    await tester.pump();
    await tester.pump();
    final turn = find.byKey(const Key('player-desktop-orbit-turn'));
    double turns() => tester.widget<RotationTransition>(turn).turns.value;
    final initial = turns();
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), closeTo(initial, 1e-6));
  });

  testWidgets(
    'cached artwork stays real across desktop and mobile breakpoints',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const imageUrl = 'https://example.test/cached-cover.png';
      final manager = TestImageCacheManager(
        cachedFile: FileInfo(
          const LocalFileSystem().file('assets/branding/TuneFlow.png'),
          FileSource.Cache,
          DateTime.utc(2030),
          imageUrl,
        ),
      );
      final imageCache = FakeAppImageCache(manager: manager);
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.playTracks([
        Track.fromJson({
          'id': 'cached',
          'name': 'Cached',
          'source': 'kw',
          'pic': imageUrl,
        }),
      ]);
      final player = AppImageCacheScope(
        cache: imageCache,
        child: PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      );

      await tester.pumpWidget(harness(player));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
      expect(find.byKey(const Key('artwork-fallback-kw:cached')), findsNothing);
      expect(find.byType(Image), findsWidgets);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('player-mobile-layout')), findsOneWidget);
      expect(find.byKey(const Key('artwork-fallback-kw:cached')), findsNothing);
      expect(find.byType(Image), findsWidgets);

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
      expect(find.byKey(const Key('artwork-fallback-kw:cached')), findsNothing);
      expect(find.byType(Image), findsWidgets);
      expect(manager.fileStreamCalls, greaterThan(0));
    },
  );

  testWidgets('desktop queue opens as a bounded lower-right popover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks(
      List.generate(
        80,
        (index) => Track.fromJson({
          'id': 'track-$index',
          'name': 'Track $index',
          'source': 'kw',
        }),
      ),
      startIndex: 52,
    );

    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: ''),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('player-desktop-queue')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('player-desktop-queue-popover')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-desktop-queue-list')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-queue-clear')), findsOneWidget);
    expect(find.text('80 首'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-queue-track-track-52')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('player-desktop-queue-popover')))
          .height,
      lessThanOrEqualTo(544),
    );
    await tester.tap(
      find.byKey(const Key('player-desktop-queue-remove-track-53')),
    );
    await tester.pump();
    expect(controller.state.queue, hasLength(79));
    expect(controller.state.current?.id, 'track-52');
  });

  testWidgets('desktop quality popover does not shift centered transport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.play(
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    );
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: ''),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );
    final before = tester.getCenter(find.byKey(const Key('player-play-pause')));

    await tester.tap(find.byKey(const Key('player-desktop-quality')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('player-desktop-quality-popover')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-quality-flac')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('player-play-pause'))),
      before,
    );
    expect(
      tester.getCenter(find.byKey(const Key('player-desktop-progress'))).dx,
      closeTo(600, .5),
    );
  });

  testWidgets('mobile player uses the immersive glass hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);

    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: '[00:01]Line'),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('player-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('player-backdrop')), findsOneWidget);
    expect(find.byKey(const Key('player-backdrop-neutral')), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(AppGlassSurface), findsAtLeastNWidgets(2));
    expect(find.byKey(const Key('player-mobile-topbar')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-progress')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-transport')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-lyrics')), findsNothing);
    expect(
      find.byKey(const Key('player-mobile-playback-mode')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('顺序播放'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-previous')),
        matching: find.byIcon(Icons.skip_previous_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('player-next')),
        matching: find.byIcon(Icons.skip_next_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byKey(const Key('player-play-pause'))).dx,
      closeTo(
        tester.getCenter(find.byKey(const Key('player-mobile-controls'))).dx,
        .5,
      ),
    );
    await tester.tap(find.byKey(const Key('player-mobile-playback-mode')));
    await tester.pump();
    expect(controller.state.playbackMode, PlaybackMode.repeatOne);
    expect(find.bySemanticsLabel('单曲循环'), findsOneWidget);
    expect(find.byKey(const Key('player-view-artwork')), findsNothing);
    expect(find.byKey(const Key('player-view-lyrics')), findsNothing);
    expect(find.byKey(const Key('player-view-queue')), findsNothing);
    expect(find.text('封面'), findsNothing);
    expect(find.text('歌词'), findsNothing);
    expect(find.text('队列'), findsNothing);
    expect(find.text('正在播放'), findsOneWidget);
    expect(find.text('One'), findsWidgets);
    expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-artwork')), findsNothing);
    expect(find.text('Line').hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await pumpFiniteAnimations(tester);
    expect(controller.state.view, PlayerView.lyrics);
    expect(find.text('Line').hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-topbar')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('player-mobile-lyrics-page'))),
      tester.getRect(find.byKey(const Key('player-mobile-pages'))),
    );
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.state.view, PlayerView.artwork);
    expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-mobile-queue')));
    await pumpFiniteAnimations(tester);
    expect(find.text('播放队列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile player always opens on the record page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);
    controller.setView(PlayerView.lyrics);

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:01]Line'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    expect(controller.state.view, PlayerView.artwork);
    expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
    expect(find.text('Line').hitTestable(), findsNothing);
  });

  testWidgets('mobile empty lyrics appear only after swiping to lyrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);

    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: ''),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无歌词').hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await pumpFiniteAnimations(tester);
    expect(find.text('暂无歌词').hitTestable(), findsOneWidget);
  });

  testWidgets('mobile player keeps transport reachable at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({
        'id': 'one',
        'name': 'A very long mobile player track title',
        'source': 'kw',
      }),
    ]);

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:01]Line'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    for (final key in const [
      Key('player-mobile-playback-mode'),
      Key('player-previous'),
      Key('player-play-pause'),
      Key('player-next'),
      Key('player-mobile-queue'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    final modeRect = tester.getRect(
      find.byKey(const Key('player-mobile-playback-mode')),
    );
    final previousRect = tester.getRect(
      find.byKey(const Key('player-previous')),
    );
    final playRect = tester.getRect(find.byKey(const Key('player-play-pause')));
    final nextRect = tester.getRect(find.byKey(const Key('player-next')));
    final queueRect = tester.getRect(
      find.byKey(const Key('player-mobile-queue')),
    );
    final transportRect = tester.getRect(
      find.byKey(const Key('player-mobile-transport')),
    );
    expect(modeRect.right, lessThanOrEqualTo(previousRect.left));
    expect(nextRect.right, lessThanOrEqualTo(queueRect.left));
    expect(playRect.center.dx, closeTo(transportRect.center.dx, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile player keeps 320k quality on one line at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
      quality: '320k',
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    final selectedQuality = find.descendant(
      of: find.byKey(const Key('player-mobile-quality')),
      matching: find.text('320k'),
    );
    expect(selectedQuality, findsOneWidget);
    expect(
      tester
          .widget<ShadSelect<String>>(
            find.descendant(
              of: find.byKey(const Key('player-mobile-quality')),
              matching: find.byType(ShadSelect<String>),
            ),
          )
          .decoration,
      ShadDecoration.none,
    );
    expect(tester.getSize(selectedQuality).height, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile queue sheet selects and removes tracks independently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({
        'id': 'a',
        'name': 'Alpha',
        'singer': 'Artist A',
        'source': 'kw',
      }),
      Track.fromJson({
        'id': 'b',
        'name': 'Beta',
        'singer': 'Artist B',
        'source': 'kw',
      }),
      Track.fromJson({
        'id': 'c',
        'name': 'Gamma',
        'singer': 'Artist C',
        'source': 'kw',
      }),
    ]);
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('player-mobile-queue')));
    await pumpFiniteAnimations(tester);
    expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
    expect(find.text('3 首'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mobile-queue-track-b')));
    await tester.pump();
    expect(controller.state.current?.id, 'b');
    expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-mobile-queue-remove-c')));
    await tester.pump();
    expect(controller.state.queue.map((track) => track.id), ['a', 'b']);
    expect(controller.state.current?.id, 'b');
    expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
  });

  testWidgets('mobile queue clear requires confirmation and stops playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = FakeAudio();
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([
      Track.fromJson({'id': 'a', 'name': 'Alpha', 'source': 'kw'}),
      Track.fromJson({'id': 'b', 'name': 'Beta', 'source': 'kw'}),
    ]);
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('player-mobile-queue')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('player-mobile-queue-clear')));
    await pumpFiniteAnimations(tester);
    expect(find.text('清空播放队列？'), findsOneWidget);
    expect(find.text('当前播放将停止，此操作无法撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await pumpFiniteAnimations(tester);
    expect(controller.state.queue, hasLength(2));

    await tester.tap(find.byKey(const Key('player-mobile-queue-clear')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.text('清空').last);
    await pumpFiniteAnimations(tester);
    expect(controller.state.queue, isEmpty);
    expect(audio.stopPlaybackCalls, 1);
    expect(find.byKey(const Key('player-mobile-queue-sheet')), findsNothing);
    expect(find.text('播放队列为空'), findsOneWidget);
  });

  testWidgets('mobile long queue keeps its header and reveals current track', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks(
      List.generate(
        80,
        (index) => Track.fromJson({
          'id': 'mobile-$index',
          'name': 'Mobile $index',
          'source': 'kw',
        }),
      ),
      startIndex: 52,
    );
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('player-mobile-queue')));
    await pumpFiniteAnimations(tester);

    expect(find.byKey(const Key('player-mobile-queue-header')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-queue-list')), findsOneWidget);
    expect(find.text('80 首'), findsOneWidget);
    expect(
      find.byKey(const Key('mobile-queue-track-mobile-52')),
      findsOneWidget,
    );
  });

  testWidgets('mobile queue keeps stop failures local and retryable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = FakeAudio()..stopPlaybackError = StateError('stop failed');
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.play(
      Track.fromJson({'id': 'a', 'name': 'Alpha', 'source': 'kw'}),
    );
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('player-mobile-queue')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.byKey(const Key('player-mobile-queue-clear')));
    await pumpFiniteAnimations(tester);
    await tester.tap(find.text('清空').last);
    await pumpFiniteAnimations(tester);

    expect(controller.state.queue, hasLength(1));
    expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
    expect(find.text('队列操作失败'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('mobile player keeps lyric errors compact and local', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);

    var lyricAttempts = 0;
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async {
              lyricAttempts++;
              if (lyricAttempts == 1) throw StateError('no lyrics');
              return const Lyrics(original: '[00:01]Line');
            },
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('player-mobile-lyric-error')).hitTestable(),
      findsNothing,
    );
    expect(find.text('歌词暂不可用').hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await pumpFiniteAnimations(tester);
    expect(
      find.byKey(const Key('player-mobile-lyric-error')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('歌词暂不可用').hitTestable(), findsOneWidget);
    expect(find.text('重试').hitTestable(), findsOneWidget);
    expect(find.text('播放失败'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.byKey(const Key('player-mobile-topbar')), findsOneWidget);
    expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(lyricAttempts, 2);
    expect(find.text('Line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop player replaces malformed lyrics with a local state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => throw StateError('bad encoding'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('歌词暂不可用'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('lyrics error state uses the standard Lucide family', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const LyricsView(state: PlayerState(lyricsError: 'bad lyrics'))),
    );

    expect(find.text('歌词暂不可用'), findsOneWidget);
    expect(find.byIcon(LucideIcons.messageSquareText), findsOneWidget);
  });

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('player remains overflow-free at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.playTracks([
        Track.fromJson({
          'id': 'responsive',
          'name': 'A deliberately long responsive track title',
          'singer': 'Responsive artist',
          'source': 'kw',
        }),
      ]);

      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(original: ''),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
