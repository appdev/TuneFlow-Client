import '../../api/models.dart';
import '../../api/service_api.dart';
import '../../api/service_exception.dart';

final class PlaybackSource {
  const PlaybackSource({
    required this.resolved,
    required this.streamUri,
    this.bundleLyrics,
    this.lyricsUri,
    this.pictureUri,
  });
  final ResolvedTrack resolved;
  final Uri streamUri;
  final Lyrics? bundleLyrics;
  final Uri? lyricsUri;
  final Uri? pictureUri;
}

abstract interface class PlaybackResolver {
  Future<PlaybackSource> resolve(Track track, String quality);
}

final class PlaybackRepository implements PlaybackResolver {
  const PlaybackRepository(this.api);
  final ServiceApi api;

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async {
    final resolved = ResolvedTrack.fromJson(
      await api.request(
        'POST',
        '/api/v1/playback/tracks/resolve',
        body: {
          'source': track.source,
          'quality': quality,
          'preferLocal': true,
          'info': track.toServiceMusicInfoJson(),
        },
      ),
    );
    final streamUri = _resolveServicePath(
      api,
      resolved.url,
      code: 'INVALID_STREAM_URL',
      isAllowed: _isStreamPath,
    );
    final resources = resolved.resources;
    final lyricsUri = resources?.lyricsUrl == null
        ? null
        : _resolveServicePath(
            api,
            resources!.lyricsUrl!,
            code: 'INVALID_RESOURCE_URL',
            isAllowed: _isLyricsPath,
          );
    final pictureUri = resources?.pictureUrl == null
        ? null
        : _resolveServicePath(
            api,
            resources!.pictureUrl!,
            code: 'INVALID_RESOURCE_URL',
            isAllowed: _isPicturePath,
          );
    return PlaybackSource(
      resolved: resolved,
      streamUri: streamUri,
      bundleLyrics: resources?.lyrics,
      lyricsUri: lyricsUri,
      pictureUri: pictureUri,
    );
  }
}

Uri _resolveServicePath(
  ServiceApi api,
  String value, {
  required String code,
  required bool Function(List<String> segments) isAllowed,
}) {
  final uri = Uri.tryParse(value);
  final segments = uri?.pathSegments ?? const <String>[];
  if (uri == null ||
      !value.startsWith('/') ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      !isAllowed(segments)) {
    throw ServiceException(code, 'Service returned an invalid resource URL.');
  }
  return api.origin.resolve(value);
}

bool _isStreamPath(List<String> segments) =>
    (segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'streams' &&
        segments[3].isNotEmpty) ||
    _isLibraryResourcePath(segments, 'stream');

bool _isLyricsPath(List<String> segments) =>
    _isLibraryResourcePath(segments, 'lyrics');

bool _isPicturePath(List<String> segments) =>
    _isLibraryResourcePath(segments, 'picture') ||
    (segments.length == 6 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'playback' &&
        segments[3] == 'resources' &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(segments[4]) &&
        segments[5] == 'picture');

bool _isLibraryResourcePath(List<String> segments, String resource) =>
    segments.length == 6 &&
    segments[0] == 'api' &&
    segments[1] == 'v1' &&
    segments[2] == 'library' &&
    segments[3] == 'tracks' &&
    segments[4].isNotEmpty &&
    segments[5] == resource;
