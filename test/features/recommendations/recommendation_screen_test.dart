import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_controller.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_models.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_repository.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'recommendation_test_data.dart';

final class _Cache implements RecommendationCache {
  @override
  Future<void> clear() async {}
  @override
  Future<DailyRecommendations?> read() async => null;
  @override
  Future<void> write(DailyRecommendations value) async {}
}

final class _Resolver implements PlaybackResolver, ContextualPlaybackResolver {
  final List<String> ids = [];

  PlaybackSource get source => PlaybackSource(
    resolved: const ResolvedTrack(
      url: '/api/v1/streams/token',
      quality: '128k',
      expiresAt: 1000,
    ),
    streamUri: Uri.parse('http://service.local/api/v1/streams/token'),
  );

  @override
  Future<PlaybackSource> resolve(Track track, String quality) async => source;

  @override
  Future<PlaybackSource> resolveWithContext(
    Track track,
    String quality, {
    required String recommendationItemId,
  }) async {
    ids.add(recommendationItemId);
    return source;
  }
}

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets(
    'preserves recommendations when the route replaces its controller',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initialApi = ServiceApi(
        ServiceOrigin.parse('http://initial.local'),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'data': recommendationSnapshotJson()})),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final replacementRequests = <String>[];
      final replacementApi = ServiceApi(
        ServiceOrigin.parse('http://replacement.local'),
        client: MockClient((request) async {
          replacementRequests.add(request.url.path);
          return http.Response.bytes(
            utf8.encode(jsonEncode({'data': recommendationSnapshotJson()})),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      RecommendationController controller(ServiceApi api) =>
          RecommendationController(
            repository: RecommendationRepository(api),
            cache: _Cache(),
          );
      final initialController = controller(initialApi);
      final replacementController = controller(replacementApi);
      var currentController = initialController;
      late StateSetter rebuild;

      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RecommendationScreen(
                key: const Key('recommendations-route'),
                controller: currentController,
                player: PlayerController(
                  resolver: _Resolver(),
                  audio: SilentAudioPort(),
                ),
                loadPicture: (_) async => null,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Track 0'), findsOneWidget);

      rebuild(() => currentController = replacementController);
      await tester.pumpAndSettle();
      rebuild(() {});
      await tester.pumpAndSettle();

      expect(find.text('Track 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('recommendation-0')), findsOneWidget);
      expect(replacementRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders reasons and starts an attributed recommendation queue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'data': recommendationSnapshotJson()})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final resolver = _Resolver();
    final player = PlayerController(
      resolver: resolver,
      audio: SilentAudioPort(),
    );

    await tester.pumpWidget(
      harness(
        RecommendationScreen(
          controller: RecommendationController(
            repository: RecommendationRepository(api),
            cache: _Cache(),
          ),
          player: player,
          loadPicture: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('为你拓展新的音乐方向'), findsOneWidget);
    expect(find.text('值得再次播放'), findsOneWidget);
    expect(
      find.byKey(const Key('recommendation-interest-recommendation-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recommendation-interest-recommendation-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('recommendations-play-all')));
    await tester.pumpAndSettle();

    expect(resolver.ids, ['recommendation-0']);
    expect(player.state.queue, hasLength(2));
  });
}
