import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design/app_breakpoints.dart';
import '../design/components/app_navigation.dart';
import '../design/components/app_mobile_dock.dart';
import '../design/design_tokens.dart';
import '../features/connection/connection_repository.dart';
import '../features/player/mini_player.dart';
import '../features/player/player_controller.dart';
import '../features/sources/source_repository.dart';
import '../platform/app_platform.dart';
import '../platform/desktop_window_controller.dart';
import '../platform/platform_window_frame.dart';

final class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.connected,
    required this.onDisconnect,
    required this.player,
    required this.child,
    this.onOpenPlayer,
    this.onBack,
    this.onForward,
    this.platform,
  });

  final ConnectedService connected;
  final VoidCallback onDisconnect;
  final PlayerController player;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final Widget child;
  final AppPlatform? platform;

  static const _desktopDestinations = [
    AppDestination(id: 'home', label: '首页', icon: LucideIcons.house),
    AppDestination(id: 'search', label: '搜索', icon: LucideIcons.search),
    AppDestination(id: 'square', label: '歌单广场', icon: LucideIcons.grid2x2),
    AppDestination(
      id: 'charts',
      label: '排行榜',
      icon: LucideIcons.chartNoAxesColumnIncreasing,
    ),
    AppDestination(id: 'playlists', label: '我的歌单', icon: LucideIcons.heart),
    AppDestination(id: 'downloads', label: '下载管理', icon: LucideIcons.download),
    AppDestination(id: 'settings', label: '设置', icon: LucideIcons.settings),
  ];

  static const _mobileDestinations = [
    AppDestination(id: 'home', label: '首页', icon: LucideIcons.house),
    AppDestination(id: 'search', label: '搜索', icon: LucideIcons.search),
    AppDestination(id: 'playlists', label: '我的音乐', icon: LucideIcons.heart),
    AppDestination(id: 'downloads', label: '下载', icon: LucideIcons.download),
    AppDestination(id: 'more', label: '更多', icon: LucideIcons.ellipsis),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final location = GoRouterState.of(context).uri.path;
    final showMiniPlayer = !location.startsWith('/player');
    final selectedId = switch (location) {
      final value when value.startsWith('/search') => 'search',
      final value when value.startsWith('/square') => 'square',
      final value when value.startsWith('/charts') => 'charts',
      final value when value.startsWith('/playlists') => 'playlists',
      final value when value.startsWith('/downloads') => 'downloads',
      final value when value.startsWith('/settings') => 'settings',
      final value when value.startsWith('/sources') => 'sources',
      final value when value.startsWith('/more') => 'more',
      final value when value.startsWith('/states') => 'states',
      _ => 'home',
    };
    void navigate(String id) => context.go(switch (id) {
      'search' => '/search',
      'square' => '/square',
      'charts' => '/charts',
      'playlists' => '/playlists',
      'downloads' => '/downloads',
      'settings' => '/settings',
      'sources' => '/sources',
      'more' => '/more',
      _ => '/',
    });
    final openPlayer = onOpenPlayer ?? () => context.goNamed('player');

    return Scaffold(
      key: const Key('main-shell'),
      backgroundColor: tokens.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = classifyLayout(MediaQuery.sizeOf(context));
          final resolvedPlatform =
              platform ?? resolveAppPlatform(Theme.of(context).platform);
          if (layout == AppLayoutClass.mobile) {
            final mobileShell = Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: false,
              body: SafeArea(bottom: false, child: child),
              bottomNavigationBar: showMiniPlayer
                  ? AppMobileDock(
                      player: player,
                      destinations: _mobileDestinations,
                      selectedId:
                          _mobileDestinations.any(
                            (destination) => destination.id == selectedId,
                          )
                          ? selectedId
                          : 'home',
                      onSelected: navigate,
                      onOpenPlayer: openPlayer,
                    )
                  : null,
            );
            return PlatformWindowFrame(
              platform: resolvedPlatform,
              location: location,
              controller: desktopWindowController,
              onBack: onBack,
              onForward: onForward,
              onSearch: () => context.go('/search'),
              child: mobileShell,
            );
          }
          final compact = layout == AppLayoutClass.narrow;
          return PlatformWindowFrame(
            platform: resolvedPlatform,
            location: location,
            controller: desktopWindowController,
            onBack: onBack,
            onForward: onForward,
            onSearch: () => context.go('/search'),
            desktopSidebarWidth: compact ? 84 : 208,
            child: Row(
              children: [
                AppDesktopNavigation(
                  destinations: _desktopDestinations,
                  selectedId: selectedId,
                  compact: compact,
                  onSelected: navigate,
                  footer: _ConnectionFooter(
                    connected: connected,
                    compact: compact,
                    onSources: () => navigate('sources'),
                    onDisconnect: onDisconnect,
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: player,
                    builder: (context, _) {
                      final hasTrack = player.state.current != null;
                      return Stack(
                        key: const Key('desktop-content-shell'),
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: showMiniPlayer && hasTrack ? 120 : 0,
                            ),
                            child: child,
                          ),
                          if (showMiniPlayer)
                            Positioned(
                              left: AppSpacing.sm,
                              right: AppSpacing.sm,
                              bottom: AppSpacing.sm,
                              child: ClipRRect(
                                key: const Key('desktop-player-inset'),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                                child: MiniPlayer(
                                  controller: player,
                                  onOpen: openPlayer,
                                  variant: MiniPlayerVariant.desktop,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _ConnectionFooter extends StatelessWidget {
  const _ConnectionFooter({
    required this.connected,
    required this.onDisconnect,
    required this.onSources,
    required this.compact,
  });

  final ConnectedService connected;
  final VoidCallback onDisconnect;
  final VoidCallback onSources;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<List<InstalledMusicSource>>(
        future: SourceRepository(connected.api).list(),
        builder: (context, snapshot) {
          final active = snapshot.data
              ?.where((item) => item.active)
              .firstOrNull;
          return ShadButton.outline(
            height: 44,
            padding: compact ? EdgeInsets.zero : null,
            onPressed: onSources,
            child: compact
                ? const Icon(LucideIcons.audioLines, size: 18)
                : SizedBox(
                    width: 125,
                    child: Row(
                      children: [
                        const _StatusDot(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            active?.name ?? '音源管理',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
      const SizedBox(height: AppSpacing.xs),
      ShadButton.outline(
        height: 44,
        padding: compact ? EdgeInsets.zero : null,
        onPressed: onDisconnect,
        child: compact
            ? const _StatusDot()
            : const SizedBox(
                width: 125,
                child: Row(
                  children: [
                    _StatusDot(),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Service 已连接',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ],
  );
}

final class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppTokens.of(context).success,
      boxShadow: [
        BoxShadow(color: AppTokens.of(context).success, blurRadius: 12),
      ],
    ),
  );
}
