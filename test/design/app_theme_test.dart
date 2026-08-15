import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/app_theme_definition.dart';
import 'package:musicfree_service_client/design/app_theme_scope.dart';
import 'package:musicfree_service_client/design/app_breakpoints.dart';
import 'package:musicfree_service_client/design/design_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

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
    expect(theme.colorScheme.primary, const Color(0xFF00E66A));
    expect(theme.colorScheme.primaryForeground, const Color(0xFF101713));
    expect(theme.outlineButtonTheme.foregroundColor, AppTokens.dark.foreground);
    expect(
      theme.outlineButtonTheme.hoverForegroundColor,
      AppTokens.dark.primaryAction,
    );
    expect(theme.ghostButtonTheme.foregroundColor, AppTokens.dark.foreground);
    expect(theme.linkButtonTheme.foregroundColor, AppTokens.dark.foreground);
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

  test('Mist Sea exposes the approved Neutral Paper palette', () {
    expect(AppTokens.light.background, const Color(0xFFF6F6F6));
    expect(AppTokens.light.surface, const Color(0xFFFAFAFA));
    expect(AppTokens.light.surfaceWarm, const Color(0xFFEAEAEA));
    expect(AppTokens.light.foreground, const Color(0xFF252525));
    expect(AppTokens.light.foregroundSecondary, const Color(0xFF494949));
    expect(AppTokens.light.muted, const Color(0xFF626262));
    expect(AppTokens.light.border, const Color(0xFFDDDDDD));
    expect(AppTokens.light.borderSoft, const Color(0xFFEAEAEA));
    expect(AppTokens.light.accent, const Color(0xFF14745F));
    expect(AppTokens.light.accentForeground, const Color(0xFFF6F6F6));
    expect(AppTokens.light.primaryAction, const Color(0xFF14745F));
    expect(AppTokens.light.primaryActionForeground, const Color(0xFFF6F6F6));
    expect(AppTokens.light.playbackAction, const Color(0xFF14745F));
    expect(AppTokens.light.playbackActionForeground, Colors.white);
    expect(AppTokens.light.playbackTrackInactive, const Color(0xFF8A8A8A));
    expect(AppTokens.light.focusRing, const Color(0xFF008B70));
    expect(AppTokens.light.success, const Color(0xFF2F7D4A));
    expect(AppTokens.light.warning, const Color(0xFF966000));
    expect(AppTokens.light.danger, const Color(0xFFB93B3B));
    expect(AppTokens.light.overlay, const Color(0x66252525));
    expect(AppTokens.light.playerVeil, const Color(0xCCF6F6F6));
  });

  test('Mist Sea exposes the approved Soft Charcoal palette', () {
    expect(AppTokens.dark.background, const Color(0xFF171817));
    expect(AppTokens.dark.surface, const Color(0xFF202120));
    expect(AppTokens.dark.surfaceWarm, const Color(0xFF2B2C2A));
    expect(AppTokens.dark.foreground, const Color(0xFFECEDEA));
    expect(AppTokens.dark.foregroundSecondary, const Color(0xFFC6C7C3));
    expect(AppTokens.dark.muted, const Color(0xFFA0A19D));
    expect(AppTokens.dark.border, const Color(0xFF464743));
    expect(AppTokens.dark.borderSoft, const Color(0xFF30312F));
    expect(AppTokens.dark.accent, const Color(0xFF19D39B));
    expect(AppTokens.dark.accentForeground, const Color(0xFF101713));
    expect(AppTokens.dark.primaryAction, const Color(0xFF00E66A));
    expect(AppTokens.dark.primaryActionForeground, const Color(0xFF101713));
    expect(AppTokens.dark.playbackAction, const Color(0xFF14745F));
    expect(AppTokens.dark.playbackActionForeground, Colors.white);
    expect(AppTokens.dark.playbackTrackInactive, const Color(0xFF737570));
    expect(AppTokens.dark.focusRing, const Color(0xFF19D39B));
    expect(AppTokens.dark.success, const Color(0xFF75B987));
    expect(AppTokens.dark.warning, const Color(0xFFD7A45A));
    expect(AppTokens.dark.danger, const Color(0xFFE87870));
    expect(AppTokens.dark.overlay, const Color(0xB3121312));
    expect(AppTokens.dark.playerVeil, const Color(0xD9171817));
  });

  test('theme text, focus, and status roles meet contrast contracts', () {
    for (final tokens in [AppTokens.light, AppTokens.dark]) {
      expect(
        _contrastRatio(tokens.foreground, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.foregroundSecondary, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.muted, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.accent, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.accentForeground, tokens.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.primaryActionForeground, tokens.primaryAction),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.playbackActionForeground, tokens.playbackAction),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.playbackTrackInactive, tokens.background),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrastRatio(tokens.focusRing, tokens.background),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrastRatio(tokens.success, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.warning, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(tokens.danger, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('layout classes match accepted viewports', () {
    expect(classifyLayout(const Size(844, 390)), AppLayoutClass.mobile);
    expect(classifyLayout(const Size(1200, 600)), AppLayoutClass.mobile);
    expect(classifyLayout(const Size(601, 900)), AppLayoutClass.narrow);
    expect(classifyLayout(const Size(899, 601)), AppLayoutClass.narrow);
    expect(classifyLayout(const Size(900, 601)), AppLayoutClass.desktop);
    expect(classifyLayout(const Size(1440, 960)), AppLayoutClass.desktop);
  });
}
