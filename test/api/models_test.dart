import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_exception.dart';

void main() {
  test('Track preserves provider metadata while requiring an id', () {
    final track = Track.fromJson({
      'id': 'kw_1',
      'name': 'Song',
      'singer': 'Artist',
      'source': 'kw',
      'interval': '03:30',
      'providerOnly': {'albumId': 'a1'},
    });

    expect(track.id, 'kw_1');
    expect(track.title, 'Song');
    expect(track.artist, 'Artist');
    expect(track.raw['providerOnly'], {'albumId': 'a1'});
    expect(
      () => Track.fromJson({'name': 'missing'}),
      throwsA(isA<ServiceException>()),
    );
  });

  test('Track normalizes LX provider songmid for resource API writes', () {
    final track = Track.fromJson({
      'songmid': '48214177',
      'name': 'Provider result',
      'source': 'kw',
    });

    expect(track.id, '48214177');
    expect(track.toJson()['songmid'], '48214177');
    expect(track.toJson()['id'], '48214177');
  });

  test('Track normalizes the Service img field for artwork consumers', () {
    const url = 'https://cdn.example.test/cover.jpg';
    final track = Track.fromJson({
      'songmid': 'cover-1',
      'name': 'Cover song',
      'source': 'wy',
      'img': url,
    });

    expect(track.raw['pic'], url);
  });

  test('Track normalizes persisted meta.picUrl for artwork consumers', () {
    const url = 'https://cdn.example.test/persisted-cover.jpg';
    final track = Track.fromJson({
      'id': 'cover-2',
      'name': 'Persisted song',
      'source': 'kw',
      'meta': {'picUrl': url},
    });

    expect(track.raw['pic'], url);
  });

  test('Track serializes legacy Web query context for Service requests', () {
    final track = Track.fromJson({
      'id': 'legacy-id',
      'songmid': 'song-mid',
      'name': '大梦',
      'singer': '瓦依那、任素汐',
      'source': 'tx',
      'albumName': '专辑',
      'albumId': 'album-id',
      'img': 'https://img.example.test/cover.jpg',
      'types': <Object?>[
        <String, Object?>{'type': '128k', 'size': '123'},
      ],
      '_types': <String, Object?>{
        'high': <String, Object?>{'size': '456'},
      },
      'strMediaMid': 'media-mid',
      'songId': 'qq-id',
      'albumMid': 'album-mid',
    });

    final serialized = track.toServiceMusicInfoJson();
    final meta = Map<String, Object?>.from(serialized['meta']! as Map);

    expect(meta['songId'], 'song-mid');
    expect(meta['albumName'], '专辑');
    expect(meta['albumId'], 'album-id');
    expect(meta['picUrl'], 'https://img.example.test/cover.jpg');
    expect(meta['qualitys'], track.raw['types']);
    expect(meta['_qualitys'], track.raw['_types']);
    expect(meta['strMediaMid'], 'media-mid');
    expect(meta['id'], 'qq-id');
    expect(meta['albumMid'], 'album-mid');
    expect(track.raw['pic'], 'https://img.example.test/cover.jpg');
  });

  test('Track Service artwork precedence rejects non-HTTP candidates', () {
    final canonical = Track.fromJson({
      'id': 'cover-3',
      'source': 'wy',
      'meta': {'songId': 'cover-3', 'picUrl': 'https://canonical.test/a.jpg'},
      'img': 'https://img.test/a.jpg',
      'pic': 'https://pic.test/a.jpg',
    });
    final legacy = Track.fromJson({
      'id': 'cover-4',
      'source': 'wy',
      'meta': {'songId': 'cover-4', 'picUrl': 'file:///tmp/a.jpg'},
      'img': 'data:image/png;base64,AA==',
      'pic': 'https://pic.test/a.jpg',
    });

    expect(
      (canonical.toServiceMusicInfoJson()['meta']! as Map)['picUrl'],
      'https://canonical.test/a.jpg',
    );
    expect(
      (legacy.toServiceMusicInfoJson()['meta']! as Map)['picUrl'],
      'https://pic.test/a.jpg',
    );
  });

  test('Track preserves Kugou and Migu Service query fields', () {
    final kugou = Track.fromJson({
      'id': 'kg-id',
      'songmid': 'kg-song',
      'source': 'kg',
      'hash': 'kg-hash',
    });
    final migu = Track.fromJson({
      'id': 'mg-id',
      'songmid': 'mg-song',
      'source': 'mg',
      'copyrightId': 'copyright-id',
      'lrcUrl': 'lrc',
      'mrcUrl': 'mrc',
      'trcUrl': 'trc',
    });

    expect((kugou.toServiceMusicInfoJson()['meta']! as Map)['hash'], 'kg-hash');
    expect(
      migu.toServiceMusicInfoJson()['meta'],
      containsPair('copyrightId', 'copyright-id'),
    );
    expect(
      migu.toServiceMusicInfoJson()['meta'],
      containsPair('lrcUrl', 'lrc'),
    );
    expect(
      migu.toServiceMusicInfoJson()['meta'],
      containsPair('mrcUrl', 'mrc'),
    );
    expect(
      migu.toServiceMusicInfoJson()['meta'],
      containsPair('trcUrl', 'trc'),
    );
  });

  test('Leaderboard pages retain board ids and real track artwork', () {
    final boards = LeaderboardPage.fromJson({
      'list': [
        {'id': 'wy__3778678', 'bangid': '3778678', 'name': '热歌榜'},
      ],
      'source': 'wy',
    });
    final tracks = LeaderboardTrackPage.fromJson({
      'list': [
        {
          'songmid': 'song-1',
          'name': '真实歌曲',
          'source': 'wy',
          'img': 'https://cdn.example.test/song.jpg',
        },
      ],
      'total': 1,
      'page': 1,
      'limit': 30,
      'source': 'wy',
    });

    expect(boards.items.single.providerId, '3778678');
    expect(
      tracks.tracks.single.raw['pic'],
      'https://cdn.example.test/song.jpg',
    );
  });

  test('PlaylistDetail parses tracks and event snapshot is strict', () {
    final playlist = PlaylistDetail.fromJson({
      'id': 'list_1',
      'name': 'Favorites',
      'locationUpdateTime': null,
      'tracks': [
        {'id': 'track_1', 'name': 'One'},
      ],
    });
    final snapshot = EventSnapshot.fromJson({
      'sequence': 2,
      'events': [
        {'type': 'playlists.updated', 'data': [], 'sequence': 2},
      ],
    });

    expect(playlist.tracks.single.id, 'track_1');
    expect(snapshot.events.single.type, 'playlists.updated');
    expect(
      () => EventSnapshot.fromJson({'sequence': '2', 'events': []}),
      throwsA(isA<ServiceException>()),
    );
  });

  test('SearchPage normalizes provider ids and preserves total', () {
    final page = SearchPage.fromJson({
      'list': [
        {'songmid': 'm1', 'name': 'Song', 'source': 'kw'},
      ],
      'total': 31,
    });

    expect(page.tracks.single.id, 'm1');
    expect(page.total, 31);
    expect(
      () => SearchPage.fromJson({'list': 'invalid', 'total': 1}),
      throwsA(isA<ServiceException>()),
    );
  });

  test('Lyrics requires original text and accepts translation', () {
    final lyrics = Lyrics.fromJson({'lyric': 'line', 'tlyric': 'translated'});

    expect(lyrics.original, 'line');
    expect(lyrics.translation, 'translated');
    expect(
      () => Lyrics.fromJson({'lyric': 1}),
      throwsA(isA<ServiceException>()),
    );
    expect(
      () => Lyrics.fromJson({'lyric': '[00:01]���� - ������'}),
      throwsA(isA<ServiceException>()),
    );
  });

  test('resolved playback bundles parse optional resources compatibly', () {
    final legacy = ResolvedTrack.fromJson({
      'url': '/api/v1/streams/legacy',
      'quality': '128k',
      'expiresAt': 1000,
    });
    final complete = ResolvedTrack.fromJson({
      'url': '/api/v1/streams/token',
      'quality': '320k',
      'expiresAt': 2000,
      'resources': {
        'lyrics': {'lyric': '[00:00.00]bundle', 'tlyric': '翻译'},
        'pictureUrl': '/api/v1/playback/resources/picture-token/picture',
      },
      'completeness': 'complete',
    });
    final local = ResolvedTrack.fromJson({
      'url': '/api/v1/library/tracks/file-a/stream',
      'quality': '128k',
      'expiresAt': 0,
      'resources': {
        'lyricsUrl': '/api/v1/library/tracks/file-a/lyrics',
        'pictureUrl': '/api/v1/library/tracks/file-a/picture',
      },
      'completeness': 'audio-only',
    });

    expect(legacy.resources, isNull);
    expect(legacy.completeness, isNull);
    expect(complete.resources?.lyrics?.original, '[00:00.00]bundle');
    expect(complete.resources?.pictureUrl, contains('picture-token'));
    expect(complete.completeness, PlaybackBundleCompleteness.complete);
    expect(local.resources?.lyricsUrl, contains('/lyrics'));
    expect(local.completeness, PlaybackBundleCompleteness.audioOnly);
  });

  test('resolved playback resources reject ambiguous or malformed fields', () {
    Map<String, Object?> response(Map<String, Object?> resources) => {
      'url': '/api/v1/streams/token',
      'quality': '128k',
      'expiresAt': 1000,
      'resources': resources,
      'completeness': 'mixed',
    };

    expect(
      () => ResolvedTrack.fromJson(
        response({
          'lyrics': {'lyric': 'embedded'},
          'lyricsUrl': '/api/v1/library/tracks/a/lyrics',
        }),
      ),
      throwsA(isA<ServiceException>()),
    );
    expect(
      () => ResolvedTrack.fromJson(response({'pictureUrl': 3})),
      throwsA(isA<ServiceException>()),
    );
    expect(
      () => ResolvedTrack.fromJson({...response({}), 'completeness': 'best'}),
      throwsA(isA<ServiceException>()),
    );
  });

  test(
    'catalog capabilities and collection pages keep provider feature gates',
    () {
      final capabilities = CatalogCapabilities.fromJson({
        'sources': [
          {
            'id': 'wy',
            'name': '网易云音乐',
            'searchKinds': ['track', 'playlist', 'album'],
            'albumDetail': true,
          },
        ],
      });
      final page = CollectionSearchPage.fromJson({
        'list': [
          {
            'id': 'album-1',
            'kind': 'album',
            'name': 'Album',
            'source': 'wy',
            'total': 12,
          },
        ],
        'total': 1,
      });

      expect(
        capabilities.providers.single.searchKinds,
        contains(CatalogSearchKind.album),
      );
      expect(capabilities.providers.single.albumDetail, isTrue);
      expect(page.items.single.kind, CatalogSearchKind.album);
      expect(page.items.single.total, 12);
    },
  );

  test('album detail pages preserve metadata, tracks, and paging', () {
    final page = AlbumDetailPage.fromJson({
      'source': 'wy',
      'page': 1,
      'limit': 30,
      'total': 1,
      'hasMore': false,
      'album': {
        'id': 'album-1',
        'kind': 'album',
        'name': '叶惠美',
        'source': 'wy',
        'author': '周杰伦',
      },
      'tracks': [
        {'id': 'track-1', 'name': '以父之名', 'source': 'wy'},
      ],
    });

    expect(page.album.kind, CatalogSearchKind.album);
    expect(page.album.author, '周杰伦');
    expect(page.tracks.single.id, 'track-1');
    expect(page.hasMore, isFalse);
  });

  test('playlist discovery capabilities are explicit and optional', () {
    final enabled = CatalogCapabilities.fromJson({
      'sources': [
        {
          'id': 'kw',
          'name': '酷我音乐',
          'searchKinds': ['track', 'playlist'],
          'playlistDiscovery': {'tags': true, 'browse': true, 'detail': true},
        },
        {
          'id': 'legacy',
          'name': 'Legacy',
          'searchKinds': ['track'],
        },
      ],
    });

    expect(enabled.providers.first.playlistDiscovery?.tags, isTrue);
    expect(enabled.providers.first.playlistDiscovery?.browse, isTrue);
    expect(enabled.providers.first.playlistDiscovery?.detail, isTrue);
    expect(enabled.providers.last.playlistDiscovery, isNull);
  });

  test('playlist discovery pages preserve native ids and real metadata', () {
    final filters = PlaylistDiscoveryFilters.fromJson({
      'source': 'kw',
      'sorts': [
        {'id': 'hot', 'name': '最热'},
      ],
      'hotTags': [
        {'id': '2189-10000', 'name': '短视频'},
      ],
      'groups': [
        {
          'name': '主题',
          'tags': [
            {'id': '2189-10000', 'name': '短视频'},
          ],
        },
      ],
    });
    final browse = PlaylistBrowsePage.fromJson({
      'source': 'kw',
      'page': 1,
      'limit': 30,
      'total': null,
      'hasMore': true,
      'list': [
        {
          'id': 'digest-8__3677488020',
          'kind': 'playlist',
          'name': '真实歌单',
          'source': 'kw',
          'author': '第一天',
          'total': 41,
          'playCount': '450.4万',
        },
      ],
    });
    final detail = OnlinePlaylistPage.fromJson({
      'source': 'kw',
      'page': 1,
      'limit': 1000,
      'total': 1,
      'hasMore': false,
      'playlist': browse.items.single.toJson(),
      'tracks': [
        {'songmid': 'track-1', 'name': '真实歌曲', 'source': 'kw'},
      ],
    });

    expect(filters.hotTags.single.id, '2189-10000');
    expect(filters.groups.single.tags.single.name, '短视频');
    expect(browse.items.single.id, 'digest-8__3677488020');
    expect(browse.items.single.playCount, '450.4万');
    expect(browse.total, isNull);
    expect(browse.hasMore, isTrue);
    expect(detail.playlist.name, '真实歌单');
    expect(detail.tracks.single.id, 'track-1');
    expect(detail.hasMore, isFalse);
  });

  test('DownloadJob exposes strict status and legal actions', () {
    final paused = DownloadJob.fromJson({
      'id': 'd1',
      'status': 'paused',
      'musicInfo': {'id': 'm1', 'source': 'kw'},
      'quality': '128k',
      'extension': 'mp3',
      'fileName': 'Song.mp3',
      'downloaded': 50,
      'total': 100,
      'progress': 50,
      'queuePosition': null,
      'createdAt': 1000,
      'updatedAt': 2000,
    });

    expect(paused.status, DownloadStatus.paused);
    expect(paused.canResume, isTrue);
    expect(paused.canPause, isFalse);
    expect(paused.canDelete, isTrue);
    expect(paused.progress, .5);
    expect(
      () => DownloadJob.fromJson({...paused.raw, 'status': 'mystery'}),
      throwsA(isA<ServiceException>()),
    );
    expect(
      () => DownloadJob.fromJson({...paused.raw, 'progress': 101}),
      throwsA(isA<ServiceException>()),
    );
  });

  test('DownloadJob accepts Service snapshots without optional timestamps', () {
    final job = DownloadJob.fromJson({
      'id': 'legacy-download',
      'status': 'completed',
      'musicInfo': {
        'id': 'song',
        'name': 'Song',
        'singer': 'Artist',
        'source': 'kw',
      },
      'quality': '128k',
      'extension': 'mp3',
      'fileName': 'Song.mp3',
      'downloaded': 1024,
      'total': 1024,
      'progress': 100,
    });

    expect(job.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(job.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
