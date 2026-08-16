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
