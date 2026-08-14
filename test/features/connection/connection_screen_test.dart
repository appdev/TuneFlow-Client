import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/app/app.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/memory_app_preferences.dart';

void main() {
  testWidgets('shows TuneFlow branding and a macOS Service placeholder', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MusicFreeServiceApp(preferences: MemoryAppPreferences()),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<ShadInputFormField>(
        find.byKey(const Key('service-origin-field')),
      );
      expect(
        find.image(const AssetImage('assets/branding/TuneFlow.png')),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.music2), findsNothing);
      expect(
        find.text('输入运行 Service 的电脑地址。Android 模拟器访问本机请使用 10.0.2.2。'),
        findsNothing,
      );
      expect(field.controller?.text, isEmpty);
      expect(find.text('http://127.0.0.1:3124'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows the Android emulator Service address as a placeholder', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MusicFreeServiceApp(preferences: MemoryAppPreferences()),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<ShadInputFormField>(
        find.byKey(const Key('service-origin-field')),
      );
      expect(field.controller?.text, isEmpty);
      expect(find.text('http://10.0.2.2:3124'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps the entered origin visible for an unsupported API', (
    tester,
  ) async {
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('health')
                  ? {'status': 'ok'}
                  : {
                      'runtime': 'service',
                      'apiVersion': 'v2',
                      'features': <String, Object?>{},
                    },
            }),
            200,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('service-origin-field')),
      'http://service.local',
    );
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('UNSUPPORTED_API_VERSION'), findsOneWidget);
    expect(
      tester
          .widget<ShadInputFormField>(
            find.byKey(const Key('service-origin-field')),
          )
          .controller
          ?.text,
      'http://service.local',
    );
    expect(find.byKey(const Key('connection-route')), findsOneWidget);
  });
}
