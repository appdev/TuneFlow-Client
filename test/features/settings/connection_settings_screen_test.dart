import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/settings/connection_settings_screen.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';
import 'package:musicfree_service_client/features/settings/settings_controller.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('hides the immutable bootstrap origin and saves shared origins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final applied = <({String bootstrap, String lan, String external})>[];
    var shared = const ServiceAccessOrigins(
      lanOrigin: 'http://lan.local',
      externalOrigin: 'https://external.example',
    );
    final controller = SettingsController(
      settings: const AppSettings(origin: 'https://bootstrap.example'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      loadServiceAccessOrigins: () async => shared,
      updateServiceAccessOrigins: (value) async => shared = value,
      applyServiceEndpoints:
          ({
            required bootstrapOrigin,
            required lanOrigin,
            required externalOrigin,
          }) async {
            applied.add((
              bootstrap: bootstrapOrigin,
              lan: lanOrigin,
              external: externalOrigin,
            ));
          },
    );

    await tester.pumpWidget(
      harness(ConnectionSettingsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('首次连接 / 备用地址'), findsNothing);
    expect(find.byKey(const Key('connection-bootstrap-origin')), findsNothing);
    expect(find.text('https://bootstrap.example'), findsNothing);
    expect(find.text('内网访问地址'), findsOneWidget);
    expect(find.text('外网访问地址'), findsOneWidget);
    expect(find.text('http://lan.local'), findsOneWidget);
    expect(find.text('https://external.example'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('connection-lan-origin')),
      'http://new-lan.local/',
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-connection-settings')),
    );
    await tester.tap(find.byKey(const Key('save-connection-settings')));
    await tester.pumpAndSettle();

    expect(applied, [
      (
        bootstrap: 'https://bootstrap.example',
        lan: 'http://new-lan.local',
        external: 'https://external.example',
      ),
    ]);

    await tester.enterText(
      find.byKey(const Key('connection-lan-origin')),
      'not-a-url',
    );
    await tester.tap(find.byKey(const Key('save-connection-settings')));
    await tester.pump();

    expect(find.text('请输入有效的 HTTP(S) 地址'), findsOneWidget);
    expect(applied, hasLength(1));
  });
}
