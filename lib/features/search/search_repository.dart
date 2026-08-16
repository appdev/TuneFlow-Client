import '../../api/models.dart';
import '../../api/service_api.dart';
import '../../api/service_exception.dart';

final class SearchRepository {
  const SearchRepository(this.api);
  final ServiceApi api;

  Future<CatalogCapabilities> capabilities() async =>
      CatalogCapabilities.fromJson(
        await api.request('GET', '/api/v1/catalog/capabilities'),
      );

  Future<SearchPage> search({
    required String source,
    required String text,
    required int page,
    required int pageSize,
  }) async {
    final value = await api.request(
      'POST',
      '/api/v1/catalog/tracks/search',
      body: {
        'source': source,
        'text': text,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return SearchPage.fromJson(value);
  }

  Future<CollectionSearchPage> searchCollections({
    required CatalogSearchKind kind,
    required String source,
    required String text,
    required int page,
    required int pageSize,
  }) async {
    if (kind == CatalogSearchKind.track) {
      throw ArgumentError.value(kind, 'kind', 'Use search for tracks.');
    }
    final segment = kind == CatalogSearchKind.playlist ? 'playlists' : 'albums';
    return CollectionSearchPage.fromJson(
      await api.request(
        'POST',
        '/api/v1/catalog/$segment/search',
        body: {
          'source': source,
          'text': text,
          'page': page,
          'pageSize': pageSize,
        },
      ),
    );
  }

  Future<Lyrics> lyrics(Track track) async {
    final meta = track.raw['meta'];
    final value = meta is Map ? meta['lyricsUrl'] : null;
    final resourcePath = value is String ? _lyricsResourcePath(value) : null;
    if (resourcePath != null) {
      return Lyrics.fromJson(await api.request('GET', resourcePath));
    }
    return Lyrics.fromJson(
      await api.request(
        'POST',
        '/api/v1/catalog/tracks/lyrics',
        body: {
          'source': track.source,
          'musicInfo': track.toServiceMusicInfoJson(),
        },
      ),
    );
  }

  String? _lyricsResourcePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final origin = api.origin.uri;
    if (uri.hasScheme &&
        (uri.scheme != origin.scheme ||
            uri.host != origin.host ||
            uri.port != origin.port)) {
      return null;
    }
    if (!uri.hasScheme && (uri.hasAuthority || !value.startsWith('/'))) {
      return null;
    }
    final segments = uri.pathSegments;
    final valid =
        segments.length == 6 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'library' &&
        segments[3] == 'tracks' &&
        segments[4].isNotEmpty &&
        segments[5] == 'lyrics';
    return valid ? uri.path : null;
  }

  Future<LeaderboardPage> leaderboards({required String source}) async =>
      LeaderboardPage.fromJson(
        await api.request(
          'POST',
          '/api/v1/catalog/leaderboards',
          body: {'source': source},
        ),
      );

  Future<LeaderboardTrackPage> leaderboardTracks({
    required String source,
    required String boardId,
    required int page,
  }) async => LeaderboardTrackPage.fromJson(
    await api.request(
      'POST',
      '/api/v1/catalog/leaderboards/tracks',
      body: {'source': source, 'boardId': boardId, 'page': page},
    ),
  );

  Future<PlaylistDiscoveryFilters> playlistTags({
    required String source,
  }) async => PlaylistDiscoveryFilters.fromJson(
    await api.request(
      'POST',
      '/api/v1/catalog/playlists/tags',
      body: {'source': source},
    ),
  );

  Future<PlaylistBrowsePage> browsePlaylists({
    required String source,
    required String sortId,
    required String tagId,
    required int page,
  }) async => PlaylistBrowsePage.fromJson(
    await api.request(
      'POST',
      '/api/v1/catalog/playlists/browse',
      body: {'source': source, 'sortId': sortId, 'tagId': tagId, 'page': page},
    ),
  );

  Future<OnlinePlaylistPage> onlinePlaylist({
    required String source,
    required String playlistId,
    required int page,
  }) async => OnlinePlaylistPage.fromJson(
    await api.request(
      'POST',
      '/api/v1/catalog/playlists/detail',
      body: {'source': source, 'playlistId': playlistId, 'page': page},
    ),
  );

  Future<AlbumDetailPage> album({
    required String source,
    required String albumId,
    required int page,
  }) async => AlbumDetailPage.fromJson(
    await api.request(
      'POST',
      '/api/v1/catalog/albums/detail',
      body: {'source': source, 'albumId': albumId, 'page': page},
    ),
  );

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
    final path = _pictureResourcePath(jsonString(json['url'], 'picture.url'));
    if (path == null) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid picture.url field.',
        details: {'field': 'picture.url'},
      );
    }
    return api.origin.resolve(path).toString();
  }

  String? _pictureResourcePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final origin = api.origin.uri;
    if (uri.hasScheme &&
        (uri.scheme != origin.scheme ||
            uri.host != origin.host ||
            uri.port != origin.port)) {
      return null;
    }
    if (!uri.hasScheme && (uri.hasAuthority || !value.startsWith('/'))) {
      return null;
    }
    final segments = uri.pathSegments;
    final valid =
        segments.length == 6 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'playback' &&
        segments[3] == 'resources' &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(segments[4]) &&
        segments[5] == 'picture';
    return valid ? uri.path : null;
  }
}
