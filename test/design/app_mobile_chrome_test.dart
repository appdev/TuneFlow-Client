import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_form.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/design/components/app_mobile_chrome.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp(
  theme: buildLightTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('mobile header keeps a compact display title', (tester) async {
    await tester.pumpWidget(
      harness(const AppMobilePageHeader(title: '搜索', eyebrow: '发现音乐')),
    );

    final title = tester.widget<Text>(find.text('搜索'));
    expect(title.style?.fontSize, 24);
    expect(title.style?.fontStyle, FontStyle.normal);
  });

  testWidgets('glass field uses the shared control material', (tester) async {
    await tester.pumpWidget(
      harness(
        const AppTextField(placeholder: '搜索歌曲', surface: AppFieldSurface.glass),
      ),
    );

    expect(find.byType(AppGlassSurface), findsOneWidget);
    expect(find.text('搜索歌曲'), findsOneWidget);
  });

  testWidgets('segmented control exposes selection and changes value', (
    tester,
  ) async {
    var value = 'songs';
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => AppGlassSegmentedControl<String>(
            value: value,
            items: const {'songs': '歌曲', 'albums': '专辑'},
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('歌曲，已选择'), findsOneWidget);
    await tester.tap(find.text('专辑'));
    await tester.pump();
    expect(find.bySemanticsLabel('专辑，已选择'), findsOneWidget);
  });

  testWidgets('mobile back control is accessible and invokes its callback', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      harness(AppMobilePageHeader(title: '设置', onBack: () => presses++)),
    );

    final back = find.byKey(const Key('mobile-page-back'));
    expect(back, findsOneWidget);
    expect(find.bySemanticsLabel('返回'), findsOneWidget);
    expect(tester.getSize(back).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(back).height, greaterThanOrEqualTo(44));

    await tester.longPress(back);
    await tester.pumpAndSettle();
    expect(find.text('返回'), findsOneWidget);

    await tester.tap(back);
    expect(presses, 1);
  });

  testWidgets('primary mobile header omits back control by default', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const AppMobilePageHeader(title: '发现')));
    expect(find.byKey(const Key('mobile-page-back')), findsNothing);
  });
}
