import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';

ServiceApi apiWith(
  Future<http.Response> Function(http.Request request) handler,
) => ServiceApi(
  ServiceOrigin.parse('http://service.local'),
  client: MockClient(handler),
);

http.Response data(Object? value, [int status = 200]) =>
    http.Response(jsonEncode({'data': value}), status);

void main() {
  test('Service access origins round trip through shared settings', () async {
    final requests = <http.Request>[];
    final repository = ServiceSettingsRepository(
      apiWith((request) async {
        requests.add(request);
        return data({
          'service.lanOrigin': 'http://192.168.1.20:3124',
          'service.externalOrigin': 'https://music.example.com',
        });
      }),
    );

    expect(
      await repository.getAccessOrigins(),
      const ServiceAccessOrigins(
        lanOrigin: 'http://192.168.1.20:3124',
        externalOrigin: 'https://music.example.com',
      ),
    );
    await repository.updateAccessOrigins(
      const ServiceAccessOrigins(
        lanOrigin: 'http://192.168.1.20:3124',
        externalOrigin: 'https://music.example.com',
      ),
    );

    expect(requests.map((request) => request.method), ['GET', 'PATCH']);
    expect(jsonDecode(requests.last.body), {
      'service.lanOrigin': 'http://192.168.1.20:3124',
      'service.externalOrigin': 'https://music.example.com',
    });
  });

  test('connection checks health then v1 capabilities', () async {
    final paths = <String>[];
    final repository = ConnectionRepository(
      (origin) => apiWith((request) async {
        paths.add(request.url.path);
        return request.url.path.endsWith('health')
            ? data({'status': 'ok'})
            : data({
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              });
      }),
    );

    final connected = await repository.connect('http://service.local/');

    expect(paths, ['/api/v1/health', '/api/v1/capabilities']);
    expect(connected.origin.uri.toString(), 'http://service.local');
  });

  test(
    'connected snapshots retain API identity across diagnostics updates',
    () {
      final api = apiWith((_) async => data(null));
      final unreachable = ConnectionDiagnostics(
        origin: 'http://service.local',
        connected: false,
        latency: null,
        apiVersion: null,
        networkRoute: NetworkRoute.lan,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      final original = ConnectedService(
        api: api,
        capabilities: const Capabilities(
          runtime: 'service',
          apiVersion: 'v1',
          features: {},
        ),
        diagnostics: unreachable,
      );
      final reachable = ConnectionDiagnostics(
        origin: 'https://external.example',
        connected: true,
        latency: const Duration(milliseconds: 12),
        apiVersion: 'v1',
        networkRoute: NetworkRoute.external,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(2),
      );

      api.switchOrigin(ServiceOrigin.parse('https://external.example'));
      final copied = original.copyWith(diagnostics: reachable);

      expect(identical(original.api, copied.api), isTrue);
      expect(copied.origin.uri.toString(), 'https://external.example');
      expect(copied.diagnostics, same(reachable));
    },
  );

  test(
    'playlist listing explicitly requests the complete Service library',
    () async {
      late http.Request call;
      final repository = PlaylistRepository(
        apiWith((request) async {
          call = request;
          return data([
            {'id': 'default', 'name': 'list__name_default'},
            {'id': 'love', 'name': 'list__name_love'},
          ]);
        }),
      );

      final playlists = await repository.list();

      expect(call.url.path, '/api/v1/playlists');
      expect(call.url.queryParameters, {'includeBuiltIn': 'true'});
      expect(playlists.map((playlist) => playlist.id), ['default', 'love']);
    },
  );

  test('search, lyrics and picture map only current catalog routes', () async {
    final calls = <http.Request>[];
    final repository = SearchRepository(
      apiWith((request) async {
        calls.add(request);
        if (request.url.path.endsWith('search')) {
          return data({
            'list': [
              {'id': '1', 'name': 'Song', 'source': 'kw'},
            ],
            'total': 1,
          });
        }
        if (request.url.path.endsWith('picture')) {
          return data({
            'url':
                '/api/v1/playback/resources/${List.filled(64, 'a').join()}/picture',
          });
        }
        return data({'lyric': 'line'});
      }),
    );
    final page = await repository.search(
      source: 'kw',
      text: 'fixture',
      page: 1,
      pageSize: 30,
    );
    final lyrics = await repository.lyrics(page.tracks.single);
    final picture = await repository.picture(page.tracks.single);

    expect(calls.map((e) => e.url.path), [
      '/api/v1/catalog/tracks/search',
      '/api/v1/catalog/tracks/lyrics',
      '/api/v1/catalog/tracks/picture',
    ]);
    expect(jsonDecode(calls.first.body), {
      'source': 'kw',
      'text': 'fixture',
      'page': 1,
      'pageSize': 30,
    });
    for (final call in calls.skip(1)) {
      final body = jsonDecode(call.body) as Map<String, Object?>;
      expect(
        body['musicInfo'],
        containsPair('meta', containsPair('songId', '1')),
      );
    }
    expect(page.total, 1);
    expect(lyrics.original, 'line');
    expect(
      picture,
      'http://service.local/api/v1/playback/resources/${List.filled(64, 'a').join()}/picture',
    );
  });

  test(
    'local lyrics use the Service resource while online lyrics use catalog',
    () async {
      final calls = <http.Request>[];
      final repository = SearchRepository(
        apiWith((request) async {
          calls.add(request);
          return data({'lyric': 'line'});
        }),
      );
      final local = Track.fromJson({
        'id': 'local-a',
        'source': 'local',
        'meta': {'lyricsUrl': '/api/v1/library/tracks/file-a/lyrics'},
      });
      final online = Track.fromJson({'id': 'online-a', 'source': 'kw'});

      await repository.lyrics(local);
      await repository.lyrics(online);

      expect(calls.map((call) => '${call.method} ${call.url.path}'), [
        'GET /api/v1/library/tracks/file-a/lyrics',
        'POST /api/v1/catalog/tracks/lyrics',
      ]);
    },
  );

  test(
    'bundle lyrics use a validated same-origin absolute resource URL',
    () async {
      late http.Request captured;
      final repository = SearchRepository(
        apiWith((request) async {
          captured = request;
          return data({'lyric': '[00:00.00]local bundle'});
        }),
      );
      final track = Track.fromJson({
        'id': 'online-id',
        'source': 'kw',
        'meta': {
          'lyricsUrl':
              'http://service.local/api/v1/library/tracks/file-a/lyrics',
        },
      });

      final lyrics = await repository.lyrics(track);

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/library/tracks/file-a/lyrics');
      expect(lyrics.original, '[00:00.00]local bundle');
    },
  );

  test(
    'local track without a lyrics resource asks Service to resolve it',
    () async {
      late http.Request captured;
      final repository = SearchRepository(
        apiWith((request) async {
          captured = request;
          return data({'lyric': '[00:01.00]resolved'});
        }),
      );

      final lyrics = await repository.lyrics(
        Track.fromJson({
          'id': 'local-a',
          'name': 'Fixture',
          'singer': 'Artist',
          'source': 'local',
          'interval': '03:00',
        }),
      );

      expect(lyrics.original, '[00:01.00]resolved');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/v1/catalog/tracks/lyrics');
      expect(jsonDecode(captured.body), {
        'source': 'local',
        'musicInfo': {
          'id': 'local-a',
          'name': 'Fixture',
          'singer': 'Artist',
          'source': 'local',
          'interval': '03:00',
          'meta': {'songId': 'local-a'},
        },
      });
    },
  );

  test('catalog picture rejects a non-Service resource URL', () async {
    final repository = SearchRepository(
      apiWith((_) async => data({'url': 'https://external.test/cover.jpg'})),
    );

    await expectLater(
      repository.picture(Track.fromJson({'id': 'track-a', 'source': 'kw'})),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test(
    'catalog capability gates and collection searches use typed routes',
    () async {
      final calls = <http.Request>[];
      final repository = SearchRepository(
        apiWith((request) async {
          calls.add(request);
          if (request.method == 'GET') {
            return data({
              'sources': [
                {
                  'id': 'wy',
                  'name': 'NetEase',
                  'searchKinds': ['track', 'playlist', 'album'],
                },
              ],
            });
          }
          return data({
            'list': [
              {'id': 'a1', 'kind': 'album', 'name': 'A', 'source': 'wy'},
            ],
            'total': 1,
          });
        }),
      );

      final capabilities = await repository.capabilities();
      final albums = await repository.searchCollections(
        kind: CatalogSearchKind.album,
        source: 'wy',
        text: 'fixture',
        page: 1,
        pageSize: 20,
      );

      expect(
        capabilities.providers.single.searchKinds,
        contains(CatalogSearchKind.album),
      );
      expect(albums.items.single.id, 'a1');
      expect(calls.map((request) => request.url.path), [
        '/api/v1/catalog/capabilities',
        '/api/v1/catalog/albums/search',
      ]);
    },
  );

  test('leaderboards use Service catalog routes', () async {
    final calls = <http.Request>[];
    final repository = SearchRepository(
      apiWith((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/leaderboards')) {
          return data({
            'list': [
              {'id': 'kw__16', 'bangid': '16', 'name': 'Hot chart'},
            ],
            'source': 'kw',
          });
        }
        return data({
          'list': [
            {
              'songmid': 'song-1',
              'name': 'Song',
              'source': 'kw',
              'img': 'https://cdn.example.test/song.jpg',
            },
          ],
          'total': 1,
          'limit': 30,
          'page': 1,
          'source': 'kw',
        });
      }),
    );

    final boards = await repository.leaderboards(source: 'kw');
    final tracks = await repository.leaderboardTracks(
      source: 'kw',
      boardId: boards.items.single.providerId,
      page: 1,
    );

    expect(tracks.tracks.single.raw['pic'], isNotNull);
    expect(calls.map((request) => request.url.path), [
      '/api/v1/catalog/leaderboards',
      '/api/v1/catalog/leaderboards/tracks',
    ]);
  });

  test('album detail uses the typed Service catalog route', () async {
    late http.Request captured;
    final repository = SearchRepository(
      apiWith((request) async {
        captured = request;
        return data({
          'source': 'wy',
          'page': 2,
          'limit': 30,
          'total': 1,
          'hasMore': false,
          'album': {
            'id': 'album-1',
            'kind': 'album',
            'name': 'Album',
            'source': 'wy',
          },
          'tracks': [
            {'id': 'track-1', 'name': 'Track', 'source': 'wy'},
          ],
        });
      }),
    );

    final page = await repository.album(
      source: 'wy',
      albumId: 'album-1',
      page: 2,
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/catalog/albums/detail');
    expect(jsonDecode(captured.body), {
      'source': 'wy',
      'albumId': 'album-1',
      'page': 2,
    });
    expect(page.album.id, 'album-1');
  });

  test('playlist repository uses resource routes', () async {
    final calls = <http.Request>[];
    final repository = PlaylistRepository(
      apiWith((request) async {
        calls.add(request);
        if (request.url.path == '/api/v1/playlists') return data([]);
        return data({'id': 'a/b', 'name': 'A', 'tracks': <Object?>[]});
      }),
    );

    await repository.list();
    await repository.get('a/b');

    expect(calls[1].url.path, '/api/v1/playlists/a%2Fb');
    expect(calls.every((e) => !e.url.path.contains('/actions/')), isTrue);
  });

  test('playlist reorder sends the Service-required position', () async {
    late http.Request captured;
    final repository = PlaylistRepository(
      apiWith((request) async {
        captured = request;
        return data(<Object?>[]);
      }),
    );

    await repository.reorderTracks('road trip', 2, ['track-1']);

    expect(captured.url.path, '/api/v1/playlists/road%20trip/tracks/reorder');
    expect(jsonDecode(captured.body), {
      'position': 2,
      'trackIds': ['track-1'],
    });
  });

  test(
    'playback accepts Service proxy and local-library stream paths',
    () async {
      var url = '/api/v1/streams/token';
      late http.Request captured;
      final repository = PlaybackRepository(
        apiWith((request) async {
          captured = request;
          return data({'url': url, 'quality': '128k', 'expiresAt': 1000});
        }),
      );
      final track = Track.fromJson({'id': '1', 'source': 'kw'});

      final resolved = await repository.resolve(track, '128k');
      expect(
        resolved.streamUri.toString(),
        'http://service.local/api/v1/streams/token',
      );
      expect(jsonDecode(captured.body), {
        'source': 'kw',
        'quality': '128k',
        'preferLocal': true,
        'info': track.toServiceMusicInfoJson(),
      });

      url = '/api/v1/library/tracks/${List.filled(64, 'a').join()}/stream';
      final local = await repository.resolve(track, '128k');
      expect(local.streamUri.path, url);

      url = 'https://upstream.example/song.mp3';
      await expectLater(
        repository.resolve(track, '128k'),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'INVALID_STREAM_URL',
          ),
        ),
      );
    },
  );

  test(
    'playback normalizes validated bundle resources to Service URIs',
    () async {
      final pictureToken = List.filled(64, 'a').join();
      var response = <String, Object?>{
        'url': '/api/v1/streams/token',
        'quality': '320k',
        'expiresAt': 1000,
        'resources': {
          'lyrics': {'lyric': '[00:00.00]bundle'},
          'pictureUrl': '/api/v1/playback/resources/$pictureToken/picture',
        },
        'completeness': 'complete',
      };
      final repository = PlaybackRepository(
        apiWith((_) async => data(response)),
      );
      final track = Track.fromJson({'id': '1', 'source': 'kw'});

      final online = await repository.resolve(track, '320k');
      expect(online.bundleLyrics?.original, '[00:00.00]bundle');
      expect(
        online.pictureUri.toString(),
        'http://service.local/api/v1/playback/resources/$pictureToken/picture',
      );

      response = {
        'url': '/api/v1/library/tracks/file-a/stream',
        'quality': '320k',
        'expiresAt': 0,
        'resources': {
          'lyricsUrl': '/api/v1/library/tracks/file-a/lyrics',
          'pictureUrl': '/api/v1/library/tracks/file-a/picture',
        },
        'completeness': 'complete',
      };
      final local = await repository.resolve(track, '320k');
      expect(
        local.lyricsUri.toString(),
        'http://service.local/api/v1/library/tracks/file-a/lyrics',
      );
      expect(
        local.pictureUri.toString(),
        'http://service.local/api/v1/library/tracks/file-a/picture',
      );
    },
  );

  test('playback rejects external or malformed resource URLs', () async {
    var resourceUrl = 'https://outside.test/art.jpg';
    final repository = PlaybackRepository(
      apiWith(
        (_) async => data({
          'url': '/api/v1/streams/token',
          'quality': '128k',
          'expiresAt': 1000,
          'resources': {'pictureUrl': resourceUrl},
          'completeness': 'mixed',
        }),
      ),
    );
    final track = Track.fromJson({'id': '1', 'source': 'kw'});

    for (final invalid in [
      'https://outside.test/art.jpg',
      'file:///tmp/art.jpg',
      '//outside.test/art.jpg',
      '/api/v1/playback/resources/token/picture?raw=1',
      '/api/v1/playback/resources/token/picture#fragment',
    ]) {
      resourceUrl = invalid;
      await expectLater(
        repository.resolve(track, '128k'),
        throwsA(isA<ServiceException>()),
        reason: invalid,
      );
    }
  });

  test('download create sends no client filesystem fields', () async {
    late http.Request captured;
    final repository = DownloadRepository(
      apiWith((request) async {
        captured = request;
        return data({
          'id': 'd1',
          'status': 'waiting',
          'musicInfo': {'id': '1'},
          'quality': '128k',
          'extension': 'mp3',
          'fileName': 'song.mp3',
          'downloaded': 0,
          'total': 0,
          'progress': 0,
          'queuePosition': 1,
          'createdAt': 1000,
          'updatedAt': 1000,
        }, 201);
      }),
    );

    await repository.create(
      Track.fromJson({'id': '1', 'source': 'kw'}),
      '128k',
    );
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body.keys, containsAll(<String>['musicInfo', 'quality']));
    expect(
      body['musicInfo'],
      containsPair('meta', containsPair('songId', '1')),
    );
    expect(body.keys, isNot(contains('path')));
    expect(body.keys, isNot(contains('fileName')));
  });
}
