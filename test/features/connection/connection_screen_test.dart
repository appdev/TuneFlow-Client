import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/app/app.dart';
import 'package:musicfree_service_client/design/components/app_button.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/memory_app_preferences.dart';

final class _DelayedAppPreferences implements AppPreferences {
  final readCompleter = Completer<AppSettings>();
  AppSettings settings = const AppSettings();

  @override
  Future<void> clearOrigin() async {
    settings = settings.copyWith(clearOrigin: true);
  }

  @override
  Future<AppSettings> read() => readCompleter.future;

  @override
  Future<void> write(AppSettings value) async {
    settings = value;
  }
}

void main() {
  testWidgets(
    'shows the saved origin in a dedicated cold-start connecting view',
    (tester) async {
      final pendingHealth = Completer<http.Response>();
      final repository = ConnectionRepository(
        (origin) => ServiceApi(
          origin,
          client: MockClient((request) => pendingHealth.future),
        ),
      );

      await tester.pumpWidget(
        MusicFreeServiceApp(
          connectionRepository: repository,
          preferences: MemoryAppPreferences(
            const AppSettings(origin: 'http://saved.local'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cold-start-connecting-route')),
        findsOneWidget,
      );
      expect(find.text('Connecting to TuneFlow Service'), findsOneWidget);
      expect(find.text('http://saved.local'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('service-origin-field')), findsNothing);

      pendingHealth.completeError(http.ClientException('test cleanup'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('prefills the saved origin after cold-start connection fails', (
    tester,
  ) async {
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (request) async =>
              throw http.ClientException('connection refused', request.url),
        ),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: MemoryAppPreferences(
          const AppSettings(origin: 'http://offline.local'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection-route')), findsOneWidget);
    expect(find.byKey(const Key('connection-error')), findsOneWidget);
    expect(find.text('连接失败'), findsOneWidget);
    expect(
      find.text('无法连接到 Service，请检查地址、网络和 Service 是否正在运行。'),
      findsOneWidget,
    );
    expect(find.textContaining('ServiceException'), findsNothing);
    expect(find.textContaining('NETWORK_ERROR'), findsNothing);
    expect(
      tester
          .widget<ShadInputFormField>(
            find.byKey(const Key('service-origin-field')),
          )
          .controller
          ?.text,
      'http://offline.local',
    );
  });

  testWidgets('keeps a user-triggered connection attempt on the form', (
    tester,
  ) async {
    final pendingHealth = Completer<http.Response>();
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) => pendingHealth.future),
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
      'http://manual.local',
    );
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();

    expect(find.byKey(const Key('cold-start-connecting-route')), findsNothing);
    expect(find.byKey(const Key('connection-route')), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(const Key('connect-button'))).loading,
      isTrue,
    );

    pendingHealth.completeError(http.ClientException('test cleanup'));
    await tester.pumpAndSettle();
  });

  testWidgets('does not overwrite user input when saved settings arrive late', (
    tester,
  ) async {
    final preferences = _DelayedAppPreferences();
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (request) async =>
              throw http.ClientException('connection refused', request.url),
        ),
      ),
    );

    await tester.pumpWidget(
      MusicFreeServiceApp(
        connectionRepository: repository,
        preferences: preferences,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('service-origin-field')),
      'http://manual.local',
    );

    preferences.readCompleter.complete(
      const AppSettings(origin: 'http://saved.local'),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ShadInputFormField>(
            find.byKey(const Key('service-origin-field')),
          )
          .controller
          ?.text,
      'http://manual.local',
    );
    expect(find.byKey(const Key('cold-start-connecting-route')), findsNothing);
  });

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

    expect(find.text('Service 版本与当前客户端不兼容，请更新 Service 后重试。'), findsOneWidget);
    expect(find.textContaining('UNSUPPORTED_API_VERSION'), findsNothing);
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
