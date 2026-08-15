import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/app/app.dart';
import 'package:musicfree_service_client/app/player_providers.dart';
import 'package:musicfree_service_client/design/components/app_button.dart';
import 'package:musicfree_service_client/design/components/app_mobile_dock.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/connection_controller.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/platform/macos_menu_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/memory_app_preferences.dart';

void main() {
  testWidgets('activates an injected macOS menu bar port safely', (
    tester,
  ) async {
    final menuBar = _RecordingMenuBarPort();

    await tester.pumpWidget(
      MusicFreeServiceApp(
        preferences: MemoryAppPreferences(const AppSettings()),
        macOSMenuBar: menuBar,
      ),
    );
    await tester.pumpAndSettle();

    expect(menuBar.initializeCalls, 1);
    expect(menuBar.states, [MacOSMenuBarSnapshot.idle]);
  });

  testWidgets('system theme follows host brightness without ripple splash', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MusicFreeServiceApp(
        preferences: MemoryAppPreferences(
          const AppSettings(themeMode: ThemeMode.system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    BuildContext routeContext() =>
        tester.element(find.byKey(const Key('connection-route')));
    expect(ShadTheme.of(routeContext()).brightness, Brightness.light);
    expect(Theme.of(routeContext()).brightness, Brightness.light);
    expect(
      Theme.of(routeContext()).splashFactory,
      same(NoSplash.splashFactory),
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(ShadTheme.of(routeContext()).brightness, Brightness.dark);
    expect(Theme.of(routeContext()).brightness, Brightness.dark);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} theme ignores host brightness changes', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MusicFreeServiceApp(
          preferences: MemoryAppPreferences(AppSettings(themeMode: mode)),
        ),
      );
      await tester.pumpAndSettle();

      final expected = mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      BuildContext routeContext() =>
          tester.element(find.byKey(const Key('connection-route')));
      expect(ShadTheme.of(routeContext()).brightness, expected);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      expect(ShadTheme.of(routeContext()).brightness, expected);
      expect(Theme.of(routeContext()).brightness, expected);
    });
  }

  testWidgets('applies persisted dark theme and English locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MusicFreeServiceApp(
        preferences: MemoryAppPreferences(
          const AppSettings(
            themeMode: ThemeMode.dark,
            language: AppLanguage.en,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('connection-route')));
    expect(ShadTheme.of(context).brightness, Brightness.dark);
    expect(find.text('Connect to TuneFlow Service'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).onGenerateTitle!(
        context,
      ),
      'TuneFlow',
    );
  });

  testWidgets('failed persisted connection leaves the loading route', (
    tester,
  ) async {
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (request) async =>
              throw http.ClientException('connection refused', request.url),
        ),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://offline.local'),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(container.read(connectionProvider).hasError, isTrue);

    expect(find.byKey(const Key('connection-route')), findsOneWidget);
    expect(find.byKey(const Key('connection-error')), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(const Key('connect-button'))).loading,
      isFalse,
    );
  });

  testWidgets('connects and enters the route-based home shell', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryAppPreferences(
      const AppSettings(language: AppLanguage.en),
    );
    final requests = <String>[];
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          final path = request.url.path;
          requests.add('${request.method} $path');
          if (request.method == 'GET' && path == '/api/v1/playlists/love') {
            return http.Response(
              jsonEncode({
                'data': {'id': 'love', 'name': '我的收藏', 'tracks': <Object?>[]},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.method == 'POST' &&
              path == '/api/v1/playlists/love/tracks') {
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'desktop-inset', 'name': '遮挡测试', 'source': 'kw'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final value = switch (path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            '/api/v1/playlists' => <Object?>[],
            '/api/v1/downloads' => <Object?>[],
            _ => <Object?>[],
          };
          return http.Response(jsonEncode({'data': value}), 200);
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShadApp), findsOneWidget);
    expect(find.byKey(const Key('connection-route')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('service-origin-field')),
      'http://service.local',
    );
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-route')), findsOneWidget);
    expect(find.byKey(const Key('main-shell')), findsOneWidget);
    expect(find.byKey(const Key('desktop-navigation')), findsOneWidget);
    expect(
      find.text('随后播放'),
      findsNothing,
      reason: 'unrelated desktop pages must not reserve a queue column',
    );
    expect(find.byKey(const Key('desktop-persistent-player')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('desktop-persistent-player'))).height,
      0,
      reason: 'an empty desktop player must not reserve shell space',
    );
    expect(
      tester.getSize(find.byKey(const Key('desktop-title-bar'))).height,
      38,
    );
    expect(
      tester.getSize(find.byKey(const Key('desktop-navigation'))).width,
      208,
    );
    final navigationRect = tester.getRect(
      find.byKey(const Key('desktop-navigation')),
    );
    final leadingTitleSurfaceRect = tester.getRect(
      find.byKey(const Key('desktop-title-leading-surface')),
    );
    expect(leadingTitleSurfaceRect.left, navigationRect.left);
    expect(leadingTitleSurfaceRect.right, navigationRect.right);
    expect(
      tester.getTopLeft(find.byKey(const Key('desktop-back'))).dx,
      greaterThanOrEqualTo(navigationRect.right),
    );
    final contentShellRect = tester.getRect(
      find.byKey(const Key('desktop-content-shell')),
    );
    expect(contentShellRect.left, navigationRect.right);
    final playerInsetRect = tester.getRect(
      find.byKey(const Key('desktop-player-inset')),
    );
    expect(playerInsetRect.left, contentShellRect.left + 12);
    expect(playerInsetRect.right, contentShellRect.right - 12);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    await container.read(playerControllerProvider)!.playTracks([
      Track.fromJson({'id': 'desktop-inset', 'name': '遮挡测试', 'source': 'kw'}),
    ]);
    await tester.pumpAndSettle();
    final sharedActions = container.read(currentTrackActionsProvider)!;
    expect(
      sharedActions.track?.id,
      'desktop-inset',
      reason: requests.join('\n'),
    );
    expect(sharedActions.favoriteKnown, isTrue, reason: requests.join('\n'));
    expect(find.byKey(const Key('desktop-mini-favorite')), findsOneWidget);
    expect(find.byKey(const Key('desktop-mini-download')), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(find.byKey(const Key('desktop-mini-favorite')))
          .enabled,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('desktop-mini-favorite')));
    await tester.pumpAndSettle();
    final activePlayerRect = tester.getRect(
      find.byKey(const Key('desktop-persistent-player')),
    );
    final activePageRect = tester.getRect(find.byKey(const Key('home-route')));
    expect(
      activePageRect.bottom,
      lessThanOrEqualTo(activePlayerRect.top - 12),
      reason: 'desktop pages must end above the persistent player',
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Home · TuneFlow'), findsNothing);
    expect(preferences.settings.origin, 'http://service.local');

    final router = GoRouter.of(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    router.go('/player');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-route')), findsOneWidget);
    expect(find.byKey(const Key('desktop-navigation')), findsNothing);
    expect(find.byKey(const Key('desktop-persistent-player')), findsNothing);
    expect(find.byKey(const Key('desktop-full-favorite')), findsOneWidget);
    expect(find.byKey(const Key('desktop-full-download')), findsOneWidget);
    expect(find.bySemanticsLabel('取消收藏'), findsOneWidget);
    final playerBackIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('desktop-back')),
        matching: find.byType(Icon),
      ),
    );
    expect(
      playerBackIcon.color,
      fallbackArtworkPalette(
        'kw:desktop-inset',
        brightness: Brightness.light,
      ).vinylAccent,
    );

    router.go('/');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('macos-title-bar')), findsOneWidget);
    expect(find.byKey(const Key('window-minimize')), findsNothing);
    expect(find.byKey(const Key('window-maximize')), findsNothing);
    expect(find.byKey(const Key('window-close')), findsNothing);

    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    await tester.tap(find.text('下载管理').last);
    await tester.pumpAndSettle();
    expect(find.text('暂无 Service 下载任务'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-route')), findsOneWidget);
    expect(find.textContaining('插件'), findsNothing);
    expect(find.textContaining('文件夹'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('local library card uses its read-only production route', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          final value = switch (request.url.path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            '/api/v1/playlists' => [
              {'id': 'love', 'name': 'list__name_love'},
            ],
            '/api/v1/playlists/love' => {
              'id': 'love',
              'name': 'love',
              'tracks': <Object?>[],
            },
            '/api/v1/library/tracks' => [
              {
                'id': 'local-file',
                'musicInfo': {
                  'id': 'local-track',
                  'name': 'Local Track',
                  'source': 'kw',
                },
                'size': 12,
                'extension': 'mp3',
                'streamUrl': '/api/v1/library/tracks/local-file/stream',
              },
            ],
            _ => <Object?>[],
          };
          return http.Response(jsonEncode({'data': value}), 200);
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://service.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester.element(find.byKey(const Key('main-shell')));
    final router = GoRouter.of(shell);

    router.go('/playlists');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local-library-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-library-route')), findsOneWidget);
    expect(
      GoRouterState.of(
        tester.element(find.byKey(const Key('local-library-route'))),
      ).uri.path,
      '/library',
    );
    expect(find.text('Local Track'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      GoRouterState.of(
        tester.element(find.byKey(const Key('main-shell'))),
      ).uri.path,
      '/playlists',
    );
    await tester.tap(find.byKey(const Key('playlist-love')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playlist-detail-route')), findsOneWidget);
    expect(
      GoRouterState.of(
        tester.element(find.byKey(const Key('playlist-detail-route'))),
      ).uri.path,
      '/playlists/love',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile shell uses compact player and five destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          final value = switch (request.url.path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            _ => <Object?>[],
          };
          return http.Response(jsonEncode({'data': value}), 200);
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://service.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-player-dock')), findsOneWidget);
    expect(
      find.byKey(const Key('macos-title-bar')),
      findsOneWidget,
      reason: 'a narrow macOS window still needs drag and traffic-light space',
    );
    expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const Key('mobile-mini-player')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('mobile-bottom-navigation'))).height,
      64,
    );
    expect(
      tester.getSize(find.byKey(const Key('mobile-bottom-navigation'))).width,
      366,
      reason: 'the empty-queue dock still fills the viewport minus 12px insets',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-bottom-navigation')),
        matching: find.text('我的音乐'),
      ),
      findsOneWidget,
    );
    for (final label in const ['首页', '搜索', '发现', '我的音乐', '更多']) {
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
    expect(
      tester
          .widget<Scaffold>(find.byKey(const Key('mobile-shell-scaffold')))
          .resizeToAvoidBottomInset,
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('search-field')), '保留搜索状态');
    await tester.tap(find.bySemanticsLabel('首页'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-route')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('保留搜索状态'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('首页'));
    await tester.pumpAndSettle();

    GestureDetector? homeDownloads;
    void findHomeDownloads(Element element) {
      if (element.widget case final GestureDetector gesture) {
        homeDownloads = gesture;
      }
      element.visitChildren(findHomeDownloads);
    }

    tester
        .element(find.byKey(const Key('home-downloads'), skipOffstage: false))
        .visitChildren(findHomeDownloads);
    homeDownloads!.onTap!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloads-route')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('更多'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('downloads-route')),
      findsOneWidget,
      reason: 'mobile Home downloads must belong to the More branch',
    );

    await tester.tap(find.bySemanticsLabel('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-route')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('更多'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-route')),
      findsOneWidget,
      reason: 'mobile Search settings must belong to the More branch',
    );
    await tester.tap(find.bySemanticsLabel('首页'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    await container.read(playerControllerProvider)!.playTracks([
      Track.fromJson({'id': 'mobile-back', 'name': '返回测试', 'source': 'kw'}),
    ]);
    await tester.pump();
    final mobilePageRect = tester.getRect(find.byKey(const Key('home-route')));
    final mobileDockRect = tester.getRect(
      find.byKey(const Key('mobile-player-dock')),
    );
    expect(
      mobilePageRect.bottom,
      lessThanOrEqualTo(mobileDockRect.top),
      reason: 'mobile pages must end above the player and navigation dock',
    );
    tester.element(find.byKey(const Key('main-shell'))).go('/player');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('mobile-player-dock')), findsNothing);
    expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);

    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-route')), findsNothing);
    expect(find.byKey(const Key('home-route')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile dock stays in place when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          final value = switch (request.url.path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            _ => <Object?>[],
          };
          return http.Response(jsonEncode({'data': value}), 200);
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://service.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    await container.read(playerControllerProvider)!.playTracks([
      Track.fromJson({'id': 'ime-track', 'name': '键盘测试', 'source': 'kw'}),
    ]);
    await tester.pump();
    final dockBeforeKeyboard = tester.getRect(
      find.byKey(const Key('mobile-player-dock')),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('mobile-player-dock'))),
      dockBeforeKeyboard,
      reason: 'the keyboard should cover the dock instead of lifting it',
    );
  });

  testWidgets('returning from player preserves the underlying detail page', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var detailRequests = 0;
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          final value = switch (request.url.path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            '/api/v1/catalog/playlists/detail' => () {
              detailRequests++;
              return {
                'source': 'kw',
                'page': 1,
                'limit': 30,
                'total': 1,
                'hasMore': false,
                'playlist': {
                  'id': 'list-1',
                  'kind': 'playlist',
                  'name': '测试歌单',
                  'source': 'kw',
                },
                'tracks': [
                  {'id': 'song-1', 'name': '返回后仍在', 'source': 'kw'},
                ],
              };
            }(),
            _ => <Object?>[],
          };
          return http.Response(
            jsonEncode({'data': value}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://service.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shellContext = tester.element(find.byKey(const Key('main-shell')));
    shellContext.go(
      '/square/kw/list-1',
      extra: const CatalogCollection(
        id: 'list-1',
        kind: CatalogSearchKind.playlist,
        name: '测试歌单',
        source: 'kw',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('返回后仍在'), findsOneWidget);
    expect(detailRequests, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    container
        .read(playerControllerProvider)!
        .enqueue(
          Track.fromJson({'id': 'song-1', 'name': '返回后仍在', 'source': 'kw'}),
        );
    await tester.pump();
    tester.widget<AppMobileDock>(find.byType(AppMobileDock)).onOpenPlayer();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-route')), findsOneWidget);
    expect(find.text('返回后仍在'), findsNothing);
    expect(detailRequests, 1);

    Navigator.of(
      tester.element(find.byKey(const Key('player-route'))),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-route')), findsNothing);
    expect(find.text('返回后仍在'), findsOneWidget);
    expect(detailRequests, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reconnecting reloads playlist UI from the new Service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requestedUrls = <Uri>[];
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) async {
          requestedUrls.add(request.url);
          final first = request.url.host == 'first.local';
          final playlistId = first ? 'first-playlist' : 'second-playlist';
          final playlistName = first ? '服务器 A 歌单' : '服务器 B 歌单';
          final value = switch (request.url.path) {
            '/api/v1/health' => {'status': 'ok'},
            '/api/v1/capabilities' => {
              'runtime': 'service',
              'apiVersion': 'v1',
              'features': <String, Object?>{},
            },
            '/api/v1/events/snapshot' => {'sequence': 0, 'events': <Object?>[]},
            '/api/v1/playlists' => [
              {'id': playlistId, 'name': playlistName},
            ],
            final path when path == '/api/v1/playlists/$playlistId' => {
              'id': playlistId,
              'name': playlistName,
              'tracks': <Object?>[],
            },
            _ => <Object?>[],
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode({'data': value})),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://first.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.element(find.byKey(const Key('main-shell'))).go('/playlists');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('playlists-gallery-wide')),
      findsOneWidget,
      reason: requestedUrls.join('\n'),
    );
    expect(
      find.text('服务器 A 歌单'),
      findsOneWidget,
      reason: requestedUrls.join('\n'),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('main-shell'))),
    );
    await container
        .read(connectionProvider.notifier)
        .connect('http://second.local');
    await tester.pumpAndSettle();
    tester.element(find.byKey(const Key('main-shell'))).go('/playlists');
    await tester.pumpAndSettle();

    expect(find.text('服务器 A 歌单'), findsNothing);
    expect(find.text('服务器 B 歌单'), findsOneWidget);
    expect(
      requestedUrls.map((url) => url.host),
      containsAllInOrder(['first.local', 'second.local']),
    );
  });
}

final class _RecordingMenuBarPort implements MacOSMenuBarPort {
  int initializeCalls = 0;
  final states = <MacOSMenuBarSnapshot>[];

  @override
  Stream<MacOSMenuBarCommand> get commands => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> terminate() async {}

  @override
  Future<void> updateState(MacOSMenuBarSnapshot state) async =>
      states.add(state);
}
