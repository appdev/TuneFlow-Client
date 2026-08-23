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
  testWidgets('record keeps fixed light layers outside rotating material', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    expect(find.byKey(const Key('player-desktop-orbit-vinyl')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-desktop-orbit-vinyl')),
        matching: find.byType(AppArtwork),
      ),
      findsOneWidget,
    );
    final ambilight = find.byKey(const Key('player-desktop-vinyl-ambilight'));
    expect(ambilight, findsOneWidget);
    expect(
      find.ancestor(
        of: ambilight,
        matching: find.byKey(const Key('player-desktop-orbit-turn')),
      ),
      findsNothing,
    );
    final glaze = find.byKey(const Key('player-desktop-vinyl-optical-glaze'));
    expect(glaze, findsOneWidget);
    expect(
      find.ancestor(
        of: glaze,
        matching: find.byKey(const Key('player-desktop-orbit-turn')),
      ),
      findsNothing,
    );
    final underlight = find.byKey(const Key('player-desktop-vinyl-underlight'));
    expect(underlight, findsOneWidget);
    expect(
      find.ancestor(
        of: underlight,
        matching: find.byKey(const Key('player-desktop-orbit-turn')),
      ),
      findsNothing,
    );
    for (final key in const [
      Key('player-desktop-vinyl-material'),
      Key('player-desktop-vinyl-resin-texture'),
      Key('player-desktop-vinyl-groove-highlight'),
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
    for (final removedKey in const [
      Key('player-desktop-vinyl-diffraction'),
      Key('player-desktop-vinyl-refraction'),
      Key('player-desktop-vinyl-edge-fade'),
    ]) {
      expect(find.byKey(removedKey), findsNothing);
    }
    expect(
      tester.getSize(find.byKey(const Key('player-desktop-vinyl-artwork'))),
      const Size.square(240),
    );
    expect(find.bySemanticsLabel('Current song封面'), findsOneWidget);
    expect(
      find.byKey(const Key('player-desktop-vinyl-ambilight-turn')),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('player-desktop-vinyl-artwork')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Opacity || widget is ColorFiltered,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('shared resin entry point accepts platform structural keys', (
    tester,
  ) async {
    const rootKey = Key('shared-root');
    const turnKey = Key('shared-turn');
    const artworkKey = Key('shared-artwork');
    const spindleKey = Key('shared-spindle');
    await tester.pumpWidget(
      _harness(
        rotating: false,
        vinylKey: rootKey,
        turnKey: turnKey,
        artworkKey: artworkKey,
        spindleKey: spindleKey,
      ),
    );

    for (final key in const [rootKey, turnKey, artworkKey, spindleKey]) {
      expect(find.byKey(key), findsOneWidget);
    }
    for (final key in const [
      Key('player-desktop-vinyl-resin-texture'),
      Key('player-desktop-vinyl-groove-highlight'),
    ]) {
      expect(
        find.ancestor(of: find.byKey(key), matching: find.byKey(turnKey)),
        findsOneWidget,
      );
    }
  });

  testWidgets('ambilight keeps geometry while blur policy changes', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    final ambilight = find.byKey(const Key('player-desktop-vinyl-ambilight'));
    final blurredSize = tester.getSize(ambilight);
    expect(blurredSize, const Size.square(432));
    expect(
      find.byKey(const Key('player-desktop-vinyl-ambilight-blur')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('player-desktop-vinyl-ambilight-fallback')),
      findsNothing,
    );

    await tester.pumpWidget(
      _harness(rotating: false, reduceTransparency: true),
    );

    expect(tester.getSize(ambilight), blurredSize);
    expect(
      find.byKey(const Key('player-desktop-vinyl-ambilight-blur')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('player-desktop-vinyl-ambilight-fallback')),
      findsOneWidget,
    );
    final glazePaint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-optical-glaze-paint')),
    );
    expect((glazePaint.painter! as VinylOpticalGlazePainter).softened, isFalse);
  });

  testWidgets('vinyl uses palette-driven base and continuous asset layers', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    final paint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-material')),
    );
    final painter = paint.painter! as PressedVinylPainter;
    expect(painter.baseColor, palette.vinylAccent);
    expect(painter.materialOpacity, .54);
    expect(painter.materialOpacity, greaterThan(0));
    expect(painter.materialOpacity, lessThan(1));
    expect(
      painter.shouldRepaint(
        PressedVinylPainter(baseColor: palette.vinylAccent),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        PressedVinylPainter(baseColor: const Color(0xFF2856A8)),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        PressedVinylPainter(
          baseColor: palette.vinylAccent,
          materialOpacity: .70,
        ),
      ),
      isTrue,
    );
    final texture = tester.widget<Image>(
      find.byKey(const Key('player-desktop-vinyl-resin-texture')),
    );
    final grooves = tester.widget<Image>(
      find.byKey(const Key('player-desktop-vinyl-groove-highlight')),
    );
    expect(
      (texture.image as AssetImage).assetName,
      'assets/vinyl/qq_record_player_multi_texture.png',
    );
    expect(texture.colorBlendMode, BlendMode.softLight);
    expect(
      (grooves.image as AssetImage).assetName,
      'assets/vinyl/qq_record_player_multi_highlight.png',
    );
    expect(grooves.colorBlendMode, BlendMode.modulate);
  });

  testWidgets('blue resin tint compensates chroma before compositing', (
    tester,
  ) async {
    const bluePalette = ArtworkPalette(
      backgroundBase: Color(0xFFF0F4FA),
      backgroundCompanion: Color(0xFFF4EEF8),
      vinylAccent: Color(0xFF1864AD),
      foreground: Color(0xFF17191B),
    );
    await tester.pumpWidget(
      _harness(rotating: false, vinylPalette: bluePalette),
    );

    final texture = tester.widget<Image>(
      find.byKey(const Key('player-desktop-vinyl-resin-texture')),
    );
    final tint = HSVColor.fromColor(texture.color!);

    expect(tint.hue, inInclusiveRange(210, 220));
    expect(tint.saturation, greaterThanOrEqualTo(.90));
    expect(tint.value, inInclusiveRange(.86, .96));
  });

  testWidgets('optical glaze is a fixed palette-driven resin ring', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    final paint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-optical-glaze-paint')),
    );
    final painter = paint.painter! as VinylOpticalGlazePainter;
    expect(painter.accentColor, palette.vinylAccent);
    expect(painter.companionColor, palette.backgroundCompanion);
    expect(painter.innerFraction, .60);
    expect(painter.softened, isTrue);
    expect(
      painter.shouldRepaint(
        VinylOpticalGlazePainter(
          accentColor: palette.vinylAccent,
          companionColor: palette.backgroundCompanion,
          softened: true,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('underlight is a fixed palette-driven transmission ring', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    final paint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-underlight-paint')),
    );
    final painter = paint.painter! as VinylUnderlightPainter;
    expect(painter.accentColor, palette.vinylAccent);
    expect(painter.companionColor, palette.backgroundCompanion);
    expect(painter.innerFraction, .60);
    expect(painter.softened, isTrue);
    expect(
      painter.shouldRepaint(
        VinylUnderlightPainter(
          accentColor: palette.vinylAccent,
          companionColor: palette.backgroundCompanion,
          softened: true,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('ambilight adapts its material to theme brightness', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: false));

    final lightPaint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-ambilight-paint')),
    );
    expect(
      (lightPaint.painter! as VinylAmbilightPainter).brightness,
      Brightness.light,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _harness(rotating: false, themeMode: ThemeMode.dark),
    );

    final darkPaint = tester.widget<CustomPaint>(
      find.byKey(const Key('player-desktop-vinyl-ambilight-paint')),
    );
    expect(
      (darkPaint.painter! as VinylAmbilightPainter).brightness,
      Brightness.dark,
    );
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

  testWidgets('rotation reuses the vinyl and fixed light rasters', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(rotating: true));
    await tester.pump();

    final material = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-material')),
    );
    final ambilight = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-ambilight-paint')),
    );
    final glaze = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-optical-glaze-paint')),
    );
    final underlight = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-underlight-paint')),
    );
    var materialPaints = 0;
    var ambilightPaints = 0;
    var glazePaints = 0;
    var underlightPaints = 0;
    final previousCallback = debugOnProfilePaint;
    debugOnProfilePaint = (renderObject) {
      previousCallback?.call(renderObject);
      if (identical(renderObject, material)) materialPaints++;
      if (identical(renderObject, ambilight)) ambilightPaints++;
      if (identical(renderObject, glaze)) glazePaints++;
      if (identical(renderObject, underlight)) underlightPaints++;
    };
    try {
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(materialPaints, 0);
      expect(ambilightPaints, 0);
      expect(glazePaints, 0);
      expect(underlightPaints, 0);
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

    final material = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-material')),
    );
    final ambilight = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-ambilight-paint')),
    );
    final glaze = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-optical-glaze-paint')),
    );
    final underlight = tester.renderObject(
      find.byKey(const Key('player-desktop-vinyl-underlight-paint')),
    );
    var materialPaints = 0;
    var ambilightPaints = 0;
    var glazePaints = 0;
    var underlightPaints = 0;
    final previousCallback = debugOnProfilePaint;
    debugOnProfilePaint = (renderObject) {
      previousCallback?.call(renderObject);
      if (identical(renderObject, material)) materialPaints++;
      if (identical(renderObject, ambilight)) ambilightPaints++;
      if (identical(renderObject, glaze)) glazePaints++;
      if (identical(renderObject, underlight)) underlightPaints++;
    };
    try {
      for (var update = 0; update < 8; update++) {
        playbackUpdates.value++;
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(materialPaints, 0);
      expect(ambilightPaints, 0);
      expect(glazePaints, 0);
      expect(underlightPaints, 0);
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
  bool reduceTransparency = false,
  ThemeMode themeMode = ThemeMode.light,
  ValueListenable<int>? playbackUpdates,
  ArtworkPalette vinylPalette = palette,
  Key vinylKey = const Key('player-desktop-orbit-vinyl'),
  Key turnKey = const Key('player-desktop-orbit-turn'),
  Key artworkKey = const Key('player-desktop-vinyl-artwork'),
  Key spindleKey = const Key('player-desktop-vinyl-spindle'),
}) => ShadApp.custom(
  key: ValueKey(themeMode),
  theme: buildLightTheme(),
  darkTheme: buildDarkTheme(),
  themeMode: themeMode,
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: AppGlassPolicyScope(
        reduceTransparency: reduceTransparency,
        performanceDegraded: false,
        child: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 400,
              child: playbackUpdates == null
                  ? _vinyl(
                      rotating,
                      vinylPalette,
                      vinylKey: vinylKey,
                      turnKey: turnKey,
                      artworkKey: artworkKey,
                      spindleKey: spindleKey,
                    )
                  : ValueListenableBuilder(
                      valueListenable: playbackUpdates,
                      builder: (context, _, _) => _vinyl(
                        rotating,
                        vinylPalette,
                        vinylKey: vinylKey,
                        turnKey: turnKey,
                        artworkKey: artworkKey,
                        spindleKey: spindleKey,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Widget _vinyl(
  bool rotating,
  ArtworkPalette vinylPalette, {
  required Key vinylKey,
  required Key turnKey,
  required Key artworkKey,
  required Key spindleKey,
}) => DesktopOrbitVinyl(
  vinylKey: vinylKey,
  turnKey: turnKey,
  artworkKey: artworkKey,
  spindleKey: spindleKey,
  source: const AppArtworkSource.fallback(fallbackSeed: 'current'),
  palette: vinylPalette,
  seed: 'current',
  semanticLabel: 'Current song封面',
  rotating: rotating,
);
