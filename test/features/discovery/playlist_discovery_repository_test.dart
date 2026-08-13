import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';

void main() {
  test('playlist discovery calls only the normalized Service routes', () async {
    final calls = <http.Request>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        calls.add(request);
        final Object data;
        if (request.url.path.endsWith('/tags')) {
          data = {
            'source': 'kw',
            'sorts': [
              {'id': 'hot', 'name': '最热'},
            ],
            'hotTags': <Object?>[],
            'groups': <Object?>[],
          };
        } else if (request.url.path.endsWith('/browse')) {
          data = {
            'source': 'kw',
            'page': 2,
            'limit': 30,
            'total': 31,
            'hasMore': false,
            'list': [
              {
                'id': 'list-1',
                'kind': 'playlist',
                'name': '真实歌单',
                'source': 'kw',
              },
            ],
          };
        } else {
          data = {
            'source': 'kw',
            'page': 1,
            'limit': 1000,
            'total': 1,
            'hasMore': false,
            'playlist': {
              'id': 'list-1',
              'kind': 'playlist',
              'name': '真实歌单',
              'source': 'kw',
            },
            'tracks': [
              {'songmid': 'song-1', 'name': '真实歌曲', 'source': 'kw'},
            ],
          };
        }
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final repository = SearchRepository(api);

    final filters = await repository.playlistTags(source: 'kw');
    final browse = await repository.browsePlaylists(
      source: 'kw',
      sortId: 'hot',
      tagId: '2189-10000',
      page: 2,
    );
    final detail = await repository.onlinePlaylist(
      source: 'kw',
      playlistId: 'list-1',
      page: 1,
    );

    expect(filters.sorts.single.id, 'hot');
    expect(browse.items.single.id, 'list-1');
    expect(detail.tracks.single.id, 'song-1');
    expect(calls.map((call) => call.url.path), [
      '/api/v1/catalog/playlists/tags',
      '/api/v1/catalog/playlists/browse',
      '/api/v1/catalog/playlists/detail',
    ]);
    expect(jsonDecode(calls[0].body), {'source': 'kw'});
    expect(jsonDecode(calls[1].body), {
      'source': 'kw',
      'sortId': 'hot',
      'tagId': '2189-10000',
      'page': 2,
    });
    expect(jsonDecode(calls[2].body), {
      'source': 'kw',
      'playlistId': 'list-1',
      'page': 1,
    });
  });
}
