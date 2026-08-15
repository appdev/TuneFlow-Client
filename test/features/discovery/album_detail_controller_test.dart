import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/discovery/album_detail_controller.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';

http.Response data(Object? value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

CatalogCollection album(String name) => CatalogCollection(
  id: 'album-1',
  kind: CatalogSearchKind.album,
  name: name,
  source: 'wy',
  author: 'Artist',
);

void main() {
  test('loads pages in order and deduplicates repeated tracks', () async {
    final pages = <int>[];
    final repository = SearchRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final page = body['page']! as int;
          pages.add(page);
          return data({
            'source': 'wy',
            'page': page,
            'limit': 1,
            'total': 2,
            'hasMore': page == 1,
            'album': album('Authoritative album').toJson(),
            'tracks': page == 1
                ? [
                    {'id': 't1', 'name': 'One', 'source': 'wy'},
                  ]
                : [
                    {'id': 't1', 'name': 'One', 'source': 'wy'},
                    {'id': 't2', 'name': 'Two', 'source': 'wy'},
                  ],
          });
        }),
      ),
    );
    final controller = AlbumDetailController(
      catalog: repository,
      source: 'wy',
      albumId: 'album-1',
      supported: true,
      initialAlbum: album('Seed album'),
    );

    await controller.load();
    await controller.loadPage(2);

    expect(pages, [1, 2]);
    expect(controller.state.album?.name, 'Authoritative album');
    expect(controller.state.tracks.map((track) => track.id), ['t1', 't2']);
    expect(controller.state.hasMore, isFalse);
  });

  test('unsupported albums preserve seed metadata without a request', () async {
    var requests = 0;
    final controller = AlbumDetailController(
      catalog: SearchRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((_) async {
            requests++;
            return data(null);
          }),
        ),
      ),
      source: 'wy',
      albumId: 'album-1',
      supported: false,
      initialAlbum: album('Seed album'),
    );

    await controller.load();

    expect(requests, 0);
    expect(controller.state.unsupported, isTrue);
    expect(controller.state.album?.name, 'Seed album');
  });

  test(
    'disposing during a pending album request invalidates its result',
    () async {
      final response = Completer<http.Response>();
      final controller = AlbumDetailController(
        catalog: SearchRepository(
          ServiceApi(
            ServiceOrigin.parse('http://service.local'),
            client: MockClient((_) => response.future),
          ),
        ),
        source: 'wy',
        albumId: 'album-1',
        supported: true,
        initialAlbum: album('Seed album'),
      );

      final pending = controller.load();
      controller.dispose();
      response.complete(
        data({
          'source': 'wy',
          'page': 1,
          'limit': 30,
          'total': 0,
          'hasMore': false,
          'album': album('Late album').toJson(),
          'tracks': <Object?>[],
        }),
      );

      await expectLater(pending, completes);
    },
  );
}
