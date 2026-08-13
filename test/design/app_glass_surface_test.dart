import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_glass_policy.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/app_theme_definition.dart';
import 'package:musicfree_service_client/design/app_theme_scope.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness({
  required Widget child,
  bool highContrast = false,
  bool disableAnimations = false,
  bool reduceTransparency = false,
}) {
  final definition = AppThemeRegistry.mistSea;
  return ShadApp(
    theme: buildLightTheme(definition),
    home: MediaQuery(
      data: MediaQueryData(
        highContrast: highContrast,
        disableAnimations: disableAnimations,
      ),
      child: AppThemeScope(
        definition: definition,
        child: AppGlassPolicyScope(
          reduceTransparency: reduceTransparency,
          performanceDegraded: false,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  test('every Mist Sea variant defines every glass role', () {
    for (final variant in [
      AppThemeRegistry.mistSea.light,
      AppThemeRegistry.mistSea.dark,
    ]) {
      expect(variant.glass.keys.toSet(), AppGlassRole.values.toSet());
      expect(variant.glass[AppGlassRole.nav]!.blurSigma, greaterThan(0));
      expect(
        variant.glass[AppGlassRole.fallback]!.fallbackFill,
        isNot(Colors.transparent),
      );
    }
  });

  testWidgets('glass surface enables blur in the normal policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        child: const Center(
          child: AppGlassSurface(
            role: AppGlassRole.nav,
            child: SizedBox(key: Key('content'), width: 120, height: 48),
          ),
        ),
      ),
    );

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.enabled, isTrue);
    expect(
      tester.getSize(find.byKey(const Key('content'))),
      const Size(120, 48),
    );
  });

  testWidgets('reduced transparency disables blur without changing geometry', (
    tester,
  ) async {
    Future<Size> render(bool reduced) async {
      await tester.pumpWidget(
        harness(
          reduceTransparency: reduced,
          child: const Center(
            child: AppGlassSurface(
              role: AppGlassRole.control,
              child: SizedBox(key: Key('content'), width: 144, height: 52),
            ),
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.enabled, !reduced);
      return tester.getSize(find.byKey(const Key('content')));
    }

    expect(await render(false), await render(true));
  });

  testWidgets('high contrast requests the opaque fallback', (tester) async {
    await tester.pumpWidget(
      harness(
        highContrast: true,
        child: const AppGlassSurface(
          role: AppGlassRole.sheet,
          child: SizedBox(width: 80, height: 80),
        ),
      ),
    );

    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
  });

  testWidgets('disabled animations produces the reduced motion policy', (
    tester,
  ) async {
    late AppGlassPolicy policy;
    await tester.pumpWidget(
      harness(
        disableAnimations: true,
        child: Builder(
          builder: (context) {
            policy = AppGlassPolicyScope.policyOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(policy.reduceMotion, isTrue);
  });

  test('performance policy degrades after sustained slow frames', () {
    final controller = AppGlassPerformanceController();
    for (var index = 0; index < 48; index++) {
      controller.recordFrame(const Duration(milliseconds: 12));
    }
    for (var index = 0; index < 12; index++) {
      controller.recordFrame(const Duration(milliseconds: 25));
    }

    expect(controller.degraded, isTrue);
    controller.recordFrame(const Duration(milliseconds: 8));
    expect(controller.degraded, isTrue);
  });
}
