import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/player_backdrop.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

Widget harness(Widget child) => AppImageCacheScope(
  cache: FakeAppImageCache(manager: TestImageCacheManager()),
  child: ShadApp(
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('backdrop is decorative and uses the supplied artwork URL', (
    tester,
  ) async {
    final source = AppArtworkSource.network(
      'https://example.com/cover.jpg',
      fallbackSeed: 'one',
    );
    await tester.pumpWidget(
      harness(PlayerBackdrop(source: source, transitionKey: 'one')),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, source.url);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byKey(const Key('player-backdrop-artwork')), findsOneWidget);
    expect(find.byKey(const Key('player-backdrop-neutral')), findsNothing);
    expect(find.bySemanticsLabel('封面背景'), findsNothing);
  });

  testWidgets('backdrop stays neutral when the artwork URL is missing', (
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

    expect(find.byKey(const Key('player-backdrop-neutral')), findsOneWidget);
    expect(find.byType(AppArtwork), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(const Key('artwork-fallback-missing')), findsNothing);
  });
}
