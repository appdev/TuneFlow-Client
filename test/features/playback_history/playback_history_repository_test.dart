import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/playback_history/playback_history_repository.dart';

http.Response data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

void main() {
  test(
    'record playback posts the complete track to the history route',
    () async {
      late http.Request call;
      final repository = PlaybackHistoryRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            call = request;
            return data({
              'track': jsonDecode(request.body)['track'],
              'playedAt': 123,
            });
          }),
        ),
      );
      final track = Track.fromJson({
        'id': 'history-1',
        'source': 'kw',
        'name': 'Night Wind',
        'providerOnly': {'albumId': 'a1'},
      });

      await repository.recordPlayback(track);

      expect(call.method, 'POST');
      expect(call.url.path, '/api/v1/playback/history');
      expect(jsonDecode(call.body), {'track': track.toJson()});
    },
  );

  test(
    'read playback history preserves metadata and skips malformed entries',
    () async {
      final repository = PlaybackHistoryRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient(
            (_) async => data([
              {
                'track': {
                  'id': 'history-1',
                  'source': 'kw',
                  'name': 'Night Wind',
                  'providerOnly': {'albumId': 'a1'},
                },
                'playedAt': 123,
              },
              {
                'track': {'id': 'broken', 'source': 'kw'},
              },
            ]),
          ),
        ),
      );

      final history = await repository.readPlaybackHistory();

      expect(history, hasLength(1));
      expect(history.single.track.id, 'history-1');
      expect(history.single.track.raw['providerOnly'], {'albumId': 'a1'});
      expect(history.single.playedAt.millisecondsSinceEpoch, 123);
    },
  );
}
