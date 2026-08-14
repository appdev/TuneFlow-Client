import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_states.dart';
import '../../design/app_theme_definition.dart';
import '../../design/design_tokens.dart';
import '../downloads/download_repository.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_repository.dart';
import 'adaptive_track_actions.dart';
import 'search_controller.dart';
import 'search_desktop_results.dart';
import 'search_history_panel.dart';
import 'search_history_repository.dart';
import 'search_mobile_results.dart';
import 'search_track_metadata.dart';
import 'track_action.dart';

final class SearchScreen extends StatefulWidget {
  SearchScreen({
    super.key,
    required this.controller,
    required this.playlists,
    required this.downloads,
    required this.player,
    this.onSettings,
    SearchHistoryRepository? history,
  }) : history = history ?? SearchHistoryRepository();

  final SearchController controller;
  final PlaylistRepository playlists;
  final DownloadRepository downloads;
  final PlayerController player;
  final VoidCallback? onSettings;
  final SearchHistoryRepository history;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  String selectedSource = 'kw';
  var mobileLayout = false;
  List<String> historyItems = const [];
  var historyDismissed = false;

  bool get showHistory =>
      searchFocus.hasFocus &&
      query.text.trim().isEmpty &&
      historyItems.isNotEmpty &&
      !historyDismissed;

  @override
  void initState() {
    super.initState();
    query.text = widget.controller.state.query;
    selectedSource = widget.controller.state.source;
    scroll.addListener(_loadMore);
    query.addListener(_historyChanged);
    searchFocus.addListener(_historyChanged);
    unawaited(_loadHistory());
    unawaited(
      widget.controller.loadCapabilities().then((_) {
        if (!mounted) return;
        setState(() {
          selectedSource = mobileLayout && query.text.trim().isEmpty
              ? SearchController.aggregateSource
              : widget.controller.state.source;
        });
      }),
    );
  }

  Future<void> _loadHistory() async {
    final items = await widget.history.load();
    if (mounted) setState(() => historyItems = items);
  }

  void _historyChanged() {
    if (!mounted) return;
    if (query.text.isNotEmpty) historyDismissed = false;
    setState(() {});
  }

  void _loadMore() {
    if (mobileLayout && scroll.position.extentAfter < 240) {
      unawaited(widget.controller.loadNextPage());
    }
  }

  Future<void> _search({String? submittedKeyword}) async {
    final keyword = (submittedKeyword ?? query.text).trim();
    final search = widget.controller.search(
      source: selectedSource,
      query: keyword,
    );
    if (keyword.isNotEmpty) {
      final items = await widget.history.record(keyword);
      if (mounted) {
        setState(() {
          historyItems = items;
          historyDismissed = true;
        });
      }
    }
    await search;
  }

  Future<void> _selectHistory(String keyword) async {
    setState(() {
      query.value = TextEditingValue(
        text: keyword,
        selection: TextSelection.collapsed(offset: keyword.length),
      );
      historyDismissed = true;
    });
    searchFocus.unfocus();
    await _search(submittedKeyword: keyword);
  }

  Future<void> _removeHistory(String keyword) async {
    final items = await widget.history.remove(keyword);
    if (mounted) setState(() => historyItems = items);
  }

  Future<void> _clearHistory() async {
    final items = await widget.history.clear();
    if (mounted) setState(() => historyItems = items);
  }

  Future<void> _play(Track track) async {
    final embedded = track.raw['pic'];
    if (embedded is String && embedded.isNotEmpty) {
      await widget.player.play(track);
      return;
    }
    final picture = await widget.controller.loadPicture(track);
    final playable = picture == null
        ? track
        : Track.fromJson({...track.toJson(), 'pic': picture.toString()});
    await widget.player.play(playable);
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
    String? successTitle,
  }) async {
    try {
      await action();
      if (mounted && successTitle != null) {
        showAppMessage(context, title: successTitle);
      } else if (mounted && success != null) {
        showAppMessage(context, title: '完成', message: success);
      }
    } on Object catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          title: '操作失败',
          message: error.toString(),
          destructive: true,
        );
      }
    }
  }

  Future<void> _lyrics(Track track) async {
    final lyrics = await widget.controller.loadLyrics(track);
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: track.title.isEmpty ? '歌词' : track.title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 430),
        child: SingleChildScrollView(
          child: SelectableText(
            [
              lyrics.original,
              if (lyrics.translation case final value?) value,
            ].join('\n\n'),
          ),
        ),
      ),
    );
  }

  Future<void> _choosePlaylist(Track track) async {
    final items = await widget.playlists.list();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: '添加到歌单',
      child: items.isEmpty
          ? const AppEmptyState(message: '还没有歌单')
          : ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final playlist = items[index];
                return AppButton(
                  variant: ShadButtonVariant.ghost,
                  onPressed: () => _run(
                    () => widget.playlists.addTracks(playlist.id, [track]),
                    success: '已添加到 ${playlist.name}',
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(playlist.name),
                  ),
                );
              },
            ),
    );
  }

  List<TrackAction> _actionsFor(Track track) => buildTrackActions(
    track: track,
    player: widget.player,
    showLyrics: (value) => _run(() => _lyrics(value)),
    addToPlaylist: (value) => _run(() => _choosePlaylist(value)),
    download: (value, quality) => _run(
      () => widget.downloads.create(value, quality),
      successTitle: '已加入下载队列',
    ),
  );

  void _more(Track track) {
    unawaited(
      showMobileTrackActions(
        context,
        track: track,
        metadata: SearchTrackMetadata.fromTrack(track),
        actions: _actionsFor(track),
      ),
    );
  }

  Future<void> _page(int page) async {
    await widget.controller.goToPage(page);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _selectMobileView(SearchView view, SearchState state) async {
    final kind = switch (view) {
      SearchView.albums => CatalogSearchKind.album,
      SearchView.playlists => CatalogSearchKind.playlist,
      SearchView.overview || SearchView.tracks => CatalogSearchKind.track,
    };
    var source = selectedSource;
    final currentSupports =
        kind == CatalogSearchKind.track ||
        state.providers.any(
          (provider) =>
              provider.id == source && provider.searchKinds.contains(kind),
        );
    if (!currentSupports) {
      String? fallback;
      for (final provider in state.providers) {
        if (provider.searchKinds.contains(kind)) {
          fallback = provider.id;
          break;
        }
      }
      if (fallback == null) return;
      source = fallback;
      setState(() => selectedSource = source);
      await widget.controller.search(source: source, query: query.text);
    }
    await widget.controller.selectView(view);
  }

  Future<void> _chooseSource(SearchState state) async {
    final optionWidth = MediaQuery.sizeOf(context).width - 112;
    final selected = await showAppSheet<String>(
      context,
      title: '音乐来源',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final provider in [
            ...state.providers.map((item) => (item.id, item.name)),
            (SearchController.aggregateSource, '全部来源'),
          ])
            AppButton(
              key: Key('search-source-option-${provider.$1}'),
              variant: ShadButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(provider.$1),
              child: SizedBox(
                width: optionWidth,
                child: Row(
                  children: [
                    Expanded(child: Text(provider.$2)),
                    if (provider.$1 == selectedSource)
                      const Icon(LucideIcons.check, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == selectedSource) return;
    setState(() => selectedSource = selected);
    await _search();
  }

  @override
  void dispose() {
    scroll
      ..removeListener(_loadMore)
      ..dispose();
    query.dispose();
    searchFocus.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final state = widget.controller.state;
        final mobile =
            classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
        mobileLayout = mobile;
        return ColoredBox(
          key: Key(mobile ? 'search-mobile-layout' : 'search-wide-layout'),
          color: AppTokens.of(context).background,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? (constraints.maxWidth <= 360 ? 10 : 12) : 30,
              mobile ? 10 : 24,
              mobile ? (constraints.maxWidth <= 360 ? 10 : 12) : 30,
              0,
            ),
            child: CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.escape): () {
                  if (showHistory) setState(() => historyDismissed = true);
                },
              },
              child: TapRegion(
                onTapOutside: (_) {
                  if (showHistory) setState(() => historyDismissed = true);
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mobile) ...[
                          _MobileSearchMasthead(onSettings: widget.onSettings),
                          const SizedBox(height: 28),
                          Text(
                            '搜索',
                            key: const Key('search-page-title'),
                            style: AppTypography.mobilePageTitle,
                          ),
                          const SizedBox(height: 20),
                        ],
                        _SearchBar(
                          mobile: mobile,
                          state: state,
                          controller: query,
                          focusNode: searchFocus,
                          onSearch: _search,
                        ),
                        if (mobile && showHistory) ...[
                          const SizedBox(height: 8),
                          SearchHistoryPanel(
                            items: historyItems,
                            mobile: true,
                            onSelected: (value) =>
                                unawaited(_selectHistory(value)),
                            onRemoved: (value) =>
                                unawaited(_removeHistory(value)),
                            onCleared: () => unawaited(_clearHistory()),
                          ),
                        ],
                        if (mobile) ...[
                          const SizedBox(height: 20),
                          _MobileSearchFilters(
                            state: state,
                            sourceLabel: _sourceLabel(state, selectedSource),
                            onViewSelected: (view) =>
                                unawaited(_selectMobileView(view, state)),
                            onSourcePressed: () =>
                                unawaited(_chooseSource(state)),
                          ),
                          if (!showHistory && state.query.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _MobileResultsHeading(state: state),
                            const SizedBox(height: 8),
                          ],
                        ] else ...[
                          const SizedBox(height: 18),
                          _SourceTabs(
                            state: state,
                            selected: selectedSource,
                            onSelected: (source) {
                              setState(() => selectedSource = source);
                              unawaited(_search());
                            },
                          ),
                          _ViewTabs(
                            controller: widget.controller,
                            state: state,
                            onSelected: (view) =>
                                unawaited(widget.controller.selectView(view)),
                          ),
                        ],
                        if (!(mobile && showHistory))
                          Expanded(
                            child: mobile
                                ? SearchMobileResults(
                                    state: state,
                                    scrollController: scroll,
                                    loadPicture: widget.controller.loadPicture,
                                    onPlay: (track) =>
                                        unawaited(_run(() => _play(track))),
                                    onFavorite: (track) => unawaited(
                                      _run(() => _choosePlaylist(track)),
                                    ),
                                    onMore: _more,
                                    onViewAll: (view) => unawaited(
                                      widget.controller.selectView(view),
                                    ),
                                    onRetry: (kind) => unawaited(
                                      widget.controller.retrySection(kind),
                                    ),
                                  )
                                : SearchDesktopResults(
                                    state: state,
                                    scrollController: scroll,
                                    loadPicture: widget.controller.loadPicture,
                                    onPlay: (track) =>
                                        unawaited(_run(() => _play(track))),
                                    onFavorite: (track) => unawaited(
                                      _run(() => _choosePlaylist(track)),
                                    ),
                                    actionsFor: _actionsFor,
                                    onViewAll: (view) => unawaited(
                                      widget.controller.selectView(view),
                                    ),
                                    onPage: (page) => unawaited(_page(page)),
                                    onRetry: (kind) => unawaited(
                                      widget.controller.retrySection(kind),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    if (!mobile && showHistory)
                      Positioned(
                        top: 48,
                        left: 0,
                        width: 610,
                        child: SearchHistoryPanel(
                          items: historyItems,
                          mobile: false,
                          onSelected: (value) =>
                              unawaited(_selectHistory(value)),
                          onRemoved: (value) =>
                              unawaited(_removeHistory(value)),
                          onCleared: () => unawaited(_clearHistory()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.mobile,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onSearch,
  });
  final bool mobile;
  final SearchState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: mobile ? 52 : 42,
    child: Row(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: mobile ? double.infinity : 610,
              minHeight: mobile ? 52 : 0,
            ),
            child: AppTextField(
              key: const Key('search-field'),
              controller: controller,
              focusNode: focusNode,
              placeholder: '搜索音乐',
              surface: mobile
                  ? AppFieldSurface.glass
                  : AppFieldSurface.standard,
              leading: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(LucideIcons.search, size: 18),
              ),
              trailing: mobile
                  ? null
                  : const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Text('⌘ K', style: AppTypography.metadata),
                    ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
        ),
      ],
    ),
  );
}

String _sourceLabel(SearchState state, String source) {
  if (source == SearchController.aggregateSource) return '全部来源';
  return state.providers
          .where((provider) => provider.id == source)
          .firstOrNull
          ?.name ??
      '选择来源';
}

final class _MobileSearchMasthead extends StatelessWidget {
  const _MobileSearchMasthead({required this.onSettings});

  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('search-mobile-masthead'),
    height: 44,
    child: Row(
      children: [
        Image.asset(
          'assets/branding/TuneFlow.png',
          key: const Key('brand-logo'),
          width: 28,
          height: 28,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            LucideIcons.audioLines,
            size: 24,
            color: AppTokens.of(context).accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'TuneFlow',
            style: AppTypography.section.copyWith(fontSize: 19),
          ),
        ),
        AppGlassSurface(
          role: AppGlassRole.control,
          padding: EdgeInsets.zero,
          child: IconButton(
            key: const Key('search-settings'),
            tooltip: '设置',
            onPressed: onSettings,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(LucideIcons.settings, size: 20),
          ),
        ),
      ],
    ),
  );
}

final class _MobileSearchFilters extends StatelessWidget {
  const _MobileSearchFilters({
    required this.state,
    required this.sourceLabel,
    required this.onViewSelected,
    required this.onSourcePressed,
  });

  final SearchState state;
  final String sourceLabel;
  final ValueChanged<SearchView> onViewSelected;
  final VoidCallback onSourcePressed;

  SearchView get selectedView => switch (state.view) {
    SearchView.overview => SearchView.tracks,
    final view => view,
  };

  bool supports(SearchView view) {
    if (view == SearchView.tracks || view == SearchView.overview) return true;
    final kind = view == SearchView.albums
        ? CatalogSearchKind.album
        : CatalogSearchKind.playlist;
    return state.providers.any(
      (provider) => provider.searchKinds.contains(kind),
    );
  }

  @override
  Widget build(BuildContext context) => AppGlassSurface(
    key: const Key('search-mobile-filters'),
    role: AppGlassRole.control,
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        _MobileFilterItem(
          key: const Key('search-mobile-filter-tracks'),
          label: '歌曲',
          selected: selectedView == SearchView.tracks,
          onPressed: () => onViewSelected(SearchView.tracks),
        ),
        _MobileFilterItem(
          key: const Key('search-mobile-filter-albums'),
          label: '专辑',
          selected: selectedView == SearchView.albums,
          onPressed: supports(SearchView.albums)
              ? () => onViewSelected(SearchView.albums)
              : null,
        ),
        _MobileFilterItem(
          key: const Key('search-mobile-filter-playlists'),
          label: '歌单',
          selected: selectedView == SearchView.playlists,
          onPressed: supports(SearchView.playlists)
              ? () => onViewSelected(SearchView.playlists)
              : null,
        ),
        _MobileFilterItem(
          key: const Key('search-source-control'),
          label: sourceLabel,
          selected: false,
          onPressed: onSourcePressed,
        ),
      ],
    ),
  );
}

final class _MobileFilterItem extends StatelessWidget {
  const _MobileFilterItem({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.compactCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceWarm : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.compactCard),
              border: selected ? Border.all(color: tokens.borderSoft) : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppTypography.body.copyWith(
                color: onPressed == null
                    ? tokens.muted.withValues(alpha: .55)
                    : selected
                    ? tokens.accent
                    : tokens.foregroundSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _MobileResultsHeading extends StatelessWidget {
  const _MobileResultsHeading({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final (title, unit) = switch (state.view) {
      SearchView.albums => ('专辑', '张'),
      SearchView.playlists => ('歌单', '个'),
      _ => ('歌曲', '首'),
    };
    final section = state.activeSection;
    final count = section.total ?? section.items.length;
    return Row(
      key: const Key('search-results-heading'),
      children: [
        Expanded(child: Text(title, style: AppTypography.section)),
        Text(
          '$count $unit',
          style: AppTypography.counter.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
      ],
    );
  }
}

final class _SourceTabs extends StatelessWidget {
  const _SourceTabs({
    required this.state,
    required this.selected,
    required this.onSelected,
  });
  final SearchState state;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final providers = [
      ...state.providers.map((item) => (item.id, item.name)),
      (SearchController.aggregateSource, '聚合搜索'),
    ];
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        key: const Key('search-source-tabs'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: providers
              .map(
                (provider) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    key: Key('search-source-${provider.$1}'),
                    onPressed: () => onSelected(provider.$1),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: provider.$1 == selected
                          ? AppTokens.of(context).accent
                          : AppTokens.of(context).muted,
                      backgroundColor: provider.$1 == selected
                          ? AppTokens.of(context).accent.withValues(alpha: .14)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Text(
                      provider.$2,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

final class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.controller,
    required this.state,
    required this.onSelected,
  });
  final SearchController controller;
  final SearchState state;
  final ValueChanged<SearchView> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = {
      SearchView.overview: '综合',
      SearchView.tracks: '单曲',
      SearchView.playlists: '歌单',
    };
    final visibleViews = controller.supportedViews
        .where((view) => view != SearchView.albums)
        .toList(growable: false);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: visibleViews
            .map(
              (view) => TextButton(
                key: Key('search-view-${view.name}'),
                onPressed: () => onSelected(view),
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  foregroundColor: view == state.view
                      ? AppTokens.of(context).foreground
                      : AppTokens.of(context).muted,
                ),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: view == state.view
                            ? AppTokens.of(context).accent
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[view]!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
