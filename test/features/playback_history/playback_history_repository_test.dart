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
    'start posts only the complete track and platform and returns playback id',
    () async {
      late http.Request call;
      final repository = PlaybackHistoryRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            call = request;
            return data({
              'playbackId': 'play-1',
              'track': jsonDecode(request.body)['track'],
              'platform': 'android',
              'startedAt': 123,
            });
          }),
        ),
        platform: 'android',
      );
      final track = Track.fromJson({
        'id': 'history-1',
        'source': 'kw',
        'name': 'Night Wind',
        'providerOnly': {'albumId': 'a1'},
      });

      final playbackId = await repository.start(track);

      expect(playbackId, 'play-1');
      expect(call.method, 'POST');
      expect(call.url.path, '/api/v1/playback/history');
      expect(jsonDecode(call.body), {
        'track': track.toJson(),
        'platform': 'android',
      });
    },
  );

  test('end patches terminal playback facts in seconds', () async {
    late http.Request call;
    final repository = PlaybackHistoryRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          call = request;
          return data({
            'playbackId': 'play/1',
            'track': {'id': 'history-1', 'source': 'kw'},
            'platform': 'android',
            'startedAt': 123,
          });
        }),
      ),
      platform: 'android',
    );

    await repository.end(
      'play/1',
      completed: false,
      position: const Duration(milliseconds: 12500),
      duration: const Duration(seconds: 180),
    );

    expect(call.method, 'PATCH');
    expect(call.url.path, '/api/v1/playback/history/play%2F1');
    expect(jsonDecode(call.body), {
      'completed': false,
      'lastPositionSeconds': 12.5,
      'durationSeconds': 180.0,
    });
  });

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
                'startedAt': 123,
              },
              {
                'track': {'id': 'broken', 'source': 'kw'},
              },
            ]),
          ),
        ),
        platform: 'linux',
      );

      final history = await repository.readPlaybackHistory();

      expect(history, hasLength(1));
      expect(history.single.track.id, 'history-1');
      expect(history.single.track.raw['providerOnly'], {'albumId': 'a1'});
      expect(history.single.playedAt.millisecondsSinceEpoch, 123);
    },
  );
}
