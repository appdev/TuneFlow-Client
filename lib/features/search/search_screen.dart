import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/app_states.dart';
import '../../design/app_theme_definition.dart';
import '../../design/design_tokens.dart';
import '../downloads/download_repository.dart';
import '../downloads/redownload_confirmation.dart';
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
    this.onOpenCollection,
    SearchHistoryRepository? history,
  }) : history = history ?? SearchHistoryRepository();

  final SearchController controller;
  final PlaylistRepository playlists;
  final DownloadRepository downloads;
  final PlayerController player;
  final ValueChanged<CatalogCollection>? onOpenCollection;
  final SearchHistoryRepository history;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final searchTapGroup = Object();
  late final SearchController _controller;
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
    _controller = widget.controller;
    query.text = _controller.state.query;
    selectedSource = _controller.state.source;
    scroll.addListener(_loadMore);
    query.addListener(_historyChanged);
    searchFocus.addListener(_historyChanged);
    unawaited(_loadHistory());
    unawaited(
      _controller.loadCapabilities().then((_) {
        if (!mounted) return;
        setState(() {
          selectedSource = mobileLayout && query.text.trim().isEmpty
              ? SearchController.aggregateSource
              : _controller.state.source;
        });
      }),
    );
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, _controller)) {
      widget.controller.dispose();
    }
  }

  Future<void> _loadHistory() async {
    final items = await widget.history.load();
    if (mounted) setState(() => historyItems = items);
  }

  void _historyChanged() {
    if (!mounted) return;
    if (query.text.isNotEmpty || searchFocus.hasFocus) {
      historyDismissed = false;
    }
    setState(() {});
  }

  void _loadMore() {
    if (mobileLayout && scroll.position.extentAfter < 240) {
      unawaited(_controller.loadNextPage());
    }
  }

  Future<void> _search({String? submittedKeyword}) async {
    final keyword = (submittedKeyword ?? query.text).trim();
    final search = _controller.search(source: selectedSource, query: keyword);
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

  Future<void> _clearSearch() async {
    query.clear();
    await _controller.search(
      source: selectedSource,
      query: '',
      view: _controller.state.view,
    );
    if (!mounted) return;
    searchFocus.requestFocus();
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !searchFocus.hasFocus) return;
          unawaited(
            SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
          );
        });
      }),
    );
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

  Widget _mobileSearchBarWithHistory(SearchState state) => TapRegion(
    groupId: searchTapGroup,
    onTapOutside: (_) {
      if (!showHistory) return;
      searchFocus.unfocus();
      setState(() => historyDismissed = true);
    },
    child: LayoutBuilder(
      builder: (context, constraints) => ShadPortal(
        visible: showHistory,
        anchor: const ShadAnchorAuto(offset: Offset(0, 8)),
        portalBuilder: (context) => SizedBox(
          width: constraints.maxWidth,
          child: TapRegion(
            groupId: searchTapGroup,
            child: SearchHistoryPanel(
              items: historyItems,
              mobile: true,
              onSelected: (value) => unawaited(_selectHistory(value)),
              onRemoved: (value) => unawaited(_removeHistory(value)),
              onCleared: () => unawaited(_clearHistory()),
            ),
          ),
        ),
        child: _SearchBar(
          mobile: true,
          state: state,
          controller: query,
          focusNode: searchFocus,
          tapRegionGroupId: searchTapGroup,
          onSearch: _search,
          onClear: _clearSearch,
        ),
      ),
    ),
  );

  Future<void> _play(Track track) async {
    final playback = widget.player.play(track);
    final embedded = track.raw['pic'];
    if (embedded is! String || embedded.isEmpty) {
      unawaited(_loadPlaybackArtwork(track));
    }
    await playback;
  }

  Future<void> _loadPlaybackArtwork(Track track) async {
    final picture = await _controller.loadPicture(track);
    if (picture != null) {
      widget.player.updateTrackArtwork(track, picture);
    }
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
          message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
          destructive: true,
        );
      }
    }
  }

  Future<void> _lyrics(Track track) async {
    final lyrics = await _controller.loadLyrics(track);
    if (!mounted) return;
    await AppBottomSheet.showContent<void>(
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

  Future<void> _download(Track track, String quality) async {
    try {
      final result = await const AppUserDownloadCoordinator().create(
        context,
        widget.downloads,
        track,
        quality,
      );
      if (!mounted || result.job == null) return;
      showAppMessage(context, title: result.replaced ? '已加入重新下载队列' : '已加入下载队列');
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '操作失败',
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<void> _choosePlaylist(Track track) async {
    final items = await widget.playlists.list();
    if (!mounted) return;
    await AppBottomSheet.showContent<void>(
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

  List<TrackAction> _actionsFor(Track track) {
    final standard = buildTrackActions(
      track: track,
      player: widget.player,
      showLyrics: (value) => _run(() => _lyrics(value)),
      addToPlaylist: (value) => _run(() => _choosePlaylist(value)),
      download: _download,
    );
    return [
      TrackAction(
        id: TrackActionId.playNow,
        label: '立即播放',
        icon: AppPlaybackIcons.play,
        invoke: () => _play(track),
      ),
      ...standard.where((action) => action.id != TrackActionId.playNow),
    ];
  }

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
    await _controller.goToPage(page);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _selectMobileView(SearchView view, SearchState state) async {
    final kind = _kindForView(view);
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
      await _controller.search(source: source, query: query.text, view: view);
      return;
    }
    await _controller.selectView(view);
  }

  Future<void> _chooseSource(SearchState state) async {
    final kind = _kindForView(state.view);
    final providers = state.providers
        .where((provider) => provider.searchKinds.contains(kind))
        .toList(growable: false);
    final options = [
      for (final provider in providers)
        AppBottomSheetSelection<String>(
          key: Key('search-source-option-${provider.id}'),
          value: provider.id,
          label: provider.name,
        ),
      if (kind == CatalogSearchKind.track)
        const AppBottomSheetSelection<String>(
          key: Key('search-source-option-all'),
          value: SearchController.aggregateSource,
          label: '全部来源',
        ),
    ];
    if (options.isEmpty) return;
    final currentSelection =
        options.any((option) => option.value == selectedSource)
        ? selectedSource
        : options.first.value;
    final selected = await AppBottomSheet.showSelection<String>(
      context,
      title: '音乐来源',
      message: kind == CatalogSearchKind.album && providers.length == 1
          ? '当前仅${providers.single.name}支持专辑搜索'
          : null,
      options: options,
      selectedValue: currentSelection,
    );
    if (!mounted || selected == null || selected == selectedSource) return;
    setState(() => selectedSource = selected);
    await _controller.search(
      source: selected,
      query: query.text,
      view: state.view,
    );
  }

  CatalogSearchKind _kindForView(SearchView view) => switch (view) {
    SearchView.albums => CatalogSearchKind.album,
    SearchView.playlists => CatalogSearchKind.playlist,
    SearchView.overview || SearchView.tracks => CatalogSearchKind.track,
  };

  @override
  void dispose() {
    scroll
      ..removeListener(_loadMore)
      ..dispose();
    query.dispose();
    searchFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final state = _controller.state;
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Builder(
                    builder: (context) {
                      final contents = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (mobile) ...[
                            const _MobileSearchMasthead(),
                            const SizedBox(height: 28),
                            Text(
                              '搜索',
                              key: const Key('search-page-title'),
                              style: AppTypography.mobilePageTitle,
                            ),
                            const SizedBox(height: 20),
                          ],
                          mobile
                              ? _mobileSearchBarWithHistory(state)
                              : _SearchBar(
                                  mobile: false,
                                  state: state,
                                  controller: query,
                                  focusNode: searchFocus,
                                  tapRegionGroupId: searchTapGroup,
                                  onSearch: _search,
                                  onClear: _clearSearch,
                                ),
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
                            if (state.query.isNotEmpty) ...[
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
                              controller: _controller,
                              state: state,
                              onSelected: (view) =>
                                  unawaited(_controller.selectView(view)),
                            ),
                          ],
                          mobile
                              ? SearchMobileResults(
                                  state: state,
                                  scrollController: scroll,
                                  embedded: true,
                                  loadPicture: _controller.loadPicture,
                                  onPlay: (track) =>
                                      unawaited(_run(() => _play(track))),
                                  onFavorite: (track) => unawaited(
                                    _run(() => _choosePlaylist(track)),
                                  ),
                                  onMore: _more,
                                  onViewAll: (view) =>
                                      unawaited(_controller.selectView(view)),
                                  onRetry: (kind) =>
                                      unawaited(_controller.retrySection(kind)),
                                  onOpenCollection:
                                      widget.onOpenCollection ?? (_) {},
                                )
                              : Expanded(
                                  child: SearchDesktopResults(
                                    state: state,
                                    scrollController: scroll,
                                    loadPicture: _controller.loadPicture,
                                    onPlay: (track) =>
                                        unawaited(_run(() => _play(track))),
                                    onFavorite: (track) => unawaited(
                                      _run(() => _choosePlaylist(track)),
                                    ),
                                    actionsFor: _actionsFor,
                                    onViewAll: (view) =>
                                        unawaited(_controller.selectView(view)),
                                    onPage: (page) => unawaited(_page(page)),
                                    onRetry: (kind) => unawaited(
                                      _controller.retrySection(kind),
                                    ),
                                    onOpenCollection:
                                        widget.onOpenCollection ?? (_) {},
                                  ),
                                ),
                        ],
                      );
                      return mobile
                          ? SingleChildScrollView(
                              key: const Key('search-mobile-scroll'),
                              controller: scroll,
                              child: contents,
                            )
                          : contents;
                    },
                  ),
                  if (!mobile && showHistory)
                    Positioned(
                      top: 48,
                      left: 0,
                      width: 610,
                      child: TapRegion(
                        groupId: searchTapGroup,
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
                    ),
                ],
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
    required this.tapRegionGroupId,
    required this.onSearch,
    required this.onClear,
  });
  final bool mobile;
  final SearchState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Object tapRegionGroupId;
  final Future<void> Function() onSearch;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final fieldHeight = mobile ? 52.0 : 46.0;
    return SizedBox(
      height: fieldHeight,
      child: Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: mobile ? double.infinity : 610,
                minHeight: fieldHeight,
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) {
                  final key = event.logicalKey;
                  if (event is KeyDownEvent &&
                      (key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.numpadEnter)) {
                    unawaited(onSearch());
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: AppTextField(
                  key: const Key('search-field'),
                  controller: controller,
                  focusNode: focusNode,
                  groupId: tapRegionGroupId,
                  placeholder: '搜索音乐',
                  textInputAction: TextInputAction.search,
                  surface: mobile
                      ? AppFieldSurface.glass
                      : AppFieldSurface.standard,
                  padding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: mobile ? 3 : 0,
                  ),
                  leading: const SizedBox(
                    key: Key('search-field-leading'),
                    width: 44,
                    height: 44,
                    child: Center(child: Icon(LucideIcons.search, size: 18)),
                  ),
                  trailing: controller.text.isNotEmpty
                      ? Semantics(
                          label: '清除搜索',
                          button: true,
                          child: IconButton(
                            key: const Key('search-clear'),
                            tooltip: '清除搜索',
                            onPressed: () => unawaited(onClear()),
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(44),
                              maximumSize: const Size.square(44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.x, size: 18),
                          ),
                        )
                      : mobile
                      ? null
                      : const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Text('⌘ K', style: AppTypography.metadata),
                        ),
                  onSubmitted: (_) => onSearch(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
  const _MobileSearchMasthead();

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
