import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/playback_progress.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('changing tracks cancels the old seek gesture', (tester) async {
    final seeks = <Duration>[];
    Widget progress(String track, int seconds) => ShadApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: PlaybackProgress(
          trackIdentity: track,
          position: Duration(seconds: seconds),
          duration: const Duration(minutes: 3),
          onSeek: seeks.add,
        ),
      ),
    );
    await tester.pumpWidget(progress('one', 30));
    final area = tester.getRect(
      find.byKey(const Key('playback-progress-hit-area')),
    );
    final gesture = await tester.startGesture(area.center);
    await tester.pump();
    await tester.pumpWidget(progress('two', 10));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pump();
    expect(seeks, isEmpty);
    expect(find.text('0:10'), findsOneWidget);
    await tester.tapAt(area.center);
    expect(seeks, [const Duration(seconds: 90)]);
  });
  testWidgets('playback progress keeps times aligned and supports seeking', (
    tester,
  ) async {
    Duration? seeked;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: PlaybackProgress(
                position: const Duration(minutes: 1, seconds: 5),
                duration: const Duration(minutes: 4, seconds: 5),
                onSeek: (value) => seeked = value,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
    expect(
      tester.getCenter(find.text('1:05')).dy,
      tester.getCenter(find.text('4:05')).dy,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('playback-progress-hit-area')))
          .height,
      28,
    );
    final slider = tester.widget<ShadSlider>(find.byType(ShadSlider));
    expect(slider.trackHeight, 4);
    expect(slider.thumbRadius, 6);
    expect(slider.inactiveTrackColor, AppTokens.light.playbackTrackInactive);
    expect(
      _contrastRatio(slider.inactiveTrackColor!, AppTokens.light.background),
      greaterThanOrEqualTo(3),
    );
    expect(tester.getSize(find.text('1:05')).width, lessThanOrEqualTo(42));
    expect(tester.getSize(find.text('4:05')).width, lessThanOrEqualTo(42));

    final sliderRect = tester.getRect(
      find.byKey(const Key('playback-progress-hit-area')),
    );
    final gesture = await tester.startGesture(
      Offset(sliderRect.left + sliderRect.width * 0.25, sliderRect.center.dy),
    );
    await gesture.moveTo(
      Offset(sliderRect.left + sliderRect.width * 0.75, sliderRect.center.dy),
    );
    await tester.pump();
    expect(seeked, isNull, reason: 'dragging previews without seeking');
    expect(find.text('3:03'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(seeked, isNotNull);
    expect(seeked!.inSeconds, greaterThan(180));
  });

  testWidgets('playback progress expands only its interaction height', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: PlaybackProgress(
            position: const Duration(seconds: 30),
            duration: const Duration(minutes: 3),
            hitExtent: 44,
            trackHeight: 4,
            thumbDiameter: 12,
            onSeek: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const Key('playback-progress-hit-area')))
          .height,
      44,
    );
    final slider = tester.widget<ShadSlider>(find.byType(ShadSlider));
    expect(slider.trackHeight, 4);
    expect(slider.thumbRadius, 6);
  });

  testWidgets('playback progress disables seeking without a duration', (
    tester,
  ) async {
    var seekCount = 0;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: PlaybackProgress(
            position: Duration.zero,
            duration: Duration.zero,
            onSeek: (_) => seekCount += 1,
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(ShadSlider)));
    await tester.pump();

    expect(seekCount, 0);
  });

  testWidgets('cancelling a seek restores the actual position', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: PlaybackProgress(
            position: const Duration(seconds: 30),
            duration: const Duration(minutes: 3),
            onSeek: seeks.add,
          ),
        ),
      ),
    );
    final area = tester.getRect(
      find.byKey(const Key('playback-progress-hit-area')),
    );
    final gesture = await tester.startGesture(area.center);
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);
    await gesture.cancel();
    await tester.pump();
    expect(seeks, isEmpty);
    expect(find.text('0:30'), findsOneWidget);
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}
