import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/fake_app_image_cache.dart';
import '../support/test_image_cache_manager.dart';

Widget fallbackHarness({
  required ThemeMode mode,
  required String seed,
  double size = 120,
  IconData icon = LucideIcons.music2,
  bool showFallback = true,
}) => ShadApp(
  key: ValueKey(mode),
  theme: buildLightTheme(),
  darkTheme: buildDarkTheme(),
  themeMode: mode,
  home: Center(
    child: AppArtwork(
      seed: seed,
      semanticLabel: '$seed cover',
      size: size,
      icon: icon,
      showFallback: showFallback,
    ),
  ),
);

void main() {
  test('artwork source owns one normalized URL for all consumers', () {
    final source = AppArtworkSource.network(
      'https://example.com/cover.jpg',
      fallbackSeed: 'source:track',
    );

    expect(source.url, 'https://example.com/cover.jpg');
    expect(source.fallbackSeed, 'source:track');
  });

  test('missing artwork source retains its deterministic fallback seed', () {
    final source = AppArtworkSource.fromUrl(null, fallbackSeed: 'fallback');

    expect(source.url, isNull);
    expect(source.fallbackSeed, 'fallback');
  });

  test('NetEase artwork replaces CDN nodes that reject Flutter requests', () {
    final source = AppArtworkSource.network(
      'https://p2.music.126.net/example.jpg',
      fallbackSeed: 'wy:track',
    );

    expect(source.url, 'https://p3.music.126.net/example.jpg');
  });

  testWidgets('uses the shared CE cache with stable normalized URL identity', (
    tester,
  ) async {
    final manager = TestImageCacheManager();
    final cache = FakeAppImageCache(manager: manager);

    await tester.pumpWidget(
      MaterialApp(
        home: AppImageCacheScope(
          cache: cache,
          child: const AppArtwork(
            imageUrl: 'https://p2.music.126.net/cover.jpg',
            seed: 'wy:one',
            semanticLabel: '缓存封面',
            size: 48,
          ),
        ),
      ),
    );

    final rendered = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(rendered.imageUrl, 'https://p3.music.126.net/cover.jpg');
    expect(rendered.cacheKey, 'https://p3.music.126.net/cover.jpg');
    expect(rendered.httpHeaders, artworkRequestHeaders);
    expect(rendered.cacheManager, same(cache.manager));
    expect(rendered.disablePlaceholderOnCacheHit, isTrue);
    expect(rendered.useOldImageOnUrlChange, isFalse);
    expect(rendered.fadeInDuration, Duration.zero);
    expect(rendered.fadeOutDuration, Duration.zero);
    expect(rendered.fit, BoxFit.cover);
    expect(rendered.filterQuality, FilterQuality.medium);
  });

  testWidgets('a changed URL never keeps the previous real image', (
    tester,
  ) async {
    const oldUrl = 'https://example.test/old.png';
    const newUrl = 'https://example.test/new.png';
    final manager = TestImageCacheManager(
      cachedFile: FileInfo(
        const LocalFileSystem().file('assets/branding/TuneFlow.png'),
        FileSource.Cache,
        DateTime.utc(2030),
        oldUrl,
      ),
    );
    final cache = FakeAppImageCache(manager: manager);

    Widget artwork(String url, String seed) => MaterialApp(
      home: AppImageCacheScope(
        cache: cache,
        child: AppArtwork(
          imageUrl: url,
          seed: seed,
          semanticLabel: '$seed cover',
          size: 48,
        ),
      ),
    );

    await tester.pumpWidget(artwork(oldUrl, 'old'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('artwork-fallback-old')), findsNothing);

    manager.cachedFile = null;
    manager.fileStream = const Stream<FileResponse>.empty();
    await tester.pumpWidget(artwork(newUrl, 'new'));
    await tester.pump();
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, newUrl);
    final rendered = tester.widget<Image>(find.byType(Image));
    expect((rendered.image as CachedNetworkImageProvider).url, newUrl);
    expect(find.byKey(const Key('artwork-fallback-new')), findsOneWidget);
  });

  testWidgets('both themes use the same record and filled-note structure', (
    tester,
  ) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        fallbackHarness(mode: mode, seed: mode.name, size: 120),
      );

      expect(
        find.byKey(Key('artwork-fallback-record-${mode.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('artwork-fallback-symbol-${mode.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('artwork-fallback-filled-note-${mode.name}')),
        findsOneWidget,
      );
      expect(find.text('TUNEFLOW'), findsNothing);
    }
  });

  testWidgets('both themes preserve a playlist-specific icon', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        fallbackHarness(
          mode: mode,
          seed: 'playlist',
          icon: LucideIcons.listMusic,
        ),
      );

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('artwork-fallback-symbol-playlist')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, LucideIcons.listMusic);
      expect(
        find.byKey(const Key('artwork-fallback-filled-note-playlist')),
        findsNothing,
      );
    }
  });

  testWidgets('dark fallback removes the waveform at every size', (
    tester,
  ) async {
    for (final size in [44.0, 96.0, 192.0]) {
      await tester.pumpWidget(
        fallbackHarness(mode: ThemeMode.dark, seed: 'dark', size: size),
      );
      expect(
        find.byKey(const Key('artwork-fallback-record-dark')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('artwork-fallback-dark-waveform-dark')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('artwork-fallback-dark-wordmark-dark')),
        findsNothing,
      );
    }
  });

  testWidgets('theme switching preserves artwork semantics and geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      fallbackHarness(mode: ThemeMode.light, seed: 'switch', size: 120),
    );
    var semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('artwork-fallback-switch')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.label, 'switch cover');
    expect(tester.getSize(find.byType(AppArtwork)), const Size(120, 120));
    expect(
      find.byKey(const Key('artwork-fallback-record-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('artwork-fallback-filled-note-switch')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      fallbackHarness(mode: ThemeMode.dark, seed: 'switch', size: 120),
    );
    await tester.pumpAndSettle();
    semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('artwork-fallback-switch')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.label, 'switch cover');
    expect(tester.getSize(find.byType(AppArtwork)), const Size(120, 120));
    expect(
      find.byKey(const Key('artwork-fallback-record-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('artwork-fallback-filled-note-switch')),
      findsOneWidget,
    );
  });

  testWidgets('fallback opt-out remains empty', (tester) async {
    await tester.pumpWidget(
      fallbackHarness(
        mode: ThemeMode.light,
        seed: 'hidden',
        showFallback: false,
      ),
    );

    expect(find.byKey(const Key('artwork-fallback-hidden')), findsNothing);
  });

  testWidgets('network loading honors fallback opt-out', (tester) async {
    final cache = FakeAppImageCache(manager: TestImageCacheManager());

    await tester.pumpWidget(
      MaterialApp(
        home: AppImageCacheScope(
          cache: cache,
          child: const AppArtwork(
            imageUrl: 'https://example.test/pending.png',
            seed: 'hidden-network',
            semanticLabel: 'pending cover',
            size: 48,
            showFallback: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('artwork-fallback-hidden-network')),
      findsNothing,
    );
  });

  testWidgets('without an app cache network artwork stays managed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppArtwork(
          imageUrl: 'https://example.test/unmanaged.png',
          seed: 'unmanaged',
          semanticLabel: 'unmanaged cover',
          size: 48,
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(
      find.byKey(const Key('artwork-fallback-unmanaged')),
      findsOneWidget,
    );
  });
}
