import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';

final class FakeResolver implements PlaybackResolver {
  int calls = 0;
  final List<String> qualities = [];

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async {
    calls++;
    qualities.add(quality);
    return PlaybackSource(
      resolved: const ResolvedTrack(
        url: '/api/v1/streams/token',
        quality: '128k',
        expiresAt: 1000,
      ),
      streamUri: Uri.parse('http://service.local/api/v1/streams/token-$calls'),
    );
  }
}

class FakeAudio implements AudioPort {
  final controller = StreamController<AudioSnapshot>.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopPlaybackCalls = 0;
  final List<Duration> seekCalls = [];
  Object? playError;
  Object? stopPlaybackError;
  bool cached = false;
  Future<void> Function()? previousCallback;
  Future<void> Function()? nextCallback;

  @override
  Stream<AudioSnapshot> get snapshots => controller.stream;

  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {
    previousCallback = previous;
    nextCallback = next;
  }

  @override
  Future<bool> playCachedTrack(Track track, String quality) async => cached;

  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {
    playCalls++;
    if (playError case final error?) throw error;
  }

  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> resume() async => resumeCalls++;
  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> stopPlayback() async {
    stopPlaybackCalls++;
    if (stopPlaybackError case final error?) throw error;
  }
}

Track track(String id) =>
    Track.fromJson({'id': id, 'name': id, 'source': 'kw'});

void main() {
  test('audio stop command keeps the port reusable', () async {
    final fake = FakeAudio();
    final AudioPort audio = fake;

    await audio.stopPlayback();
    await audio.resume();

    expect(fake.stopPlaybackCalls, 1);
    expect(fake.resumeCalls, 1);
  });

  test('removing before current preserves the current track', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      track('a'),
      track('b'),
      track('c'),
    ], startIndex: 1);

    expect(await controller.removeAt(0), isTrue);
    expect(controller.state.queue.map((item) => item.id), ['b', 'c']);
    expect(controller.state.current?.id, 'b');
    expect(controller.state.currentIndex, 0);
  });

  test('removing after current keeps its index and playback', () async {
    final audio = FakeAudio();
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([track('a'), track('b'), track('c')]);
    final playCalls = audio.playCalls;

    expect(await controller.removeAt(2), isTrue);
    expect(controller.state.current?.id, 'a');
    expect(controller.state.currentIndex, 0);
    expect(audio.playCalls, playCalls);
  });

  test('removing current prefers the original next track', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([
      track('a'),
      track('b'),
      track('c'),
    ], startIndex: 1);

    expect(await controller.removeAt(1), isTrue);
    expect(controller.state.queue.map((item) => item.id), ['a', 'c']);
    expect(controller.state.current?.id, 'c');
    expect(controller.state.currentIndex, 1);
  });

  test('removing current tail falls back to the previous track', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([track('a'), track('b')], startIndex: 1);

    expect(await controller.removeAt(1), isTrue);
    expect(controller.state.queue.map((item) => item.id), ['a']);
    expect(controller.state.current?.id, 'a');
    expect(controller.state.currentIndex, 0);
  });

  test('removing the final track stops and empties the player', () async {
    final audio = FakeAudio();
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.play(track('a'));

    expect(await controller.removeAt(0), isTrue);
    expect(audio.stopPlaybackCalls, 1);
    expect(controller.state.queue, isEmpty);
    expect(controller.state.current, isNull);
    expect(controller.state.currentIndex, -1);
  });

  test('invalid removal is ignored', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );

    expect(await controller.removeAt(0), isFalse);
  });

  test('clear queue stops audio and preserves player preferences', () async {
    final audio = FakeAudio();
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: audio,
      quality: '320k',
      showTranslation: false,
    );
    await controller.playTracks([track('a'), track('b')]);

    expect(await controller.clearQueue(), isTrue);
    expect(audio.stopPlaybackCalls, 1);
    expect(controller.state.queue, isEmpty);
    expect(controller.state.quality, '320k');
    expect(controller.state.showTranslation, isFalse);
  });

  test('failed stop keeps the queue and exposes an error', () async {
    final audio = FakeAudio()..stopPlaybackError = StateError('stop failed');
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.play(track('a'));

    expect(await controller.clearQueue(), isFalse);
    expect(controller.state.current?.id, 'a');
    expect(controller.state.error, isA<StateError>());
  });

  test('failed final-track removal keeps the track', () async {
    final audio = FakeAudio()..stopPlaybackError = StateError('stop failed');
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.play(track('a'));

    expect(await controller.removeAt(0), isFalse);
    expect(controller.state.current?.id, 'a');
    expect(controller.state.queue.map((item) => item.id), ['a']);
  });

  test(
    'play next inserts after current and replaces queued duplicate',
    () async {
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.playTracks([track('a'), track('c'), track('b')]);

      await controller.playNext(track('b'));

      expect(controller.state.queue.map((item) => item.id), ['a', 'b', 'c']);
      expect(controller.state.current?.id, 'a');
    },
  );

  test('play next starts playback when the queue is empty', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );

    await controller.playNext(track('a'));

    expect(controller.state.current?.id, 'a');
  });

  test(
    'queue replacement, navigation, and quality reach the resolver',
    () async {
      final resolver = FakeResolver();
      final audio = FakeAudio();
      final controller = PlayerController(resolver: resolver, audio: audio);

      await controller.playTracks([track('a'), track('b')], startIndex: 1);
      expect(controller.state.current?.id, 'b');
      await controller.previous();
      expect(controller.state.current?.id, 'a');
      await controller.next();
      expect(controller.state.current?.id, 'b');
      await controller.next();
      expect(controller.state.current?.id, 'b');
      controller.enqueue(track('c'));
      await controller.setQuality('320k');

      expect(controller.state.queue.map((item) => item.id), ['a', 'b', 'c']);
      expect(resolver.qualities.last, '320k');
      expect(audio.previousCallback, isNotNull);
      expect(audio.nextCallback, isNotNull);
    },
  );

  test('failed quality switch rolls back the selected quality', () async {
    final audio = FakeAudio();
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: audio,
      quality: '320k',
    );
    await controller.play(track('a'));
    audio.playError = StateError('quality unavailable');

    await controller.setQuality('flac');

    expect(controller.state.quality, '320k');
    expect(controller.state.error, isA<StateError>());
  });

  test(
    'audio snapshots update transport state and controls delegate',
    () async {
      final audio = FakeAudio();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
      );
      audio.controller.add(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.ready,
          position: Duration(seconds: 4),
          duration: Duration(seconds: 10),
          buffered: Duration(seconds: 7),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.pause();
      await controller.resume();

      expect(controller.state.playing, isTrue);
      expect(controller.state.position, const Duration(seconds: 4));
      expect(audio.pauseCalls, 1);
      expect(audio.resumeCalls, 1);
    },
  );

  test('playback mode cycles through sequential repeat-one and shuffle', () {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );

    expect(controller.state.playbackMode, PlaybackMode.sequential);
    controller.cyclePlaybackMode();
    expect(controller.state.playbackMode, PlaybackMode.repeatOne);
    controller.cyclePlaybackMode();
    expect(controller.state.playbackMode, PlaybackMode.shuffle);
    controller.cyclePlaybackMode();
    expect(controller.state.playbackMode, PlaybackMode.sequential);
  });

  test(
    'repeat-one replays the current track when playback completes',
    () async {
      final audio = FakeAudio();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
      );
      await controller.playTracks([track('a'), track('b')]);
      controller.cyclePlaybackMode();

      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.completed),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.current?.id, 'a');
      expect(audio.playCalls, 2);
    },
  );

  test('shuffle next selects a different queued track', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.playTracks([track('a'), track('b'), track('c')]);
    controller.cyclePlaybackMode();
    controller.cyclePlaybackMode();

    await controller.next();

    expect(controller.state.current?.id, isNot('a'));
  });

  test(
    'expired playback token resolves exactly once more then exposes error',
    () async {
      final resolver = FakeResolver();
      final audio = FakeAudio()
        ..playError = const PlaybackStreamExpiredException();
      final controller = PlayerController(resolver: resolver, audio: audio);

      await controller.playTracks([track('a')]);

      expect(resolver.calls, 2);
      expect(audio.playCalls, 2);
      expect(controller.state.error, isA<PlaybackStreamExpiredException>());
    },
  );

  test('successful expiry retry clears the first error', () async {
    final resolver = FakeResolver();
    final audio = _ExpireOnceAudio();
    final controller = PlayerController(resolver: resolver, audio: audio);

    await controller.playTracks([track('a')]);

    expect(resolver.calls, 2);
    expect(controller.state.error, isNull);
  });

  test('lyrics failure stays separate from playback failure', () async {
    final resolver = FakeResolver();
    final audio = FakeAudio();
    final controller = PlayerController(resolver: resolver, audio: audio);
    await controller.play(track('a'));

    await controller.loadLyrics((_) async => throw StateError('no lyrics'));

    expect(controller.state.error, isNull);
    expect(controller.state.lyricsError, isA<StateError>());
    await controller.resume();
    expect(resolver.calls, 1);
    expect(audio.playCalls, 1);
    expect(audio.resumeCalls, 1);
  });

  test('lyrics failure clears stale lyrics from an earlier response', () async {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );
    await controller.play(track('a'));
    await controller.loadLyrics(
      (_) async => const Lyrics(original: '[00:01]old line'),
    );

    await controller.loadLyrics((_) async => throw StateError('bad encoding'));

    expect(controller.state.lyrics, isNull);
    expect(controller.state.lyricsError, isA<StateError>());
  });

  test(
    'resume retries a failed track instead of delegating a stale resume',
    () async {
      final resolver = FakeResolver();
      final audio = FakeAudio()..playError = StateError('network');
      final controller = PlayerController(resolver: resolver, audio: audio);

      await controller.play(track('a'));
      expect(controller.state.processing, PlayerProcessing.error);

      audio.playError = null;
      await controller.resume();

      expect(audio.playCalls, 2);
      expect(audio.resumeCalls, 0);
      expect(controller.state.error, isNull);
    },
  );

  test('resume restarts a completed track from the beginning', () async {
    final audio = FakeAudio();
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.play(track('a'));
    audio.controller.add(
      const AudioSnapshot(
        playing: false,
        processing: PlayerProcessing.completed,
        position: Duration(seconds: 30),
        duration: Duration(seconds: 30),
        buffered: Duration(seconds: 30),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.resume();

    expect(audio.seekCalls, [Duration.zero]);
    expect(audio.resumeCalls, 1);
  });

  test(
    'cached playback remains available without resolving the Service',
    () async {
      final resolver = FakeResolver();
      final audio = FakeAudio()..cached = true;
      final controller = PlayerController(resolver: resolver, audio: audio);

      await controller.playTracks([track('offline')]);

      expect(resolver.calls, 0);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'invalid cached playback falls back to a fresh Service stream',
    () async {
      final resolver = FakeResolver();
      final audio = _InvalidCacheAudio();
      final controller = PlayerController(resolver: resolver, audio: audio);

      await controller.playTracks([track('stale-cache')]);

      expect(resolver.calls, 1);
      expect(audio.playCalls, 1);
      expect(controller.state.error, isNull);
    },
  );

  test('queue remains available as a full-player entry intent', () {
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
    );

    controller.setView(PlayerView.queue);

    expect(controller.state.view, PlayerView.queue);
  });
}

final class _ExpireOnceAudio extends FakeAudio {
  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {
    playCalls++;
    if (playCalls == 1) throw const PlaybackStreamExpiredException();
  }
}

final class _InvalidCacheAudio extends FakeAudio {
  @override
  Future<bool> playCachedTrack(Track track, String quality) async {
    throw StateError('invalid cache');
  }
}
