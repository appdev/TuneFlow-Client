import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUpAll(() async {
    final bodyFont = FontLoader('NotoSansCJKsc')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
    final iconFont = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await Future.wait([bodyFont.load(), iconFont.load()]);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in [44.0, 192.0]) {
      testWidgets('default artwork ${mode.name} ${size.toInt()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          ShadApp(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: mode,
            home: ColoredBox(
              color: mode == ThemeMode.dark
                  ? const Color(0xFF171817)
                  : const Color(0xFFF6F6F6),
              child: Center(
                child: RepaintBoundary(
                  key: const Key('artwork-golden'),
                  child: AppArtwork(
                    seed: 'golden-seed',
                    semanticLabel: '默认歌曲封面',
                    size: size,
                    borderRadius: size == 44 ? 8 : 20,
                  ),
                ),
              ),
            ),
          ),
        );

        await expectLater(
          find.byKey(const Key('artwork-golden')),
          matchesGoldenFile(
            'goldens/default-artwork-${mode.name}-${size.toInt()}.png',
          ),
        );
      });
    }
  }
}
