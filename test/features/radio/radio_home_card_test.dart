import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/radio/radio_controller.dart';
import 'package:musicfree_service_client/features/radio/radio_home_card.dart';
import 'package:musicfree_service_client/features/radio/radio_models.dart';
import 'package:musicfree_service_client/features/radio/radio_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final class _Resolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) =>
      throw UnimplementedError();
}

final class _Radio implements RadioSessionPort {
  @override
  Future<void> close(String sessionId) async {}
  @override
  Future<RadioBatch> create({
    required RadioMode mode,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 10,
  }) => throw UnimplementedError();
  @override
  Future<RadioBatch> next({
    required String sessionId,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 10,
  }) => throw UnimplementedError();
}

Widget harness(double width, RadioController controller) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: ShadAppBuilder(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: RadioHomeCard(controller: controller),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final (width, key) in [
    (360.0, 'radio-home-mobile'),
    (720.0, 'radio-home-compact'),
    (1180.0, 'radio-home-wide'),
  ]) {
    testWidgets('radio home card adapts at ${width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width + 100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = PlayerController(
        resolver: _Resolver(),
        audio: SilentAudioPort(),
      );
      final controller = RadioController(repository: _Radio(), player: player);
      addTearDown(controller.dispose);
      addTearDown(player.dispose);

      await tester.pumpWidget(harness(width, controller));
      await tester.pump();

      expect(find.byKey(Key(key)), findsOneWidget);
      expect(find.byKey(const Key('radio-start')), findsOneWidget);
      expect(find.byKey(const Key('radio-auto-continuation')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
