import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:musicfree_service_client/l10n/app_localizations.dart';
import 'package:musicfree_service_client/platform/app_platform.dart';
import 'package:musicfree_service_client/platform/desktop_window_controller.dart';
import 'package:musicfree_service_client/platform/platform_window_frame.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final platform in [AppPlatform.android, AppPlatform.ios]) {
    testWidgets('$platform does not render desktop window chrome', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform));

      expect(find.byKey(const Key('window-frame-content')), findsOneWidget);
      expect(find.byKey(const Key('desktop-title-bar')), findsNothing);
      expect(find.byKey(const Key('window-close')), findsNothing);
    });
  }

  testWidgets('macOS reserves traffic-light space without Flutter controls', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(AppPlatform.macos));

    expect(find.byKey(const Key('desktop-title-bar')), findsOneWidget);
    expect(find.byKey(const Key('macos-title-bar')), findsOneWidget);
    expect(
      find.byKey(const Key('macos-traffic-light-safe-area')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('window-minimize')), findsNothing);
    expect(find.byKey(const Key('window-maximize')), findsNothing);
    expect(find.byKey(const Key('window-close')), findsNothing);
    final titleBar = tester.widget<Container>(
      find.byKey(const Key('desktop-title-bar')),
    );
    final decoration = titleBar.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets('player window chrome keeps only back over the shared canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        AppPlatform.macos,
        location: '/player',
        onBack: () {},
        onSearch: () {},
      ),
    );

    expect(find.bySemanticsLabel('返回'), findsOneWidget);
    expect(find.bySemanticsLabel('前进'), findsNothing);
    expect(find.bySemanticsLabel('全局搜索'), findsNothing);
    expect(find.text('正在播放 · 音流'), findsNothing);
    final titleBar = tester.widget<Container>(
      find.byKey(const Key('desktop-title-bar')),
    );
    final decoration = titleBar.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNull);
  });

  testWidgets('desktop shell title bar continues the sidebar and content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(AppPlatform.macos, desktopSidebarWidth: 208),
    );

    final titleBar = tester.widget<Container>(
      find.byKey(const Key('desktop-title-bar')),
    );
    final decoration = titleBar.decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.light.background);
    expect(
      tester.getSize(find.byKey(const Key('desktop-title-leading-surface'))),
      const Size(208, 38),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('desktop-back'))).dx,
      greaterThanOrEqualTo(208),
    );
  });

  testWidgets('desktop title actions stay clickable inside the drag region', (
    tester,
  ) async {
    var backCount = 0;
    var forwardCount = 0;
    await tester.pumpWidget(
      _harness(
        AppPlatform.macos,
        onBack: () => backCount++,
        onForward: () => forwardCount++,
      ),
    );

    await tester.tap(find.byKey(const Key('desktop-back')));
    await tester.tap(find.byKey(const Key('desktop-forward')));

    expect(backCount, 1);
    expect(forwardCount, 1);
  });

  testWidgets('desktop shell omits centered page title and global search', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        AppPlatform.macos,
        location: '/square',
        onSearch: () {},
        desktopSidebarWidth: 208,
      ),
    );

    expect(find.text('歌单广场 · 音流'), findsNothing);
    expect(find.bySemanticsLabel('全局搜索'), findsNothing);
  });

  testWidgets('narrow macOS player leaves back navigation to mobile chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _harness(AppPlatform.macos, location: '/player', onBack: () {}),
    );

    expect(find.byKey(const Key('desktop-title-bar')), findsOneWidget);
    expect(find.bySemanticsLabel('返回'), findsNothing);
  });

  for (final platform in [AppPlatform.windows, AppPlatform.linux]) {
    testWidgets('$platform renders right-side caption controls', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform));

      expect(find.byKey(const Key('desktop-title-bar')), findsOneWidget);
      expect(
        find.byKey(
          Key(
            platform == AppPlatform.windows
                ? 'windows-title-bar'
                : 'linux-title-bar',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('window-minimize')), findsOneWidget);
      expect(find.byKey(const Key('window-maximize')), findsOneWidget);
      expect(find.byKey(const Key('window-close')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('desktop-title-bar'))).height,
        38,
      );
    });
  }
}

Widget _harness(
  AppPlatform platform, {
  String location = '/search',
  VoidCallback? onBack,
  VoidCallback? onForward,
  VoidCallback? onSearch,
  double? desktopSidebarWidth,
}) {
  final controller = DesktopWindowController(_FakeWindowOperations());
  return ShadApp.custom(
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
        body: ShadAppBuilder(
          child: PlatformWindowFrame(
            platform: platform,
            location: location,
            controller: controller,
            onBack: onBack,
            onForward: onForward,
            onSearch: onSearch,
            desktopSidebarWidth: desktopSidebarWidth,
            child: const ColoredBox(
              key: Key('window-frame-content'),
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _FakeWindowOperations implements WindowOperations {
  @override
  Future<void> close() async {}

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> maximize() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> unmaximize() async {}
}
