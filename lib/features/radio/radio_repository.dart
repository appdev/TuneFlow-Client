import '../../api/models.dart';
import '../../api/service_api.dart';
import 'radio_models.dart';

abstract interface class RadioSessionPort {
  Future<RadioBatch> create({
    required RadioMode mode,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = radioBatchSize,
  });
  Future<RadioBatch> next({
    required String sessionId,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = radioBatchSize,
  });
  Future<void> close(String sessionId);
}

final class RadioRepository implements RadioSessionPort {
  const RadioRepository(this.api);
  final ServiceApi api;

  Map<String, Object?> _batch({
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    required List<Track> queuedTracks,
    required int limit,
  }) => {
    'requestId': requestId,
    'queueGeneration': queueGeneration,
    'currentTrack': currentTrack?.toServiceMusicInfoJson(),
    'queuedTracks': queuedTracks
        .map((track) => track.toServiceMusicInfoJson())
        .toList(growable: false),
    'limit': limit,
  };

  @override
  Future<RadioBatch> create({
    required RadioMode mode,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = radioBatchSize,
  }) async => RadioBatch.fromJson(
    await api.request(
      'POST',
      '/api/v1/radio/sessions',
      body: {
        'mode': mode == RadioMode.dedicated
            ? 'dedicated'
            : 'queue_continuation',
        ..._batch(
          queueGeneration: queueGeneration,
          requestId: requestId,
          currentTrack: currentTrack,
          queuedTracks: queuedTracks,
          limit: limit,
        ),
      },
    ),
  );

  @override
  Future<RadioBatch> next({
    required String sessionId,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = radioBatchSize,
  }) async => RadioBatch.fromJson(
    await api.request(
      'POST',
      '/api/v1/radio/sessions/${Uri.encodeComponent(sessionId)}/next',
      body: _batch(
        queueGeneration: queueGeneration,
        requestId: requestId,
        currentTrack: currentTrack,
        queuedTracks: queuedTracks,
        limit: limit,
      ),
    ),
  );

  Future<RadioBatch> get(String sessionId) async => RadioBatch.fromJson(
    await api.request(
      'GET',
      '/api/v1/radio/sessions/${Uri.encodeComponent(sessionId)}',
    ),
  );

  @override
  Future<void> close(String sessionId) async {
    await api.request(
      'DELETE',
      '/api/v1/radio/sessions/${Uri.encodeComponent(sessionId)}',
    );
  }

  Future<RadioAiServiceStatus> status() async => RadioAiServiceStatus.fromJson(
    await api.request('GET', '/api/v1/recommendations/ai/status'),
  );
  Future<bool> testConnection() async =>
      (await api.request('POST', '/api/v1/recommendations/ai/test')
          as Map)['ok'] ==
      true;
  Future<RadioAiServiceStatus> reanalyze() async =>
      RadioAiServiceStatus.fromJson(
        await api.request('POST', '/api/v1/recommendations/ai/reanalyze'),
      );
}
