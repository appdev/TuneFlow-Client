import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlist_detail_controller.dart';

void main() {
  test(
    'filters locally, sorts naturally, and keeps source identities separate',
    () async {
      final requests = <http.Request>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
      addTearDown(api.close);
      final controller = PlaylistDetailController(
        PlaylistRepository(api),
        'list',
      );
      addTearDown(controller.dispose);
      final detail = PlaylistDetail.fromJson({
        'id': 'list',
        'name': 'Test',
        'tracks': [
          {'id': 'same', 'source': 'a', 'name': 'Song 10', 'singer': 'Singer'},
          {'id': 'same', 'source': 'b', 'name': 'Song 2', 'singer': 'Other'},
          {'id': 'three', 'source': 'a', 'name': 'Song 1', 'singer': 'Singer'},
        ],
      });
      controller.state = PlaylistDetailState(detail: detail);
      controller.setSort(PlaylistSort.title);
      expect(controller.visibleTracks.map((t) => t.title), [
        'Song 1',
        'Song 2',
        'Song 10',
      ]);
      controller.setQuery('Singer');
      expect(controller.visibleTracks.length, 2);
      controller.selectAllVisible();
      expect(controller.selected, {('a', 'same'), ('a', 'three')});
      await expectLater(controller.removeSelected(), throwsStateError);
      expect(requests, isEmpty);
      await controller.addSelectedTo('destination');
      final payload = jsonDecode(requests.single.body) as Map;
      expect((payload['tracks'] as List).length, 2);
      expect((payload['tracks'] as List).first['source'], 'a');
      expect(controller.selected, isEmpty);
    },
  );
}
