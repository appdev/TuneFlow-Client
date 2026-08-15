import '../../api/models.dart';
import '../../api/service_api.dart';

abstract interface class PlaybackSessionPort {
  Future<String> start(Track track);

  Future<void> end(
    String playbackId, {
    required bool completed,
    required Duration position,
    required Duration duration,
  });
}

final class PlaybackHistoryRepository implements PlaybackSessionPort {
  const PlaybackHistoryRepository(this.api, {required this.platform});

  final ServiceApi api;
  final String platform;

  @override
  Future<String> start(Track track) async {
    final value = await api.request(
      'POST',
      '/api/v1/playback/history',
      body: {'track': track.toJson(), 'platform': platform},
    );
    if (value is! Map || value['playbackId'] is! String) {
      throw const FormatException(
        'Playback history response is missing playbackId.',
      );
    }
    final playbackId = value['playbackId'] as String;
    if (playbackId.isEmpty) {
      throw const FormatException(
        'Playback history response is missing playbackId.',
      );
    }
    return playbackId;
  }

  @override
  Future<void> end(
    String playbackId, {
    required bool completed,
    required Duration position,
    required Duration duration,
  }) async {
    await api.request(
      'PATCH',
      '/api/v1/playback/history/${Uri.encodeComponent(playbackId)}',
      body: {
        'completed': completed,
        'lastPositionSeconds': position.inMicroseconds / 1000000,
        'durationSeconds': duration.inMicroseconds / 1000000,
      },
    );
  }

  Future<List<PlaybackHistoryEntry>> readPlaybackHistory() async {
    final value = await api.request('GET', '/api/v1/playback/history');
    if (value is! List) return const [];
    final result = <PlaybackHistoryEntry>[];
    for (final item in value) {
      if (item is! Map) continue;
      final json = Map<String, Object?>.from(item);
      final trackJson = json['track'];
      final playedAt = json['startedAt'];
      if (trackJson is! Map || playedAt is! num) continue;
      try {
        result.add(
          PlaybackHistoryEntry(
            track: Track.fromJson(Map<String, Object?>.from(trackJson)),
            playedAt: DateTime.fromMillisecondsSinceEpoch(playedAt.toInt()),
          ),
        );
      } on Object {
        continue;
      }
      if (result.length == 50) break;
    }
    return List.unmodifiable(result);
  }
}

final class PlaybackHistoryEntry {
  const PlaybackHistoryEntry({required this.track, required this.playedAt});

  final Track track;
  final DateTime playedAt;
}
