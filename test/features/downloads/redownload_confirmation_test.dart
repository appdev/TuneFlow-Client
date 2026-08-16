import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/redownload_confirmation.dart';
import 'package:musicfree_service_client/features/downloads/user_download_coordinator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('treats an unmounted confirmation context as cancellation', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(_harness(const SizedBox()));

    final result = await const AppRedownloadConfirmation().confirm(
      captured,
      '重新下载成功后将替换现有文件。',
    );

    expect(result, isFalse);
  });

  testWidgets('uses the ActionSheet for mobile replacement confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await const AppRedownloadConfirmation().confirm(
                context,
                '重新下载成功后将替换现有文件。',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await _pumpRoute(tester);

    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(find.text('重新下载成功后将替换现有文件。'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await _pumpRoute(tester);

    expect(result, isTrue);
  });

  testWidgets('uses a center dialog outside mobile layouts', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await const AppRedownloadConfirmation().confirm(
                context,
                '重新下载成功后将替换现有文件。',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
    expect(find.text('重新下载'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('binds an interactive download to replacement confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final policies = <String?>[];
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final policy = body['existingFilePolicy'] as String?;
          policies.add(policy);
          if (policy == 'error') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'DOWNLOAD_ALREADY_EXISTS',
                  'message': 'already exists',
                },
              }),
              409,
            );
          }
          return _downloadResponse();
        }),
      ),
    );
    UserDownloadResult? result;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await const AppUserDownloadCoordinator().create(
                context,
                repository,
                Track.fromJson({'id': 'one', 'source': 'kw'}),
                'flac',
              );
            },
            child: const Text('下载'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('下载'));
    await _pumpRoute(tester);
    await tester.tap(find.text('确定'));
    await _pumpRoute(tester);

    expect(policies, ['error', 'replace']);
    expect(result?.replaced, isTrue);
  });
}

Widget _harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

Future<void> _pumpRoute(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

http.Response _downloadResponse() => http.Response(
  jsonEncode({
    'data': {
      'id': 'replacement-one',
      'status': 'waiting',
      'musicInfo': {'id': 'one', 'source': 'kw'},
      'quality': 'flac',
      'extension': 'flac',
      'fileName': 'one.flac',
      'downloaded': 0,
      'total': 0,
      'progress': 0,
      'queuePosition': 1,
      'createdAt': 1000,
      'updatedAt': 1000,
    },
  }),
  201,
);
