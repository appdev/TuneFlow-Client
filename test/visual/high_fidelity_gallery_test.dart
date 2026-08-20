import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/app/app_shell.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/downloads_screen.dart';
import 'package:musicfree_service_client/features/home/home_screen.dart';
import 'package:musicfree_service_client/features/player/player_screen.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_controller.dart';
import 'package:musicfree_service_client/features/search/search_screen.dart';
import 'package:musicfree_service_client/features/search/search_track_artwork.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/l10n/app_localizations.dart';
import 'package:musicfree_service_client/platform/app_platform.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'high_fidelity_fixtures.dart';

void configureViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Widget shellHarness({
  required String path,
  required Widget child,
  required PlayerController player,
  ThemeMode themeMode = ThemeMode.dark,
}) {
  final api = fixtureApi();
  final connected = ConnectedService(
    api: api,
    capabilities: const Capabilities(
      runtime: 'service',
      apiVersion: 'v1',
      features: {},
    ),
  );
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(
        path: path,
        builder: (context, state) => AppShell(
          connected: connected,
          onDisconnect: () {},
          player: player,
          location: state.uri.path,
          platform: AppPlatform.macos,
          child: child,
        ),
      ),
    ],
  );
  return ShadApp.custom(
    theme: buildLightTheme(),
    darkTheme: buildDarkTheme(),
    themeMode: themeMode,
    appBuilder: (context) => MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => ShadAppBuilder(child: child!),
    ),
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize(
      enablePerformanceMonitor: false,
      warmUpImpellerPipeline: false,
    );
    final dataFontLoader = FontLoader('IBMPlexMono')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Medium.ttf'));
    final iconLoader = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    final materialIconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([
      dataFontLoader.load(),
      iconLoader.load(),
      materialIconLoader.load(),
    ]);
  });

  for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('home desktop ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(1440, 960));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtureHomeController();
      final player = await fixturePlayerController();
      await tester.pumpWidget(
        shellHarness(
          path: '/',
          player: player,
          themeMode: themeMode,
          child: HomeScreen(
            controller: controller,
            onSearch: () {},
            onPlaylists: () {},
            onDownloads: () {},
            player: player,
            now: () => DateTime(2026, 1, 1, 20),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile('goldens/home-desktop-${themeMode.name}.png'),
      );
    });

    testWidgets('search narrow ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(1024, 768));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtureSearchController();
      final player = await fixturePlayerController();
      final api = fixtureApi();
      await tester.pumpWidget(
        shellHarness(
          path: '/search',
          player: player,
          themeMode: themeMode,
          child: SearchScreen(
            controller: controller,
            playlists: PlaylistRepository(api),
            downloads: DownloadRepository(api),
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile('goldens/search-narrow-${themeMode.name}.png'),
      );
    });

    testWidgets('search desktop overview ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(1440, 900));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtureSearchController();
      final player = await fixturePlayerController();
      final api = fixtureApi();
      await tester.pumpWidget(
        shellHarness(
          path: '/search',
          player: player,
          themeMode: themeMode,
          child: SearchScreen(
            controller: controller,
            playlists: PlaylistRepository(api),
            downloads: DownloadRepository(api),
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile(
          'goldens/search-desktop-overview-${themeMode.name}.png',
        ),
      );
    });

    testWidgets('search mobile track list and actions ${themeMode.name}', (
      tester,
    ) async {
      configureViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtureSearchController();
      await controller.selectView(SearchView.tracks);
      final player = await fixturePlayerController();
      final api = fixtureApi();
      await tester.pumpWidget(
        shellHarness(
          path: '/search',
          player: player,
          themeMode: themeMode,
          child: SearchScreen(
            controller: controller,
            playlists: PlaylistRepository(api),
            downloads: DownloadRepository(api),
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SearchTrackArtwork), findsNothing);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile('goldens/search-mobile-tracks-${themeMode.name}.png'),
      );

      await tester.tap(find.byKey(const Key('search-more-kw-wind')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ShadSheet),
        matchesGoldenFile(
          'goldens/search-mobile-actions-${themeMode.name}.png',
        ),
      );
    });

    testWidgets('player mobile ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixturePlayerController();
      await tester.pumpWidget(
        shellHarness(
          path: '/player',
          player: controller,
          themeMode: themeMode,
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async => const Lyrics(
              original: '[00:01]晚风轻轻吹过\n[00:40]城市慢慢安静',
              translation: '[00:01]The night wind passes',
            ),
            wakeLock: NoopWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mobile-mini-player')), findsNothing);
      expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
      expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
      expect(find.byKey(const Key('player-mobile-progress')), findsOneWidget);
      expect(find.byKey(const Key('player-mobile-transport')), findsOneWidget);
      expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
      expect(find.text('封面'), findsNothing);
      expect(find.text('歌词'), findsNothing);
      expect(find.text('队列'), findsNothing);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile('goldens/player-mobile-${themeMode.name}.png'),
      );
    });

    testWidgets('player mobile queue ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixturePlayerController();
      await tester.pumpWidget(
        shellHarness(
          path: '/player',
          player: controller,
          themeMode: themeMode,
          child: PlayerScreen(
            controller: controller,
            lyricsLoader: (_) async =>
                const Lyrics(original: '[00:01]晚风轻轻吹过\n[00:40]城市慢慢安静'),
            wakeLock: NoopWakeLock(),
            keepAwake: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-mobile-queue')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('player-mobile-queue-sheet')),
        findsOneWidget,
      );
      expect(find.text('5 首'), findsOneWidget);
      expect(
        find.byKey(const Key('player-mobile-queue-clear')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/player-mobile-queue-${themeMode.name}.png'),
      );
    });

    testWidgets('downloads compact ${themeMode.name}', (tester) async {
      configureViewport(tester, const Size(360, 800));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await fixtureDownloadsController();
      final player = await fixturePlayerController();
      await tester.pumpWidget(
        shellHarness(
          path: '/downloads',
          player: player,
          themeMode: themeMode,
          child: DownloadsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('main-shell')),
        matchesGoldenFile('goldens/downloads-compact-${themeMode.name}.png'),
      );
    });
  }
}
