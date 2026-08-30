import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';

void main() {
  test(
    'contextual resolve sends recommendation attribution separately',
    () async {
      late http.Request call;
      final repository = PlaybackRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            call = request;
            return http.Response(
              jsonEncode({
                'data': {
                  'url': '/api/v1/streams/token',
                  'quality': '128k',
                  'expiresAt': 1000,
                },
              }),
              200,
            );
          }),
        ),
      );
      final track = Track.fromJson({
        'id': 'track-1',
        'source': 'kw',
        'name': 'Recommended',
      });

      await repository.resolveWithContext(
        track,
        '128k',
        recommendationItemId: 'recommendation-1',
      );

      final body = jsonDecode(call.body) as Map<String, Object?>;
      expect(body['recommendationItemId'], 'recommendation-1');
      expect(
        (body['info'] as Map).containsKey('recommendationItemId'),
        isFalse,
      );
    },
  );
}
