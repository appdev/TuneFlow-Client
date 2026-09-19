@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_button.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/downloads_controller.dart';
import 'package:musicfree_service_client/features/downloads/downloads_screen.dart';
import 'package:musicfree_service_client/features/settings/settings_controller.dart';
import 'package:musicfree_service_client/features/settings/settings_screen.dart';
import 'package:musicfree_service_client/features/sources/source_repository.dart';
import 'package:musicfree_service_client/features/sources/sources_controller.dart';
import 'package:musicfree_service_client/features/sources/sources_screen.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

ServiceApi emptyApi() => ServiceApi(
  ServiceOrigin.parse('http://service.local'),
  client: MockClient((_) async => http.Response(jsonEncode({'data': []}), 200)),
);

void main() {
  testWidgets(
    'Web downloads describe Server storage, not offline device files',
    (tester) async {
      await tester.pumpWidget(
        harness(
          DownloadsScreen(
            controller: DownloadsController(DownloadRepository(emptyApi())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('浏览器播放仍需连接 Service'), findsOneWidget);
      expect(find.textContaining('已完成内容仍可播放'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Web settings do not expose native file cache actions', (
    tester,
  ) async {
    final controller = SettingsController(
      settings: const AppSettings(),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
    );
    await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('浏览器存储'), findsOneWidget);
    expect(find.byKey(const Key('settings-clear-local-cache')), findsNothing);
    expect(find.byKey(const Key('settings-cache-limit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty sources cannot launch an invalid export download', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SourcesScreen(
          controller: SourcesController(SourceRepository(emptyApi())),
          onExport: (_) async => fail('Empty source export must stay disabled'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('source-export')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
