import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme_definition.dart';

final class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    required this.definition,
    required super.child,
    super.key,
  });

  final AppThemeDefinition definition;

  static AppThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing above this context.');
    return scope!;
  }

  static AppThemeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>();

  static AppThemeVariant variantOf(BuildContext context) {
    final brightness = ShadTheme.of(context).brightness;
    return (maybeOf(context)?.definition ?? AppThemeRegistry.mistSea).variant(
      brightness,
    );
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      definition != oldWidget.definition;
}
