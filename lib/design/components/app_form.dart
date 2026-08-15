import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme_definition.dart';
import 'app_glass_surface.dart';

enum AppFieldSurface { standard, glass }

final class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    required this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.surface = AppFieldSurface.standard,
    this.groupId,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final AppFieldSurface surface;
  final Object? groupId;

  @override
  Widget build(BuildContext context) {
    final input = ShadInput(
      controller: controller,
      focusNode: focusNode,
      initialValue: controller == null ? initialValue : null,
      placeholder: Text(placeholder),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      leading: leading,
      trailing: trailing,
      enabled: enabled,
      groupId: groupId,
    );
    return surface == AppFieldSurface.glass
        ? AppGlassSurface(role: AppGlassRole.control, child: input)
        : input;
  }
}
