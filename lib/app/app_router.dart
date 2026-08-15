import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../design/app_breakpoints.dart';
import '../features/connection/connection_repository.dart';
import '../features/connection/connection_screen.dart';
import '../features/downloads/download_repository.dart';
import '../features/downloads/downloads_controller.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/discovery/album_detail_controller.dart';
import '../features/discovery/album_detail_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/discovery/discovery_hub_screen.dart';
import '../features/discovery/online_playlist_detail_controller.dart';
import '../features/discovery/online_playlist_detail_screen.dart';
import '../features/home/home_controller.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_repository.dart';
import '../features/library/local_library_controller.dart';
import '../features/library/local_library_screen.dart';
import '../features/more/more_screen.dart';
import '../features/player/player_controller.dart';
import '../features/player/current_track_actions_controller.dart';
import '../features/player/player_screen.dart';
import '../features/player/wake_lock_port.dart';
import '../features/playback_history/playback_history_repository.dart';
import '../features/playback_history/playback_platform.dart';
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

ValueKey<String> sourceRouteKey(int version) => ValueKey('sources-$version');

GoRouter buildAppRouter({
  required AsyncValue<ConnectedService?> Function() readConnection,
  required PlayerController? Function() readPlayer,
  required CurrentTrackActionsController? Function() readCurrentTrackActions,
  required bool Function() readKeepAwake,
  required SettingsController? Function() readSettings,
  required int Function() readSourceVersion,
  required int Function() readPlaylistVersion,
  required int Function() readDownloadVersion,
  required int Function() readLibraryVersion,
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
  CurrentTrackActionsController requireCurrentTrackActions() =>
      readCurrentTrackActions()!;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    await requirePlayer().playTracks(tracks, startIndex: startIndex);
  }

  Widget onlinePlaylistRoute(GoRouterState state) {
    final connected = requireConnected();
    final source = state.pathParameters['source']!;
    final playlistId = state.pathParameters['playlistId']!;
    return OnlinePlaylistDetailScreen(
      key: ValueKey('online-playlist-$source-$playlistId'),
      controller: OnlinePlaylistDetailController(
        catalog: SearchRepository(connected.api),
        playlists: PlaylistRepository(connected.api),
        source: source,
        playlistId: playlistId,
        initialPlaylist: state.extra is CatalogCollection
            ? state.extra! as CatalogCollection
            : null,
      ),
      player: requirePlayer(),
      downloads: DownloadRepository(connected.api),
    );
  }

  Widget localLibraryRoute() {
    final connected = requireConnected();
    return LocalLibraryScreen(
      key: ValueKey('local-library-${readLibraryVersion()}'),
      controller: LocalLibraryController(LibraryRepository(connected.api)),
      playlists: PlaylistRepository(connected.api),
      playTracks: playTracks,
    );
  }

  Widget downloadsRoute() => DownloadsScreen(
    key: ValueKey('downloads-${readDownloadVersion()}'),
    controller: DownloadsController(DownloadRepository(requireConnected().api)),
  );

  Widget sourcesRoute() => SourcesScreen(
    key: sourceRouteKey(readSourceVersion()),
    controller: SourcesController(SourceRepository(requireConnected().api)),
  );

  bool isMobileLayout(BuildContext context) =>
      classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;

  void openDownloads(BuildContext context) =>
      context.goNamed(isMobileLayout(context) ? 'more-downloads' : 'downloads');

  void openSettings(BuildContext context) =>
      context.goNamed(isMobileLayout(context) ? 'more-settings' : 'settings');

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
      child: _PlayerRouteCanvas(
        platform: platform,
        player: requirePlayer(),
        actions: requireCurrentTrackActions(),
        lyricsLoader: SearchRepository(connected.api).lyrics,
        playlists: PlaylistRepository(connected.api),
        keepAwake: readKeepAwake(),
        onBack: closePlayer,
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
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
            currentTrackActions: requireCurrentTrackActions(),
            location: state.uri.path,
            onOpenPlayer: () => openPlayer(context),
            onBack: navigationHistory.canGoBack
                ? () => navigateTo(navigationHistory.goBack())
                : null,
            onForward: navigationHistory.canGoForward
                ? () => navigateTo(navigationHistory.goForward())
                : null,
            child: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                builder: (context, state) {
                  final connected = requireConnected();
                  return KeyedSubtree(
                    key: ValueKey(
                      'home-${readPlaylistVersion()}-'
                      '${readDownloadVersion()}-${readLibraryVersion()}',
                    ),
                    child: HomeScreen(
                      key: const Key('home-route'),
                      controller: HomeController(
                        playlists: PlaylistRepository(connected.api),
                        downloads: DownloadRepository(connected.api),
                        library: LibraryRepository(connected.api),
                        history: PlaybackHistoryRepository(
                          connected.api,
                          platform: currentPlaybackPlatform(),
                        ),
                      ),
                      onSearch: () => context.goNamed('search'),
                      onPlaylists: () => context.goNamed('playlists'),
                      onDownloads: () => openDownloads(context),
                      onSettings: () => openSettings(context),
                      player: requirePlayer(),
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                builder: (context, state) {
                  final connected = requireConnected();
                  final controller = feature.SearchController(
                    SearchRepository(connected.api),
                  );
                  return SearchScreen(
                    controller: controller,
                    playlists: PlaylistRepository(connected.api),
                    downloads: DownloadRepository(connected.api),
                    player: requirePlayer(),
                    onSettings: () => openSettings(context),
                    onOpenCollection: (collection) {
                      if (collection.kind == CatalogSearchKind.playlist) {
                        context.pushNamed(
                          'search-online-playlist',
                          pathParameters: {
                            'source': collection.source,
                            'playlistId': collection.id,
                          },
                          extra: collection,
                        );
                        return;
                      }
                      final provider = controller.state.providers
                          .where((item) => item.id == collection.source)
                          .firstOrNull;
                      context.pushNamed(
                        'album-detail',
                        pathParameters: {
                          'source': collection.source,
                          'albumId': collection.id,
                        },
                        extra: AlbumDetailRouteArgs(
                          album: collection,
                          supported: provider?.albumDetail == true,
                        ),
                      );
                    },
                  );
                },
                routes: [
                  GoRoute(
                    path: 'playlist/:source/:playlistId',
                    name: 'search-online-playlist',
                    builder: (context, state) => onlinePlaylistRoute(state),
                  ),
                  GoRoute(
                    path: 'album/:source/:albumId',
                    name: 'album-detail',
                    builder: (context, state) {
                      final connected = requireConnected();
                      final source = state.pathParameters['source']!;
                      final albumId = state.pathParameters['albumId']!;
                      final args = state.extra is AlbumDetailRouteArgs
                          ? state.extra! as AlbumDetailRouteArgs
                          : AlbumDetailRouteArgs(
                              album: CatalogCollection(
                                id: albumId,
                                kind: CatalogSearchKind.album,
                                name: albumId,
                                source: source,
                              ),
                              supported: false,
                            );
                      return AlbumDetailScreen(
                        key: ValueKey('album-$source-$albumId'),
                        controller: AlbumDetailController(
                          catalog: SearchRepository(connected.api),
                          source: source,
                          albumId: albumId,
                          supported: args.supported,
                          initialAlbum: args.album,
                        ),
                        player: requirePlayer(),
                        playlists: PlaylistRepository(connected.api),
                        downloads: DownloadRepository(connected.api),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                name: 'discover',
                builder: (context, state) => DiscoveryHubScreen(
                  repository: SearchRepository(requireConnected().api),
                  playlists: PlaylistRepository(requireConnected().api),
                  playTracks: playTracks,
                  onOpenPlaylist: (playlist) => context.pushNamed(
                    'discover-online-playlist',
                    pathParameters: {
                      'source': playlist.source,
                      'playlistId': playlist.id,
                    },
                    extra: playlist,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'playlist/:source/:playlistId',
                    name: 'discover-online-playlist',
                    builder: (context, state) => onlinePlaylistRoute(state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playlists',
                name: 'playlists',
                builder: (context, state) {
                  final connected = requireConnected();
                  return PlaylistsScreen(
                    key: ValueKey(
                      'playlists-${readPlaylistVersion()}-'
                      '${readLibraryVersion()}',
                    ),
                    controller: PlaylistsController(
                      PlaylistRepository(connected.api),
                      library: LibraryRepository(connected.api),
                    ),
                    onOpen: (id) => context.pushNamed(
                      'playlist',
                      pathParameters: {'id': id},
                    ),
                    onOpenLocal: () => context.pushNamed('local-library'),
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
                        onDeleted: () => context.canPop()
                            ? context.pop()
                            : context.goNamed('playlists'),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: '/library',
                name: 'local-library',
                builder: (context, state) => localLibraryRoute(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                name: 'more',
                builder: (context, state) {
                  final connected = requireConnected();
                  return MoreScreen(
                    serviceHost: connected.origin.uri.host,
                    onSources: () => context.pushNamed('more-sources'),
                    onSettings: () => context.pushNamed('more-settings'),
                    onDownloads: () => context.pushNamed('more-downloads'),
                    onDisconnect: disconnect,
                  );
                },
                routes: [
                  GoRoute(
                    path: 'downloads',
                    name: 'more-downloads',
                    builder: (context, state) => downloadsRoute(),
                  ),
                  GoRoute(
                    path: 'settings',
                    name: 'more-settings',
                    builder: (context, state) =>
                        SettingsScreen(controller: readSettings()!),
                  ),
                  GoRoute(
                    path: 'sources',
                    name: 'more-sources',
                    builder: (context, state) => sourcesRoute(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/square',
                name: 'square',
                builder: (context, state) => DiscoveryScreen(
                  repository: SearchRepository(requireConnected().api),
                  kind: DiscoveryKind.playlists,
                  onSearch: () => context.goNamed('search'),
                  playlists: PlaylistRepository(requireConnected().api),
                  onOpenPlaylist: (playlist) => context.pushNamed(
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
                    builder: (context, state) => onlinePlaylistRoute(state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                name: 'downloads',
                builder: (context, state) => downloadsRoute(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) =>
                    SettingsScreen(controller: readSettings()!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sources',
                name: 'sources',
                builder: (context, state) => sourcesRoute(),
              ),
            ],
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

final class _PlayerRouteCanvas extends StatefulWidget {
  const _PlayerRouteCanvas({
    required this.platform,
    required this.player,
    required this.actions,
    required this.lyricsLoader,
    required this.playlists,
    required this.keepAwake,
    required this.onBack,
  });

  final AppPlatform platform;
  final PlayerController player;
  final CurrentTrackActionsController actions;
  final Future<Lyrics> Function(Track track) lyricsLoader;
  final PlaylistRepository playlists;
  final bool keepAwake;
  final VoidCallback onBack;

  @override
  State<_PlayerRouteCanvas> createState() => _PlayerRouteCanvasState();
}

final class _PlayerRouteCanvasState extends State<_PlayerRouteCanvas> {
  Color? accent;

  void updateAccent(Color next) {
    if (accent == next) return;
    setState(() => accent = next);
  }

  @override
  Widget build(BuildContext context) => PlatformWindowFrame(
    platform: widget.platform,
    location: '/player',
    controller: desktopWindowController,
    onBack: widget.onBack,
    playerAccent: accent,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayerScreen(
        controller: widget.player,
        actions: widget.actions,
        lyricsLoader: widget.lyricsLoader,
        playlists: widget.playlists,
        wakeLock: const SystemWakeLock(),
        keepAwake: widget.keepAwake,
        onBack: widget.onBack,
        topChromeInset: widget.platform.isDesktop ? 38 : 0,
        onAccentChanged: updateAccent,
      ),
    ),
  );
}
