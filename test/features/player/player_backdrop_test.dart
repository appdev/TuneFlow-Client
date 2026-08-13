import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/player_backdrop.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp(
  theme: buildLightTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('backdrop is decorative and uses the supplied provider', (
    tester,
  ) async {
    final source = AppArtworkSource.network(
      'https://example.com/cover.jpg',
      fallbackSeed: 'one',
    );
    await tester.pumpWidget(
      harness(PlayerBackdrop(source: source, transitionKey: 'one')),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(identical(image.image, source.provider), isTrue);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.bySemanticsLabel('封面背景'), findsNothing);
  });

  testWidgets('backdrop uses deterministic artwork when the URL is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        PlayerBackdrop(
          source: AppArtworkSource.fromUrl(null, fallbackSeed: 'missing'),
          transitionKey: 'missing',
        ),
      ),
    );

    expect(find.byKey(const Key('artwork-fallback-missing')), findsOneWidget);
  });
}
