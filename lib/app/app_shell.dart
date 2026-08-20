import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design/app_breakpoints.dart';
import '../design/components/app_navigation.dart';
import '../design/components/app_mobile_dock.dart';
import '../design/design_tokens.dart';
import '../features/connection/connection_repository.dart';
import '../features/player/mini_player.dart';
import '../features/player/current_track_actions_controller.dart';
import '../features/player/player_controller.dart';
import '../features/sources/source_repository.dart';
import '../platform/app_platform.dart';
import '../platform/desktop_window_controller.dart';
import '../platform/platform_window_frame.dart';

final class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.connected,
    this.onConnectionSettings,
    this.onDisconnect,
    required this.player,
    required this.child,
    this.currentTrackActions,
    this.location,
    this.onOpenPlayer,
    this.onBack,
    this.onForward,
    this.platform,
  });

  final ConnectedService connected;
  final VoidCallback? onConnectionSettings;
  @Deprecated(
    'Use onConnectionSettings; disconnect is no longer a footer action.',
  )
  final VoidCallback? onDisconnect;
  final PlayerController player;
  final CurrentTrackActionsController? currentTrackActions;
  final String? location;
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
    AppDestination(id: 'discover', label: '发现', icon: LucideIcons.compass),
    AppDestination(id: 'playlists', label: '我的音乐', icon: LucideIcons.heart),
    AppDestination(id: 'more', label: '更多', icon: LucideIcons.ellipsis),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final location = this.location ?? GoRouterState.of(context).uri.path;
    final showMiniPlayer = !location.startsWith('/player');
    final desktopSelectedId = navigationSelectionForLocation(location);
    final mobileSelectedId = navigationSelectionForLocation(
      location,
      mobile: true,
    );
    void navigate(String id) {
      if (child case final StatefulNavigationShell navigationShell) {
        final branchIndex = switch (id) {
          'home' => 0,
          'search' => 1,
          'discover' => 2,
          'playlists' => 3,
          'more' => 4,
          'square' => 5,
          'charts' => 6,
          'downloads' => 7,
          'settings' => 8,
          'sources' => 9,
          _ => null,
        };
        if (branchIndex != null) {
          navigationShell.goBranch(branchIndex, initialLocation: true);
          return;
        }
      }
      final target = switch (id) {
        'search' => '/search',
        'square' => '/square',
        'charts' => '/charts',
        'discover' => '/discover',
        'playlists' => '/playlists',
        'downloads' => '/downloads',
        'settings' => '/settings',
        'sources' => '/sources',
        'more' => '/more',
        _ => '/',
      };
      if (target == location) return;
      unawaited(context.push(target));
    }

    final openPlayer =
        onOpenPlayer ?? () => unawaited(context.pushNamed('player'));

    return Scaffold(
      key: const Key('main-shell'),
      backgroundColor: tokens.background,
      resizeToAvoidBottomInset:
          classifyLayout(MediaQuery.sizeOf(context)) != AppLayoutClass.mobile,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = classifyLayout(MediaQuery.sizeOf(context));
          final resolvedPlatform =
              platform ?? resolveAppPlatform(Theme.of(context).platform);
          if (layout == AppLayoutClass.mobile) {
            final mobileShell = Scaffold(
              key: const Key('mobile-shell-scaffold'),
              backgroundColor: Colors.transparent,
              extendBody: false,
              resizeToAvoidBottomInset: false,
              body: SafeArea(bottom: false, child: child),
              bottomNavigationBar: showMiniPlayer
                  ? AppMobileDock(
                      player: player,
                      destinations: _mobileDestinations,
                      selectedId: mobileSelectedId,
                      onSelected: navigate,
                      onOpenPlayer: openPlayer,
                      showNavigation: showsMobilePrimaryNavigation(location),
                    )
                  : null,
            );
            return PlatformWindowFrame(
              platform: resolvedPlatform,
              location: location,
              controller: desktopWindowController,
              onBack: onBack,
              onForward: onForward,
              onSearch: () => unawaited(context.push('/search')),
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
            onSearch: () => unawaited(context.push('/search')),
            desktopSidebarWidth: compact ? 84 : 208,
            child: Row(
              children: [
                AppDesktopNavigation(
                  destinations: _desktopDestinations,
                  selectedId: desktopSelectedId,
                  compact: compact,
                  onSelected: navigate,
                  footer: _ConnectionFooter(
                    connected: connected,
                    compact: compact,
                    onSources: () => navigate('sources'),
                    onConnectionSettings: onConnectionSettings ?? () {},
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
                                  actions: currentTrackActions,
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

const _mobilePrimaryLocations = <String>{
  '/',
  '/search',
  '/discover',
  '/playlists',
  '/more',
};

bool showsMobilePrimaryNavigation(String location) =>
    _mobilePrimaryLocations.contains(location);

String navigationSelectionForLocation(String location, {bool mobile = false}) {
  if (location.startsWith('/search')) return 'search';
  if (location.startsWith('/playlists') || location.startsWith('/library')) {
    return 'playlists';
  }
  if (location.startsWith('/discover')) return 'discover';
  if (location.startsWith('/downloads')) return mobile ? 'more' : 'downloads';
  if (location.startsWith('/square')) return mobile ? 'discover' : 'square';
  if (location.startsWith('/charts')) return mobile ? 'discover' : 'charts';
  if (location.startsWith('/settings')) return mobile ? 'more' : 'settings';
  if (location.startsWith('/sources')) return mobile ? 'more' : 'sources';
  if (location.startsWith('/more')) return 'more';
  if (location.startsWith('/states')) return 'states';
  return 'home';
}

final class _ConnectionFooter extends StatelessWidget {
  const _ConnectionFooter({
    required this.connected,
    required this.onConnectionSettings,
    required this.onSources,
    required this.compact,
  });

  final ConnectedService connected;
  final VoidCallback onConnectionSettings;
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
        onPressed: onConnectionSettings,
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
