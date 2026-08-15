import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/desktop_dynamic_player_backdrop.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const palette = ArtworkPalette(
  backgroundBase: Color(0xFFE2F1EF),
  backgroundCompanion: Color(0xFFF5D9CC),
  vinylAccent: Color(0xFFD77E34),
  foreground: Color(0xFF202020),
);

Widget harness({bool reduceMotion = false}) => ShadApp(
  theme: buildLightTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Scaffold(
      body: DesktopDynamicPlayerBackdrop(
        palette: palette,
        transitionKey: 'track',
      ),
    ),
  ),
);

void main() {
  testWidgets('desktop backdrop draws two decorative palette gradients', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    expect(find.byKey(const Key('player-desktop-backdrop')), findsOneWidget);
    expect(
      find.byKey(const Key('player-desktop-backdrop-gradient-base')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('player-desktop-backdrop-gradient-companion')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('track'), findsNothing);
    expect(
      tester
          .widget<TweenAnimationBuilder<ArtworkPalette>>(
            find.byType(TweenAnimationBuilder<ArtworkPalette>),
          )
          .duration,
      const Duration(milliseconds: 560),
    );
  });

  testWidgets('reduced motion caps the palette transition at 150ms', (
    tester,
  ) async {
    await tester.pumpWidget(harness(reduceMotion: true));

    expect(
      tester
          .widget<TweenAnimationBuilder<ArtworkPalette>>(
            find.byType(TweenAnimationBuilder<ArtworkPalette>),
          )
          .duration,
      const Duration(milliseconds: 150),
    );
  });
}
