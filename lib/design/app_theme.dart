import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme_definition.dart';
import 'design_tokens.dart';

const appToastAlignment = Alignment(0, -0.45);

ThemeData buildAppMaterialTheme(ThemeData base) =>
    base.copyWith(splashFactory: NoSplash.splashFactory);

ShadThemeData buildLightTheme([
  AppThemeDefinition definition = AppThemeRegistry.mistSea,
]) => _themeFor(definition.light);

ShadThemeData buildDarkTheme([
  AppThemeDefinition definition = AppThemeRegistry.mistSea,
]) => _themeFor(definition.dark);

ShadThemeData _themeFor(AppThemeVariant variant) {
  final tokens = variant.tokens;
  final interactiveDefault = variant.brightness == Brightness.dark
      ? tokens.foreground
      : tokens.primaryAction;
  final restingActionTheme = ShadButtonTheme(
    foregroundColor: interactiveDefault,
    hoverForegroundColor: tokens.primaryAction,
    pressedForegroundColor: tokens.primaryAction,
  );
  return ShadThemeData(
    brightness: variant.brightness,
    colorScheme: _schemeFor(variant),
    textTheme: ShadTextTheme(family: AppTypography.bodyFontFamily),
    radius: const BorderRadius.all(Radius.circular(AppRadii.control)),
    breakpoints: ShadBreakpoints(sm: 720, md: 900, lg: 1180),
    sonnerTheme: const ShadSonnerTheme(alignment: appToastAlignment),
    outlineButtonTheme: restingActionTheme,
    ghostButtonTheme: restingActionTheme,
    linkButtonTheme: restingActionTheme,
  );
}

ShadColorScheme _schemeFor(AppThemeVariant variant) {
  final tokens = variant.tokens;
  final parameters = (
    background: tokens.background,
    foreground: tokens.foreground,
    card: tokens.surface,
    cardForeground: tokens.foreground,
    popover: tokens.surface,
    popoverForeground: tokens.foreground,
    primary: tokens.primaryAction,
    primaryForeground: tokens.primaryActionForeground,
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
