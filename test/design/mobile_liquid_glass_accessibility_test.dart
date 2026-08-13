import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_glass_policy.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/app_theme_definition.dart';
import 'package:musicfree_service_client/design/app_theme_scope.dart';
import 'package:musicfree_service_client/design/components/app_navigation.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const destinations = [
  AppDestination(id: 'home', label: '首页', icon: LucideIcons.house),
  AppDestination(id: 'search', label: '搜索', icon: LucideIcons.search),
  AppDestination(id: 'library', label: '我的音乐', icon: LucideIcons.heart),
  AppDestination(id: 'downloads', label: '下载', icon: LucideIcons.download),
  AppDestination(id: 'more', label: '更多', icon: LucideIcons.ellipsis),
];

Widget harness({
  required Widget child,
  double textScale = 1,
  bool highContrast = false,
  bool disableAnimations = false,
  bool reduceTransparency = false,
}) {
  const definition = AppThemeRegistry.mistSea;
  return ShadApp(
    theme: buildLightTheme(definition),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        textScaler: TextScaler.linear(textScale),
        highContrast: highContrast,
        disableAnimations: disableAnimations,
      ),
      child: AppThemeScope(
        definition: definition,
        child: AppGlassPolicyScope(
          reduceTransparency: reduceTransparency,
          performanceDegraded: false,
          child: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('mobile destinations remain reachable at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          textScale: scale,
          child: AppMobileNavigation(
            destinations: destinations,
            selectedId: 'search',
            onSelected: (_) {},
          ),
        ),
      );

      for (final destination in destinations) {
        final target = find.bySemanticsLabel(destination.label);
        expect(target, findsOneWidget);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('high contrast and reduced transparency retain navigation size', (
    tester,
  ) async {
    Future<Size> render({
      bool highContrast = false,
      bool reduced = false,
    }) async {
      await tester.pumpWidget(
        harness(
          highContrast: highContrast,
          reduceTransparency: reduced,
          child: AppMobileNavigation(
            destinations: destinations,
            selectedId: 'home',
            onSelected: (_) {},
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.enabled, !(highContrast || reduced));
      return tester.getSize(find.byKey(const Key('mobile-bottom-navigation')));
    }

    final normal = await render();
    expect(await render(highContrast: true), normal);
    expect(await render(reduced: true), normal);
  });

  testWidgets('reduced motion removes navigation selection animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        disableAnimations: true,
        child: AppMobileNavigation(
          destinations: destinations,
          selectedId: 'home',
          onSelected: (_) {},
        ),
      ),
    );

    final lenses = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(lenses, isNotEmpty);
    expect(lenses.every((lens) => lens.duration == Duration.zero), isTrue);
  });
}
