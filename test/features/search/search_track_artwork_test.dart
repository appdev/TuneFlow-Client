import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/search/search_track_artwork.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('uses response artwork without requesting fallback', (
    tester,
  ) async {
    var calls = 0;
    final track = Track.fromJson({
      'id': 'one',
      'name': 'One',
      'source': 'tx',
      'img': 'https://example.test/one.jpg',
    });
    final manager = TestImageCacheManager();
    await tester.pumpWidget(
      harness(
        AppImageCacheScope(
          cache: FakeAppImageCache(manager: manager),
          child: SearchTrackArtwork(
            track: track,
            loadPicture: (_) async {
              calls++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(calls, 0);
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://example.test/one.jpg');
    expect(image.cacheKey, 'https://example.test/one.jpg');
    expect(image.httpHeaders?['User-Agent'], startsWith('Mozilla/5.0'));
    expect(image.cacheManager, same(manager));
  });

  testWidgets('requests missing artwork once then shows initial fallback', (
    tester,
  ) async {
    var calls = 0;
    final track = Track.fromJson({'id': 'one', 'name': '晴天', 'source': 'tx'});
    final widget = SearchTrackArtwork(
      track: track,
      loadPicture: (_) async {
        calls++;
        return null;
      },
    );
    await tester.pumpWidget(harness(widget));
    await tester.pump();
    await tester.pumpWidget(harness(widget));
    await tester.pump();

    expect(calls, 1);
    expect(
      find.byKey(const Key('search-artwork-fallback-tx-one')),
      findsOneWidget,
    );
    expect(find.text('晴'), findsOneWidget);
  });

  testWidgets('same track identity adopts a refreshed response URL', (
    tester,
  ) async {
    final manager = TestImageCacheManager();
    final cache = FakeAppImageCache(manager: manager);
    final oldTrack = Track.fromJson({
      'id': 'same',
      'name': 'Same',
      'source': 'tx',
      'pic': 'https://example.test/old.jpg',
    });
    final newTrack = Track.fromJson({
      'id': 'same',
      'name': 'Same',
      'source': 'tx',
      'pic': 'https://example.test/new.jpg',
    });

    Widget artwork(Track track) => harness(
      AppImageCacheScope(
        cache: cache,
        child: SearchTrackArtwork(
          track: track,
          loadPicture: (_) async => null,
        ),
      ),
    );

    await tester.pumpWidget(artwork(oldTrack));
    await tester.pump();
    expect(
      tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).imageUrl,
      'https://example.test/old.jpg',
    );

    await tester.pumpWidget(artwork(newTrack));
    await tester.pump();

    expect(
      tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).imageUrl,
      'https://example.test/new.jpg',
    );
  });
}
