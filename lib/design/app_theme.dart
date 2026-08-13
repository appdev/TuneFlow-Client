import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme_definition.dart';
import 'design_tokens.dart';

ShadThemeData buildLightTheme([
  AppThemeDefinition definition = AppThemeRegistry.mistSea,
]) => ShadThemeData(
  brightness: Brightness.light,
  colorScheme: _schemeFor(definition.light),
  textTheme: ShadTextTheme(family: AppTypography.bodyFontFamily),
  radius: const BorderRadius.all(Radius.circular(AppRadii.control)),
  breakpoints: ShadBreakpoints(sm: 720, md: 900, lg: 1180),
);

ShadThemeData buildDarkTheme([
  AppThemeDefinition definition = AppThemeRegistry.mistSea,
]) => ShadThemeData(
  brightness: Brightness.dark,
  colorScheme: _schemeFor(definition.dark),
  textTheme: ShadTextTheme(family: AppTypography.bodyFontFamily),
  radius: const BorderRadius.all(Radius.circular(AppRadii.control)),
  breakpoints: ShadBreakpoints(sm: 720, md: 900, lg: 1180),
);

ShadColorScheme _schemeFor(AppThemeVariant variant) {
  final tokens = variant.tokens;
  final parameters = (
    background: tokens.background,
    foreground: tokens.foreground,
    card: tokens.surface,
    cardForeground: tokens.foreground,
    popover: tokens.surface,
    popoverForeground: tokens.foreground,
    primary: tokens.accent,
    primaryForeground: tokens.accentForeground,
    secondary: tokens.surfaceWarm,
    secondaryForeground: tokens.foreground,
    muted: tokens.surfaceWarm,
    mutedForeground: tokens.muted,
    accent: tokens.surfaceWarm,
    accentForeground: tokens.foreground,
    destructive: tokens.danger,
    border: tokens.border,
    input: tokens.border,
    ring: tokens.focusRing,
  );
  return variant.brightness == Brightness.dark
      ? ShadZincColorScheme.dark(
          background: parameters.background,
          foreground: parameters.foreground,
          card: parameters.card,
          cardForeground: parameters.cardForeground,
          popover: parameters.popover,
          popoverForeground: parameters.popoverForeground,
          primary: parameters.primary,
          primaryForeground: parameters.primaryForeground,
          secondary: parameters.secondary,
          secondaryForeground: parameters.secondaryForeground,
          muted: parameters.muted,
          mutedForeground: parameters.mutedForeground,
          accent: parameters.accent,
          accentForeground: parameters.accentForeground,
          destructive: parameters.destructive,
          border: parameters.border,
          input: parameters.input,
          ring: parameters.ring,
        )
      : ShadZincColorScheme.light(
          background: parameters.background,
          foreground: parameters.foreground,
          card: parameters.card,
          cardForeground: parameters.cardForeground,
          popover: parameters.popover,
          popoverForeground: parameters.popoverForeground,
          primary: parameters.primary,
          primaryForeground: parameters.primaryForeground,
          secondary: parameters.secondary,
          secondaryForeground: parameters.secondaryForeground,
          muted: parameters.muted,
          mutedForeground: parameters.mutedForeground,
          accent: parameters.accent,
          accentForeground: parameters.accentForeground,
          destructive: parameters.destructive,
          border: parameters.border,
          input: parameters.input,
          ring: parameters.ring,
        );
}
