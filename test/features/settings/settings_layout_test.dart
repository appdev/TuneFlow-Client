import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/settings/settings_controller.dart';
import 'package:musicfree_service_client/features/settings/settings_screen.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Optional local visual evidence; normal tests need neither system fonts nor IO.
const _previewDirectory = String.fromEnvironment('SETTINGS_PREVIEW_DIR');
const _previewFont = String.fromEnvironment('SETTINGS_PREVIEW_FONT');

void main() {
  setUpAll(() async {
    if (_previewDirectory.isEmpty) return;
    if (_previewFont.isNotEmpty) {
      final bytes = ByteData.sublistView(
        await File(_previewFont).readAsBytes(),
      );
      for (final family in ['Roboto', 'packages/shadcn_ui/Geist', 'serif']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  for (final width in [320.0, 375.0, 414.0, 768.0, 1024.0, 1440.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('settings layout $width ${mode.name} text $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 960);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = SettingsController(
            settings: const AppSettings(origin: 'http://service.local'),
            save: (_) async {},
            connect: (_) async {},
            disconnect: () async {},
            setPlayerQuality: (_) async {},
          );
          addTearDown(controller.dispose);
          var connectionsOpened = 0;
          var serviceOpened = 0;
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            ShadApp.custom(
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              themeMode: mode,
              appBuilder: (context) => MaterialApp(
                theme: Theme.of(context),
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: ShadAppBuilder(
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: SettingsScreen(
                          controller: controller,
                          onConnectionSettings: () => connectionsOpened++,
                          onServiceSettings: () => serviceOpened++,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('settings-two-columns')),
            width >= 1000 ? findsOneWidget : findsNothing,
          );
          for (final title in ['播放', '歌词', '通用', 'Service 与连接', '本机缓存']) {
            expect(find.text(title), findsOneWidget);
          }

          Future<void> capture(String section) async {
            if (_previewDirectory.isEmpty ||
                scale != 1 ||
                (width != 375 && width != 1440)) {
              return;
            }
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = await Directory(
                _previewDirectory,
              ).create(recursive: true);
              await File(
                '${directory.path}/settings-${width.toInt()}-${mode.name}-$section.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          await capture('top');
          await tester.ensureVisible(find.text('歌词'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture('lyrics');
          await tester.ensureVisible(
            find.byKey(const Key('settings-connection-entry')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('settings-connection-entry')));
          expect(connectionsOpened, 1);
          await tester.ensureVisible(
            find.byKey(const Key('settings-service-functions-entry')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('settings-service-functions-entry')),
          );
          expect(serviceOpened, 1);
          await tester.ensureVisible(
            find.byKey(const Key('settings-clear-local-cache')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture('bottom');
        });
      }
    }
  }
}
