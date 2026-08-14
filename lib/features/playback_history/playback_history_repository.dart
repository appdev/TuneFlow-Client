import '../../api/models.dart';
import '../../api/service_api.dart';

final class PlaybackHistoryRepository {
  const PlaybackHistoryRepository(this.api);

  final ServiceApi api;

  Future<void> recordPlayback(Track track) async {
    await api.request(
      'POST',
      '/api/v1/playback/history',
      body: {'track': track.toJson()},
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
      final playedAt = json['playedAt'];
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
