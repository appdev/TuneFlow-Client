import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_glass_policy.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/mobile_vinyl_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
      const Size.square(240),
    );
    expect(
      find.byKey(const Key('player-mobile-vinyl-spindle')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('One封面'), findsOneWidget);
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
}

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.byKey(const Key('player-mobile-vinyl-turn')),
    )
    .turns
    .value;

Widget _harness({required bool rotating, bool disableAnimations = false}) {
  return ShadApp.custom(
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
                dimension: 240,
                child: MobileVinylRecord(
                  source: const AppArtworkSource.fallback(
                    fallbackSeed: 'kw:one',
                  ),
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
