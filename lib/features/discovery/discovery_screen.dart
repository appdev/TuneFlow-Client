import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import '../playlists/playlist_repository.dart';
import '../search/track_action.dart';
import '../search/search_repository.dart';
import 'playlist_discovery_controller.dart';
import 'playlist_discovery_view.dart';

enum DiscoveryKind { playlists, charts }

final class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    required this.repository,
    required this.kind,
    required this.onSearch,
    this.onOpenPlaylist,
    this.playTracks,
    this.playlists,
  });

  final SearchRepository repository;
  final DiscoveryKind kind;
  final VoidCallback onSearch;
  final ValueChanged<CatalogCollection>? onOpenPlaylist;
  final Future<void> Function(List<Track> tracks)? playTracks;
  final PlaylistRepository? playlists;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

final class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late Future<CatalogCapabilities> capabilities = widget.repository
      .capabilities();
  String? selectedProvider;
  PlaylistDiscoveryController? playlistController;

  @override
  void initState() {
    super.initState();
    if (widget.kind == DiscoveryKind.playlists) {
      playlistController = PlaylistDiscoveryController(widget.repository);
    }
  }

  void retry() =>
      setState(() => capabilities = widget.repository.capabilities());

  Future<void> _choosePlaylist(Track track) async {
    final repository = widget.playlists;
    if (repository == null) return;
    final playlists = await repository.list();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: '添加到歌单',
      child: playlists.isEmpty
          ? const AppEmptyState(message: '还没有歌单')
          : ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return AppButton(
                  variant: ShadButtonVariant.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(_addTrack(repository, playlist, track));
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(playlist.name),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addTrack(
    PlaylistRepository repository,
    PlaylistSummary playlist,
    Track track,
  ) async {
    try {
      await repository.addTracks(playlist.id, [track]);
      if (!mounted) return;
      showAppMessage(context, title: '完成', message: '已添加到 ${playlist.name}');
    } on Object {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '添加失败',
        message: '暂时无法添加到该歌单，请稍后重试。',
        destructive: true,
      );
    }
  }

  @override
  void dispose() {
    playlistController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile =
        classifyLayout(MediaQuery.sizeOf(context).width) ==
        AppLayoutClass.mobile;
    final charts = widget.kind == DiscoveryKind.charts;
    if (!charts) {
      return PlaylistDiscoveryView(
        controller: playlistController!,
        onOpenPlaylist:
            widget.onOpenPlaylist ?? (playlist) => widget.onSearch(),
      );
    }
    return ColoredBox(
      key: Key(charts ? 'charts-layout' : 'playlist-square-layout'),
      color: AppTokens.of(context).background,
      child: FutureBuilder<CatalogCapabilities>(
        future: capabilities,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: EdgeInsets.all(mobile ? 18 : 34),
              children: [
                AppNotice.error(
                  title: '无法读取平台能力',
                  message: snapshot.error.toString(),
                ),
                const SizedBox(height: 12),
                AppButton(
                  variant: ShadButtonVariant.outline,
                  onPressed: retry,
                  child: const Text('重试'),
                ),
              ],
            );
          }
          final providers = snapshot.data!.providers
              .where((provider) => provider.leaderboards)
              .toList(growable: false);
          if (providers.isEmpty) return const _Unavailable();
          selectedProvider ??= providers.first.id;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 38,
              mobile ? 20 : 34,
              mobile ? 16 : 38,
              48,
            ),
            children: [
              _PageHeader(charts: charts, mobile: mobile),
              const SizedBox(height: 18),
              _ProviderChips(
                providers: providers,
                selected: selectedProvider!,
                onSelected: (value) => setState(() => selectedProvider = value),
              ),
              SizedBox(height: mobile ? 16 : 28),
              _LeaderboardView(
                key: ValueKey(selectedProvider),
                repository: widget.repository,
                source: selectedProvider!,
                mobile: mobile,
                playTracks: widget.playTracks,
                onFavorite: widget.playlists == null ? null : _choosePlaylist,
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.charts, required this.mobile});
  final bool charts;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        charts ? '每天更新' : '动态平台 · Service API',
        style: AppTypography.metadata.copyWith(
          color: AppTokens.of(context).muted,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        charts ? '排行榜' : '歌单广场',
        style: mobile
            ? AppTypography.display.copyWith(fontSize: 31)
            : AppTypography.display,
      ),
    ],
  );
}

final class _ProviderChips extends StatelessWidget {
  const _ProviderChips({
    required this.providers,
    required this.selected,
    required this.onSelected,
  });
  final List<CatalogProvider> providers;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final provider in providers) ...[
          AppButton(
            variant: selected == provider.id
                ? ShadButtonVariant.primary
                : ShadButtonVariant.outline,
            onPressed: () => onSelected(provider.id),
            child: Text(provider.name.replaceAll('音乐', '')),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

final class _LeaderboardView extends StatefulWidget {
  const _LeaderboardView({
    super.key,
    required this.repository,
    required this.source,
    required this.mobile,
    this.playTracks,
    this.onFavorite,
  });
  final SearchRepository repository;
  final String source;
  final bool mobile;
  final Future<void> Function(List<Track> tracks)? playTracks;
  final Future<void> Function(Track track)? onFavorite;

  @override
  State<_LeaderboardView> createState() => _LeaderboardViewState();
}

final class _LeaderboardViewState extends State<_LeaderboardView> {
  late final Future<LeaderboardPage> boards = widget.repository.leaderboards(
    source: widget.source,
  );
  Leaderboard? selected;

  Future<LeaderboardTrackPage> tracks(Leaderboard board) =>
      widget.repository.leaderboardTracks(
        source: widget.source,
        boardId: board.providerId,
        page: 1,
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<LeaderboardPage>(
    future: boards,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return AppNotice.error(
          title: '排行榜加载失败',
          message: snapshot.error.toString(),
        );
      }
      if (snapshot.data!.items.isEmpty) return const Text('当前音源没有返回排行榜');
      selected ??= snapshot.data!.items.first;
      return _buildContent(context, snapshot.data!.items, selected!);
    },
  );

  Widget _buildContent(
    BuildContext context,
    List<Leaderboard> boards,
    Leaderboard active,
  ) {
    final charts = Column(
      children: [
        for (final board in boards.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppButton(
              variant: board.id == active.id
                  ? ShadButtonVariant.secondary
                  : ShadButtonVariant.outline,
              onPressed: () => setState(() => selected = board),
              child: SizedBox(
                width: widget.mobile
                    ? MediaQuery.sizeOf(context).width - 80
                    : 190,
                child: Row(
                  children: [
                    if (!widget.mobile) ...[
                      const Icon(
                        LucideIcons.chartNoAxesColumnIncreasing,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(board.name, overflow: TextOverflow.ellipsis),
                    ),
                    Text(board.id == active.id && widget.mobile ? '当前' : '›'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    final trackList = FutureBuilder<LeaderboardTrackPage>(
      key: ValueKey(active.id),
      future: tracks(active),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppNotice.error(
            title: '榜单歌曲加载失败',
            message: snapshot.error.toString(),
          );
        }
        final items = snapshot.data!.tracks;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(active.name, style: AppTypography.section),
                        Text(
                          '${items.length} 首 · ${widget.source}',
                          style: AppTypography.metadata,
                        ),
                      ],
                    ),
                  ),
                  if (items.isNotEmpty && widget.playTracks != null)
                    AppButton(
                      onPressed: () => widget.playTracks!(items),
                      child: const Text('播放全部'),
                    ),
                ],
              ),
            ),
            if (!widget.mobile)
              CatalogTrackTableHeader(
                showAlbum: false,
                showDuration: true,
                compact: true,
                showFavorite: widget.onFavorite != null,
              ),
            for (final entry in items.indexed)
              if (widget.mobile)
                _MobileLeaderboardTrack(
                  track: entry.$2,
                  onPlay: widget.playTracks == null
                      ? null
                      : () => unawaited(widget.playTracks!([entry.$2])),
                )
              else
                CatalogTrackRow(
                  index: entry.$1 + 1,
                  track: entry.$2,
                  providers: const [],
                  aggregate: false,
                  showAlbum: false,
                  showDuration: true,
                  compact: true,
                  loadPicture: (track) async {
                    final embedded = track.raw['pic'];
                    return embedded is String ? Uri.tryParse(embedded) : null;
                  },
                  onPlay: () {
                    if (widget.playTracks case final play?) {
                      unawaited(play([entry.$2]));
                    }
                  },
                  onFavorite: widget.onFavorite == null
                      ? null
                      : () => unawaited(widget.onFavorite!(entry.$2)),
                  actions: [
                    if (widget.playTracks != null)
                      TrackAction(
                        id: TrackActionId.playNow,
                        label: '立即播放',
                        icon: LucideIcons.play,
                        invoke: () => widget.playTracks!([entry.$2]),
                      ),
                    if (widget.onFavorite != null)
                      TrackAction(
                        id: TrackActionId.addToPlaylist,
                        label: '添加到歌单',
                        icon: LucideIcons.heartPlus,
                        invoke: () => widget.onFavorite!(entry.$2),
                      ),
                  ],
                  reserveFavoriteSpace: widget.onFavorite != null,
                  rowKeyPrefix: 'leaderboard',
                  singleTap: true,
                ),
          ],
        );
      },
    );
    if (widget.mobile) {
      return Column(children: [charts, const SizedBox(height: 8), trackList]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTokens.of(context).surface,
              border: Border.all(color: AppTokens.of(context).border),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: charts,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: trackList),
      ],
    );
  }
}

final class _MobileLeaderboardTrack extends StatelessWidget {
  const _MobileLeaderboardTrack({required this.track, required this.onPlay});

  final Track track;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPlay,
    child: Container(
      height: 62,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTokens.of(context).border)),
      ),
      child: Row(
        children: [
          AppArtwork(
            imageUrl: track.raw['pic'] is String
                ? track.raw['pic']! as String
                : null,
            seed: track.id,
            semanticLabel: '${track.title}封面',
            size: 42,
            borderRadius: 9,
            showFallback: false,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, style: AppTypography.title),
                Text(
                  track.artist,
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).foregroundSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.ellipsis, size: 18),
        ],
      ),
    ),
  );
}

final class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleOff, color: AppTokens.of(context).muted),
          const SizedBox(height: 12),
          const Text('当前音源未提供歌单能力', style: AppTypography.section),
          const SizedBox(height: 6),
          const Text('切换音源后可再次检查。'),
        ],
      ),
    ),
  );
}
