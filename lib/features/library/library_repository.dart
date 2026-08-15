import '../../api/models.dart';
import '../../api/service_api.dart';
import '../../api/service_exception.dart';

final class LibraryRepository {
  const LibraryRepository(this.api);
  final ServiceApi api;

  Future<List<LibraryTrack>> list() async => jsonList(
    await api.request('GET', '/api/v1/library/tracks'),
    'library',
  ).map(_trackFromJson).toList(growable: false);

  Future<List<LibraryTrack>> scan() async => jsonList(
    await api.request('POST', '/api/v1/library/scan'),
    'library',
  ).map(_trackFromJson).toList(growable: false);

  Future<void> delete(String id) => api.request(
    'DELETE',
    '/api/v1/library/tracks/${Uri.encodeComponent(id)}',
  );

  Uri streamUri(LibraryTrack track) => api.origin.resolve(track.streamPath);

  LibraryTrack _trackFromJson(Object? value) {
    final item = jsonObject(value, 'libraryTrack');
    final id = jsonString(item['id'], 'libraryTrack.id');
    final picturePath = _resourcePath(item['pictureUrl'], id, 'picture');
    final lyricsPath = _resourcePath(item['lyricsUrl'], id, 'lyrics');
    final musicInfo = jsonObject(item['musicInfo'], 'libraryTrack.musicInfo');
    final meta = musicInfo['meta'] == null
        ? <String, Object?>{}
        : jsonObject(musicInfo['meta'], 'libraryTrack.musicInfo.meta');
    meta.remove('lyricsUrl');
    final pictureUrl = picturePath == null
        ? null
        : api.origin.resolve(picturePath).toString();
    musicInfo.remove('pic');
    return LibraryTrack.fromJson({
      ...item,
      if (pictureUrl != null) 'pictureUrl': pictureUrl,
      'musicInfo': {
        ...musicInfo,
        if (pictureUrl != null) 'pic': pictureUrl,
        'meta': {...meta, if (lyricsPath != null) 'lyricsUrl': lyricsPath},
      },
    });
  }

  String? _resourcePath(Object? value, String id, String kind) {
    if (value == null) return null;
    final expected = '/api/v1/library/tracks/${Uri.encodeComponent(id)}/$kind';
    if (value is! String) {
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid libraryTrack.${kind}Url field.',
        details: {'field': 'libraryTrack.${kind}Url'},
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value != expected ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid libraryTrack.${kind}Url field.',
        details: {'field': 'libraryTrack.${kind}Url'},
      );
    }
    return value;
  }
}
