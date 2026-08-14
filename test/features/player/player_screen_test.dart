import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/features/player/mini_player.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_screen.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/player/wake_lock_port.dart';
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
  Future<void> pause() async {}
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

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

Future<void> pumpFiniteAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
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

    await tester.pumpWidget(
      harness(
        MiniPlayer(
          controller: controller,
          onOpen: () => opened = true,
          variant: MiniPlayerVariant.desktop,
        ),
      ),
    );

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
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
    await tester.tap(find.byKey(const Key('desktop-track-surface')));
    expect(opened, isTrue);
    await tester.tap(find.byKey(const Key('desktop-lyrics')));
    expect(controller.state.view, PlayerView.lyrics);
    await tester.tap(find.byKey(const Key('desktop-queue')));
    expect(controller.state.view, PlayerView.queue);
    expect(find.byKey(const Key('player-previous-mini')), findsOneWidget);
    expect(find.byKey(const Key('player-next-mini')), findsOneWidget);
    expect(find.byIcon(LucideIcons.skipBack), findsOneWidget);
    expect(find.byIcon(LucideIcons.skipForward), findsOneWidget);
  });

  testWidgets('desktop player maps loading and playback transport states', (
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
    await tester.tap(find.byKey(const Key('desktop-play-pause')));
    expect(audio.resumeCalls, 0);

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
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    ]);
    final wakeLock = FakeWakeLock();

    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:00]line'),
          wakeLock: wakeLock,
          keepAwake: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('One'), findsOneWidget);
    expect(find.byKey(const Key('player-previous')), findsOneWidget);
    expect(find.byKey(const Key('player-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('player-next')), findsOneWidget);
    expect(find.byKey(const Key('player-wide-layout')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-artwork')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-metadata')), findsOneWidget);
    expect(find.byKey(const Key('player-desktop-controls')), findsOneWidget);
    expect(find.byKey(const Key('player-view-artwork')), findsNothing);
    expect(find.byKey(const Key('player-view-lyrics')), findsNothing);
    expect(find.byKey(const Key('player-view-queue')), findsNothing);
    expect(find.bySemanticsLabel('One封面'), findsWidgets);
    expect(find.text('line'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('desktop-lyrics-viewport'))).height,
      360,
    );
    expect(wakeLock.values, [true]);

    await tester.pumpWidget(harness(const SizedBox()));
    await tester.pump();
    expect(wakeLock.values, [true, false]);
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
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
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
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
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
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: '[00:01]Line'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
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
    await tester.pumpAndSettle();
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
        PlayerScreen(
          controller: controller,
          lyricsLoader: (_) async => const Lyrics(original: ''),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无歌词').hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
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
        PlayerScreen(
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
    );
    await tester.pump();

    expect(
      find.byKey(const Key('player-mobile-lyric-error')).hitTestable(),
      findsNothing,
    );
    expect(find.text('歌词暂不可用').hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
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
