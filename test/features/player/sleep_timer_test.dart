import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'player_controller_test.dart' show FakeAudio, FakeResolver, track;

void main() {
  testWidgets('deadline at a track boundary cannot start the next track', (
    tester,
  ) async {
    final audio = FakeAudio();
    final player = PlayerController(resolver: FakeResolver(), audio: audio);
    await player.playTracks([track('a'), track('b')]);
    player.setSleepTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.completed),
    );
    await tester.pump();
    expect(audio.playCalls, 1);
    expect(audio.pauseCalls, 1);
    player.dispose();
    await audio.controller.close();
  });
  test('finish current track suppresses repeat and automatic next', () async {
    final audio = FakeAudio();
    final player = PlayerController(resolver: FakeResolver(), audio: audio);
    addTearDown(player.dispose);
    addTearDown(audio.controller.close);
    await player.playTracks([track('a'), track('b')]);
    player.cyclePlaybackMode();
    player.setSleepTimer(null);
    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.completed),
    );
    await Future<void>.delayed(Duration.zero);
    expect(audio.pauseCalls, 1);
    expect(audio.playCalls, 1);
    expect(player.stopAfterCurrent, isFalse);
  });

  testWidgets('timer can be cancelled and expiration pauses only once', (
    tester,
  ) async {
    final audio = FakeAudio();
    final player = PlayerController(resolver: FakeResolver(), audio: audio);
    await player.play(track('a'));
    player.setSleepTimer(const Duration(seconds: 1));
    player.cancelSleepTimer();
    await tester.pump(const Duration(seconds: 2));
    expect(audio.pauseCalls, 0);
    player.setSleepTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(audio.pauseCalls, 1);
    expect(player.sleepDeadline, isNull);
    player.dispose();
    await audio.controller.close();
  });
}
