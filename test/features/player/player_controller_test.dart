import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/playback_history/playback_history_repository.dart';
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
  final List<Track> playedTracks = [];
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
    playedTracks.add(track);
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

PlaybackSource bundleSource({
  Lyrics? lyrics,
  Uri? lyricsUri,
  Uri? pictureUri,
  PlaybackBundleCompleteness completeness = PlaybackBundleCompleteness.complete,
}) => PlaybackSource(
  resolved: ResolvedTrack(
    url: '/api/v1/streams/token',
    quality: '128k',
    expiresAt: 1000,
    completeness: completeness,
  ),
  streamUri: Uri.parse('http://service.local/api/v1/streams/token'),
  bundleLyrics: lyrics,
  lyricsUri: lyricsUri,
  pictureUri: pictureUri,
);

final class FixedResolver implements PlaybackResolver {
  FixedResolver(this.source);
  final PlaybackSource source;
  int calls = 0;

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async {
    calls++;
    return source;
  }
}

final class DeferredResolver implements PlaybackResolver {
  final List<Completer<PlaybackSource>> requests = [];

  @override
  Future<PlaybackSource> resolve(Track track, String quality) {
    final completer = Completer<PlaybackSource>();
    requests.add(completer);
    return completer.future;
  }
}

final class ErrorResolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async {
    throw StateError('resource refresh unavailable');
  }
}

class FakeSessions implements PlaybackSessionPort {
  final List<String> starts = [];
  Object? startError;
  Object? endError;
  final List<
    ({String playbackId, bool completed, Duration position, Duration duration})
  >
  ends = [];

  @override
  Future<String> start(Track track) async {
    if (startError case final error?) throw error;
    starts.add(track.id);
    return 'play-${starts.length}';
  }

  @override
  Future<void> end(
    String playbackId, {
    required bool completed,
    required Duration position,
    required Duration duration,
  }) async {
    if (endError case final error?) throw error;
    ends.add((
      playbackId: playbackId,
      completed: completed,
      position: position,
      duration: duration,
    ));
  }
}

final class DeferredSessions extends FakeSessions {
  final List<Completer<String>> pendingStarts = [];

  @override
  Future<String> start(Track track) {
    starts.add(track.id);
    final pending = Completer<String>();
    pendingStarts.add(pending);
    return pending.future;
  }
}

final class DeferredEndSessions extends FakeSessions {
  final List<Completer<void>> pendingEnds = [];

  @override
  Future<void> end(
    String playbackId, {
    required bool completed,
    required Duration position,
    required Duration duration,
  }) {
    final pending = Completer<void>();
    pendingEnds.add(pending);
    return pending.future;
  }
}

void main() {
  test(
    'applies embedded bundle lyrics and artwork before audio starts',
    () async {
      final audio = FakeAudio();
      final controller = PlayerController(
        resolver: FixedResolver(
          bundleSource(
            lyrics: const Lyrics(original: '[00:00.00]bundle'),
            pictureUri: Uri.parse(
              'http://service.local/api/v1/playback/resources/token/picture',
            ),
          ),
        ),
        audio: audio,
      );

      await controller.play(track('bundle'));

      expect(
        controller.state.current?.raw['pic'],
        'http://service.local/api/v1/playback/resources/token/picture',
      );
      expect(audio.playedTracks.single.raw['pic'], contains('/picture'));
      expect(controller.state.lyrics?.original, '[00:00.00]bundle');
      expect(
        controller.state.bundleCompleteness,
        PlaybackBundleCompleteness.complete,
      );
      var lyricsLoaderCalls = 0;
      await controller.loadLyrics((_) async {
        lyricsLoaderCalls++;
        return const Lyrics(original: 'duplicate');
      });
      expect(lyricsLoaderCalls, 0);
    },
  );

  test('applies a bundle lyrics URL for the delayed loader', () async {
    final controller = PlayerController(
      resolver: FixedResolver(
        bundleSource(
          lyricsUri: Uri.parse(
            'http://service.local/api/v1/library/tracks/file-a/lyrics',
          ),
          completeness: PlaybackBundleCompleteness.mixed,
        ),
      ),
      audio: FakeAudio(),
    );
    await controller.play(track('local-match'));
    var calls = 0;

    await controller.loadLyrics((resolvedTrack) async {
      calls++;
      expect(
        (resolvedTrack.raw['meta'] as Map)['lyricsUrl'],
        'http://service.local/api/v1/library/tracks/file-a/lyrics',
      );
      return const Lyrics(original: '[00:01.00]loaded');
    });

    expect(calls, 1);
    expect(controller.state.lyrics?.original, '[00:01.00]loaded');
  });

  test('a stale bundle resolve cannot mutate a newer selected track', () async {
    final resolver = DeferredResolver();
    final controller = PlayerController(resolver: resolver, audio: FakeAudio());

    final first = controller.play(track('a'));
    await Future<void>.delayed(Duration.zero);
    final second = controller.play(track('b'));
    await Future<void>.delayed(Duration.zero);
    resolver.requests[1].complete(
      bundleSource(pictureUri: Uri.parse('http://service.local/b-picture')),
    );
    await second;
    resolver.requests[0].complete(
      bundleSource(pictureUri: Uri.parse('http://service.local/a-picture')),
    );
    await first;

    expect(controller.state.current?.id, 'b');
    expect(controller.state.current?.raw['pic'], endsWith('/b-picture'));
  });

  test('cached playback retains local artwork and lyrics resources', () async {
    final resolver = FakeResolver();
    final controller = PlayerController(
      resolver: resolver,
      audio: FakeAudio()..cached = true,
    );
    final local = Track.fromJson({
      'id': 'local',
      'source': 'local',
      'pic': '/api/v1/library/tracks/local/picture',
      'meta': {'lyricsUrl': '/api/v1/library/tracks/local/lyrics'},
    });

    await controller.play(local);

    expect(resolver.calls, 0);
    expect(controller.state.current?.raw['pic'], contains('/picture'));
    expect(
      (controller.state.current?.raw['meta'] as Map)['lyricsUrl'],
      contains('/lyrics'),
    );
  });

  test(
    'cached local playback refreshes missing lyrics and artwork without replacing audio',
    () async {
      final resolver = FixedResolver(
        bundleSource(
          lyrics: const Lyrics(original: '[00:01.00]resolved'),
          pictureUri: Uri.parse(
            'http://service.local/api/v1/playback/resources/token/picture',
          ),
          completeness: PlaybackBundleCompleteness.mixed,
        ),
      );
      final audio = FakeAudio()..cached = true;
      final controller = PlayerController(resolver: resolver, audio: audio);
      final local = Track.fromJson({
        'id': 'local-missing',
        'name': 'Fixture',
        'singer': 'Artist',
        'source': 'local',
      });

      await controller.play(local);
      await Future<void>.delayed(Duration.zero);

      expect(audio.playCalls, 0);
      expect(resolver.calls, 1);
      expect(controller.state.lyrics?.original, '[00:01.00]resolved');
      expect(controller.state.current?.raw['pic'], contains('/picture'));
      expect(
        controller.state.bundleCompleteness,
        PlaybackBundleCompleteness.mixed,
      );
    },
  );

  test(
    'cached local resource refresh failure does not fail playback',
    () async {
      final audio = FakeAudio()..cached = true;
      final controller = PlayerController(
        resolver: ErrorResolver(),
        audio: audio,
      );
      final local = Track.fromJson({
        'id': 'local-offline',
        'name': 'Fixture',
        'singer': 'Artist',
        'source': 'local',
      });

      await controller.play(local);
      await Future<void>.delayed(Duration.zero);

      expect(audio.playCalls, 0);
      expect(controller.state.current?.id, 'local-offline');
      expect(controller.state.error, isNull);
    },
  );

  test(
    'late cached local resource refresh cannot mutate a newer track',
    () async {
      final resolver = DeferredResolver();
      final audio = FakeAudio()..cached = true;
      final controller = PlayerController(resolver: resolver, audio: audio);
      final first = Track.fromJson({
        'id': 'local-a',
        'name': 'A',
        'source': 'local',
      });
      final second = Track.fromJson({
        'id': 'local-b',
        'name': 'B',
        'source': 'local',
      });

      await controller.play(first);
      await Future<void>.delayed(Duration.zero);
      await controller.play(second);
      await Future<void>.delayed(Duration.zero);
      resolver.requests[1].complete(
        bundleSource(pictureUri: Uri.parse('http://service.local/b-picture')),
      );
      await Future<void>.delayed(Duration.zero);
      resolver.requests[0].complete(
        bundleSource(pictureUri: Uri.parse('http://service.local/a-picture')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.current?.id, 'local-b');
      expect(controller.state.current?.raw['pic'], endsWith('/b-picture'));
    },
  );

  test('late lyric loading cannot overwrite a newly resolved bundle', () async {
    final resolver = DeferredResolver();
    final controller = PlayerController(resolver: resolver, audio: FakeAudio());
    final playing = controller.play(track('a'));
    await Future<void>.delayed(Duration.zero);
    final pending = Completer<Lyrics>();
    final loading = controller.loadLyrics((_) => pending.future);

    resolver.requests.single.complete(
      bundleSource(lyrics: const Lyrics(original: '[00:00.00]bundle')),
    );
    await playing;
    pending.complete(const Lyrics(original: '[00:00.00]stale'));
    await loading;

    expect(controller.state.lyrics?.original, '[00:00.00]bundle');
  });

  test(
    'successful playback starts a session and natural completion ends it',
    () async {
      final audio = FakeAudio();
      final sessions = FakeSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
        sessions: sessions,
      );

      await controller.play(track('a'));
      audio.controller.add(
        const AudioSnapshot(
          processing: PlayerProcessing.completed,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sessions.starts, ['a']);
      expect(sessions.ends, [
        (
          playbackId: 'play-1',
          completed: true,
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 30),
        ),
      ]);
    },
  );

  test(
    'switching tracks interrupts the old session before starting the new one',
    () async {
      final audio = FakeAudio();
      final sessions = FakeSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
        sessions: sessions,
      );
      await controller.playTracks([track('a'), track('b')]);
      audio.controller.add(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.ready,
          position: Duration(seconds: 12),
          duration: Duration(seconds: 100),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.next();

      expect(sessions.starts, ['a', 'b']);
      expect(sessions.ends, [
        (
          playbackId: 'play-1',
          completed: false,
          position: const Duration(seconds: 12),
          duration: const Duration(seconds: 100),
        ),
      ]);
    },
  );

  test(
    'switching while session start is pending ends the late old id',
    () async {
      final sessions = DeferredSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
        sessions: sessions,
      );

      final firstPlay = controller.play(track('a'));
      await Future<void>.delayed(Duration.zero);
      final secondPlay = controller.play(track('b'));
      await Future<void>.delayed(Duration.zero);
      expect(sessions.starts, ['a', 'b']);

      sessions.pendingStarts[0].complete('play-a');
      await firstPlay;
      sessions.pendingStarts[1].complete('play-b');
      await secondPlay;

      expect(sessions.ends.single, (
        playbackId: 'play-a',
        completed: false,
        position: Duration.zero,
        duration: Duration.zero,
      ));
    },
  );

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

  test('sequential completion advances to the next queued track', () async {
    final audio = FakeAudio();
    final controller = PlayerController(resolver: FakeResolver(), audio: audio);
    await controller.playTracks([track('a'), track('b')]);

    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.completed),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.current?.id, 'b');
    expect(audio.playCalls, 2);
  });

  test(
    'completed playback is presented as stopped when backend stays playing',
    () async {
      final audio = FakeAudio();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
      );
      await controller.play(track('a'));

      audio.controller.add(
        const AudioSnapshot(
          playing: true,
          processing: PlayerProcessing.completed,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 30),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.processing, PlayerProcessing.completed);
      expect(controller.state.playing, isFalse);
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
    'resource notification refreshes only the matching current track with missing lyrics',
    () async {
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.play(track('a'));
      var calls = 0;
      Future<Lyrics> loader(Track _) async {
        calls++;
        return const Lyrics(original: '[00:01]new line');
      }

      expect(
        await controller.refreshLyricsIfMissing(
          loader,
          source: 'kw',
          trackId: 'other',
        ),
        isFalse,
      );
      expect(
        await controller.refreshLyricsIfMissing(
          loader,
          source: 'kw',
          trackId: 'a',
        ),
        isTrue,
      );
      expect(
        await controller.refreshLyricsIfMissing(
          loader,
          source: 'kw',
          trackId: 'a',
        ),
        isFalse,
      );

      expect(calls, 1);
      expect(controller.state.lyrics?.original, '[00:01]new line');
    },
  );

  test(
    'reconnect lyric revalidation coalesces duplicate in-flight refreshes',
    () async {
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.play(track('a'));
      final completer = Completer<Lyrics>();
      var calls = 0;
      Future<Lyrics> loader(Track _) {
        calls++;
        return completer.future;
      }

      final first = controller.refreshLyricsIfMissing(loader);
      final second = controller.refreshLyricsIfMissing(loader);
      completer.complete(const Lyrics(original: '[00:01]connected'));

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(calls, 1);
    },
  );

  test(
    'a pending lyric refresh for an old track does not block the new track',
    () async {
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      final firstLyrics = Completer<Lyrics>();
      var firstCalls = 0;
      var secondCalls = 0;

      await controller.play(track('a'));
      final first = controller.refreshLyricsIfMissing((_) {
        firstCalls++;
        return firstLyrics.future;
      });
      await controller.play(track('b'));
      final second = controller.refreshLyricsIfMissing((_) async {
        secondCalls++;
        return const Lyrics(original: '[00:02]track b');
      });

      expect(await second, isTrue);
      firstLyrics.complete(const Lyrics(original: '[00:01]track a'));
      expect(await first, isFalse);
      expect(firstCalls, 1);
      expect(secondCalls, 1);
      expect(controller.state.current?.id, 'b');
      expect(controller.state.lyrics?.original, '[00:02]track b');
    },
  );

  test(
    'picture resource notification updates only the matching current track',
    () async {
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
      );
      await controller.play(track('a'));
      var calls = 0;

      expect(
        await controller.refreshArtworkIfMissing(
          (_) async {
            calls++;
            return '/api/v1/playback/resources/picture-token/picture';
          },
          source: 'kw',
          trackId: 'other',
        ),
        isFalse,
      );
      expect(
        await controller.refreshArtworkIfMissing(
          (_) async {
            calls++;
            return '/api/v1/playback/resources/picture-token/picture';
          },
          source: 'kw',
          trackId: 'a',
        ),
        isTrue,
      );

      expect(calls, 1);
      expect(controller.state.current?.raw['pic'], contains('picture-token'));
    },
  );

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

  test('successful cached playback reports once after audio starts', () async {
    final sessions = FakeSessions();
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio()..cached = true,
      sessions: sessions,
    );

    await controller.play(track('cached'));
    await Future<void>.delayed(Duration.zero);

    expect(sessions.starts, ['cached']);
  });

  test(
    'ready snapshot during previous session end remains authoritative',
    () async {
      final audio = FakeAudio()..cached = true;
      final sessions = DeferredEndSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
        sessions: sessions,
      );
      await controller.play(track('first'));
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);

      final switching = controller.play(track('second'));
      await Future<void>.delayed(Duration.zero);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);
      sessions.pendingEnds.single.complete();
      await switching;

      expect(controller.state.current?.id, 'second');
      expect(controller.state.processing, PlayerProcessing.ready);
    },
  );

  test(
    'ready snapshot during session end remains authoritative for queue selection',
    () async {
      final audio = FakeAudio()..cached = true;
      final sessions = DeferredEndSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
        sessions: sessions,
      );
      await controller.playTracks([track('first'), track('second')]);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);

      final switching = controller.playIndex(1);
      await Future<void>.delayed(Duration.zero);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);
      sessions.pendingEnds.single.complete();
      await switching;

      expect(controller.state.current?.id, 'second');
      expect(controller.state.processing, PlayerProcessing.ready);
    },
  );

  test(
    'ready snapshot during session end remains authoritative after removing current track',
    () async {
      final audio = FakeAudio()..cached = true;
      final sessions = DeferredEndSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: audio,
        sessions: sessions,
      );
      await controller.playTracks([track('first'), track('second')]);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);

      final removing = controller.removeAt(0);
      await Future<void>.delayed(Duration.zero);
      audio.controller.add(
        const AudioSnapshot(processing: PlayerProcessing.ready),
      );
      await Future<void>.delayed(Duration.zero);
      sessions.pendingEnds.single.complete();
      await removing;

      expect(controller.state.current?.id, 'second');
      expect(controller.state.processing, PlayerProcessing.ready);
    },
  );

  test(
    'successful streamed playback reports once after audio starts',
    () async {
      final sessions = FakeSessions();
      final controller = PlayerController(
        resolver: FakeResolver(),
        audio: FakeAudio(),
        sessions: sessions,
      );

      await controller.play(track('streamed'));
      await Future<void>.delayed(Duration.zero);

      expect(sessions.starts, ['streamed']);
    },
  );

  test('failed playback startup does not report', () async {
    final sessions = FakeSessions();
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio()..playError = StateError('startup failed'),
      sessions: sessions,
    );

    await controller.play(track('failed'));
    await Future<void>.delayed(Duration.zero);

    expect(sessions.starts, isEmpty);
    expect(controller.state.error, isA<StateError>());
  });

  test('ordinary pause and resume do not report again', () async {
    final sessions = FakeSessions();
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
      sessions: sessions,
    );
    await controller.play(track('streamed'));
    await Future<void>.delayed(Duration.zero);
    sessions.starts.clear();

    await controller.pause();
    await controller.resume();
    await Future<void>.delayed(Duration.zero);

    expect(sessions.starts, isEmpty);
  });

  test('reporting failure does not change successful playback state', () async {
    final sessions = FakeSessions()..startError = StateError('report failed');
    final controller = PlayerController(
      resolver: FakeResolver(),
      audio: FakeAudio(),
      sessions: sessions,
    );

    await controller.play(track('streamed'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.error, isNull);
  });

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
