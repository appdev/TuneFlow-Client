import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/track_actions.dart';
import '../../design/design_tokens.dart';
import '../playlists/playlist_repository.dart';
import '../search/search_repository.dart';
import 'discovery_screen.dart';
import 'playlist_discovery_controller.dart';
import 'playlist_discovery_view.dart';

final class DiscoveryHubScreen extends StatefulWidget {
  const DiscoveryHubScreen({
    super.key,
    required this.repository,
    required this.playlists,
    required this.playTracks,
    required this.onOpenPlaylist,
  });

  final SearchRepository repository;
  final PlaylistRepository playlists;
  final PlayTracks playTracks;
  final ValueChanged<CatalogCollection> onOpenPlaylist;

  @override
  State<DiscoveryHubScreen> createState() => _DiscoveryHubScreenState();
}

final class _DiscoveryHubScreenState extends State<DiscoveryHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final PlaylistDiscoveryController _playlists =
      PlaylistDiscoveryController(widget.repository);

  @override
  void dispose() {
    _tabs.dispose();
    _playlists.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('discovery-hub-route'),
    color: AppTokens.of(context).background,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: AppMobilePageHeader(title: '发现'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(key: Key('discovery-tab-playlists'), text: '歌单广场'),
              Tab(key: Key('discovery-tab-charts'), text: '排行榜'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            key: const Key('discovery-tab-view'),
            controller: _tabs,
            children: [
              PlaylistDiscoveryView(
                controller: _playlists,
                embedded: true,
                onOpenPlaylist: widget.onOpenPlaylist,
              ),
              DiscoveryScreen(
                repository: widget.repository,
                kind: DiscoveryKind.charts,
                onSearch: () {},
                playTracks: widget.playTracks,
                playlists: widget.playlists,
                embedded: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
