import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Semantic visual roles translated from the accepted Open Design project.
@immutable
final class AppTokens {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.surfaceWarm,
    required this.foreground,
    required this.foregroundSecondary,
    required this.muted,
    required this.border,
    required this.borderSoft,
    required this.accent,
    required this.accentForeground,
    required this.primaryAction,
    required this.primaryActionForeground,
    required this.playbackAction,
    required this.playbackActionForeground,
    required this.playbackTrackInactive,
    required this.success,
    required this.warning,
    required this.danger,
    required this.focusRing,
    required this.overlay,
    required this.playerVeil,
  });

  static const light = AppTokens(
    background: Color(0xFFF6F6F6),
    surface: Color(0xFFFAFAFA),
    surfaceWarm: Color(0xFFEAEAEA),
    foreground: Color(0xFF252525),
    foregroundSecondary: Color(0xFF494949),
    muted: Color(0xFF626262),
    border: Color(0xFFDDDDDD),
    borderSoft: Color(0xFFEAEAEA),
    accent: Color(0xFF14745F),
    accentForeground: Color(0xFFF6F6F6),
    primaryAction: Color(0xFF14745F),
    primaryActionForeground: Color(0xFFF6F6F6),
    playbackAction: Color(0xFF14745F),
    playbackActionForeground: Colors.white,
    playbackTrackInactive: Color(0xFF8A8A8A),
    success: Color(0xFF2F7D4A),
    warning: Color(0xFF966000),
    danger: Color(0xFFB93B3B),
    focusRing: Color(0xFF008B70),
    overlay: Color(0x66252525),
    playerVeil: Color(0xCCF6F6F6),
  );

  static const dark = AppTokens(
    background: Color(0xFF171817),
    surface: Color(0xFF202120),
    surfaceWarm: Color(0xFF2B2C2A),
    foreground: Color(0xFFECEDEA),
    foregroundSecondary: Color(0xFFC6C7C3),
    muted: Color(0xFFA0A19D),
    border: Color(0xFF464743),
    borderSoft: Color(0xFF30312F),
    accent: Color(0xFF19D39B),
    accentForeground: Color(0xFF101713),
    primaryAction: Color(0xFF00E66A),
    primaryActionForeground: Color(0xFF101713),
    playbackAction: Color(0xFF14745F),
    playbackActionForeground: Colors.white,
    playbackTrackInactive: Color(0xFF737570),
    success: Color(0xFF75B987),
    warning: Color(0xFFD7A45A),
    danger: Color(0xFFE87870),
    focusRing: Color(0xFF19D39B),
    overlay: Color(0xB3121312),
    playerVeil: Color(0xD9171817),
  );

  static AppTokens of(BuildContext context) =>
      ShadTheme.of(context).brightness == Brightness.dark ? dark : light;

  final Color background;
  final Color surface;
  final Color surfaceWarm;
  final Color foreground;
  final Color foregroundSecondary;
  final Color muted;
  final Color border;
  final Color borderSoft;
  final Color accent;
  final Color accentForeground;
  final Color primaryAction;
  final Color primaryActionForeground;
  final Color playbackAction;
  final Color playbackActionForeground;
  final Color playbackTrackInactive;
  final Color success;
  final Color warning;
  final Color danger;
  final Color focusRing;
  final Color overlay;
  final Color playerVeil;
}

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double section = 64;
}

abstract final class AppRadii {
  static const double control = 8;
  static const double compactCard = 12;
  static const double card = 16;
  static const double panel = 20;
  static const double sheet = 24;
  static const double pill = 999;
}

abstract final class AppDurations {
  static const Duration state = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 280);
  static const Duration reducedMotion = Duration(milliseconds: 150);
}

abstract final class AppCurves {
  static const Curve out = Cubic(0.16, 1, 0.3, 1);
  static const Curve inOut = Cubic(0.65, 0, 0.35, 1);
}

abstract final class AppShadows {
  static const panel = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const raised = <BoxShadow>[
    BoxShadow(color: Color(0x30000000), blurRadius: 42, offset: Offset(0, 18)),
  ];
}

abstract final class AppTypography {
  static const String displayFontFamily = 'NotoSerifSC';
  static const String bodyFontFamily = 'NotoSansCJKsc';
  static const String dataFontFamily = 'IBMPlexMono';
  static const String fontFamily = bodyFontFamily;
  static const hero = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    letterSpacing: -0.5,
  );
  static const display = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    letterSpacing: -0.3,
  );
  static const pageTitle = display;
  static const mobilePageTitle = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    letterSpacing: -0.2,
  );
  static const section = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    letterSpacing: -0.2,
  );
  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.45,
  );
  static const metadata = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );
  static const counter = TextStyle(
    fontFamily: dataFontFamily,
    fontSize: 12,
    height: 1.35,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
