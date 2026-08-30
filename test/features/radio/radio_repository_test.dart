import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/radio/radio_models.dart';
import 'package:musicfree_service_client/features/radio/radio_repository.dart';

http.Response data(Object? value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json'},
);
Map<String, Object?> batchJson({String sessionId = 'radio-1'}) => {
  'sessionId': sessionId,
  'mode': 'dedicated',
  'status': 'active',
  'aiStatus': 'enhanced',
  'profileId': 'profile-1',
  'items': [
    {
      'recommendationItemId': 'item-1',
      'radioSessionId': sessionId,
      'canonicalTrackId': 'track-1',
      'track': {
        'id': 'track-1',
        'source': 'kw',
        'name': 'Track',
        'singer': 'Artist',
      },
      'rankingSource': 'ai',
      'bucket': 'new',
      'reason': {'type': 'exploration', 'labels': <String>[]},
      'feedback': {'interested': false, 'interestedFeedbackId': null},
    },
  ],
};

void main() {
  test(
    'creates a radio session with bounded queue context and no secret field',
    () async {
      late http.Request call;
      final repository = RadioRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            call = request;
            return data(batchJson());
          }),
        ),
      );
      final result = await repository.create(
        mode: RadioMode.dedicated,
        queueGeneration: 4,
        requestId: 'request-4',
        currentTrack: Track.fromJson({
          'id': 'current',
          'source': 'kw',
          'name': 'Current',
          'singer': 'Artist',
        }),
      );
      final body = jsonDecode(call.body) as Map;
      expect(call.url.path, '/api/v1/radio/sessions');
      expect(body, containsPair('queueGeneration', 4));
      expect(body.toString(), isNot(contains('apiKey')));
      expect(result.aiStatus, RadioAiStatus.enhanced);
      expect(result.items.single.track.id, 'track-1');
    },
  );

  test('rejects item/session mismatch', () {
    final invalid = batchJson()
      ..['items'] = [
        (batchJson()['items'] as List).single as Map<String, Object?>
          ..['radioSessionId'] = 'other',
      ];
    expect(() => RadioBatch.fromJson(invalid), throwsA(isA<Exception>()));
  });
}
