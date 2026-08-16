import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_bottom_sheet.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

Future<void> pumpRoute(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('supports one confirmation action plus separate cancel', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showActions<bool>(
                context,
                title: '重新下载',
                message: '下载成功后将替换现有文件。',
                actions: const [
                  AppBottomSheetAction(
                    key: Key('confirm-redownload'),
                    value: true,
                    label: '确定',
                  ),
                ],
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);

    expect(find.text('下载成功后将替换现有文件。'), findsOneWidget);
    expect(find.byKey(const Key('app-action-sheet-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-redownload')));
    await pumpRoute(tester);

    expect(result, isTrue);
  });

  testWidgets('returns a typed choice after dismissing the sheet', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showActions<String>(
                context,
                title: '潮汐',
                message: '林间 · 无损',
                actions: const [
                  AppBottomSheetAction(value: 'favorite', label: '收藏歌曲'),
                  AppBottomSheetAction(value: 'playlist', label: '添加到歌单'),
                  AppBottomSheetAction(
                    key: Key('download-choice'),
                    value: 'download',
                    label: '下载当前歌曲',
                  ),
                ],
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);

    expect(find.text('潮汐'), findsOneWidget);
    expect(find.text('林间 · 无损'), findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('潮汐'))
          .text
          .style
          ?.decoration,
      TextDecoration.none,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('林间 · 无损'))
          .text
          .style
          ?.decoration,
      TextDecoration.none,
    );
    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(
      find.byKey(const Key('app-action-sheet-cancel-group')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('download-choice')));
    await pumpRoute(tester);

    expect(result, 'download');
    expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
  });

  testWidgets('cancel dismisses without a value', (tester) async {
    var completed = false;
    String? result = 'unchanged';
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showActions<String>(
                context,
                title: '歌曲操作',
                actions: const [
                  AppBottomSheetAction(value: 'favorite', label: '收藏歌曲'),
                  AppBottomSheetAction(value: 'download', label: '下载当前歌曲'),
                ],
              );
              completed = true;
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);
    await tester.tap(find.byKey(const Key('app-action-sheet-cancel')));
    await pumpRoute(tester);

    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('barrier and system back dismiss without a value', (
    tester,
  ) async {
    Future<String?> open(BuildContext context) =>
        AppBottomSheet.showActions<String>(
          context,
          title: '歌曲操作',
          actions: const [
            AppBottomSheetAction(value: 'favorite', label: '收藏歌曲'),
            AppBottomSheetAction(value: 'download', label: '下载当前歌曲'),
          ],
        );

    String? result = 'unchanged';
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await open(context),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);
    await tester.tapAt(const Offset(4, 4));
    await pumpRoute(tester);
    expect(result, isNull);

    result = 'unchanged';
    await tester.tap(find.text('打开'));
    await pumpRoute(tester);
    await tester.binding.handlePopRoute();
    await pumpRoute(tester);
    expect(result, isNull);
  });

  testWidgets('keeps choices reachable at 320px with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AppBottomSheet.showActions<String>(
              context,
              title: '一首名字稍微长一些的歌曲',
              message: '一位名字稍微长一些的歌手 · Hi-Res',
              actions: const [
                AppBottomSheetAction(value: 'favorite', label: '收藏歌曲'),
                AppBottomSheetAction(value: 'playlist', label: '添加到歌单'),
                AppBottomSheetAction(value: 'download', label: '下载当前歌曲'),
              ],
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('下载当前歌曲'), findsOneWidget);
    expect(find.byKey(const Key('app-action-sheet-cancel')), findsOneWidget);
  });
}
