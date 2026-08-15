import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design/app_breakpoints.dart';

final class DesktopTitleContent extends StatelessWidget {
  const DesktopTitleContent({
    super.key,
    required this.location,
    required this.leadingInset,
    this.centerLeadingInset = 0,
    required this.trailingInset,
    this.onBack,
    this.onForward,
    this.onSearch,
    this.playerAccent,
  });

  final String location;
  final double leadingInset;
  final double centerLeadingInset;
  final double trailingInset;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onSearch;
  final Color? playerAccent;

  @override
  Widget build(BuildContext context) {
    if (location.startsWith('/player')) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (classifyLayout(MediaQuery.sizeOf(context)) ==
              AppLayoutClass.mobile) {
            return const SizedBox.shrink();
          }
          return Stack(
            children: [
              Positioned(
                left: leadingInset,
                top: 0,
                bottom: 0,
                child: _TitleAction(
                  key: const Key('desktop-back'),
                  icon: LucideIcons.chevronLeft,
                  label: '返回',
                  onPressed: onBack,
                  foregroundColor: playerAccent,
                ),
              ),
            ],
          );
        },
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(left: leadingInset, right: trailingInset),
            child: Row(
              children: [
                _TitleAction(
                  key: const Key('desktop-back'),
                  icon: LucideIcons.chevronLeft,
                  label: '返回',
                  onPressed: onBack,
                ),
                const SizedBox(width: 4),
                _TitleAction(
                  key: const Key('desktop-forward'),
                  icon: LucideIcons.chevronRight,
                  label: '前进',
                  onPressed: onForward,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class _TitleAction extends StatelessWidget {
  const _TitleAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: Tooltip(
      message: label,
      child: ShadButton.raw(
        variant: ShadButtonVariant.ghost,
        width: 38,
        height: 38,
        padding: EdgeInsets.zero,
        enabled: onPressed != null,
        onPressed: onPressed,
        foregroundColor: foregroundColor,
        hoverForegroundColor: foregroundColor,
        pressedForegroundColor: foregroundColor,
        child: Icon(icon, size: 17, color: foregroundColor),
      ),
    ),
  );
}
