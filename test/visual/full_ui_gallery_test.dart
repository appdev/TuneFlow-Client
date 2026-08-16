import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/app/app_shell.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_button.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:musicfree_service_client/features/discovery/discovery_screen.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/downloads_screen.dart';
import 'package:musicfree_service_client/features/home/home_screen.dart';
import 'package:musicfree_service_client/features/more/more_screen.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/player_screen.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/playlists/playlist_detail_screen.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlists_screen.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:musicfree_service_client/features/search/search_controller.dart'
    as feature;
import 'package:musicfree_service_client/features/search/search_history_repository.dart';
import 'package:musicfree_service_client/features/search/search_screen.dart';
import 'package:musicfree_service_client/features/settings/settings_screen.dart';
import 'package:musicfree_service_client/features/sources/sources_screen.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/l10n/app_localizations.dart';
import 'package:musicfree_service_client/platform/app_platform.dart';
import 'package:musicfree_service_client/platform/desktop_window_controller.dart';
import 'package:musicfree_service_client/platform/platform_window_frame.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'high_fidelity_fixtures.dart';

void _configureViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Widget _shellHarness({
  required String path,
  required Widget child,
  required PlayerController player,
  required AppPlatform platform,
  required ThemeMode themeMode,
}) {
  final api = fixtureApi();
  final connected = ConnectedService(
    origin: ServiceOrigin.parse('http://service.local'),
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
          platform: platform,
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

Widget _playerHarness({
  required Widget child,
  required AppPlatform platform,
  required ThemeMode themeMode,
}) => ShadApp.custom(
  theme: buildLightTheme(),
  darkTheme: buildDarkTheme(),
  themeMode: themeMode,
  appBuilder: (context) => MaterialApp(
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
    home: PlatformWindowFrame(
      platform: platform,
      location: '/player',
      controller: desktopWindowController,
      onBack: () {},
      playerAccent: fallbackArtworkPalette(
        'kw:wind',
        brightness: themeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ).vinylAccent,
      child: Scaffold(
        key: const Key('main-shell'),
        backgroundColor: Colors.transparent,
        body: ShadAppBuilder(child: child),
      ),
    ),
  ),
);

const _desktopPages = <String>[
  'home',
  'search',
  'playlist-square',
  'charts',
  'my-playlists',
  'playlist-detail',
  'player',
  'downloads',
  'settings',
  'sources',
  'states',
];

const _mobilePages = <String>[
  'home',
  'search',
  'playlist-square',
  'charts',
  'library',
  'playlist-detail',
  'player',
  'downloads',
  'settings',
  'sources',
  'more',
];

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize(
      enablePerformanceMonitor: false,
      warmUpImpellerPipeline: false,
    );
    final chineseFontLoader = FontLoader('NotoSansCJKsc')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
    final displayFontLoader = FontLoader('NotoSerifSC')
      ..addFont(
        rootBundle.load('assets/fonts/NotoSerifSC-VariableFont_wght.ttf'),
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
      chineseFontLoader.load(),
      displayFontLoader.load(),
      dataFontLoader.load(),
      iconLoader.load(),
      materialIconLoader.load(),
    ]);
  });

  for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
    for (final viewport in const [Size(1440, 960), Size(1024, 768)]) {
      for (final page in _desktopPages) {
        testWidgets('desktop $page ${themeMode.name} '
            '${viewport.width.toInt()}x${viewport.height.toInt()}', (
          tester,
        ) async {
          await _capture(
            tester,
            page: page,
            viewport: viewport,
            mobile: false,
            themeMode: themeMode,
          );
        });
      }
    }

    for (final viewport in const [Size(390, 844), Size(360, 800)]) {
      for (final page in _mobilePages) {
        testWidgets('mobile $page ${themeMode.name} '
            '${viewport.width.toInt()}x${viewport.height.toInt()}', (
          tester,
        ) async {
          await _capture(
            tester,
            page: page,
            viewport: viewport,
            mobile: true,
            themeMode: themeMode,
          );
        });
      }
    }

    for (final fixture in const [
      (Size(1440, 960), false),
      (Size(1024, 768), false),
      (Size(390, 844), true),
    ]) {
      testWidgets(
        '${fixture.$2 ? 'mobile' : 'desktop'} search history '
        '${themeMode.name} '
        '${fixture.$1.width.toInt()}x${fixture.$1.height.toInt()}',
        (tester) => _captureSearchHistory(
          tester,
          viewport: fixture.$1,
          mobile: fixture.$2,
          themeMode: themeMode,
        ),
      );
    }

    for (final platform in const [
      AppPlatform.macos,
      AppPlatform.windows,
      AppPlatform.linux,
    ]) {
      for (final viewport in const [Size(1440, 960), Size(1024, 768)]) {
        testWidgets(
          '${platform.name} window frame ${themeMode.name} '
          '${viewport.width.toInt()}x${viewport.height.toInt()}',
          (tester) => _capturePlatformFrame(
            tester,
            platform: platform,
            viewport: viewport,
            themeMode: themeMode,
          ),
        );
      }
    }
  }
}

Future<void> _capturePlatformFrame(
  WidgetTester tester, {
  required AppPlatform platform,
  required Size viewport,
  required ThemeMode themeMode,
}) async {
  _configureViewport(tester, viewport);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final player = await fixturePlayerController();
  await tester.pumpWidget(
    _shellHarness(
      path: '/',
      player: player,
      platform: platform,
      themeMode: themeMode,
      child: HomeScreen(
        controller: await fixtureHomeController(),
        onSearch: () {},
        onPlaylists: () {},
        onDownloads: () {},
        onSettings: () {},
        player: player,
        now: () => DateTime(2026, 1, 1, 20),
      ),
    ),
  );
  for (var attempt = 0; attempt < 10; attempt++) {
    if (find.byKey(const Key('home-screen')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('home-screen')), findsOneWidget);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/TuneFlow.png'),
      tester.element(find.byKey(const Key('main-shell'))),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(const Key('main-shell')),
    matchesGoldenFile(
      _goldenPath(
        '${platform.name}-window-frame-'
        '${viewport.width.toInt()}x${viewport.height.toInt()}',
        themeMode,
      ),
    ),
  );
}

Future<void> _captureSearchHistory(
  WidgetTester tester, {
  required Size viewport,
  required bool mobile,
  required ThemeMode themeMode,
}) async {
  _configureViewport(tester, viewport);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({
    SearchHistoryRepository.storageKey: ['晚风', '挪威的森林', '突然的自我'],
  });
  final preferences = await SharedPreferences.getInstance();
  final api = fixtureApi();
  final controller = feature.SearchController(SearchRepository(api));
  await controller.loadCapabilities();
  final player = await fixturePlayerController();
  final surface = SearchScreen(
    controller: controller,
    playlists: PlaylistRepository(api),
    downloads: DownloadRepository(api),
    player: player,
    history: SearchHistoryRepository(loadPreferences: () async => preferences),
  );
  await tester.pumpWidget(
    _shellHarness(
      path: '/search',
      player: player,
      child: surface,
      platform: mobile ? AppPlatform.android : AppPlatform.macos,
      themeMode: themeMode,
    ),
  );
  await _precacheBranding(tester);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.byKey(const Key('search-field')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('search-history-panel')), findsOneWidget);
  final platform = mobile ? 'mobile' : 'desktop';
  await expectLater(
    find.byKey(const Key('main-shell')),
    matchesGoldenFile(
      _goldenPath(
        '$platform-search-history-'
        '${viewport.width.toInt()}x${viewport.height.toInt()}',
        themeMode,
      ),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester, {
  required String page,
  required Size viewport,
  required bool mobile,
  required ThemeMode themeMode,
}) async {
  _configureViewport(tester, viewport);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final player = await fixturePlayerController();
  if (page == 'player' && mobile) player.setView(PlayerView.lyrics);
  final surface = await _surface(page, player);
  final route = _route(page);
  await tester.pumpWidget(
    page == 'player' && !mobile
        ? _playerHarness(
            child: surface,
            platform: mobile ? AppPlatform.android : AppPlatform.macos,
            themeMode: themeMode,
          )
        : _shellHarness(
            path: route,
            player: player,
            child: surface,
            platform: mobile ? AppPlatform.android : AppPlatform.macos,
            themeMode: themeMode,
          ),
  );
  await _precacheBranding(tester);
  await tester.pump(const Duration(milliseconds: 250));
  if (page == 'playlist-square' || page == 'charts') {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(tester.takeException(), isNull, reason: '$page must render cleanly');
  final platform = mobile ? 'mobile' : 'desktop';
  final width = viewport.width.toInt();
  final height = viewport.height.toInt();
  await expectLater(
    find.byKey(const Key('main-shell')),
    matchesGoldenFile(
      _goldenPath('$platform-$page-${width}x$height', themeMode),
    ),
  );
}

String _goldenPath(String stem, ThemeMode themeMode) =>
    themeMode == ThemeMode.dark
    ? 'full_goldens/$stem.png'
    : 'full_goldens/$stem-light.png';

Future<void> _precacheBranding(WidgetTester tester) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/TuneFlow.png'),
      tester.element(find.byKey(const Key('main-shell'))),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

String _route(String page) => switch (page) {
  'home' => '/',
  'search' => '/search',
  'playlist-square' => '/square',
  'charts' => '/charts',
  'my-playlists' || 'library' => '/playlists',
  'playlist-detail' => '/playlists/wind',
  'player' => '/player',
  'downloads' => '/downloads',
  'settings' => '/settings',
  'sources' => '/sources',
  'more' => '/more',
  _ => '/states',
};

Future<Widget> _surface(String page, PlayerController player) async {
  final api = fixtureApi();
  return switch (page) {
    'home' => HomeScreen(
      controller: await fixtureHomeController(),
      onSearch: () {},
      onPlaylists: () {},
      onDownloads: () {},
      onSettings: () {},
      player: player,
      now: () => DateTime(2026, 1, 1, 20),
    ),
    'search' => SearchScreen(
      controller: await fixtureSearchController(),
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      player: player,
    ),
    'playlist-square' => DiscoveryScreen(
      repository: SearchRepository(api),
      kind: DiscoveryKind.playlists,
      onSearch: () {},
      playlists: PlaylistRepository(api),
    ),
    'charts' => DiscoveryScreen(
      repository: SearchRepository(api),
      kind: DiscoveryKind.charts,
      onSearch: () {},
      playlists: PlaylistRepository(api),
    ),
    'my-playlists' || 'library' => PlaylistsScreen(
      controller: await fixturePlaylistsController(),
      onOpen: (_) {},
      onOpenLocal: () {},
    ),
    'playlist-detail' => PlaylistDetailScreen(
      controller: fixturePlaylistDetailController(),
      playTracks: (tracks, {startIndex = 0}) async {},
    ),
    'player' => PlayerScreen(
      controller: player,
      lyricsLoader: (_) async => const Lyrics(
        original: '[00:10]慢慢吹 轻轻送\n[00:35]人生路 你就走\n[02:12]就当我俩没有明天',
        translation: '[00:35]Go on, along the road that is yours',
      ),
      wakeLock: NoopWakeLock(),
      keepAwake: false,
    ),
    'downloads' => DownloadsScreen(
      controller: await fixtureDownloadsController(),
    ),
    'settings' => SettingsScreen(controller: fixtureSettingsController()),
    'sources' => SourcesScreen(controller: fixtureSourcesController()),
    'more' => MoreScreen(
      serviceHost: '192.168.1.24',
      onSources: () {},
      onSettings: () {},
      onDownloads: () {},
      onDisconnect: () async {},
    ),
    _ => const _StatesShowcase(),
  };
}

final class _StatesShowcase extends StatelessWidget {
  const _StatesShowcase();

  static const items = <(String, String)>[
    ('加载', '骨架屏而非空白'),
    ('空状态', '给出下一步操作'),
    ('部分失败', '保留成功平台结果'),
    ('全部失败', '重试与诊断入口'),
    ('无启用音源', '播放与下载禁用'),
    ('连接阻断', '使用 dialog'),
    ('缓存过期', '使用页内提示'),
    ('操作成功', '使用 toast'),
    ('能力缺失', '入口保留并说明原因'),
  ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTokens.of(context).background,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(38, 34, 38, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('视觉合同覆盖', style: AppTypography.metadata),
          const SizedBox(height: 4),
          const Text('状态演示', style: AppTypography.display),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: MediaQuery.sizeOf(context).width > 1180
                    ? 2.2
                    : 1.7,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ShadCard(
                  padding: const EdgeInsets.all(18),
                  title: Text(item.$1),
                  description: Text(item.$2),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        variant: ShadButtonVariant.outline,
                        onPressed: () {},
                        child: const Text('演示'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
