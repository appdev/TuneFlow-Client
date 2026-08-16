import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/status_badge.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/downloads_controller.dart';
import 'package:musicfree_service_client/features/downloads/downloads_screen.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

Widget harness(Widget child) => AppImageCacheScope(
  cache: FakeAppImageCache(manager: TestImageCacheManager()),
  child: ShadApp.custom(
    theme: buildLightTheme(),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      home: Scaffold(body: ShadAppBuilder(child: child)),
    ),
  ),
);

Map<String, Object?> job(String status) => {
  'id': status,
  'status': status,
  'musicInfo': {'id': 'track-$status', 'name': status},
  'quality': '128k',
  'extension': 'mp3',
  'fileName': '$status.mp3',
  'downloaded': 0,
  'total': 10,
  'progress': 0,
  'queuePosition': 1,
  'createdAt': 1000,
  'updatedAt': 1000,
};

void main() {
  testWidgets('desktop history clear uses the centered confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('completed'), job('error'), job('running')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    await tester.tap(find.byKey(const Key('clear-download-history')));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.text('清除下载记录？'), findsOneWidget);
    expect(find.textContaining('将清除 2 条'), findsOneWidget);
    expect(find.textContaining('已下载的歌曲文件会保留'), findsOneWidget);
  });

  testWidgets('mobile history clear uses the bottom confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('completed'), job('error'), job('running')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    final action = tester.widget<IconButton>(
      find.byKey(const Key('clear-download-history')),
    );
    expect(action.tooltip, '清除下载记录');
    expect(action.constraints!.minWidth, greaterThanOrEqualTo(44));
    expect(action.constraints!.minHeight, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('clear-download-history')));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsNothing);
    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(find.text('清除下载记录？'), findsOneWidget);
  });

  testWidgets('history clear is disabled when only active jobs remain', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('waiting'), job('running'), job('paused')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    final action = tester.widget<IconButton>(
      find.byKey(const Key('clear-download-history')),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets(
    'confirming history clear sends one request and keeps active jobs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deleteCalls = 0;
      var cleared = false;
      final repository = DownloadRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleteCalls += 1;
              cleared = true;
              return http.Response(
                jsonEncode({
                  'data': {'cleared': 2},
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': cleared
                    ? [job('running')]
                    : [job('completed'), job('error'), job('running')],
              }),
              200,
            );
          }),
        ),
      );
      final controller = DownloadsController(repository);
      await controller.refresh();
      await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

      await tester.tap(find.byKey(const Key('clear-download-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('app-bottom-sheet-destructive')));
      await tester.pumpAndSettle();

      expect(deleteCalls, 1);
      expect(find.text('completed'), findsNothing);
      expect(find.text('error'), findsNothing);
      expect(find.text('running'), findsOneWidget);
    },
  );

  testWidgets('unsupported history clear preserves rows and requests upgrade', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            return http.Response(
              jsonEncode({
                'error': {'code': 'NOT_FOUND', 'message': 'Route not found'},
              }),
              404,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [job('completed')],
            }),
            200,
          );
        }),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    await tester.tap(find.byKey(const Key('clear-download-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-bottom-sheet-destructive')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('completed'), findsOneWidget);
    expect(find.text('下载记录未清除'), findsOneWidget);
    expect(find.textContaining('请更新 Service 后重试'), findsOneWidget);
  });

  testWidgets('download menu uses the shared choice presentation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('waiting')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    await tester.tap(find.byKey(const Key('download-actions-waiting')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(find.byType(ShadSheet), findsNothing);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('delete choice replaces the menu with one confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('waiting')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();
    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    await tester.tap(find.byKey(const Key('download-actions-waiting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除下载任务？'), findsOneWidget);
    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(find.byType(ShadSheet), findsNothing);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('mobile downloads use one coordinated page scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('waiting')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    expect(find.byKey(const Key('downloads-mobile-scroll')), findsOneWidget);
  });

  testWidgets('download errors are presented as user-facing Chinese messages', (
    tester,
  ) async {
    final value = job('error')
      ..['error'] =
          'Metadata: Unsupported source action\n'
          'Completed download file is missing';
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [value],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    expect(find.text('已下载文件缺失，请重新下载'), findsOneWidget);
    expect(find.textContaining('Unsupported source action'), findsNothing);
    expect(find.textContaining('Completed download file'), findsNothing);
  });

  testWidgets('download snapshot renders a persisted meta.picUrl cover', (
    tester,
  ) async {
    final value = job('completed');
    value['musicInfo'] = {
      'id': 'covered-track',
      'name': 'Covered track',
      'source': 'tx',
      'meta': {'picUrl': 'https://cdn.example.test/download.jpg'},
    };
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [value],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    final images = tester.widgetList<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      images.map((image) => image.imageUrl),
      contains(contains('download.jpg')),
    );
  });

  testWidgets('download without persisted artwork resolves its cover', (
    tester,
  ) async {
    final value = job('completed');
    value['musicInfo'] = {
      'id': 'missing-cover',
      'name': 'Missing cover',
      'source': 'kw',
      'meta': {'songId': '39000261', 'albumId': '2179149'},
    };
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/tracks/picture')) {
            return http.Response(
              jsonEncode({
                'data': {'url': 'http://images.test/resolved-cover.jpg'},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [value],
            }),
            200,
          );
        }),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));
    await tester.pumpAndSettle();

    final images = tester.widgetList<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      images.map((image) => image.imageUrl),
      contains(contains('resolved-cover.jpg')),
    );
  });

  testWidgets('download without available artwork shows a fallback', (
    tester,
  ) async {
    final value = job('completed');
    value['musicInfo'] = {
      'id': 'missing-cover',
      'name': 'Missing cover',
      'source': 'local',
    };
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/downloads') {
            return http.Response(
              jsonEncode({
                'data': [value],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'No picture'},
            }),
            404,
          );
        }),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('artwork-fallback-local:missing-cover')),
      findsOneWidget,
    );
  });

  testWidgets('desktop download status is vertically centered in its row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final value = job('completed');
    value['musicInfo'] = {
      'id': 'aligned',
      'name': 'Aligned track',
      'source': 'tx',
      'meta': {'picUrl': 'https://images.test/aligned.jpg'},
    };
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [value],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

    final statusCenter = tester.getCenter(find.byType(AppStatusBadge));
    final actionsCenter = tester.getCenter(
      find.byKey(const Key('download-actions-completed')),
    );
    expect(statusCenter.dy, closeTo(actionsCenter.dy, 0.5));
  });

  testWidgets('waiting job exposes only legal start and delete actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [job('waiting')],
            }),
            200,
          ),
        ),
      ),
    );
    final controller = DownloadsController(repository);
    await controller.refresh();

    await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));
    expect(find.byKey(const Key('downloads-route')), findsOneWidget);
    await tester.tap(find.byKey(const Key('download-actions-waiting')));
    await tester.pumpAndSettle();

    expect(find.text('开始'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('继续'), findsNothing);
    expect(find.textContaining('文件夹'), findsNothing);
    expect(find.byKey(const Key('downloads-wide-layout')), findsOneWidget);
  });
}
