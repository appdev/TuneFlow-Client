import 'package:flutter/material.dart';
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
  testWidgets('showDestructive uses a centered dialog on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showDestructive(
                context,
                title: '从 Service 删除这首音乐？',
                message: '将永久删除歌曲及其歌词、封面等相关资源。',
                confirmLabel: '删除',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);

    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
    expect(find.text('从 Service 删除这首音乐？'), findsOneWidget);
    expect(find.text('将永久删除歌曲及其歌词、封面等相关资源。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-bottom-sheet-destructive')));
    await pumpRoute(tester);

    expect(result, isTrue);
  });

  testWidgets('showDestructive confirms from the shared bottom sheet', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showDestructive(
                context,
                title: '从 Service 删除这首音乐？',
                message: '将永久删除歌曲及其歌词、封面等相关资源。',
                confirmLabel: '删除',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await pumpRoute(tester);

    expect(find.byType(ShadDialog), findsNothing);
    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(find.text('从 Service 删除这首音乐？'), findsOneWidget);
    expect(find.text('将永久删除歌曲及其歌词、封面等相关资源。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-bottom-sheet-destructive')));
    await pumpRoute(tester);

    expect(result, isTrue);
  });

  testWidgets('showDestructive cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await AppBottomSheet.showDestructive(
                context,
                title: '删除下载任务？',
                message: 'example.flac',
                confirmLabel: '删除',
              );
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

    expect(result, isFalse);
  });

  testWidgets('showActions returns the selected typed value', (tester) async {
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
    await tester.tap(find.byKey(const Key('download-choice')));
    await pumpRoute(tester);

    expect(result, 'download');
    expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
  });

  testWidgets(
    'showSelection returns a typed value from a scrollable mobile sheet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AppBottomSheet.showSelection<String>(
                  context,
                  title: '音乐来源',
                  message: '选择当前分类支持的来源',
                  selectedValue: 'kw',
                  options: const [
                    AppBottomSheetSelection(
                      key: Key('source-kw'),
                      value: 'kw',
                      label: '酷我音乐',
                    ),
                    AppBottomSheetSelection(value: 'kg', label: '酷狗音乐'),
                    AppBottomSheetSelection(value: 'tx', label: 'QQ音乐'),
                    AppBottomSheetSelection(value: 'wy', label: '网易音乐'),
                    AppBottomSheetSelection(value: 'mg', label: '咪咕音乐'),
                    AppBottomSheetSelection(value: 'all', label: '全部来源'),
                    AppBottomSheetSelection(value: 'one', label: '备用来源一'),
                    AppBottomSheetSelection(
                      key: Key('source-last'),
                      value: 'last',
                      label: '备用来源二',
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

      expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
      expect(
        find.byKey(const Key('app-action-sheet-cancel-group')),
        findsOneWidget,
      );
      final selected = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const Key('source-kw')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(selected.properties.selected, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('source-last')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-last')));
      await pumpRoute(tester);

      expect(result, 'last');
      expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
    },
  );

  testWidgets('showSelection uses the shared desktop dialog', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    AppBottomSheet.showSelection<String>(
      context,
      title: '音乐来源',
      selectedValue: 'kw',
      options: const [AppBottomSheetSelection(value: 'kw', label: '酷我音乐')],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-adaptive-dialog')), findsOneWidget);
    expect(find.byType(ShadSheet), findsNothing);
  });

  testWidgets('showContent owns the sheet chrome around caller content', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    AppBottomSheet.showContent<void>(
      context,
      title: '歌词',
      child: const Text('潮汐歌词'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShadSheet), findsOneWidget);
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('潮汐歌词'), findsOneWidget);
  });

  testWidgets('showContent uses a centered dialog on desktop', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    AppBottomSheet.showContent<void>(
      context,
      title: '歌词',
      child: const Text('潮汐歌词'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byType(ShadSheet), findsNothing);
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('潮汐歌词'), findsOneWidget);
  });

  testWidgets('showDraggable applies shared mobile sheet bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      harness(
        Builder(
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
      child: const SizedBox(key: Key('queue-content')),
    );
    await tester.pumpAndSettle();

    final draggable = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(draggable.initialChildSize, .64);
    expect(draggable.minChildSize, .48);
    expect(draggable.maxChildSize, .90);
    expect(find.byKey(const Key('queue-content')), findsOneWidget);
  });
}
