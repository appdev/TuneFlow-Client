import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/more/more_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('mobile more confirms before disconnecting the current Service', (
    tester,
  ) async {
    var disconnects = 0;
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onDisconnect: () async => disconnects++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('more-disconnect')));
    await tester.pumpAndSettle();

    expect(find.text('断开当前 Service？'), findsOneWidget);
    expect(disconnects, 0);

    await tester.tap(find.text('断开连接').last);
    await tester.pumpAndSettle();

    expect(disconnects, 1);
  });

  testWidgets('mobile more owns downloads instead of discovery links', (
    tester,
  ) async {
    var downloads = 0;
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () => downloads++,
          onDisconnect: () async {},
        ),
      ),
    );

    expect(find.text('歌单广场'), findsNothing);
    expect(find.text('排行榜'), findsNothing);
    await tester.tap(find.byKey(const Key('more-downloads')));
    expect(downloads, 1);
  });
}
