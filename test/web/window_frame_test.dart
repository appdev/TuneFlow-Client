@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/platform/app_platform.dart';
import 'package:musicfree_service_client/platform/desktop_window_controller.dart';
import 'package:musicfree_service_client/platform/platform_window_frame.dart';

void main() {
  testWidgets('desktop browser never renders native window controls', (
    tester,
  ) async {
    for (final platform in [
      AppPlatform.macos,
      AppPlatform.windows,
      AppPlatform.linux,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformWindowFrame(
            platform: platform,
            location: '/',
            controller: desktopWindowController,
            child: const Text('Web content'),
          ),
        ),
      );
      expect(find.text('Web content'), findsOneWidget);
      expect(find.byKey(const Key('desktop-title-bar')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
