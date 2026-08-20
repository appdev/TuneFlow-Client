import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/more/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

Future<PackageInfo> packageInfo() async => PackageInfo(
  appName: 'TuneFlow',
  packageName: 'musicfree_service_client',
  version: '1.0.4',
  buildNumber: '5',
);

void main() {
  testWidgets('shows project description, version, and repository links', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      harness(
        AboutScreen(
          loadPackageInfo: packageInfo,
          openExternalUri: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-screen')), findsOneWidget);
    expect(find.text('TuneFlow · 音流'), findsOneWidget);
    expect(find.textContaining('跨平台音乐客户端'), findsOneWidget);
    expect(find.text('版本 1.0.4+5'), findsOneWidget);
    expect(
      find.text('https://github.com/appdev/TuneFlow-Client'),
      findsOneWidget,
    );
    expect(find.text('https://github.com/appdev/TuneFlow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('about-client-repository')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('about-service-repository')));
    await tester.pump();

    expect(opened, [
      Uri.parse('https://github.com/appdev/TuneFlow-Client'),
      Uri.parse('https://github.com/appdev/TuneFlow'),
    ]);
  });

  testWidgets('reports a repository link launch failure', (tester) async {
    await tester.pumpWidget(
      harness(
        AboutScreen(
          loadPackageInfo: packageInfo,
          openExternalUri: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-client-repository')));
    await tester.pumpAndSettle();

    expect(find.text('无法打开链接'), findsOneWidget);
  });

  testWidgets('reports package metadata loading failure', (tester) async {
    await tester.pumpWidget(
      harness(
        AboutScreen(
          loadPackageInfo: () async => throw StateError('missing'),
          openExternalUri: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('版本读取失败'), findsOneWidget);
  });
}
