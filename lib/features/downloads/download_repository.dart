import '../../api/models.dart';
import '../../api/service_api.dart';

enum ExistingFilePolicy {
  reuse('reuse'),
  error('error'),
  replace('replace'),
  duplicate('duplicate');

  const ExistingFilePolicy(this.wireName);

  final String wireName;
}

final class DownloadRepository {
  const DownloadRepository(this.api);
  final ServiceApi api;

  Future<List<DownloadJob>> list() async => jsonList(
    await api.request('GET', '/api/v1/downloads'),
    'downloads',
  ).map(DownloadJob.fromJson).toList(growable: false);

  Future<String> picture(Track track) async {
    final value = await api.request(
      'POST',
      '/api/v1/catalog/tracks/picture',
      body: {
        'source': track.source,
        'musicInfo': track.toServiceMusicInfoJson(),
      },
    );
    final json = jsonObject(value, 'picture');
    return jsonString(json['url'], 'picture.url');
  }

  Future<DownloadJob> create(
    Track track,
    String quality, {
    Object? qualityList,
    String? listId,
    ExistingFilePolicy? existingFilePolicy,
  }) async {
    final body = <String, Object?>{
      'musicInfo': track.toServiceMusicInfoJson(),
      'quality': quality,
      if (qualityList != null) 'qualityList': qualityList,
      if (listId != null) 'listId': listId,
      if (existingFilePolicy != null)
        'existingFilePolicy': existingFilePolicy.wireName,
    };
    return DownloadJob.fromJson(
      await api.request('POST', '/api/v1/downloads', body: body),
    );
  }

  Future<DownloadJob> start(String id) => _action(id, 'start');
  Future<DownloadJob> pause(String id) => _action(id, 'pause');
  Future<DownloadJob> resume(String id) => _action(id, 'resume');
  Future<int> clearHistory() async {
    final json = jsonObject(
      await api.request('DELETE', '/api/v1/downloads/history/records'),
      'clearDownloadHistory',
    );
    return jsonInt(json['cleared'], 'clearDownloadHistory.cleared');
  }

  Future<DownloadJob> _action(String id, String action) async =>
      DownloadJob.fromJson(
        await api.request(
          'POST',
          '/api/v1/downloads/${Uri.encodeComponent(id)}/$action',
        ),
      );
  Future<void> delete(String id) =>
      api.request('DELETE', '/api/v1/downloads/${Uri.encodeComponent(id)}');
}
