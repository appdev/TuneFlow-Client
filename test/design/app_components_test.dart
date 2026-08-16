import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:musicfree_service_client/design/app_breakpoints.dart';
import 'package:musicfree_service_client/design/components/app_navigation.dart';
import 'package:musicfree_service_client/design/components/app_playback_button.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/design/components/app_button.dart';
import 'package:musicfree_service_client/design/components/app_bottom_sheet.dart';
import 'package:musicfree_service_client/design/components/app_feedback.dart';
import 'package:musicfree_service_client/design/components/app_form.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/design/components/app_states.dart';
import 'package:musicfree_service_client/design/components/queue_panel.dart';
import 'package:musicfree_service_client/design/components/playlist_card.dart';
import 'package:musicfree_service_client/design/components/track_tile.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:musicfree_service_client/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/fake_app_image_cache.dart';
import '../support/test_image_cache_manager.dart';

void main() {
  test('typography uses the bundled Chinese UI font', () {
    expect(AppTypography.fontFamily, 'NotoSansCJKsc');
  });

  Track track(String id) => Track.fromJson({
    'id': id,
    'name': '歌曲$id',
    'singer': '歌手$id',
    'source': 'kw',
  });

  testWidgets('AppButton keeps a 48dp interactive target', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Center(
            child: AppButton(
              key: const Key('action'),
              onPressed: () {},
              child: const Text('连接'),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('action'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('playback buttons use solid glyphs and semantic colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Column(
            children: [
              AppButton.playback(
                key: const Key('labeled-playback'),
                onPressed: () {},
                leading: const AppPlaybackGlyph.play(size: 18),
                child: const Text('播放全部'),
              ),
              AppPlaybackIconButton(
                key: const Key('icon-playback'),
                tooltip: '播放',
                onPressed: () {},
                child: const AppPlaybackGlyph.play(size: 20),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.widget<AppPlaybackGlyph>(find.byType(AppPlaybackGlyph).first).icon,
      AppPlaybackIcons.play,
    );
    final labeled = tester.widget<ShadButton>(
      find.descendant(
        of: find.byKey(const Key('labeled-playback')),
        matching: find.byType(ShadButton),
      ),
    );
    expect(labeled.backgroundColor, AppTokens.light.playbackAction);
    expect(labeled.foregroundColor, AppTokens.light.playbackActionForeground);
    final icon = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('icon-playback')),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      icon.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppTokens.light.playbackAction,
    );
    expect(
      icon.style?.foregroundColor?.resolve(<WidgetState>{}),
      AppTokens.light.playbackActionForeground,
    );
  });

  testWidgets('dark primary AppButton uses the brighter action color', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              key: const Key('primary-action'),
              onPressed: () {},
              child: const Text('播放'),
            ),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('primary-action')));
    final colors = ShadTheme.of(context).colorScheme;
    expect(colors.primary, const Color(0xFF00E66A));
    expect(colors.primaryForeground, const Color(0xFF101713));
    expect(AppTokens.of(context).accent, const Color(0xFF19D39B));
  });

  testWidgets(
    'dark outline actions stay neutral until pointer hover reveals green',
    (tester) async {
      await tester.pumpWidget(
        ShadApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: AppButton(
              variant: ShadButtonVariant.outline,
              onPressed: () {},
              child: const Text('搜索音乐'),
            ),
          ),
        ),
      );

      final label = find.text('搜索音乐');
      Color? labelColor() =>
          DefaultTextStyle.of(tester.element(label)).style.color;

      expect(labelColor(), AppTokens.dark.foreground);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(label));
      await tester.pumpAndSettle();

      expect(labelColor(), AppTokens.dark.primaryAction);
      await pointer.removePointer();
    },
  );

  testWidgets('light outline actions retain the approved green default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: AppButton(
            variant: ShadButtonVariant.outline,
            onPressed: () {},
            child: const Text('搜索音乐'),
          ),
        ),
      ),
    );

    final label = find.text('搜索音乐');
    expect(
      DefaultTextStyle.of(tester.element(label)).style.color,
      AppTokens.light.primaryAction,
    );
  });

  testWidgets('desktop navigation renders the localized TuneFlow brand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShadApp.custom(
        theme: buildLightTheme(),
        appBuilder: (context) => MaterialApp(
          theme: Theme.of(context),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AppDesktopNavigation(
              destinations: const [
                AppDestination(id: 'home', label: 'Home', icon: Icons.home),
              ],
              selectedId: 'home',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('brand-logo')), findsOneWidget);
    expect(find.byKey(const Key('brand-wordmark')), findsOneWidget);
    expect(find.text('TuneFlow'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byKey(const Key('brand-logo'))).image,
      const AssetImage('assets/branding/TuneFlow.png'),
    );
    final navigation = tester.widget<Container>(
      find.byKey(const Key('desktop-navigation')),
    );
    final decoration = navigation.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets('desktop navigation keeps every icon in one fixed column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const destinations = [
      AppDestination(id: 'home', label: '首页', icon: Icons.home),
      AppDestination(id: 'search', label: '搜索', icon: Icons.search),
      AppDestination(id: 'square', label: '歌单广场', icon: Icons.grid_view),
      AppDestination(id: 'charts', label: '排行榜', icon: Icons.bar_chart),
      AppDestination(id: 'playlists', label: '我的歌单', icon: Icons.favorite),
      AppDestination(id: 'downloads', label: '下载管理', icon: Icons.download),
      AppDestination(id: 'settings', label: '设置', icon: Icons.settings),
    ];

    await tester.pumpWidget(
      ShadApp.custom(
        theme: buildLightTheme(),
        appBuilder: (context) => MaterialApp(
          theme: Theme.of(context),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AppDesktopNavigation(
              destinations: destinations,
              selectedId: 'playlists',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final iconLefts = destinations
        .map(
          (destination) => tester
              .getTopLeft(
                find.byKey(
                  ValueKey('desktop-destination-icon-${destination.id}'),
                ),
              )
              .dx,
        )
        .toList();
    final labelLefts = destinations
        .map(
          (destination) => tester
              .getTopLeft(
                find.byKey(
                  ValueKey('desktop-destination-label-${destination.id}'),
                ),
              )
              .dx,
        )
        .toList();

    expect(iconLefts.toSet(), hasLength(1));
    expect(labelLefts.toSet(), hasLength(1));
  });

  testWidgets('loading AppButton disables repeated activation', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: AppButton(
            loading: true,
            onPressed: () => presses++,
            child: const Text('保存'),
          ),
        ),
      ),
    );

    expect(tester.widget<ShadButton>(find.byType(ShadButton)).enabled, isFalse);
    expect(presses, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AppTextField forwards edited values', (tester) async {
    var value = '';
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: AppTextField(
            key: const Key('field'),
            placeholder: 'Service 地址',
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('field')), 'http://service');
    expect(value, 'http://service');
  });

  testWidgets('AppNotice exposes destructive errors persistently', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: AppNotice.error(title: '连接失败', message: 'NETWORK_ERROR'),
        ),
      ),
    );

    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('NETWORK_ERROR'), findsOneWidget);
    expect(
      tester.widget<ShadAlert>(find.byType(ShadAlert)).variant,
      ShadAlertVariant.destructive,
    );
  });

  testWidgets('AppRetryState invokes retry from an empty-safe surface', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: AppRetryState(
            message: '暂时无法加载',
            retryLabel: '重试',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('destructive bottom sheet returns only the confirmed result', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final result = AppBottomSheet.showDestructive(
      context,
      title: '删除歌单？',
      message: '此操作不可撤销',
      cancelLabel: '取消',
      confirmLabel: '删除',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('showAppMessage displays transient Sonner feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Builder(
          builder: (context) => AppButton(
            onPressed: () =>
                showAppMessage(context, title: '已保存', message: '设置已更新'),
            child: const Text('触发'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('设置已更新'), findsOneWidget);
  });

  testWidgets('showAppMessage can display a title-only confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Builder(
          builder: (context) => AppButton(
            onPressed: () => showAppMessage(context, title: '已加入下载队列'),
            child: const Text('下载'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('下载'));
    await tester.pump();
    expect(find.text('已加入下载队列'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
    expect(find.text('已交给 Service 下载'), findsNothing);
  });

  testWidgets('showAppMessage is upper-middle on desktop and mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [Size(1200, 800), Size(390, 844)]) {
      tester.view.physicalSize = size;
      final toastTitle = '定位提示-${size.width}';
      await tester.pumpWidget(
        ShadApp(
          theme: buildLightTheme(),
          builder: (context, child) => ShadAppBuilder(child: child!),
          home: Builder(
            builder: (context) => AppButton(
              onPressed: () => showAppMessage(context, title: toastTitle),
              child: const Text('触发定位'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发定位'));
      await tester.pump();

      final toast = find.ancestor(
        of: find.text(toastTitle),
        matching: find.byType(ShadToast),
      );
      final toastCenter = tester.getCenter(toast);
      expect(toastCenter.dx, closeTo(size.width / 2, 1));
      expect(toastCenter.dy, greaterThan(size.height * .25));
      expect(toastCenter.dy, lessThan(size.height * .40));
    }
  });

  testWidgets('AppBottomSheet content uses a bottom Shad sheet', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    AppBottomSheet.showContent<void>(
      context,
      title: '歌曲操作',
      child: const Text('加入歌单'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShadSheet), findsOneWidget);
    expect(find.text('加入歌单'), findsOneWidget);
  });

  testWidgets('AppBottomSheet supports bounded draggable mobile extents', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    AppBottomSheet.showDraggable<void>(
      context,
      title: '播放队列',
      initialChildSize: .64,
      minChildSize: .48,
      maxChildSize: .90,
      child: const SizedBox(key: Key('sheet-content')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byKey(const Key('sheet-content')), findsOneWidget);
    expect(find.byType(AppGlassSurface), findsOneWidget);
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
  });

  test('app layout changes at the accepted mobile boundary', () {
    expect(appLayoutForSize(const Size(1200, 600)), AppLayout.phone);
    expect(appLayoutForSize(const Size(601, 900)), AppLayout.tablet);
  });

  test('playlist gallery adds columns before cards exceed their maximum', () {
    expect(playlistGalleryColumnCount(availableWidth: 500, spacing: 16), 3);
    expect(playlistGalleryColumnCount(availableWidth: 800, spacing: 16), 4);
    expect(playlistGalleryColumnCount(availableWidth: 1324, spacing: 16), 6);
    expect(playlistGalleryColumnCount(availableWidth: 1636, spacing: 16), 7);
    final extent = playlistGalleryItemExtent(
      availableWidth: 1324,
      spacing: 16,
      columns: 6,
    );
    expect(extent, lessThanOrEqualTo(playlistGalleryMaxItemExtent));
    expect(
      playlistGalleryChildAspectRatio(extent),
      extent / (extent + playlistGalleryMetadataExtent),
    );
  });

  testWidgets('artwork fallback is deterministic and semantically labeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: const AppArtwork(
          imageUrl: null,
          seed: 'kw:42',
          semanticLabel: '晚风封面',
          size: 120,
        ),
      ),
    );

    expect(find.bySemanticsLabel('晚风封面'), findsOneWidget);
    expect(find.byKey(const Key('artwork-fallback-kw:42')), findsOneWidget);
  });

  testWidgets('network artwork sends browser-compatible request headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppImageCacheScope(
        cache: FakeAppImageCache(manager: TestImageCacheManager()),
        child: ShadApp(
          theme: buildLightTheme(),
          home: const AppArtwork(
            imageUrl: 'https://example.test/cover.jpg',
            seed: 'header-cover',
            semanticLabel: '请求头封面',
            size: 52,
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.httpHeaders?['User-Agent'], startsWith('Mozilla/5.0'));
  });

  testWidgets('track without a picture does not render generated artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: TrackTile(
            track: track('no-cover'),
            onPlay: () {},
            onActions: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('artwork-fallback-kw:no-cover')), findsNothing);
    expect(find.byKey(const Key('play-track-no-cover')), findsOneWidget);
  });

  testWidgets('failed network artwork is replaced by generated artwork', (
    tester,
  ) async {
    final cache = FakeAppImageCache(
      manager: TestImageCacheManager(
        fileStream: Stream<FileResponse>.error(StateError('failed')),
      ),
    );
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: AppImageCacheScope(
          cache: cache,
          child: const AppArtwork(
            imageUrl: 'https://invalid.example.test/missing.jpg',
            seed: 'failed-cover',
            semanticLabel: '失败封面',
            size: 52,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('artwork-fallback-failed-cover')),
      findsOneWidget,
    );
  });

  testWidgets('playlist without artwork keeps a consistent gallery frame', (
    tester,
  ) async {
    const playlist = PlaylistDetail(id: 'love', name: '收藏', tracks: []);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 300,
            child: PlaylistCard(
              playlist: playlist,
              imageUrl: null,
              variant: PlaylistCardVariant.gallery,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('artwork-fallback-love')), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);

    final artwork = tester.widget<AppArtwork>(find.byType(AppArtwork));
    expect(artwork.borderRadius, AppRadii.compactCard);
    expect(artwork.showFallbackBorder, isFalse);

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.borderRadius, BorderRadius.circular(AppRadii.compactCard));

    final fallback = tester.widget<DecoratedBox>(
      find.byKey(const Key('artwork-fallback-love')),
    );
    final decoration = fallback.decoration as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets('gallery playlist interaction overlay stays transparent', (
    tester,
  ) async {
    const playlist = PlaylistDetail(id: 'quiet', name: '安静歌单', tracks: []);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: PlaylistCard(
              playlist: playlist,
              variant: PlaylistCardVariant.gallery,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final overlay = tester.widget<InkWell>(find.byType(InkWell)).overlayColor;
    expect(overlay?.resolve({WidgetState.hovered}), Colors.transparent);
    expect(overlay?.resolve({WidgetState.pressed}), Colors.transparent);
  });

  testWidgets('gallery playlist fits the narrow desktop grid ratio', (
    tester,
  ) async {
    const playlist = PlaylistDetail(id: 'narrow', name: '窄窗歌单', tracks: []);
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 256,
            height: 256 / .84,
            child: PlaylistCard(
              playlist: playlist,
              variant: PlaylistCardVariant.gallery,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('queue panel selects the requested queue index', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: QueuePanel(
            tracks: [track('a'), track('b')],
            currentIndex: 0,
            onSelected: (index) => selected = index,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('queue-track-b')));
    expect(selected, 1);
  });

  testWidgets('mobile navigation reports the selected destination', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        home: AppMobileNavigation(
          destinations: const [
            AppDestination(id: 'home', label: '首页', icon: Icons.home),
            AppDestination(id: 'search', label: '搜索', icon: Icons.search),
          ],
          selectedId: 'home',
          onSelected: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.text('搜索'));
    expect(selected, 'search');

    final selectedItem = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-destination-home')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = selectedItem.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
