/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 */
/* Hallmark · component: adaptive-modal · genre: atmospheric · theme: Mist Sea
 * presentations: mobile bottom sheet · desktop centered dialog
 * variants: actions · destructive · content · draggable
 * states: default · hover · focus · active · disabled
 * async states: loading · error · success are caller-owned after dismissal
 * contrast: uses project semantic tokens
 */

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_breakpoints.dart';
import '../app_theme_definition.dart';
import '../design_tokens.dart';
import 'app_button.dart';
import 'app_glass_surface.dart';

@immutable
final class AppBottomSheetAction<T> {
  const AppBottomSheetAction({
    required this.value,
    required this.label,
    this.key,
    this.enabled = true,
    this.destructive = false,
  });

  final T? value;
  final String label;
  final Key? key;
  final bool enabled;
  final bool destructive;
}

abstract final class AppBottomSheet {
  static bool _usesBottomPresentation(BuildContext context) =>
      classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;

  static Future<bool> showDestructive(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = '取消',
  }) async =>
      await showActions<bool>(
        context,
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        actions: [
          AppBottomSheetAction(
            key: const Key('app-bottom-sheet-destructive'),
            value: true,
            label: confirmLabel,
            destructive: true,
          ),
        ],
      ) ??
      false;

  static Future<T?> showActions<T>(
    BuildContext context, {
    required String title,
    String? message,
    required List<AppBottomSheetAction<T>> actions,
    String cancelLabel = '取消',
  }) {
    if (actions.isEmpty || actions.length > 4) {
      throw ArgumentError.value(
        actions.length,
        'actions.length',
        'An ActionSheet requires between one and four choices.',
      );
    }
    final tokens = AppTokens.of(context);
    if (!_usesBottomPresentation(context)) {
      return showShadDialog<T>(
        context: context,
        barrierColor: tokens.overlay,
        builder: (dialogContext) => _ActionDialog<T>(
          title: title,
          message: message,
          actions: actions,
          cancelLabel: cancelLabel,
        ),
      );
    }
    return showCupertinoModalPopup<T>(
      context: context,
      barrierColor: tokens.overlay,
      barrierDismissible: true,
      semanticsDismissible: true,
      builder: (context) => _ActionSheet<T>(
        title: title,
        message: message,
        actions: actions,
        cancelLabel: cancelLabel,
      ),
    );
  }

  static Future<T?> showContent<T>(
    BuildContext context, {
    required String title,
    String? message,
    required Widget child,
  }) => _showContent<T>(context, title: title, message: message, child: child);

  static Future<T?> showDraggable<T>(
    BuildContext context, {
    required String title,
    String? message,
    required Widget child,
    required double initialChildSize,
    double minChildSize = .48,
    double maxChildSize = .90,
  }) {
    assert(minChildSize > 0);
    assert(minChildSize <= initialChildSize);
    assert(initialChildSize <= maxChildSize);
    assert(maxChildSize <= 1);
    return _showContent<T>(
      context,
      title: title,
      message: message,
      child: child,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
    );
  }

  static Future<T?> _showContent<T>(
    BuildContext context, {
    required String title,
    String? message,
    required Widget child,
    double? initialChildSize,
    double minChildSize = .48,
    double maxChildSize = .90,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    if (!_usesBottomPresentation(context)) {
      return showShadDialog<T>(
        context: context,
        barrierColor: AppTokens.of(context).overlay,
        builder: (dialogContext) => ShadDialog(
          key: const Key('app-adaptive-dialog'),
          title: Text(title),
          description: message == null ? null : Text(message),
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: viewport.height * .8,
          ),
          scrollable: true,
          child: child,
        ),
      );
    }
    if (initialChildSize != null) {
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
          builder: (context, scrollController) => _DraggableSheetFrame(
            title: title,
            scrollController: scrollController,
            child: child,
          ),
        ),
      );
    }
    return showShadSheet<T>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (sheetContext) {
        return ShadSheet(
          title: Text(title),
          description: message == null ? null : Text(message),
          child: AppGlassSurface(
            role: AppGlassRole.sheet,
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        );
      },
    );
  }
}

final class _ActionDialog<T> extends StatelessWidget {
  const _ActionDialog({
    required this.title,
    required this.message,
    required this.actions,
    required this.cancelLabel,
  });

  final String title;
  final String? message;
  final List<AppBottomSheetAction<T>> actions;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) => ShadDialog.alert(
    key: const Key('app-adaptive-dialog'),
    title: Text(title),
    description: message == null ? null : Text(message!),
    actions: [
      AppButton(
        key: const Key('app-action-sheet-cancel'),
        variant: ShadButtonVariant.outline,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(cancelLabel),
      ),
      for (final action in actions)
        AppButton(
          key: action.key,
          variant: action.destructive
              ? ShadButtonVariant.destructive
              : actions.length == 1
              ? ShadButtonVariant.primary
              : ShadButtonVariant.outline,
          onPressed: action.enabled
              ? () => Navigator.of(context).pop(action.value)
              : null,
          child: Text(action.label, maxLines: 1),
        ),
    ],
  );
}

final class _DraggableSheetFrame extends StatelessWidget {
  const _DraggableSheetFrame({
    required this.title,
    required this.scrollController,
    required this.child,
  });

  final String title;
  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
  }
}

final class _ActionSheet<T> extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.message,
    required this.actions,
    required this.cancelLabel,
  });

  final String title;
  final String? message;
  final List<AppBottomSheetAction<T>> actions;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    const radius = BorderRadius.all(Radius.circular(15));
    return DefaultTextStyle(
      style: AppTypography.body.copyWith(
        color: tokens.foreground,
        decoration: TextDecoration.none,
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                label: title,
                explicitChildNodes: true,
                child: AppGlassSurface(
                  key: const Key('app-action-sheet-actions'),
                  role: AppGlassRole.sheet,
                  borderRadius: radius,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Column(
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.title.copyWith(
                                color: tokens.foreground,
                                fontSize: 14,
                              ),
                            ),
                            if (message case final value?) ...[
                              const SizedBox(height: 4),
                              Text(
                                value,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.metadata.copyWith(
                                  color: tokens.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _Divider(color: tokens.border),
                      for (var index = 0; index < actions.length; index++) ...[
                        if (index > 0) _Divider(color: tokens.border),
                        _ActionRow<T>(action: actions[index]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AppGlassSurface(
                key: const Key('app-action-sheet-cancel-group'),
                role: AppGlassRole.sheet,
                borderRadius: radius,
                child: _ActionRow<T>(
                  action: AppBottomSheetAction<T>(
                    key: const Key('app-action-sheet-cancel'),
                    value: null,
                    label: cancelLabel,
                  ),
                  cancel: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color.withValues(alpha: .72),
    child: const SizedBox(height: .5),
  );
}

final class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({required this.action, this.cancel = false});

  final AppBottomSheetAction<T> action;
  final bool cancel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final foreground = action.destructive ? tokens.danger : tokens.accent;
    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: action.key,
          excludeFromSemantics: true,
          canRequestFocus: action.enabled,
          onTap: action.enabled
              ? () => Navigator.of(context).pop(cancel ? null : action.value)
              : null,
          focusColor: tokens.focusRing.withValues(alpha: .14),
          hoverColor: foreground.withValues(alpha: .08),
          highlightColor: foreground.withValues(alpha: .12),
          splashColor: foreground.withValues(alpha: .10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Center(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: action.enabled
                        ? foreground
                        : tokens.muted.withValues(alpha: .62),
                    fontWeight: cancel ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
