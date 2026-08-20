import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/more/app_update.dart';
import 'package:musicfree_service_client/features/more/more_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

final class _UpdateChecker implements UpdateChecker {
  _UpdateChecker(this.callback);

  final Future<UpdateCheckResult> Function() callback;
  var calls = 0;

  @override
  Future<UpdateCheckResult> check() {
    calls++;
    return callback();
  }
}

UpToDate upToDate() => UpToDate(
  local: AppVersion.parse('1.0.4+5'),
  latest: AppVersion.parse('1.0.4'),
  releaseUri: Uri.parse(
    'https://github.com/appdev/TuneFlow-Client/releases/tag/v1.0.4',
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
          onAbout: () {},
          updateChecker: _UpdateChecker(() async => upToDate()),
          openExternalUri: (_) async => true,
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
          onAbout: () {},
          updateChecker: _UpdateChecker(() async => upToDate()),
          openExternalUri: (_) async => true,
          onDisconnect: () async {},
        ),
      ),
    );

    expect(find.text('歌单广场'), findsNothing);
    expect(find.text('排行榜'), findsNothing);
    await tester.tap(find.byKey(const Key('more-downloads')));
    expect(downloads, 1);
  });

  testWidgets('mobile more exposes settings, about, and update entries', (
    tester,
  ) async {
    var about = 0;
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onAbout: () => about++,
          updateChecker: _UpdateChecker(() async => upToDate()),
          openExternalUri: (_) async => true,
          onDisconnect: () async {},
        ),
      ),
    );

    expect(find.byKey(const Key('more-settings')), findsOneWidget);
    expect(find.byKey(const Key('more-about')), findsOneWidget);
    expect(find.byKey(const Key('more-check-update')), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-about')));
    expect(about, 1);
  });

  testWidgets('update checking suppresses a concurrent second request', (
    tester,
  ) async {
    final pending = Completer<UpdateCheckResult>();
    final checker = _UpdateChecker(() => pending.future);
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onAbout: () {},
          updateChecker: checker,
          openExternalUri: (_) async => true,
          onDisconnect: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('more-check-update')));
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-check-update')));
    expect(checker.calls, 1);

    pending.complete(upToDate());
    await tester.pumpAndSettle();
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.textContaining('1.0.4+5'), findsOneWidget);
  });

  testWidgets('available update opens its GitHub release page', (tester) async {
    final releaseUri = Uri.parse(
      'https://github.com/appdev/TuneFlow-Client/releases/tag/v1.0.5%2B6',
    );
    final opened = <Uri>[];
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onAbout: () {},
          updateChecker: _UpdateChecker(
            () async => UpdateAvailable(
              local: AppVersion.parse('1.0.4+5'),
              latest: AppVersion.parse('1.0.5+6'),
              releaseUri: releaseUri,
            ),
          ),
          openExternalUri: (uri) async {
            opened.add(uri);
            return true;
          },
          onDisconnect: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('more-check-update')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('1.0.5+6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-open-release')));
    await tester.pumpAndSettle();

    expect(opened, [releaseUri]);
  });

  testWidgets('update failure shows safe feedback', (tester) async {
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onAbout: () {},
          updateChecker: _UpdateChecker(
            () async => throw const UpdateCheckException(),
          ),
          openExternalUri: (_) async => true,
          onDisconnect: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('more-check-update')));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
    expect(find.text('暂时无法检查更新，请稍后重试。'), findsOneWidget);
  });

  testWidgets('release page launch failure shows feedback', (tester) async {
    await tester.pumpWidget(
      harness(
        MoreScreen(
          serviceHost: 'service.local',
          onSources: () {},
          onSettings: () {},
          onDownloads: () {},
          onAbout: () {},
          updateChecker: _UpdateChecker(
            () async => UpdateAvailable(
              local: AppVersion.parse('1.0.4+5'),
              latest: AppVersion.parse('1.0.5+6'),
              releaseUri: Uri.parse(
                'https://github.com/appdev/TuneFlow-Client/releases/1',
              ),
            ),
          ),
          openExternalUri: (_) async => false,
          onDisconnect: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('more-check-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-open-release')));
    await tester.pumpAndSettle();

    expect(find.text('无法打开下载页面'), findsOneWidget);
  });
}
