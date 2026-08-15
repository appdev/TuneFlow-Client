import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/sources/source_repository.dart';
import 'package:musicfree_service_client/features/sources/sources_controller.dart';
import 'package:musicfree_service_client/features/sources/sources_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Map<String, Object?> source(
  String id, {
  required bool enabled,
  int? priority,
}) => {
  'id': id,
  'name': '音源 $id',
  'description': '描述 $id',
  'version': '1.0.0',
  'author': 'Test',
  'homepage': '',
  'active': priority == 0,
  'enabled': enabled,
  'priority': priority,
  'sources': {
    'kw': {
      'type': 'music',
      'actions': ['musicUrl', 'lyric', 'pic'],
      'qualitys': ['320k'],
    },
  },
};

http.Response ok(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  test('source version label never duplicates the v prefix', () {
    expect(sourceVersionLabel('1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel('v1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel('vv1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel(''), '版本未知');
  });

  testWidgets(
    'shows enabled priority, disabled sources, switches and reorder',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final submitted = <List<String>>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return ok([
              source('a', enabled: true, priority: 0),
              source('b', enabled: true, priority: 1),
              source('c', enabled: false),
            ]);
          }
          final ids = (jsonDecode(request.body)['sourceIds'] as List)
              .cast<String>();
          submitted.add(ids);
          return ok([
            for (var index = 0; index < ids.length; index++)
              source(ids[index], enabled: true, priority: index),
            for (final id in ['a', 'b', 'c'])
              if (!ids.contains(id)) source(id, enabled: false),
          ]);
        }),
      );

      await tester.pumpWidget(
        harness(
          SourcesScreen(controller: SourcesController(SourceRepository(api))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('首选'), findsOneWidget);
      expect(find.text('备用 1'), findsOneWidget);
      expect(find.text('未启用音源'), findsOneWidget);
      expect(find.byType(ShadSwitch), findsNWidgets(3));
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(1, 0);
      await tester.pumpAndSettle();
      expect(submitted, [
        ['b', 'a'],
      ]);
    },
  );

  testWidgets('dragging a source reuses the card surface without decoration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => ok([
          source('a', enabled: true, priority: 0),
          source('b', enabled: true, priority: 1),
        ]),
      ),
    );

    await tester.pumpWidget(
      harness(
        SourcesScreen(controller: SourcesController(SourceRepository(api))),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    const cardSurface = SizedBox(key: ValueKey('drag-card-surface'));
    final proxy = list.proxyDecorator?.call(
      cardSurface,
      0,
      const AlwaysStoppedAnimation(1),
    );

    expect(proxy, same(cardSurface));
  });

  testWidgets('confirms before disabling the final enabled source', (
    tester,
  ) async {
    final submitted = <List<String>>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return ok([source('a', enabled: true, priority: 0)]);
        }
        submitted.add(
          (jsonDecode(request.body)['sourceIds'] as List).cast<String>(),
        );
        return ok([source('a', enabled: false)]);
      }),
    );
    await tester.pumpWidget(
      harness(
        SourcesScreen(controller: SourcesController(SourceRepository(api))),
      ),
    );
    await tester.pumpAndSettle();

    tester.widget<ShadSwitch>(find.byType(ShadSwitch)).onChanged?.call(false);
    await tester.pumpAndSettle();
    expect(find.text('禁用最后一个音源？'), findsOneWidget);
    expect(find.textContaining('本地音乐不受影响'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
  });
}
