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
    required this.success,
    required this.warning,
    required this.danger,
    required this.focusRing,
    required this.overlay,
    required this.playerVeil,
  });

  static const light = AppTokens(
    background: Color(0xFFECF6F3),
    surface: Color(0xFFDEECE7),
    surfaceWarm: Color(0xFFCEDFDA),
    foreground: Color(0xFF091411),
    foregroundSecondary: Color(0xFF273330),
    muted: Color(0xFF576460),
    border: Color(0xFFBFCFCA),
    borderSoft: Color(0xFFCEDFDA),
    accent: Color(0xFF136D5B),
    accentForeground: Color(0xFFEFF7F5),
    success: Color(0xFF317A45),
    warning: Color(0xFFB07A20),
    danger: Color(0xFFC43F3E),
    focusRing: Color(0xFF008E73),
    overlay: Color(0x66091411),
    playerVeil: Color(0xCCECF6F3),
  );

  static const dark = AppTokens(
    background: Color(0xFF040B09),
    surface: Color(0xFF0A1411),
    surfaceWarm: Color(0xFF14201C),
    foreground: Color(0xFFE5EDEB),
    foregroundSecondary: Color(0xFFB6C0BD),
    muted: Color(0xFF8A9592),
    border: Color(0xFF25312D),
    borderSoft: Color(0xFF14201C),
    accent: Color(0xFF6DBDA8),
    accentForeground: Color(0xFF040E0B),
    success: Color(0xFF7CBD89),
    warning: Color(0xFFE1AD63),
    danger: Color(0xFFF47B74),
    focusRing: Color(0xFF66D5BA),
    overlay: Color(0xB3000000),
    playerVeil: Color(0xD9040B09),
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
