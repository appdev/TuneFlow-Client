import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/home/home_recommendation_section.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_controller.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_models.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_repository.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';
import '../recommendations/recommendation_test_data.dart';

final class MemoryRecommendationCache implements RecommendationCache {
  @override
  Future<void> clear() async {}

  @override
  Future<DailyRecommendations?> read() async => null;

  @override
  Future<void> write(DailyRecommendations value) async {}
}

final class _Resolver implements PlaybackResolver, ContextualPlaybackResolver {
  final ids = <String>[];

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      _source();

  @override
  Future<PlaybackSource> resolveWithContext(
    Track track,
    String quality, {
    required String recommendationItemId,
  }) async {
    ids.add(recommendationItemId);
    return _source();
  }

  PlaybackSource _source() => PlaybackSource(
    resolved: const ResolvedTrack(
      url: '/api/v1/streams/token',
      quality: '128k',
      expiresAt: 1000,
    ),
    streamUri: Uri.parse('http://service.local/api/v1/streams/token'),
  );
}

Widget harness(Widget child) => AppImageCacheScope(
  cache: FakeAppImageCache(manager: TestImageCacheManager()),
  child: ShadApp.custom(
    theme: buildLightTheme(),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  ),
);

RecommendationController controllerFor({String status = 'ready'}) {
  final controller = RecommendationController(
    repository: RecommendationRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': recommendationSnapshotJson(
                  status: status,
                  count: status == 'disabled' ? 0 : 12,
                ),
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    ),
    cache: MemoryRecommendationCache(),
  );
  return controller;
}

void main() {
  for (final testCase in [(390.0, 6), (900.0, 8), (1300.0, 10)]) {
    testWidgets('shows ${testCase.$2} recommendations at ${testCase.$1}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(testCase.$1, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = controllerFor();
      await controller.load();

      await tester.pumpWidget(
        harness(
          HomeRecommendationSection(
            controller: controller,
            player: null,
            loadPicture: (_) async => null,
            onViewAll: () {},
            onSettings: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('home-recommendation-card')),
        findsNWidgets(testCase.$2),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uses actual content width inside a wide desktop shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = controllerFor();
    await controller.load();

    await tester.pumpWidget(
      harness(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 900,
            child: HomeRecommendationSection(
              controller: controller,
              player: null,
              loadPicture: (_) async => null,
              onViewAll: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-recommendation-card')), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a recommendation card starts attributed playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = controllerFor();
    await controller.load();
    final resolver = _Resolver();
    final player = PlayerController(
      resolver: resolver,
      audio: SilentAudioPort(),
    );

    await tester.pumpWidget(
      harness(
        HomeRecommendationSection(
          controller: controller,
          player: player,
          loadPicture: (_) async => null,
          onViewAll: () {},
          onSettings: () {},
        ),
      ),
    );
    await tester.tap(find.text('Track 0'));
    await tester.pumpAndSettle();

    expect(player.state.current?.id, 'track-0');
    expect(resolver.ids, ['recommendation-0']);
    expect(player.state.error, isNull);
  });

  testWidgets('interest action updates the card without starting playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <String>[];
    final controller = RecommendationController(
      repository: RecommendationRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            requests.add(request.url.path);
            final response = request.url.path.endsWith('/daily')
                ? recommendationSnapshotJson(count: 1)
                : {
                    'feedbackId': 'interested-0',
                    'active': true,
                    'type': 'interested_track',
                  };
            return http.Response.bytes(
              utf8.encode(jsonEncode({'data': response})),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
      cache: MemoryRecommendationCache(),
    );
    await controller.load();
    final resolver = _Resolver();
    final player = PlayerController(
      resolver: resolver,
      audio: SilentAudioPort(),
    );

    await tester.pumpWidget(
      harness(
        HomeRecommendationSection(
          controller: controller,
          player: player,
          loadPicture: (_) async => null,
          onViewAll: () {},
          onSettings: () {},
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('home-recommendation-interest-recommendation-0')),
    );
    await tester.pumpAndSettle();

    expect(requests.last, '/api/v1/recommendations/feedback');
    expect(controller.state.snapshot!.items.single.feedback.interested, isTrue);
    expect(player.state.current, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const Key('home-recommendation-interest-recommendation-0'),
            ),
          )
          .tooltip,
      '取消感兴趣',
    );
  });

  testWidgets('disabled state offers a direct settings action', (tester) async {
    final controller = controllerFor(status: 'disabled');
    await controller.load();
    var opened = false;

    await tester.pumpWidget(
      harness(
        HomeRecommendationSection(
          controller: controller,
          player: null,
          loadPicture: (_) async => null,
          onViewAll: () {},
          onSettings: () => opened = true,
        ),
      ),
    );
    await tester.tap(find.text('打开推荐设置'));

    expect(opened, isTrue);
    expect(find.byKey(const Key('home-recommendations-disabled')), findsOne);
  });
}
