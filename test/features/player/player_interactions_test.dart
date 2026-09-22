import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/mini_player.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_screen.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';

import 'player_controller_test.dart' show ControlledAudio, FakeResolver, track;
import 'player_screen_test.dart'
    show harness, FakeWakeLock, pumpFiniteAnimations;

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('playback controls operate the same session at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mobile = size.width < 600;
      final audio = ControlledAudio();
      final player = PlayerController(resolver: FakeResolver(), audio: audio);
      await player.playTracks([track('one'), track('two')]);
      await tester.pumpWidget(
        harness(
          PlayerScreen(
            controller: player,
            lyricsLoader: (_) async => const Lyrics(original: ''),
            wakeLock: FakeWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      audio.controller.add(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.ready,
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-play-pause')));
      expect(audio.pauseCalls, 1);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-play-pause')));
      expect(audio.resumeCalls, 1);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.buffering),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-play-pause')));
      expect(audio.pauseCalls, 2, reason: 'buffering can still be paused');
      await tester.tap(find.byKey(const Key('player-next')));
      await tester.pump();
      expect(player.state.current!.id, 'two');
      await tester.tap(find.byKey(const Key('player-previous')));
      await tester.pump();
      expect(player.state.current!.id, 'one');
      await tester.tap(
        find.byKey(
          Key(
            mobile
                ? 'player-mobile-playback-mode'
                : 'player-desktop-playback-mode',
          ),
        ),
      );
      await tester.pump();
      expect(player.state.playbackMode, PlaybackMode.repeatOne);
      if (!mobile) {
        await tester.tap(find.byKey(const Key('player-desktop-volume')));
        await pumpFiniteAnimations(tester);
        final popover = tester.getRect(
          find.byKey(const Key('player-desktop-volume-popover')),
        );
        expect(popover.height, 48);
        expect(popover.top, greaterThanOrEqualTo(0));
      }
      final volume = find.byType(Slider);
      expect(tester.getRect(volume).bottom, lessThanOrEqualTo(size.height));
      await tester.tap(volume);
      await tester.pump();
      expect(audio.volumes.last, closeTo(.5, .05));
      await tester.tap(find.byTooltip('静音'));
      await tester.pump();
      expect(audio.volumes.last, 0);
      await tester.tap(find.byTooltip('取消静音'));
      await tester.pump();
      expect(audio.volumes.last, closeTo(.5, .05));
      if (!mobile) {
        await tester.tap(find.byKey(const Key('player-desktop-volume')));
        await pumpFiniteAnimations(tester);
      }
      await tester.tap(
        find.byKey(
          Key(mobile ? 'player-mobile-speed' : 'player-desktop-speed'),
        ),
      );
      await pumpFiniteAnimations(tester);
      await tester.tap(
        mobile ? find.text('1.5x') : find.byKey(const Key('player-speed-1.5')),
      );
      await pumpFiniteAnimations(tester);
      expect(audio.speeds.last, 1.5);
      await tester.tap(
        find.byKey(
          Key(mobile ? 'player-mobile-queue' : 'player-desktop-queue'),
        ),
      );
      await pumpFiniteAnimations(tester);
      await tester.tap(
        find.byKey(
          Key(mobile ? 'mobile-queue-track-two' : 'desktop-queue-track-two'),
        ),
      );
      await tester.pump();
      expect(player.state.current!.id, 'two');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFiniteAnimations(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      await audio.controller.close();
    });

    testWidgets('player closes without stopping playback at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = ControlledAudio();
      final player = PlayerController(resolver: FakeResolver(), audio: audio);
      final wake = FakeWakeLock();
      await player.playTracks([track('one'), track('two')]);
      audio.controller.add(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.ready,
          position: Duration(seconds: 42),
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: PlayerScreen(
                      controller: player,
                      lyricsLoader: (_) async => const Lyrics(original: ''),
                      wakeLock: wake,
                      keepAwake: true,
                    ),
                  ),
                ),
              ),
              child: const Text('打开播放器'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开播放器'));
      await pumpFiniteAnimations(tester);
      expect(find.byTooltip('关闭播放器'), findsOneWidget);
      final starts = audio.playCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFiniteAnimations(tester);
      expect(find.text('打开播放器'), findsOneWidget);
      expect(player.state.position, const Duration(seconds: 42));
      expect(player.state.playing, isTrue);
      expect(audio.pauseCalls, 0);
      expect(audio.stopPlaybackCalls, 0);
      expect(wake.values.last, isFalse);
      await tester.tap(find.text('打开播放器'));
      await pumpFiniteAnimations(tester);
      expect(audio.playCalls, starts);
      await tester.tap(find.byTooltip('关闭播放器'));
      await pumpFiniteAnimations(tester);
      expect(find.text('打开播放器'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      await audio.controller.close();
    });
  }

  testWidgets('reopening mobile player retains its lyric view', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = ControlledAudio();
    final player = PlayerController(resolver: FakeResolver(), audio: audio);
    await player.play(track('one'));
    player.setView(PlayerView.lyrics);
    await tester.pumpWidget(
      harness(
        PlayerScreen(
          controller: player,
          lyricsLoader: (_) async => const Lyrics(original: '[00:00]保留歌词页面'),
          wakeLock: FakeWakeLock(),
          keepAwake: false,
        ),
      ),
    );
    await pumpFiniteAnimations(tester);
    expect(player.state.view, PlayerView.lyrics);
    expect(
      tester
          .widget<PageView>(find.byKey(const Key('player-mobile-pages')))
          .controller!
          .page,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    await audio.controller.close();
  });

  for (final variant in MiniPlayerVariant.values) {
    testWidgets('$variant mini player can shuffle from the last track', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = ControlledAudio();
      final player = PlayerController(resolver: FakeResolver(), audio: audio);
      await player.playTracks([track('one'), track('two')], startIndex: 1);
      player.cyclePlaybackMode();
      player.cyclePlaybackMode();
      var opens = 0;
      await tester.pumpWidget(
        harness(
          MiniPlayer(
            controller: player,
            variant: variant,
            onOpen: () => opens++,
          ),
        ),
      );
      await tester.tap(
        find.byKey(
          Key(
            variant == MiniPlayerVariant.mobile
                ? 'mobile-player-next'
                : 'player-next-mini',
          ),
        ),
      );
      await tester.pump();
      expect(player.state.current!.id, 'one');
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
      await audio.controller.close();
    });
  }
}
