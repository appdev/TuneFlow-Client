import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import 'app_platform.dart';
import 'desktop_title_content.dart';
import 'desktop_window_controller.dart';
import 'linux_window_controls.dart';
import 'windows_window_controls.dart';

final class PlatformWindowFrame extends StatelessWidget {
  const PlatformWindowFrame({
    super.key,
    required this.platform,
    required this.location,
    required this.controller,
    required this.child,
    this.onBack,
    this.onForward,
    this.onSearch,
    this.desktopSidebarWidth,
    this.playerAccent,
  });

  final AppPlatform platform;
  final String location;
  final DesktopWindowController controller;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onSearch;
  final double? desktopSidebarWidth;
  final Color? playerAccent;

  @override
  Widget build(BuildContext context) {
    if (!platform.isDesktop) return child;
    final playerCanvas = location.startsWith('/player');

    final controls = switch (platform) {
      AppPlatform.windows => WindowsWindowControls(controller: controller),
      AppPlatform.linux => LinuxWindowControls(controller: controller),
      AppPlatform.macos => null,
      AppPlatform.android || AppPlatform.ios => null,
    };
    final leadingInset = platform == AppPlatform.macos ? 82.0 : 10.0;
    final trailingInset = switch (platform) {
      AppPlatform.windows => 148.0,
      AppPlatform.linux => 136.0,
      _ => 10.0,
    };
    final tokens = AppTokens.of(context);
    final contentLeadingInset = desktopSidebarWidth == null
        ? leadingInset
        : desktopSidebarWidth! + 10;

    final titleBar = Container(
      key: const Key('desktop-title-bar'),
      height: 38,
      decoration: BoxDecoration(
        color: playerCanvas
            ? Colors.transparent
            : desktopSidebarWidth == null
            ? tokens.surface
            : tokens.background,
      ),
      child: Stack(
        children: [
          if (!playerCanvas && desktopSidebarWidth != null)
            Positioned(
              key: const Key('desktop-title-leading-surface'),
              left: 0,
              top: 0,
              bottom: 0,
              width: desktopSidebarWidth!,
              child: ColoredBox(color: tokens.surface),
            ),
          if (platform == AppPlatform.macos)
            const SizedBox(
              key: Key('macos-traffic-light-safe-area'),
              width: 82,
              height: 38,
            ),
          Positioned.fill(
            child: GestureDetector(
              key: Key(switch (platform) {
                AppPlatform.macos => 'macos-title-bar',
                AppPlatform.windows => 'windows-title-bar',
                AppPlatform.linux => 'linux-title-bar',
                _ => 'desktop-title-drag-region',
              }),
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => controller.startDragging(),
              onDoubleTap: controller.toggleMaximize,
            ),
          ),
          DesktopTitleContent(
            location: location,
            leadingInset: contentLeadingInset,
            centerLeadingInset: desktopSidebarWidth == null
                ? 0
                : contentLeadingInset,
            trailingInset: trailingInset,
            onBack: onBack,
            onForward: onForward,
            onSearch: onSearch,
            playerAccent: playerCanvas ? playerAccent : null,
          ),
          if (controls != null)
            Positioned(right: 0, top: 0, bottom: 0, child: controls),
        ],
      ),
    );

    if (playerCanvas) {
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(left: 0, top: 0, right: 0, child: titleBar),
        ],
      );
    }
    return Column(
      children: [
        titleBar,
        Expanded(child: child),
      ],
    );
  }
}
