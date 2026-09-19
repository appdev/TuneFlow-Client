import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/radio/radio_controller.dart';
import 'package:musicfree_service_client/features/radio/radio_models.dart';
import 'package:musicfree_service_client/features/radio/radio_repository.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_models.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Track track(String id) =>
    Track.fromJson({'id': id, 'source': 'kw', 'name': 'Track $id'});

RadioBatch batch({
  required String sessionId,
  required int start,
  int count = 10,
  RadioMode mode = RadioMode.dedicated,
}) => RadioBatch(
  sessionId: sessionId,
  mode: mode,
  status: RadioBatchStatus.active,
  aiStatus: RadioAiStatus.enhanced,
  items: List.generate(count, (offset) {
    final id = '${start + offset}';
    return RadioItem(
      recommendationItemId: 'item-$id',
      radioSessionId: sessionId,
      canonicalTrackId: 'canonical-$id',
      track: track(id),
      rankingSource: RadioRankingSource.ai,
      reason: const RecommendationReason(
        type: RecommendationReasonType.exploration,
        labels: [],
      ),
    );
  }),
);

final class _RadioRepository implements RadioSessionPort {
  final RadioBatch initial = batch(sessionId: 'radio-1', start: 0);
  final Completer<RadioBatch> nextGate = Completer<RadioBatch>();
  Completer<RadioBatch>? createGate;
  final List<int> createLimits = [];
  final List<int> nextLimits = [];
  final List<String> closed = [];
  int nextCalls = 0;

  @override
  Future<RadioBatch> create({
    required RadioMode mode,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 10,
  }) async {
    createLimits.add(limit);
    return createGate == null ? initial : await createGate!.future;
  }

  @override
  Future<RadioBatch> next({
    required String sessionId,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 10,
  }) {
    nextCalls++;
    nextLimits.add(limit);
    return nextGate.future;
  }

  @override
  Future<void> close(String sessionId) async => closed.add(sessionId);
}

final class _Resolver implements PlaybackResolver {
  int calls = 0;

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async {
    calls++;
    return PlaybackSource(
      resolved: ResolvedTrack(
        url: '/api/v1/streams/token',
        quality: quality,
        expiresAt: 1,
      ),
      streamUri: Uri.parse('http://service.local/api/v1/streams/token'),
    );
  }
}

final class _Audio implements AudioPort {
  final StreamController<AudioSnapshot> controller =
      StreamController<AudioSnapshot>.broadcast();

  @override
  Stream<AudioSnapshot> get snapshots => controller.stream;
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

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('starts with ten tracks and resolves only the current track', () async {
    final repository = _RadioRepository();
    final resolver = _Resolver();
    final audio = _Audio();
    final player = PlayerController(resolver: resolver, audio: audio);
    final controller = RadioController(repository: repository, player: player);
    addTearDown(() async {
      controller.dispose();
      player.dispose();
      await audio.controller.close();
    });

    expect(await controller.startDedicated(), isTrue);

    expect(repository.createLimits, [10]);
    expect(player.state.queue, hasLength(10));
    expect(resolver.calls, 1);
  });

  test(
    'prefetches once when two tracks remain and appends without resolving',
    () async {
      final repository = _RadioRepository();
      final resolver = _Resolver();
      final audio = _Audio();
      final player = PlayerController(resolver: resolver, audio: audio);
      final controller = RadioController(
        repository: repository,
        player: player,
      );
      addTearDown(() async {
        controller.dispose();
        player.dispose();
        await audio.controller.close();
      });
      await controller.startDedicated();

      await player.playIndex(7);
      player.notifyListeners();
      player.notifyListeners();

      expect(repository.nextCalls, 1);
      expect(repository.nextLimits, [10]);
      repository.nextGate.complete(batch(sessionId: 'radio-1', start: 10));
      await flushAsync();

      expect(player.state.queue, hasLength(20));
      expect(resolver.calls, 2);
    },
  );

  test('queue end waits for the shared prefetch before advancing', () async {
    final repository = _RadioRepository();
    final resolver = _Resolver();
    final audio = _Audio();
    final player = PlayerController(resolver: resolver, audio: audio);
    final controller = RadioController(repository: repository, player: player);
    addTearDown(() async {
      controller.dispose();
      player.dispose();
      await audio.controller.close();
    });
    await controller.startDedicated();
    await player.playIndex(7);
    await player.playIndex(9);

    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.completed),
    );
    await flushAsync();
    expect(repository.nextCalls, 1);
    expect(player.state.currentIndex, 9);

    repository.nextGate.complete(batch(sessionId: 'radio-1', start: 10));
    await flushAsync();

    expect(player.state.currentIndex, 10);
    expect(repository.nextCalls, 1);
  });

  test('stopping invalidates a late prefetch result', () async {
    final repository = _RadioRepository();
    final resolver = _Resolver();
    final audio = _Audio();
    final player = PlayerController(resolver: resolver, audio: audio);
    final controller = RadioController(repository: repository, player: player);
    addTearDown(() async {
      controller.dispose();
      player.dispose();
      await audio.controller.close();
    });
    await controller.startDedicated();
    await player.playIndex(7);
    expect(repository.nextCalls, 1);

    await controller.stop();
    repository.nextGate.complete(batch(sessionId: 'radio-1', start: 10));
    await flushAsync();

    expect(controller.state.session, isNull);
    expect(player.state.queue, hasLength(10));
    expect(repository.closed, contains('radio-1'));
  });

  for (final empty in [false, true]) {
    test(
      'prefetch ${empty ? 'empty' : 'failure'} backs off across progress updates',
      () async {
        final repository = _RadioRepository();
        final audio = _Audio();
        final player = PlayerController(resolver: _Resolver(), audio: audio);
        var now = DateTime(2026);
        final controller = RadioController(
          repository: repository,
          player: player,
          clock: () => now,
        );
        addTearDown(() async {
          controller.dispose();
          player.dispose();
          await audio.controller.close();
        });
        await controller.startDedicated();
        await player.playIndex(7);
        if (empty) {
          repository.nextGate.complete(
            batch(sessionId: 'radio-1', start: 10, count: 0),
          );
        } else {
          repository.nextGate.completeError(StateError('unavailable'));
        }
        await flushAsync();
        for (var i = 0; i < 10; i++) {
          player.notifyListeners();
          await flushAsync();
        }
        expect(repository.nextCalls, 1);
        now = now.add(const Duration(seconds: 31));
        player.notifyListeners();
        await flushAsync();
        expect(repository.nextCalls, 2);
      },
    );
  }

  test(
    'disabling automatic continuation discards an in-flight manual prefetch',
    () async {
      final repository = _RadioRepository()
        ..createGate = Completer<RadioBatch>();
      final audio = _Audio();
      final player = PlayerController(resolver: _Resolver(), audio: audio);
      final controller = RadioController(
        repository: repository,
        player: player,
      );
      addTearDown(() async {
        controller.dispose();
        player.dispose();
        await audio.controller.close();
      });
      await flushAsync();
      await player.play(track('manual'));
      await controller.setAutoContinuation(true);
      expect(repository.createLimits, hasLength(1));
      await controller.setAutoContinuation(false);
      repository.createGate!.complete(batch(sessionId: 'late', start: 10));
      await flushAsync();
      expect(player.state.queue.map((item) => item.id), ['manual']);
      expect(controller.state.session, isNull);
      expect(repository.closed, contains('late'));
    },
  );

  test(
    'clearing the queue does not allow a late prefetch to refill it',
    () async {
      final repository = _RadioRepository();
      final resolver = _Resolver();
      final audio = _Audio();
      final player = PlayerController(resolver: resolver, audio: audio);
      final controller = RadioController(
        repository: repository,
        player: player,
      );
      addTearDown(() async {
        controller.dispose();
        player.dispose();
        await audio.controller.close();
      });
      await controller.startDedicated();
      await player.playIndex(7);
      expect(repository.nextCalls, 1);

      expect(await player.clearQueue(), isTrue);
      await flushAsync();
      repository.nextGate.complete(batch(sessionId: 'radio-1', start: 10));
      await flushAsync();

      expect(player.state.queue, isEmpty);
      expect(controller.state.session, isNull);
    },
  );

  test('disposing during prefetch discards the result', () async {
    final repository = _RadioRepository();
    final resolver = _Resolver();
    final audio = _Audio();
    final player = PlayerController(resolver: resolver, audio: audio);
    final controller = RadioController(repository: repository, player: player);
    await controller.startDedicated();
    await player.playIndex(7);

    controller.dispose();
    repository.nextGate.complete(batch(sessionId: 'radio-1', start: 10));
    await flushAsync();

    expect(player.state.queue, hasLength(10));
    player.dispose();
    await audio.controller.close();
  });
}
