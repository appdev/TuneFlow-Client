import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/desktop_vinyl_portal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test(
    'normalized playback progress clamps invalid and out-of-range values',
    () {
      expect(
        normalizedPlaybackProgress(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 60),
        ),
        .5,
      );
      expect(
        normalizedPlaybackProgress(
          position: const Duration(seconds: -1),
          duration: const Duration(seconds: 60),
        ),
        0,
      );
      expect(
        normalizedPlaybackProgress(
          position: const Duration(seconds: 70),
          duration: const Duration(seconds: 60),
        ),
        1,
      );
      expect(
        normalizedPlaybackProgress(
          position: const Duration(seconds: 1),
          duration: Duration.zero,
        ),
        0,
      );
      expect(
        normalizedPlaybackProgress(
          position: const Duration(seconds: 1),
          duration: const Duration(seconds: -1),
        ),
        0,
      );
    },
  );

  testWidgets('portal keeps artwork and spindle inside its visible clip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await _pumpPortal(
      tester,
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 60),
    );

    final clip = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-portal-clip')),
    );
    final artwork = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-artwork')),
    );
    final spindle = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-spindle')),
    );
    expect(clip.contains(artwork.centerLeft), isTrue);
    expect(clip.contains(artwork.centerRight), isTrue);
    expect(clip.contains(artwork.topCenter), isTrue);
    expect(clip.contains(artwork.bottomCenter), isTrue);
    expect(clip.contains(spindle.center), isTrue);
    expect(find.bySemanticsLabel('Portal封面'), findsOneWidget);
    expect(find.bySemanticsLabel('NOW PLAYING'), findsNothing);
    expect(
      find.byKey(const Key('player-desktop-vinyl-progress-axis')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('progress marker moves down without becoming interactive', (
    tester,
  ) async {
    await _pumpPortal(
      tester,
      position: const Duration(seconds: 25),
      duration: const Duration(seconds: 100),
    );
    final first = tester.getCenter(
      find.byKey(const Key('player-desktop-vinyl-progress-marker')),
    );

    await _pumpPortal(
      tester,
      position: const Duration(seconds: 75),
      duration: const Duration(seconds: 100),
    );
    final second = tester.getCenter(
      find.byKey(const Key('player-desktop-vinyl-progress-marker')),
    );

    expect(second.dy, greaterThan(first.dy));
    final axis = find.byKey(const Key('player-desktop-vinyl-progress-axis'));
    expect(
      find.descendant(of: axis, matching: find.byType(Slider)),
      findsNothing,
    );
    expect(
      find.descendant(of: axis, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });
}

Future<void> _pumpPortal(
  WidgetTester tester, {
  required Duration position,
  required Duration duration,
}) async {
  tester.view.physicalSize = const Size(680, 625);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ShadApp.custom(
      theme: buildDarkTheme(),
      appBuilder: (context) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 680,
            height: 625,
            child: DesktopVinylPortal(
              source: const AppArtworkSource.fallback(
                fallbackSeed: 'kw:portal',
              ),
              seed: 'kw:portal',
              semanticLabel: 'Portal封面',
              rotating: false,
              position: position,
              duration: duration,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
