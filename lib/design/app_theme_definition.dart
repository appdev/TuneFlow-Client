import 'package:flutter/material.dart';

import 'design_tokens.dart';

enum AppThemeId { mistSea }

enum AppGlassRole { nav, control, sheet, clear, fallback }

@immutable
final class AppGlassStyle {
  const AppGlassStyle({
    required this.fill,
    required this.border,
    required this.highlight,
    required this.fallbackFill,
    required this.blurSigma,
    required this.saturation,
    required this.shadows,
  });

  final Color fill;
  final Color border;
  final Color highlight;
  final Color fallbackFill;
  final double blurSigma;
  final double saturation;
  final List<BoxShadow> shadows;
}

@immutable
final class AppThemeVariant {
  const AppThemeVariant({
    required this.brightness,
    required this.tokens,
    required this.glass,
  });

  final Brightness brightness;
  final AppTokens tokens;
  final Map<AppGlassRole, AppGlassStyle> glass;
}

@immutable
final class AppThemeDefinition {
  const AppThemeDefinition({
    required this.id,
    required this.light,
    required this.dark,
  });

  final AppThemeId id;
  final AppThemeVariant light;
  final AppThemeVariant dark;

  AppThemeVariant variant(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

abstract final class AppThemeRegistry {
  static const current = AppThemeId.mistSea;

  static const mistSea = AppThemeDefinition(
    id: AppThemeId.mistSea,
    light: AppThemeVariant(
      brightness: Brightness.light,
      tokens: AppTokens.light,
      glass: _mistSeaLightGlass,
    ),
    dark: AppThemeVariant(
      brightness: Brightness.dark,
      tokens: AppTokens.dark,
      glass: _mistSeaDarkGlass,
    ),
  );

  static const values = <AppThemeId, AppThemeDefinition>{
    AppThemeId.mistSea: mistSea,
  };

  static AppThemeDefinition definition(AppThemeId id) => values[id]!;
}

const _lightGlassShadow = <BoxShadow>[
  BoxShadow(color: Color(0x18252525), blurRadius: 24, offset: Offset(0, 10)),
];
const _darkGlassShadow = <BoxShadow>[
  BoxShadow(color: Color(0x52000000), blurRadius: 28, offset: Offset(0, 12)),
];

const _mistSeaLightGlass = <AppGlassRole, AppGlassStyle>{
  AppGlassRole.nav: AppGlassStyle(
    fill: Color(0xE6FAFAFA),
    border: Color(0xB3DDDDDD),
    highlight: Color(0xBFFFFFFF),
    fallbackFill: Color(0xFFFAFAFA),
    blurSigma: 24,
    saturation: 1.08,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.control: AppGlassStyle(
    fill: Color(0xD9EAEAEA),
    border: Color(0x99DDDDDD),
    highlight: Color(0xBFFFFFFF),
    fallbackFill: Color(0xFFEAEAEA),
    blurSigma: 18,
    saturation: 1.05,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.sheet: AppGlassStyle(
    fill: Color(0xF2FAFAFA),
    border: Color(0xCCDDDDDD),
    highlight: Color(0xE6FFFFFF),
    fallbackFill: Color(0xFFFAFAFA),
    blurSigma: 30,
    saturation: 1.06,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.clear: AppGlassStyle(
    fill: Color(0xA6FAFAFA),
    border: Color(0xB3FFFFFF),
    highlight: Color(0xD9FFFFFF),
    fallbackFill: Color(0xFFFAFAFA),
    blurSigma: 20,
    saturation: 1.04,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.fallback: AppGlassStyle(
    fill: Color(0xFFFAFAFA),
    border: Color(0xFFDDDDDD),
    highlight: Color(0x00FFFFFF),
    fallbackFill: Color(0xFFFAFAFA),
    blurSigma: 0,
    saturation: 1,
    shadows: _lightGlassShadow,
  ),
};

const _mistSeaDarkGlass = <AppGlassRole, AppGlassStyle>{
  AppGlassRole.nav: AppGlassStyle(
    fill: Color(0xE6202120),
    border: Color(0x99464743),
    highlight: Color(0x4DECEDEA),
    fallbackFill: Color(0xFF202120),
    blurSigma: 24,
    saturation: 1.06,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.control: AppGlassStyle(
    fill: Color(0xD92B2C2A),
    border: Color(0x80464743),
    highlight: Color(0x40ECEDEA),
    fallbackFill: Color(0xFF2B2C2A),
    blurSigma: 18,
    saturation: 1.04,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.sheet: AppGlassStyle(
    fill: Color(0xF2202120),
    border: Color(0xB3464743),
    highlight: Color(0x4DECEDEA),
    fallbackFill: Color(0xFF202120),
    blurSigma: 30,
    saturation: 1.05,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.clear: AppGlassStyle(
    fill: Color(0xA6202120),
    border: Color(0x99464743),
    highlight: Color(0x40ECEDEA),
    fallbackFill: Color(0xFF2B2C2A),
    blurSigma: 20,
    saturation: 1.03,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.fallback: AppGlassStyle(
    fill: Color(0xFF202120),
    border: Color(0xFF464743),
    highlight: Color(0x00000000),
    fallbackFill: Color(0xFF202120),
    blurSigma: 0,
    saturation: 1,
    shadows: _darkGlassShadow,
  ),
};
