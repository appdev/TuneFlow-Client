import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_glass_policy.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/desktop_orbit_vinyl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const palette = ArtworkPalette(
  backgroundBase: Color(0xFFE2F1EF),
  backgroundCompanion: Color(0xFFF5D9CC),
  vinylAccent: Color(0xFFD77E34),
  foreground: Color(0xFF202020),
);

void main() {
  testWidgets('record keeps original artwork and material in one turn', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    expect(find.byKey(const Key('player-desktop-orbit-vinyl')), findsOneWidget);
    for (final key in const [
      Key('player-desktop-vinyl-base'),
      Key('player-desktop-vinyl-refraction'),
      Key('player-desktop-vinyl-grooves'),
      Key('player-desktop-vinyl-artwork'),
      Key('player-desktop-vinyl-spindle'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(key),
          matching: find.byKey(const Key('player-desktop-orbit-turn')),
        ),
        findsOneWidget,
      );
    }
    expect(
      tester.getSize(find.byKey(const Key('player-desktop-vinyl-artwork'))),
      const Size.square(240),
    );
    expect(find.bySemanticsLabel('Current song封面'), findsOneWidget);
  });

  testWidgets('record pauses and resumes from the same angle', (tester) async {
    await tester.pumpWidget(_harness(rotating: true));
    await tester.pump(const Duration(seconds: 1));
    final playing = _turns(tester);

    await tester.pumpWidget(_harness(rotating: false));
    final stopped = _turns(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester), closeTo(stopped, 1e-6));

    await tester.pumpWidget(_harness(rotating: true));
    expect(_turns(tester), closeTo(stopped, 1e-6));
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester), greaterThan(playing));
  });

  testWidgets('record stays still with reduced motion', (tester) async {
    await tester.pumpWidget(_harness(rotating: true, disableAnimations: true));
    final initial = _turns(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_turns(tester), closeTo(initial, 1e-6));
  });

  testWidgets('rotation reuses the rasterized vinyl instead of repainting it', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: true));
    await tester.pump();

    final grooves = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-grooves')),
    );
    var groovePaints = 0;
    final previousCallback = debugOnProfilePaint;
    debugOnProfilePaint = (renderObject) {
      previousCallback?.call(renderObject);
      if (identical(renderObject, grooves)) groovePaints++;
    };
    try {
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(groovePaints, 0);
    } finally {
      debugOnProfilePaint = previousCallback;
    }
  });

  testWidgets('parent playback updates keep the vinyl rasterized', (
    tester,
  ) async {
    final playbackUpdates = ValueNotifier(0);
    addTearDown(playbackUpdates.dispose);
    await tester.pumpWidget(
      _harness(rotating: true, playbackUpdates: playbackUpdates),
    );
    await tester.pump();

    final grooves = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-grooves')),
    );
    var groovePaints = 0;
    final previousCallback = debugOnProfilePaint;
    debugOnProfilePaint = (renderObject) {
      previousCallback?.call(renderObject);
      if (identical(renderObject, grooves)) groovePaints++;
    };
    try {
      for (var update = 0; update < 8; update++) {
        playbackUpdates.value++;
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(groovePaints, 0);
    } finally {
      debugOnProfilePaint = previousCallback;
    }
  });
}

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.byKey(const Key('player-desktop-orbit-turn')),
    )
    .turns
    .value;

Widget _harness({
  required bool rotating,
  bool disableAnimations = false,
  ValueListenable<int>? playbackUpdates,
}) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: AppGlassPolicyScope(
        reduceTransparency: false,
        performanceDegraded: false,
        child: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 400,
              child: playbackUpdates == null
                  ? _vinyl(rotating)
                  : ValueListenableBuilder(
                      valueListenable: playbackUpdates,
                      builder: (context, _, _) => _vinyl(rotating),
                    ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Widget _vinyl(bool rotating) => DesktopOrbitVinyl(
  source: const AppArtworkSource.fallback(fallbackSeed: 'current'),
  palette: palette,
  seed: 'current',
  semanticLabel: 'Current song封面',
  rotating: rotating,
);
