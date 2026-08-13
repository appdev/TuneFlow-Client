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
  BoxShadow(color: Color(0x18091411), blurRadius: 24, offset: Offset(0, 10)),
];
const _darkGlassShadow = <BoxShadow>[
  BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12)),
];

const _mistSeaLightGlass = <AppGlassRole, AppGlassStyle>{
  AppGlassRole.nav: AppGlassStyle(
    fill: Color(0xD9DEECE7),
    border: Color(0x99FFFFFF),
    highlight: Color(0xBFFFFFFF),
    fallbackFill: Color(0xFFDEECE7),
    blurSigma: 24,
    saturation: 1.08,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.control: AppGlassStyle(
    fill: Color(0xC7DEECE7),
    border: Color(0x80FFFFFF),
    highlight: Color(0xA6FFFFFF),
    fallbackFill: Color(0xFFDEECE7),
    blurSigma: 18,
    saturation: 1.05,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.sheet: AppGlassStyle(
    fill: Color(0xF2DEECE7),
    border: Color(0xB3FFFFFF),
    highlight: Color(0xCCFFFFFF),
    fallbackFill: Color(0xFFDEECE7),
    blurSigma: 30,
    saturation: 1.06,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.clear: AppGlassStyle(
    fill: Color(0x8FEFF7F5),
    border: Color(0xA6FFFFFF),
    highlight: Color(0xCCFFFFFF),
    fallbackFill: Color(0xFFDEECE7),
    blurSigma: 20,
    saturation: 1.04,
    shadows: _lightGlassShadow,
  ),
  AppGlassRole.fallback: AppGlassStyle(
    fill: Color(0xFFDEECE7),
    border: Color(0xFFBFCFCA),
    highlight: Color(0x00FFFFFF),
    fallbackFill: Color(0xFFDEECE7),
    blurSigma: 0,
    saturation: 1,
    shadows: _lightGlassShadow,
  ),
};

const _mistSeaDarkGlass = <AppGlassRole, AppGlassStyle>{
  AppGlassRole.nav: AppGlassStyle(
    fill: Color(0xD90A1411),
    border: Color(0x663E514B),
    highlight: Color(0x405E746D),
    fallbackFill: Color(0xFF0A1411),
    blurSigma: 24,
    saturation: 1.06,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.control: AppGlassStyle(
    fill: Color(0xC70A1411),
    border: Color(0x593E514B),
    highlight: Color(0x335E746D),
    fallbackFill: Color(0xFF0A1411),
    blurSigma: 18,
    saturation: 1.04,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.sheet: AppGlassStyle(
    fill: Color(0xF20A1411),
    border: Color(0x7344554F),
    highlight: Color(0x405E746D),
    fallbackFill: Color(0xFF0A1411),
    blurSigma: 30,
    saturation: 1.05,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.clear: AppGlassStyle(
    fill: Color(0x8F0A1411),
    border: Color(0x735E746D),
    highlight: Color(0x405E746D),
    fallbackFill: Color(0xFF14201C),
    blurSigma: 20,
    saturation: 1.03,
    shadows: _darkGlassShadow,
  ),
  AppGlassRole.fallback: AppGlassStyle(
    fill: Color(0xFF0A1411),
    border: Color(0xFF25312D),
    highlight: Color(0x00000000),
    fallbackFill: Color(0xFF0A1411),
    blurSigma: 0,
    saturation: 1,
    shadows: _darkGlassShadow,
  ),
};
