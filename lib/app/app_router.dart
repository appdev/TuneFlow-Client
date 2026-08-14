import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../features/connection/connection_repository.dart';
import '../features/connection/connection_screen.dart';
import '../features/downloads/download_repository.dart';
import '../features/downloads/downloads_controller.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/discovery/online_playlist_detail_controller.dart';
import '../features/discovery/online_playlist_detail_screen.dart';
import '../features/home/home_controller.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_repository.dart';
import '../features/more/more_screen.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_screen.dart';
import '../features/player/wake_lock_port.dart';
import '../features/playback_history/playback_history_repository.dart';
import '../features/playlists/playlist_detail_controller.dart';
import '../features/playlists/playlist_detail_screen.dart';
import '../features/playlists/playlist_repository.dart';
import '../features/playlists/playlists_controller.dart';
import '../features/playlists/playlists_screen.dart';
import '../features/search/search_repository.dart';
import '../features/search/search_controller.dart' as feature;
import '../features/search/search_screen.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/sources/source_repository.dart';
import '../features/sources/sources_controller.dart';
import '../features/sources/sources_screen.dart';
import '../platform/app_platform.dart';
import '../platform/desktop_window_controller.dart';
import '../platform/platform_window_frame.dart';
import 'app_shell.dart';
import 'app_navigation_history.dart';

GoRouter buildAppRouter({
  required AsyncValue<ConnectedService?> Function() readConnection,
  required PlayerController? Function() readPlayer,
  required bool Function() readKeepAwake,
  required SettingsController? Function() readSettings,
  required int Function() readPlaylistVersion,
  required int Function() readDownloadVersion,
  required int Function(String id) readPlaylistDetailVersion,
  required Listenable refreshListenable,
  required Future<void> Function() disconnect,
}) {
  final connection = readConnection();
  final connected = connection.value;
  final initialLocation = connected == null ? '/connect' : '/';
  final navigationHistory = AppNavigationHistory();

  ConnectedService requireConnected() => readConnection().value!;
  PlayerController requirePlayer() => readPlayer()!;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    await requirePlayer().playTracks(tracks, startIndex: startIndex);
  }

  Widget playerRoute(BuildContext context) {
    final connected = requireConnected();
    final platform = resolveAppPlatform(Theme.of(context).platform);

    void closePlayer() {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        context.go('/');
      }
    }

    return KeyedSubtree(
      key: const Key('player-route'),
      child: PlatformWindowFrame(
        platform: platform,
        location: '/player',
        controller: desktopWindowController,
        onBack: closePlayer,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: PlayerScreen(
            controller: requirePlayer(),
            lyricsLoader: SearchRepository(connected.api).lyrics,
            wakeLock: const SystemWakeLock(),
            keepAwake: readKeepAwake(),
            onBack: closePlayer,
            topChromeInset: platform.isDesktop ? 38 : 0,
          ),
        ),
      ),
    );
  }

  void openPlayer(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(MaterialPageRoute<void>(builder: playerRoute));
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final connection = readConnection();
      final connected = connection.value;
      if (connection.isLoading) {
        return state.matchedLocation == '/connect' ? null : '/connect';
      }
      if (connected == null) {
        return state.matchedLocation == '/connect' ? null : '/connect';
      }
      if (state.matchedLocation == '/connect') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/connect',
        name: 'connection',
        builder: (context, state) => const ConnectionScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final connected = requireConnected();
          navigationHistory.record(state.uri, extra: state.extra);

          void navigateTo(AppNavigationEntry? entry) {
            if (entry == null) return;
            context.go(entry.uri.toString(), extra: entry.extra);
          }

          return AppShell(
            key: ObjectKey(connected),
            connected: connected,
            onDisconnect: disconnect,
            player: requirePlayer(),
            onOpenPlayer: () => openPlayer(context),
            onBack: navigationHistory.canGoBack
                ? () => navigateTo(navigationHistory.goBack())
                : null,
            onForward: navigationHistory.canGoForward
                ? () => navigateTo(navigationHistory.goForward())
                : null,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) {
              final connected = requireConnected();
              return KeyedSubtree(
                key: ValueKey(
                  'home-${readPlaylistVersion()}-${readDownloadVersion()}',
                ),
                child: HomeScreen(
                  key: const Key('home-route'),
                  controller: HomeController(
                    playlists: PlaylistRepository(connected.api),
                    downloads: DownloadRepository(connected.api),
                    library: LibraryRepository(connected.api),
                    history: PlaybackHistoryRepository(connected.api),
                  ),
                  onSearch: () => context.goNamed('search'),
                  onPlaylists: () => context.goNamed('playlists'),
                  onDownloads: () => context.goNamed('downloads'),
                  onSettings: () => context.goNamed('settings'),
                  player: requirePlayer(),
                ),
              );
            },
          ),
          GoRoute(
            path: '/search',
            name: 'search',
            builder: (context, state) {
              final connected = requireConnected();
              return SearchScreen(
                controller: feature.SearchController(
                  SearchRepository(connected.api),
                ),
                playlists: PlaylistRepository(connected.api),
                downloads: DownloadRepository(connected.api),
                player: requirePlayer(),
                onSettings: () => context.goNamed('settings'),
              );
            },
          ),
          GoRoute(
            path: '/square',
            name: 'square',
            builder: (context, state) => DiscoveryScreen(
              repository: SearchRepository(requireConnected().api),
              kind: DiscoveryKind.playlists,
              onSearch: () => context.goNamed('search'),
              playlists: PlaylistRepository(requireConnected().api),
              onOpenPlaylist: (playlist) => context.goNamed(
                'online-playlist',
                pathParameters: {
                  'source': playlist.source,
                  'playlistId': playlist.id,
                },
                extra: playlist,
              ),
              playTracks: playTracks,
            ),
            routes: [
              GoRoute(
                path: ':source/:playlistId',
                name: 'online-playlist',
                builder: (context, state) {
                  final connected = requireConnected();
                  final catalog = SearchRepository(connected.api);
                  final playlists = PlaylistRepository(connected.api);
                  return OnlinePlaylistDetailScreen(
                    key: ValueKey(
                      'online-playlist-${state.pathParameters['source']}-'
                      '${state.pathParameters['playlistId']}',
                    ),
                    controller: OnlinePlaylistDetailController(
                      catalog: catalog,
                      playlists: playlists,
                      source: state.pathParameters['source']!,
                      playlistId: state.pathParameters['playlistId']!,
                      initialPlaylist: state.extra is CatalogCollection
                          ? state.extra! as CatalogCollection
                          : null,
                    ),
                    player: requirePlayer(),
                    downloads: DownloadRepository(connected.api),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/charts',
            name: 'charts',
            builder: (context, state) => DiscoveryScreen(
              repository: SearchRepository(requireConnected().api),
              kind: DiscoveryKind.charts,
              onSearch: () => context.goNamed('search'),
              playTracks: playTracks,
              playlists: PlaylistRepository(requireConnected().api),
            ),
          ),
          GoRoute(
            path: '/playlists',
            name: 'playlists',
            builder: (context, state) {
              final connected = requireConnected();
              return PlaylistsScreen(
                key: ValueKey('playlists-${readPlaylistVersion()}'),
                controller: PlaylistsController(
                  PlaylistRepository(connected.api),
                ),
                onOpen: (id) =>
                    context.goNamed('playlist', pathParameters: {'id': id}),
              );
            },
            routes: [
              GoRoute(
                path: ':id',
                name: 'playlist',
                builder: (context, state) {
                  final connected = requireConnected();
                  final id = state.pathParameters['id']!;
                  return PlaylistDetailScreen(
                    key: ValueKey(
                      'playlist-$id-${readPlaylistDetailVersion(id)}',
                    ),
                    controller: PlaylistDetailController(
                      PlaylistRepository(connected.api),
                      id,
                    ),
                    playTracks: playTracks,
                    onDeleted: () => context.goNamed('playlists'),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/downloads',
            name: 'downloads',
            builder: (context, state) => DownloadsScreen(
              key: ValueKey('downloads-${readDownloadVersion()}'),
              controller: DownloadsController(
                DownloadRepository(requireConnected().api),
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) =>
                SettingsScreen(controller: readSettings()!),
          ),
          GoRoute(
            path: '/sources',
            name: 'sources',
            builder: (context, state) => SourcesScreen(
              controller: SourcesController(
                SourceRepository(requireConnected().api),
              ),
            ),
          ),
          GoRoute(
            path: '/more',
            name: 'more',
            builder: (context, state) {
              final connected = requireConnected();
              return MoreScreen(
                serviceHost: connected.origin.uri.host,
                onSources: () => context.goNamed('sources'),
                onSettings: () => context.goNamed('settings'),
                onSquare: () => context.goNamed('square'),
                onCharts: () => context.goNamed('charts'),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        builder: (context, state) => playerRoute(context),
      ),
    ],
  );
}
