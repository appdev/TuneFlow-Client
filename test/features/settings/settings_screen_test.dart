import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/settings/settings_controller.dart';
import 'package:musicfree_service_client/features/settings/settings_screen.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:musicfree_service_client/storage/media_cache.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_media_cache.dart';
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
  testWidgets('shows only approved Service-client settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));

    for (final label in const ['主题', '默认音质']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('插件'), findsNothing);
    expect(find.textContaining('文件权限'), findsNothing);
    expect(find.byKey(const Key('settings-wide-layout')), findsOneWidget);
  });

  testWidgets(
    'mobile settings can reduce transparency without changing theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saved = const AppSettings(origin: 'http://service.local');
      final controller = SettingsController(
        settings: saved,
        save: (value) async => saved = value,
        connect: (_) async {},
        disconnect: () async {},
        setPlayerQuality: (_) async {},
      );

      await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
      expect(find.text('减少透明效果'), findsOneWidget);
      await tester.tap(find.text('减少透明效果'));
      await tester.pump();

      expect(saved.reduceTransparency, isTrue);
      expect(saved.themeMode, ThemeMode.system);
    },
  );

  testWidgets('shows local-only cache usage, limit, and clear action', (
    tester,
  ) async {
    final cache = FakeMediaCache(
      usage: const MediaCacheUsage(
        audioBytes: 2 * 1024 * 1024,
        limitBytes: defaultMediaCacheLimitBytes,
      ),
    );
    final images = FakeAppImageCache(
      manager: TestImageCacheManager(),
      usageBytes: 512 * 1024,
    );
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      mediaCache: cache,
      imageCache: images,
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));

    expect(find.text('本机缓存'), findsOneWidget);
    expect(find.textContaining('不会影响 Service 端下载内容'), findsOneWidget);
    expect(find.textContaining('音频 2 MB / 5 GB'), findsOneWidget);
    expect(find.textContaining('图片 512 KB'), findsOneWidget);
    expect(find.textContaining('由图片缓存自动管理'), findsOneWidget);
    expect(find.text('音频缓存上限'), findsOneWidget);
    expect(find.byKey(const Key('settings-cache-limit')), findsOneWidget);
    expect(find.byKey(const Key('settings-clear-local-cache')), findsOneWidget);
  });

  testWidgets('reports an unavailable image cache instead of zero usage', (
    tester,
  ) async {
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      mediaCache: FakeMediaCache(),
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));

    expect(find.text('图片缓存不可用'), findsOneWidget);
    expect(find.textContaining('图片 0 B'), findsNothing);
  });

  testWidgets('desktop can load and update save while listening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final updates = <bool>[];
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      loadAutoDownloadOnPlay: () async => false,
      updateAutoDownloadOnPlay: (value) async {
        updates.add(value);
        return value;
      },
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('边听边存'), findsOneWidget);
    expect(find.text('播放在线音乐时，按 Service 的下载设置自动保存。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-auto-download-on-play')));
    await tester.pumpAndSettle();

    expect(updates, [true]);
    expect(controller.autoDownloadOnPlay, isTrue);
  });

  testWidgets('mobile exposes save while listening', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      loadAutoDownloadOnPlay: () async => true,
      updateAutoDownloadOnPlay: (value) async => value,
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-mobile-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-auto-download-on-play')),
      findsOneWidget,
    );
  });

  testWidgets('failed Service setting load is visible and disables switch', (
    tester,
  ) async {
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      loadAutoDownloadOnPlay: () async => throw StateError('offline'),
      updateAutoDownloadOnPlay: (value) async => value,
    );

    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Service 设置读取失败'), findsOneWidget);
    expect(find.text('Service 设置暂时无法读取，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
    final toggle = tester.widget<ShadSwitch>(
      find.byKey(const Key('settings-auto-download-on-play')),
    );
    expect(toggle.enabled, isFalse);
  });
}
