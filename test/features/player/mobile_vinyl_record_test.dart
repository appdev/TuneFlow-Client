import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_glass_policy.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/desktop_orbit_vinyl.dart';
import 'package:musicfree_service_client/features/player/mobile_vinyl_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _palette = ArtworkPalette(
  backgroundBase: Color(0xFFEAF2FF),
  backgroundCompanion: Color(0xFFF5E9FF),
  vinylAccent: Color(0xFF4A8FE7),
  foreground: Color(0xFF17191B),
);

void main() {
  testWidgets('mobile vinyl keeps circular artwork structure and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('player-mobile-vinyl'))),
      const Size.square(240),
    );
    expect(
      find.byKey(const Key('player-mobile-vinyl-artwork')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('player-mobile-vinyl-artwork'))),
      const Size.square(144),
    );
    expect(
      find.byKey(const Key('player-mobile-vinyl-spindle')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('One封面'), findsOneWidget);
    expect(
      find.byKey(const Key('player-desktop-vinyl-resin-texture')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('player-desktop-vinyl-groove-highlight')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('player-desktop-vinyl-resin-texture')),
        matching: find.byKey(const Key('player-desktop-vinyl-resin-clip')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('player-desktop-vinyl-groove-highlight')),
        matching: find.byKey(const Key('player-desktop-vinyl-groove-clip')),
      ),
      findsOneWidget,
    );
    final material = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-material')),
    );
    expect(
      (material.painter! as PressedVinylPainter).baseColor,
      _palette.vinylAccent,
    );
  });

  testWidgets('mobile vinyl pauses and resumes from its current angle', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: true));
    final initial = _turns(tester);

    await tester.pump(const Duration(seconds: 1));
    final playing = _turns(tester);
    expect(playing, greaterThan(initial));

    await tester.pumpWidget(_harness(rotating: false));
    final stopped = _turns(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester), closeTo(stopped, 1e-6));

    await tester.pumpWidget(_harness(rotating: true));
    expect(_turns(tester), closeTo(stopped, 1e-6));
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester), greaterThan(stopped));
  });

  testWidgets('mobile vinyl stays still when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: true, disableAnimations: true));
    final initial = _turns(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(_turns(tester), closeTo(initial, 1e-6));
  });

  testWidgets('mobile vinyl rotates with accessible navigation enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(rotating: true, accessibleNavigation: true),
    );
    final initial = _turns(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(_turns(tester), greaterThan(initial));
  });
}

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.byKey(const Key('player-mobile-vinyl-turn')),
    )
    .turns
    .value;

Widget _harness({
  required bool rotating,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) {
  return ShadApp.custom(
    theme: buildLightTheme(),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: AppGlassPolicyScope(
          reduceTransparency: false,
          performanceDegraded: false,
          child: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 240,
                child: MobileVinylRecord(
                  source: const AppArtworkSource.fallback(
                    fallbackSeed: 'kw:one',
                  ),
                  palette: _palette,
                  seed: 'kw:one',
                  semanticLabel: 'One封面',
                  rotating: rotating,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
