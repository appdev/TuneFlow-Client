import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_models.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_repository.dart';

import 'recommendation_test_data.dart';

http.Response data(Object? value, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode({'data': value})),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

RecommendationRepository repositoryFor(
  Future<http.Response> Function(http.Request request) handler,
) => RecommendationRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

void main() {
  test('treats a versioned empty ready snapshot as complete', () {
    final snapshot = DailyRecommendations.fromJson({
      'status': 'ready',
      'localDate': '2026-08-30',
      'version': 1,
      'generatedAt': 1000,
      'sourceCoverage': <Object?>[],
      'items': <Object?>[],
    });

    expect(snapshot.isComplete, isTrue);
  });

  test('parses the complete daily snapshot', () async {
    late http.Request call;
    final response = data(recommendationSnapshotJson());
    final repository = repositoryFor((request) async {
      call = request;
      return response;
    });

    final snapshot = await repository.daily();

    expect(call.method, 'GET');
    expect(call.url.path, '/api/v1/recommendations/daily');
    expect(snapshot.status, RecommendationStatus.ready);
    expect(snapshot.version, 1);
    expect(snapshot.items, hasLength(2));
    expect(snapshot.snapshotLocalDate, '2026-08-30');
    expect(snapshot.lastErrorCode, isNull);
    expect(snapshot.items.first.bucket, RecommendationBucket.newTrack);
    expect(snapshot.items.first.feedback.interested, isFalse);
    expect(
      snapshot.items.last.reason.type,
      RecommendationReasonType.familiarReplay,
    );
  });

  test('treats stale snapshots as complete and preserves failure metadata', () {
    final snapshot = DailyRecommendations.fromJson(
      recommendationSnapshotJson(status: 'stale'),
    );

    expect(snapshot.status, RecommendationStatus.stale);
    expect(snapshot.isComplete, isTrue);
    expect(snapshot.snapshotLocalDate, '2026-08-29');
    expect(snapshot.lastErrorCode, 'musicbrainz_timeout');
  });

  test('parses the disabled state without requiring snapshot fields', () {
    final snapshot = DailyRecommendations.fromJson({
      'status': 'disabled',
      'localDate': '2026-08-30',
      'sourceCoverage': <Object?>[],
      'items': <Object?>[],
    });

    expect(snapshot.status, RecommendationStatus.disabled);
    expect(snapshot.isComplete, isFalse);
    expect(snapshot.items, isEmpty);
  });

  test('refresh uses the asynchronous generation route', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/recommendations/daily/refresh');
      return data({
        'generationId': 'generation-1',
        'status': 'generating',
      }, status: 202);
    });

    await repository.refresh();
  });

  test('track feedback preserves the complete provider track', () async {
    late Map<String, Object?> body;
    final repository = repositoryFor((request) async {
      body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return data({
        'feedbackId': 'feedback-1',
        'active': true,
        'type': 'not_interested_track',
      });
    });
    final item = DailyRecommendations.fromJson(
      recommendationSnapshotJson(count: 1),
    ).items.single;

    await repository.dislikeTrack(item);

    expect(body['type'], 'not_interested_track');
    expect((body['track'] as Map)['id'], 'track-0');
    expect((body['track'] as Map)['source'], 'kw');
    expect(body.containsKey('recommendationItemId'), isFalse);
  });

  test('interested feedback preserves the complete provider track', () async {
    late Map<String, Object?> body;
    final repository = repositoryFor((request) async {
      body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return data({
        'feedbackId': 'interested-1',
        'active': true,
        'type': 'interested_track',
      });
    });
    final item = DailyRecommendations.fromJson(
      recommendationSnapshotJson(count: 1),
    ).items.single;

    final result = await repository.interestTrack(item);

    expect(result.active, isTrue);
    expect(body['type'], 'interested_track');
    expect((body['track'] as Map)['id'], 'track-0');
    expect((body['track'] as Map)['source'], 'kw');
  });

  test('keeps old cached items compatible when feedback is absent', () {
    final json = recommendationSnapshotJson(count: 1);
    ((json['items'] as List).single as Map).remove('feedback');

    final item = DailyRecommendations.fromJson(json).items.single;

    expect(item.feedback.interested, isFalse);
    expect(item.feedback.interestedFeedbackId, isNull);
  });
}
