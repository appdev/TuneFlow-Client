import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/discovery/online_playlist_detail_controller.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';

http.Response data(Object value, [int status = 200]) => http.Response(
  jsonEncode({'data': value}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('keeps the human-readable browse author over a provider id', () async {
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => data({
          'source': 'kw',
          'page': 1,
          'limit': 1,
          'total': 1,
          'hasMore': false,
          'playlist': {
            'id': 'list-1',
            'kind': 'playlist',
            'name': '真实歌单',
            'source': 'kw',
            'author': 'kw3563157520',
          },
          'tracks': [
            {'songmid': 'one', 'name': 'One', 'source': 'kw'},
          ],
        }),
      ),
    );
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
      initialPlaylist: const CatalogCollection(
        id: 'list-1',
        kind: CatalogSearchKind.playlist,
        name: '真实歌单',
        source: 'kw',
        author: '余笑笑',
      ),
    );

    await controller.load();

    expect(controller.state.playlist?.author, '余笑笑');
  });

  test(
    'accumulates pages and imports complete playlists in bounded batches',
    () async {
      final batchSizes = <int>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/detail')) {
            final body = Map<String, Object?>.from(
              jsonDecode(request.body) as Map,
            );
            final page = body['page']! as int;
            final start = page == 1 ? 0 : 100;
            final count = page == 1 ? 100 : 105;
            return data({
              'source': 'kw',
              'page': page,
              'limit': count,
              'total': 205,
              'hasMore': page == 1,
              'playlist': {
                'id': 'list-1',
                'kind': 'playlist',
                'name': '真实歌单',
                'source': 'kw',
              },
              'tracks': [
                for (var index = start; index < start + count; index++)
                  {
                    'songmid': 'track-$index',
                    'name': 'Song $index',
                    'source': 'kw',
                  },
              ],
            });
          }
          final requestBody = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          final tracks = List<Object?>.from(requestBody['tracks']! as List);
          batchSizes.add(tracks.length);
          return data(tracks);
        }),
      );
      final controller = OnlinePlaylistDetailController(
        catalog: SearchRepository(api),
        playlists: PlaylistRepository(api),
        source: 'kw',
        playlistId: 'list-1',
      );

      await controller.load();
      await controller.loadPage(2);
      expect(controller.state.tracks.length, 205);
      expect(controller.state.tracks.first.id, 'track-0');
      expect(controller.state.tracks.last.id, 'track-204');

      await controller.importAll('love');

      expect(batchSizes, [100, 100, 5]);
      expect(controller.state.importProgress?.added, 205);
      expect(controller.state.importProgress?.completed, isTrue);
    },
  );

  test('later page failure retains already loaded tracks', () async {
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        if (body['page'] == 2) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'UPSTREAM_ERROR', 'message': 'failed'},
            }),
            502,
          );
        }
        return data({
          'source': 'kw',
          'page': 1,
          'limit': 1,
          'total': 2,
          'hasMore': true,
          'playlist': {
            'id': 'list-1',
            'kind': 'playlist',
            'name': '真实歌单',
            'source': 'kw',
          },
          'tracks': [
            {'songmid': 'one', 'name': 'One', 'source': 'kw'},
          ],
        });
      }),
    );
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );

    await controller.load();
    await controller.loadPage(2);

    expect(controller.state.tracks.single.id, 'one');
    expect(controller.state.failedPage, 2);
    expect(controller.state.stale, isTrue);
  });

  test('cancellation stops at a batch boundary without rolling back', () async {
    late OnlinePlaylistDetailController controller;
    var addCalls = 0;
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/detail')) {
          return data({
            'source': 'kw',
            'page': 1,
            'limit': 150,
            'total': 150,
            'hasMore': false,
            'playlist': {
              'id': 'list-1',
              'kind': 'playlist',
              'name': '真实歌单',
              'source': 'kw',
            },
            'tracks': [
              for (var index = 0; index < 150; index++)
                {
                  'songmid': 'track-$index',
                  'name': 'Song $index',
                  'source': 'kw',
                },
            ],
          });
        }
        addCalls++;
        final requestBody = Map<String, Object?>.from(
          jsonDecode(request.body) as Map,
        );
        final tracks = List<Object?>.from(requestBody['tracks']! as List);
        controller.cancelImport();
        return data(tracks);
      }),
    );
    controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );
    await controller.load();

    await controller.importAll('love');

    expect(addCalls, 1);
    expect(controller.state.importProgress?.added, 100);
    expect(controller.state.importProgress?.cancelled, isTrue);
    expect(controller.state.importProgress?.completed, isFalse);
  });

  test('retry skips a confirmed batch after a later batch fails', () async {
    var addCalls = 0;
    final batchSizes = <int>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/detail')) {
          return data({
            'source': 'kw',
            'page': 1,
            'limit': 205,
            'total': 205,
            'hasMore': false,
            'playlist': {
              'id': 'list-1',
              'kind': 'playlist',
              'name': '真实歌单',
              'source': 'kw',
            },
            'tracks': [
              for (var index = 0; index < 205; index++)
                {
                  'songmid': 'track-$index',
                  'name': 'Song $index',
                  'source': 'kw',
                },
            ],
          });
        }
        addCalls++;
        final requestBody = Map<String, Object?>.from(
          jsonDecode(request.body) as Map,
        );
        final tracks = List<Object?>.from(requestBody['tracks']! as List);
        batchSizes.add(tracks.length);
        if (addCalls == 2) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'WRITE_FAILED', 'message': 'failed'},
            }),
            500,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return data(tracks);
      }),
    );
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );
    await controller.load();

    await controller.importAll('love');
    expect(controller.state.importProgress?.added, 100);
    expect(controller.state.importProgress?.failed, 105);

    await controller.importAll('love');
    expect(batchSizes, [100, 100, 100, 5]);
    expect(controller.state.importProgress?.added, 205);
    expect(controller.state.importProgress?.completed, isTrue);
  });
}
