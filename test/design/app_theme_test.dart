import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/app_theme_definition.dart';
import 'package:musicfree_service_client/design/app_theme_scope.dart';
import 'package:musicfree_service_client/design/app_breakpoints.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('Mist Sea is the complete current theme family', () {
    expect(AppThemeRegistry.current, AppThemeId.mistSea);
    expect(AppThemeRegistry.values.keys, {AppThemeId.mistSea});

    final definition = AppThemeRegistry.definition(AppThemeId.mistSea);
    expect(definition.light.brightness, Brightness.light);
    expect(definition.dark.brightness, Brightness.dark);
    expect(definition.light.tokens, AppTokens.light);
    expect(definition.dark.tokens, AppTokens.dark);
  });

  testWidgets('theme scope exposes the active family and brightness variant', (
    tester,
  ) async {
    final definition = AppThemeRegistry.definition(AppThemeId.mistSea);
    late AppThemeVariant active;

    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(definition),
        darkTheme: buildDarkTheme(definition),
        themeMode: ThemeMode.dark,
        home: AppThemeScope(
          definition: definition,
          child: Builder(
            builder: (context) {
              active = AppThemeScope.variantOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(active.brightness, Brightness.dark);
    expect(active.tokens, AppTokens.dark);
  });

  test('typography assigns display, body, and data roles', () {
    expect(AppTypography.pageTitle.fontFamily, AppTypography.displayFontFamily);
    expect(AppTypography.body.fontFamily, AppTypography.bodyFontFamily);
    expect(AppTypography.counter.fontFamily, AppTypography.dataFontFamily);
    expect(AppTypography.pageTitle.fontStyle, FontStyle.normal);
    expect(AppTypography.mobilePageTitle.fontSize, 24);
  });

  testWidgets('buildDarkTheme exposes a dark Zinc color scheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(AppThemeRegistry.mistSea),
        darkTheme: buildDarkTheme(AppThemeRegistry.mistSea),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) => ColoredBox(
            key: const Key('theme-probe'),
            color: ShadTheme.of(context).colorScheme.background,
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(const Key('theme-probe')));
    final theme = ShadTheme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.background, AppTokens.dark.background);
  });

  testWidgets('light and dark themes expose distinct semantic surfaces', (
    tester,
  ) async {
    Future<AppTokens> render(ThemeMode mode) async {
      late AppTokens tokens;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ShadApp(
          key: ValueKey(mode),
          theme: buildLightTheme(AppThemeRegistry.mistSea),
          darkTheme: buildDarkTheme(AppThemeRegistry.mistSea),
          themeMode: mode,
          home: Builder(
            builder: (context) {
              tokens = AppTokens.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return tokens;
    }

    final light = await render(ThemeMode.light);
    final dark = await render(ThemeMode.dark);

    expect(light.background, isNot(dark.background));
    expect(light.focusRing.computeLuminance(), greaterThan(0));
    expect(dark.danger, isNot(dark.warning));
    expect(dark.foreground, isNot(dark.foregroundSecondary));
  });

  test('layout classes match accepted viewports', () {
    expect(classifyLayout(390), AppLayoutClass.mobile);
    expect(classifyLayout(1024), AppLayoutClass.narrow);
    expect(classifyLayout(1440), AppLayoutClass.desktop);
  });
}
