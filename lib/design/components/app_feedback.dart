import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_breakpoints.dart';
import '../app_theme_definition.dart';
import '../design_tokens.dart';
import 'app_button.dart';
import 'app_glass_surface.dart';

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

Future<bool> showAppDestructiveDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
}) async =>
    await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ShadDialog.alert(
        title: Text(title),
        description: Text(message),
        actions: [
          AppButton(
            variant: ShadButtonVariant.outline,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          AppButton(
            variant: ShadButtonVariant.destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

Object? showAppMessage(
  BuildContext context, {
  required String title,
  String? message,
  bool destructive = false,
}) {
  final toast = destructive
      ? ShadToast.destructive(
          title: Text(title),
          description: message == null ? null : Text(message),
        )
      : ShadToast(
          title: Text(title),
          description: message == null ? null : Text(message),
        );
  return ShadSonner.of(context).show(toast);
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  double? initialChildSize,
  double minChildSize = .48,
  double maxChildSize = .90,
}) {
  if (initialChildSize != null) {
    assert(minChildSize > 0);
    assert(minChildSize <= initialChildSize);
    assert(initialChildSize <= maxChildSize);
    assert(maxChildSize <= 1);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        expand: false,
        builder: (context, scrollController) {
          final tokens = AppTokens.of(context);
          return AppGlassSurface(
            role: AppGlassRole.sheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet),
            ),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.border,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: AppTypography.title)),
                      Semantics(
                        button: true,
                        label: '关闭',
                        child: ShadButton.ghost(
                          width: 44,
                          height: 44,
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Icon(LucideIcons.x, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PrimaryScrollController(
                    controller: scrollController,
                    child: child,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  return showShadSheet<T>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (sheetContext) {
      final mobile =
          classifyLayout(MediaQuery.sizeOf(sheetContext)) ==
          AppLayoutClass.mobile;
      return ShadSheet(
        title: Text(title),
        child: mobile
            ? AppGlassSurface(
                role: AppGlassRole.sheet,
                padding: const EdgeInsets.all(16),
                child: child,
              )
            : child,
      );
    },
  );
}
