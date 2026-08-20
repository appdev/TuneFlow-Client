import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_glass_policy.dart';
import '../app_theme_definition.dart';
import '../design_tokens.dart';
import 'app_glass_surface.dart';

final class AppMobilePageHeader extends StatelessWidget {
  const AppMobilePageHeader({
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.onBack,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (onBack case final callback?) ...[
        AppMobileBackButton(onPressed: callback),
        const SizedBox(width: AppSpacing.xs),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow case final label?) ...[
              Text(
                label,
                style: AppTypography.metadata.copyWith(
                  color: AppTokens.of(context).muted,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
            ],
            Text(title, style: AppTypography.mobilePageTitle),
          ],
        ),
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(width: AppSpacing.sm),
        AppGlassSurface(
          role: AppGlassRole.control,
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(mainAxisSize: MainAxisSize.min, children: actions),
        ),
      ],
    ],
  );
}

final class AppMobileBackButton extends StatelessWidget {
  const AppMobileBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '返回',
    excludeSemantics: true,
    child: Tooltip(
      message: '返回',
      child: IconButton(
        key: const Key('mobile-page-back'),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: onPressed,
        icon: Icon(LucideIcons.chevronLeft, size: 20),
      ),
    ),
  );
}

final class AppGlassSegmentedControl<T> extends StatelessWidget {
  const AppGlassSegmentedControl({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    return AppGlassSurface(
      role: AppGlassRole.control,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in items.entries)
            Semantics(
              button: true,
              selected: entry.key == value,
              label: '${entry.value}${entry.key == value ? '，已选择' : ''}',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onChanged(entry.key),
                borderRadius: BorderRadius.circular(AppRadii.compactCard),
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(
                    minWidth: 56,
                    minHeight: 44,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: entry.key == value
                        ? tokens.surfaceWarm
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.compactCard),
                    border: entry.key == value
                        ? Border.all(color: tokens.border)
                        : null,
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    style: AppTypography.metadata.copyWith(
                      color: entry.key == value
                          ? tokens.accent
                          : tokens.foregroundSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
