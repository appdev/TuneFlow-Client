import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/storage/app_image_cache.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';

import '../support/fake_app_image_cache.dart';
import '../support/memory_app_preferences.dart';
import '../support/test_image_cache_manager.dart';

void main() {
  late TestImageCacheManager manager;

  setUp(() {
    manager = TestImageCacheManager();
  });

  testWidgets('exposes the exact image cache to descendants', (tester) async {
    final cache = FakeAppImageCache(manager: manager);
    AppImageCache? received;

    await tester.pumpWidget(
      AppImageCacheScope(
        cache: cache,
        child: Builder(
          builder: (context) {
            received = AppImageCacheScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(received, same(cache));
  });

  testWidgets('maybeOf returns null outside an image cache scope', (
    tester,
  ) async {
    AppImageCache? cache;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          cache = AppImageCacheScope.maybeOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(cache, isNull);
  });

  testWidgets('app installs and disposes the provided image cache', (
    tester,
  ) async {
    final cache = FakeAppImageCache(manager: manager);

    await tester.pumpWidget(
      MusicFreeServiceApp(
        preferences: MemoryAppPreferences(),
        audio: SilentAudioPort(),
        imageCache: cache,
      ),
    );
    await tester.pumpAndSettle();

    final scope = tester.widget<AppImageCacheScope>(
      find.byType(AppImageCacheScope),
    );
    expect(scope.cache, same(cache));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(cache.disposeCalls, 1);
  });
}
