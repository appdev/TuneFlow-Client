import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/settings/service_function_settings_controller.dart';
import 'package:musicfree_service_client/features/settings/service_function_settings_screen.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Map<String, Object?> settingsJson() => {
  'player.autoDownloadOnPlay': false,
  'download.enable': true,
  'download.isSavePathGroupByListName': false,
  'download.fileName': '歌名 - 歌手',
  'download.maxDownloadNum': 3,
  'download.skipExistFile': true,
  'download.isUseOtherSource': true,
  'download.isDownloadLrc': true,
  'download.isDownloadTLrc': true,
  'download.isDownloadRLrc': true,
  'download.isDownloadVerbatimLyric': true,
  'download.lrcFormat': 'utf8',
  'download.isEmbedPic': true,
  'download.isEmbedLyric': true,
  'download.isEmbedLyricT': true,
  'download.isEmbedLyricR': true,
  'download.isEmbedVerbatimLyric': true,
  'recommendation.timeZone': 'system',
  'recommendation.musicBrainzBaseUrl': officialMusicBrainzBaseUrl,
};

http.Response data(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode({'data': value})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget harness(ServiceFunctionSettingsController controller) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(
      body: ShadAppBuilder(
        child: ServiceFunctionSettingsScreen(controller: controller),
      ),
    ),
  ),
);

void main() {
  testWidgets('tests, disables, and saves the MusicBrainz setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Map<String, Object?> savedPatch;
    final controller = ServiceFunctionSettingsController(
      ServiceSettingsRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            if (request.method == 'GET') return data(settingsJson());
            if (request.url.path.endsWith('/musicbrainz/test')) {
              return data({
                'ok': true,
                'normalizedBaseUrl': officialMusicBrainzBaseUrl,
                'errorCode': null,
              });
            }
            savedPatch = Map<String, Object?>.from(
              jsonDecode(request.body) as Map,
            );
            return data(savedPatch);
          }),
        ),
      ),
    );

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('musicbrainz-url-field')),
      500,
    );

    expect(find.text(officialMusicBrainzBaseUrl), findsOneWidget);
    await tester.tap(find.byKey(const Key('musicbrainz-test-connection')));
    await tester.pumpAndSettle();
    expect(find.text('连接测试成功'), findsOneWidget);

    await tester.tap(find.byKey(const Key('musicbrainz-disable')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('service-settings-save')));
    await tester.tap(find.byKey(const Key('service-settings-save')));
    await tester.pumpAndSettle();

    expect(savedPatch['recommendation.musicBrainzBaseUrl'], isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });
}
