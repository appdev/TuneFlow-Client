import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_controller.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_models.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_repository.dart';

import 'recommendation_test_data.dart';

final class MemoryRecommendationCache implements RecommendationCache {
  DailyRecommendations? value;
  int writes = 0;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<DailyRecommendations?> read() async => value;

  @override
  Future<void> write(DailyRecommendations value) async {
    this.value = value;
    writes++;
  }
}

RecommendationRepository repositoryFor(
  Future<http.Response> Function(http.Request request) handler,
) => RecommendationRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

http.Response data(Object? value, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode({'data': value})),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'publishes cached data first and replaces it with Service data',
    () async {
      final cache = MemoryRecommendationCache()
        ..value = DailyRecommendations.fromJson(
          recommendationSnapshotJson(version: 1, count: 1),
        );
      final response = data(recommendationSnapshotJson(version: 2));
      final controller = RecommendationController(
        repository: repositoryFor((_) async => response),
        cache: cache,
      );
      final observed = <RecommendationState>[];
      controller.addListener(() => observed.add(controller.state));

      await controller.load();

      expect(observed.any((state) => state.cached), isTrue);
      expect(controller.state.snapshot?.version, 2);
      expect(controller.state.cached, isFalse);
      expect(cache.value?.version, 2);
      expect(cache.writes, 1);
    },
  );

  test(
    'retains the last complete snapshot when Service is unavailable',
    () async {
      final cached = DailyRecommendations.fromJson(
        recommendationSnapshotJson(),
      );
      final cache = MemoryRecommendationCache()..value = cached;
      final controller = RecommendationController(
        repository: repositoryFor(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'OFFLINE', 'message': 'offline'},
            }),
            503,
          ),
        ),
        cache: cache,
      );

      await controller.load();

      expect(controller.state.snapshot, same(cached));
      expect(controller.state.cached, isTrue);
      expect(controller.state.error, isNotNull);
    },
  );

  test(
    'keeps cached recommendations while same-day generation is pending',
    () async {
      final cached = DailyRecommendations.fromJson(
        recommendationSnapshotJson(version: 4),
      );
      final cache = MemoryRecommendationCache()..value = cached;
      final controller = RecommendationController(
        repository: repositoryFor(
          (_) async => data({
            'status': 'generating',
            'localDate': '2026-08-30',
            'sourceCoverage': <Object?>[],
            'items': <Object?>[],
          }),
        ),
        cache: cache,
      );

      await controller.load();

      expect(controller.state.snapshot, same(cached));
      expect(controller.state.cached, isTrue);
      expect(cache.writes, 0);
    },
  );

  test('disabled Service state clears a previously cached snapshot', () async {
    final cache = MemoryRecommendationCache()
      ..value = DailyRecommendations.fromJson(recommendationSnapshotJson());
    final controller = RecommendationController(
      repository: repositoryFor(
        (_) async => data({
          'status': 'disabled',
          'localDate': '2026-08-30',
          'sourceCoverage': <Object?>[],
          'items': <Object?>[],
        }),
      ),
      cache: cache,
    );

    await controller.load();

    expect(controller.state.snapshot?.status, RecommendationStatus.disabled);
    expect(cache.value, isNull);
  });

  test('active feedback removes matching items from view and cache', () async {
    final cache = MemoryRecommendationCache();
    final dailyResponse = data(recommendationSnapshotJson());
    final repository = repositoryFor((request) async {
      if (request.url.path.endsWith('/daily')) {
        return dailyResponse;
      }
      return data({
        'feedbackId': 'feedback-1',
        'active': true,
        'type': 'not_interested_track',
      });
    });
    final controller = RecommendationController(
      repository: repository,
      cache: cache,
    );
    await controller.load();

    final result = await controller.dislikeTrack(
      controller.state.snapshot!.items.first,
    );

    expect(result?.active, isTrue);
    expect(controller.state.snapshot?.items, hasLength(1));
    expect(cache.value?.items, hasLength(1));
  });

  test(
    'toggles interested state only after Service confirmation and caches it',
    () async {
      final cache = MemoryRecommendationCache();
      final feedbackResponses = <Map<String, Object?>>[
        {
          'feedbackId': 'interested-1',
          'active': true,
          'type': 'interested_track',
        },
        {'feedbackId': 'interested-1', 'active': false, 'type': 'undo'},
      ];
      final controller = RecommendationController(
        repository: repositoryFor((request) async {
          if (request.url.path.endsWith('/daily')) {
            return data(recommendationSnapshotJson(count: 1));
          }
          return data(feedbackResponses.removeAt(0));
        }),
        cache: cache,
      );
      await controller.load();
      final item = controller.state.snapshot!.items.single;

      final interested = await controller.toggleInterest(item);

      expect(interested?.active, isTrue);
      final activeItem = controller.state.snapshot!.items.single;
      expect(activeItem.feedback.interested, isTrue);
      expect(activeItem.feedback.interestedFeedbackId, 'interested-1');
      expect(cache.value?.items.single.feedback.interested, isTrue);

      final undone = await controller.toggleInterest(activeItem);

      expect(undone?.active, isFalse);
      expect(
        controller.state.snapshot!.items.single.feedback.interested,
        isFalse,
      );
      expect(cache.value?.items.single.feedback.interestedFeedbackId, isNull);
    },
  );
}
