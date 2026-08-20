import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:toastr_flutter/toastr.dart';

final class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.title,
    required this.message,
    this.compact = false,
  }) : destructive = false;

  const AppNotice.error({super.key, required this.title, required this.message})
    : destructive = true,
      compact = false;

  final String title;
  final String message;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact && !destructive) {
      final colors = ShadTheme.of(context).colorScheme;
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .055),
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: TextStyle(color: colors.mutedForeground)),
        ),
      );
    }
    final icon = Icon(destructive ? LucideIcons.circleAlert : LucideIcons.info);
    final titleWidget = Text(title);
    final description = Text(message);
    return destructive
        ? ShadAlert.destructive(
            icon: icon,
            title: titleWidget,
            description: description,
          )
        : ShadAlert(icon: icon, title: titleWidget, description: description);
  }
}

String showAppMessage(
  BuildContext context, {
  required String title,
  String? message,
  bool destructive = false,
}) {
  final hasMessage = message?.isNotEmpty ?? false;
  final toastMessage = hasMessage ? message! : title;
  final toastTitle = hasMessage ? title : null;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final options = ToastrOptions(
    duration: const Duration(seconds: 3),
    position: ToastrPosition.topCenter,
    showProgressBar: false,
    showCloseButton: false,
    theme: isDark ? ToastrTheme.dark : ToastrTheme.light,
    content: _AppToastContent(message: toastMessage, isDark: isDark),
  );

  return Toastr.blank(toastMessage, title: toastTitle, options: options);
}

final class _AppToastContent extends StatelessWidget {
  const _AppToastContent({required this.message, required this.isDark});

  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF5F5F4)
        : const Color(0xFF363636);
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: textColor,
        decoration: TextDecoration.none,
      ),
    );
  }
}
