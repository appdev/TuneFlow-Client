# Mobile Discovery, Collection Detail, and Tab State Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile download tab with a persistent discovery tab, move downloads into More, make search playlist/album cards open details, and preserve top-level tab state for the active Service connection.

**Architecture:** Convert the route shell to `StatefulShellRoute.indexedStack` so each top-level destination owns a persistent Navigator and page instance. Add a mobile-only discovery hub that embeds the existing playlist square and charts content in a `TabBarView`, and add an album-detail feature that follows the existing online-playlist detail patterns. Existing invalidation versions remain the authority for intentional refreshes; no disk response cache is added.

**Tech Stack:** Flutter 3.47-compatible Dart, Material/Shadcn UI, `go_router` 17.2.3, Riverpod 3.3.2, `flutter_test`, `http/testing.dart`.

## Global Constraints

- Mobile destinations are exactly: 首页、搜索、发现、我的音乐、更多.
- The discovery tab defaults to 歌单广场 and supports both tab taps and horizontal swipes to 排行榜.
- 下载管理 moves into 更多; desktop navigation remains structurally unchanged.
- Preserve loaded data, search state, scroll positions, selected discovery tab, and each branch's detail stack for the duration of one Service connection.
- Reload only on explicit refresh, relevant domain invalidation, or Service reconnect.
- Do not add disk caching or infer album tracks from track-search results.
- Treat `POST /api/v1/catalog/albums/detail` and an album-detail capability flag as a proposed Service contract; unsupported Services must produce an explicit unsupported state.
- Preserve all unrelated dirty-worktree changes. Do not commit, stage, or publish unless the user separately authorizes it.
- Device verification is optional when `adb devices` is empty, but the unverified device behaviors must be reported.

---

## File Structure

### New files

- `lib/features/discovery/discovery_hub_screen.dart`: mobile discovery tabs and retained child pages.
- `lib/features/discovery/album_detail_controller.dart`: album pagination, stale state, and queue preparation.
- `lib/features/discovery/album_detail_screen.dart`: album metadata, track list, playback, playlist-add, and download actions.
- `test/features/discovery/discovery_hub_screen_test.dart`: tab click/swipe and child-state retention.
- `test/features/discovery/album_detail_controller_test.dart`: album response, pagination, dedupe, unsupported/error behavior.
- `test/features/discovery/album_detail_screen_test.dart`: rendering and track-action behavior.

### Modified files

- `lib/api/models.dart`: album-detail capability and paginated album response model.
- `lib/features/search/search_repository.dart`: album-detail request.
- `lib/features/discovery/discovery_screen.dart`: expose reusable charts content without duplicating logic.
- `lib/features/discovery/playlist_discovery_view.dart`: embedded/header mode and stable scroll state.
- `lib/features/search/search_mobile_results.dart`: collection open callback and interactive cards.
- `lib/features/search/search_desktop_results.dart`: same collection navigation contract for desktop.
- `lib/features/search/search_screen.dart`: route-level collection callback propagation.
- `lib/features/more/more_screen.dart`: replace square/charts entries with downloads.
- `lib/app/app_shell.dart`: destination maps and `StatefulNavigationShell` branch switching.
- `lib/app/app_router.dart`: stateful branches, discovery and album routes, and preserved nested stacks.
- `test/api/models_test.dart`, `test/features/repositories_test.dart`: Service contract parsing/request tests.
- `test/features/search/search_screen_test.dart`: clickable playlist/album result tests.
- `test/features/more/more_screen_test.dart`: moved download entry.
- `test/app/app_shell_routing_test.dart`, `test/app/app_shell_test.dart`: selection, branch switching, state retention, and desktop regression.

---

### Task 1: Define the album-detail Service boundary

**Files:**
- Modify: `lib/api/models.dart`
- Modify: `lib/features/search/search_repository.dart`
- Test: `test/api/models_test.dart`
- Test: `test/features/repositories_test.dart`

**Interfaces:**
- Produces: `CatalogProvider.albumDetail`, a backward-compatible `bool` defaulting to `false` when omitted.
- Produces: `AlbumDetailPage` with `source`, `page`, `limit`, `total`, `hasMore`, `album`, and `tracks`.
- Produces: `SearchRepository.album({required String source, required String albumId, required int page})`.
- Consumes: existing `CatalogCollection`, `Track`, `ServiceApi.request`, and strict JSON helpers.

- [ ] **Step 1: Add failing capability and response-model tests**

Add tests that parse an explicit detail capability and a complete album page:

```dart
test('catalog provider parses album detail support', () {
  final capabilities = CatalogCapabilities.fromJson({
    'sources': [
      {
        'id': 'wy',
        'name': '网易音乐',
        'searchKinds': ['track', 'album'],
        'albumDetail': true,
      },
    ],
  });
  expect(capabilities.providers.single.albumDetail, isTrue);
});

test('album detail page preserves metadata and paging', () {
  final page = AlbumDetailPage.fromJson({
    'source': 'wy',
    'page': 1,
    'limit': 30,
    'total': 1,
    'hasMore': false,
    'album': {
      'id': 'album-1',
      'kind': 'album',
      'name': '叶惠美',
      'source': 'wy',
      'author': '周杰伦',
    },
    'tracks': [
      {'id': 'track-1', 'name': '以父之名', 'source': 'wy'},
    ],
  });
  expect(page.album.kind, CatalogSearchKind.album);
  expect(page.tracks.single.id, 'track-1');
  expect(page.hasMore, isFalse);
});
```

- [ ] **Step 2: Run the focused model tests and confirm failure**

Run: `flutter test test/api/models_test.dart`

Expected: compile failure because `albumDetail` and `AlbumDetailPage` do not exist.

- [ ] **Step 3: Implement strict, backward-compatible model parsing**

Add the exact public surface:

```dart
final class CatalogProvider {
  const CatalogProvider({
    required this.id,
    required this.name,
    required this.searchKinds,
    this.leaderboards = false,
    this.albumDetail = false,
    this.playlistDiscovery,
  });

  final bool albumDetail;
}

final class AlbumDetailPage {
  const AlbumDetailPage({
    required this.source,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
    required this.album,
    required this.tracks,
  });

  factory AlbumDetailPage.fromJson(Object? value) { /* strict json helpers */ }
}
```

Parse `albumDetail` with `json['albumDetail'] == true`, so older Service capability responses remain valid. Validate that the nested collection kind is `CatalogSearchKind.album` and reject invalid paging types using the existing `_invalid(...)` style.

- [ ] **Step 4: Add a failing repository request test**

Capture method, path, and JSON body, call `repository.album(source: 'wy', albumId: 'album-1', page: 2)`, and expect:

```dart
expect(request.method, 'POST');
expect(request.url.path, '/api/v1/catalog/albums/detail');
expect(jsonDecode(request.body), {
  'source': 'wy',
  'albumId': 'album-1',
  'page': 2,
});
```

- [ ] **Step 5: Run the repository test and confirm failure**

Run: `flutter test test/features/repositories_test.dart`

Expected: compile failure because `SearchRepository.album` is absent.

- [ ] **Step 6: Implement the minimal repository method and rerun tests**

```dart
Future<AlbumDetailPage> album({
  required String source,
  required String albumId,
  required int page,
}) async => AlbumDetailPage.fromJson(
  await api.request(
    'POST',
    '/api/v1/catalog/albums/detail',
    body: {'source': source, 'albumId': albumId, 'page': page},
  ),
);
```

Run: `flutter test test/api/models_test.dart test/features/repositories_test.dart`

Expected: PASS.

---

### Task 2: Build album-detail state and UI

**Files:**
- Create: `lib/features/discovery/album_detail_controller.dart`
- Create: `lib/features/discovery/album_detail_screen.dart`
- Create: `test/features/discovery/album_detail_controller_test.dart`
- Create: `test/features/discovery/album_detail_screen_test.dart`

**Interfaces:**
- Consumes: `SearchRepository.album`, `CatalogProvider.albumDetail`, `PlaylistRepository`, `DownloadRepository`, and `PlayerController`.
- Produces: `AlbumDetailController` constructed with `catalog`, `source`, `albumId`, `supported`, and `initialAlbum`.
- Produces: `AlbumDetailState` with `album`, `pages`, `tracks`, `loadingPage`, `failedPage`, `error`, `stale`, and `unsupported`.
- Produces: immutable `AlbumDetailRouteArgs(album:, supported:)` so the search page passes both seed metadata and the capability decision to the route.
- Produces: `AlbumDetailScreen(controller:, player:, playlists:, downloads:)`.

- [ ] **Step 1: Write failing controller tests for first page, paging, dedupe, and unsupported state**

Use a `MockClient` repository and assert:

```dart
final controller = AlbumDetailController(
  catalog: SearchRepository(api),
  source: 'wy',
  albumId: 'album-1',
  supported: true,
  initialAlbum: seed,
);
await controller.load();
expect(controller.state.album?.name, '叶惠美');
expect(controller.state.tracks.map((track) => track.id), ['t1']);
await controller.loadPage(2);
expect(controller.state.tracks.map((track) => track.id), ['t1', 't2']);
```

Return `t1` again on page 2 and verify it is deduplicated by `(source, id)`. Construct another controller with `supported: false`, call `load()`, and verify `state.unsupported == true` and zero HTTP requests.

- [ ] **Step 2: Run the controller tests and confirm failure**

Run: `flutter test test/features/discovery/album_detail_controller_test.dart`

Expected: compile failure because the controller file and types are absent.

- [ ] **Step 3: Implement the controller as a focused playlist-detail analogue**

Use a generation counter to discard stale async results. Preserve `initialAlbum` during first load and failed refresh. Define:

```dart
final class AlbumDetailController extends ChangeNotifier {
  AlbumDetailController({
    required this.catalog,
    required this.source,
    required this.albumId,
    required this.supported,
    this.initialAlbum,
  }) : state = AlbumDetailState(
         album: initialAlbum,
         unsupported: !supported,
       );

  Future<void> load();
  Future<void> loadPage(int page);
  Future<void> retryFailedPage();
  Future<void> loadAllPages();
}

final class AlbumDetailRouteArgs {
  const AlbumDetailRouteArgs({required this.album, required this.supported});
  final CatalogCollection album;
  final bool supported;
}
```

Set `stale` only when a request fails while tracks are already present. `loadAllPages()` must stop after a failed page and must not spin when `hasMore` is false.

- [ ] **Step 4: Run the controller tests and confirm success**

Run: `flutter test test/features/discovery/album_detail_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing Widget tests for metadata, queue index, actions, and unsupported copy**

Build the screen at `390x844`. Verify the seed metadata appears before the request completes, tap the second track, and assert the test `AudioPort` receives the complete queue with `startIndex == 1`. Open track actions and verify “添加到歌单” and download quality actions are present. For `supported: false`, expect `当前音源不支持专辑详情` and no loading spinner.

- [ ] **Step 6: Implement the album detail screen using existing UI contracts**

Mirror the proven interaction boundaries in `OnlinePlaylistDetailScreen`, but do not include whole-playlist import state. Use:

```dart
final class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.controller,
    required this.player,
    required this.playlists,
    required this.downloads,
  });
}
```

Use `CatalogTrackList`, `buildTrackActions`, `showMobileTrackActions`, `AppArtwork`, `AppNotice.error`, and the existing page-size/load-more threshold conventions. “播放全部” first calls `loadAllPages()` and refuses playback with a user-facing message if a page remains failed.

- [ ] **Step 7: Run album detail tests**

Run: `flutter test test/features/discovery/album_detail_controller_test.dart test/features/discovery/album_detail_screen_test.dart`

Expected: PASS.

---

### Task 3: Create the mobile discovery hub without duplicating discovery logic

**Files:**
- Create: `lib/features/discovery/discovery_hub_screen.dart`
- Modify: `lib/features/discovery/discovery_screen.dart`
- Modify: `lib/features/discovery/playlist_discovery_view.dart`
- Create: `test/features/discovery/discovery_hub_screen_test.dart`
- Modify: `test/features/discovery/discovery_screen_test.dart`
- Modify: `test/features/discovery/playlist_discovery_screen_test.dart`

**Interfaces:**
- Consumes: `SearchRepository`, `PlaylistRepository`, `PlayTracks`, and `ValueChanged<CatalogCollection>`.
- Produces: `DiscoveryHubScreen(repository:, playlists:, playTracks:, onOpenPlaylist:)`.
- Produces: reusable chart content via `DiscoveryScreen(..., embedded: true)` or a focused extracted `LeaderboardDiscoveryView`; choose the smaller diff after reading the complete current file.
- Produces: `PlaylistDiscoveryView(..., embedded: true)` to suppress its standalone mobile header and outer background while preserving filters and paging.

- [ ] **Step 1: Write failing discovery-hub interaction tests**

Test keys and behavior:

```dart
expect(find.byKey(const Key('discovery-tab-playlists')), findsOneWidget);
expect(find.byKey(const Key('discovery-tab-charts')), findsOneWidget);
expect(find.byKey(const Key('playlist-square-layout')), findsOneWidget);
await tester.tap(find.byKey(const Key('discovery-tab-charts')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('charts-layout')), findsOneWidget);
await tester.drag(
  find.byKey(const Key('discovery-tab-view')),
  const Offset(320, 0),
);
await tester.pumpAndSettle();
expect(find.byKey(const Key('playlist-square-layout')), findsOneWidget);
```

Also select a playlist provider/filter, switch away and back, and assert the selection and request count remain unchanged.

- [ ] **Step 2: Run the hub test and confirm failure**

Run: `flutter test test/features/discovery/discovery_hub_screen_test.dart`

Expected: compile failure because `DiscoveryHubScreen` is absent.

- [ ] **Step 3: Add embedded modes to the existing discovery views**

Add `embedded = false` constructor fields. In embedded mode:

- omit standalone `AppMobilePageHeader` widgets;
- keep the existing content keys, filters, errors, pagination, and repositories;
- use stable `PageStorageKey<String>` values for the playlist and charts scrollables;
- do not dispose controllers during tab changes because both children remain mounted.

Run existing discovery tests after the refactor:

`flutter test test/features/discovery/discovery_screen_test.dart test/features/discovery/playlist_discovery_screen_test.dart`

Expected: PASS.

- [ ] **Step 4: Implement the retained tab container**

Use `DefaultTabController(length: 2)` or an owned `TabController`, but ensure the controller belongs to the state object. The public shape is:

```dart
final class DiscoveryHubScreen extends StatefulWidget {
  const DiscoveryHubScreen({
    super.key,
    required this.repository,
    required this.playlists,
    required this.playTracks,
    required this.onOpenPlaylist,
  });
}
```

Build a mobile page header titled “发现”, a two-item `TabBar`, and an `Expanded(TabBarView(...))`. Instantiate the `PlaylistDiscoveryController` once in `initState`; construct the chart child once from stable dependencies. Dispose only when the discovery branch itself is destroyed.

- [ ] **Step 5: Run all discovery tests**

Run: `flutter test test/features/discovery/discovery_hub_screen_test.dart test/features/discovery/discovery_screen_test.dart test/features/discovery/playlist_discovery_screen_test.dart`

Expected: PASS.

---

### Task 4: Move navigation to persistent stateful branches and relocate downloads

**Files:**
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/features/more/more_screen.dart`
- Modify: `test/app/app_shell_routing_test.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `test/features/more/more_screen_test.dart`

**Interfaces:**
- Consumes: `DiscoveryHubScreen` and existing route builders/controllers.
- Produces: `AppShell.navigationShell: StatefulNavigationShell`.
- Produces: stable branch IDs mapped to `StatefulNavigationShell.goBranch(index, initialLocation:)`.
- Produces: `MoreScreen.onDownloads` and removes `onSquare`/`onCharts`.

- [ ] **Step 1: Update navigation expectation tests first**

Change the mobile route mapping assertions to:

```dart
expect(navigationSelectionForLocation('/discover', mobile: true), 'discover');
expect(navigationSelectionForLocation('/downloads', mobile: true), 'more');
expect(navigationSelectionForLocation('/settings', mobile: true), 'more');
expect(navigationSelectionForLocation('/sources', mobile: true), 'more');
```

In the full shell test, assert the mobile dock labels are exactly 首页、搜索、发现、我的音乐、更多. In `more_screen_test.dart`, tap `more-downloads` and assert one `onDownloads` invocation; assert 歌单广场 and 排行榜 are absent.

- [ ] **Step 2: Run navigation tests and confirm failure**

Run: `flutter test test/app/app_shell_routing_test.dart test/features/more/more_screen_test.dart`

Expected: failures because the current dock still includes 下载 and More still includes square/charts.

- [ ] **Step 3: Make the leaf navigation changes**

Set mobile destinations to:

```dart
static const _mobileDestinations = [
  AppDestination(id: 'home', label: '首页', icon: LucideIcons.house),
  AppDestination(id: 'search', label: '搜索', icon: LucideIcons.search),
  AppDestination(id: 'discover', label: '发现', icon: LucideIcons.compass),
  AppDestination(id: 'playlists', label: '我的音乐', icon: LucideIcons.heart),
  AppDestination(id: 'more', label: '更多', icon: LucideIcons.ellipsis),
];
```

Change `MoreScreen` to accept `VoidCallback onDownloads`, add a keyed “下载管理” tile, and remove its square/charts callbacks and tiles. Preserve all existing disconnect, settings, sources, and Service status behavior.

- [ ] **Step 4: Convert `ShellRoute` to named stateful branches**

Define stable branch order constants in `app_router.dart` or a small private route-index table. Use `StatefulShellRoute.indexedStack` with branch root routes for home, search, discover, playlists, more, square, charts, downloads, settings, and sources. Keep nested routes in their owning branches:

- online playlist under discover/square ownership;
- local and Service playlist details under playlists;
- album detail under search;
- player remains on the root Navigator.

The shell builder must pass the `StatefulNavigationShell` itself to `AppShell`. Replace string-to-`context.push` bottom navigation with branch lookup plus:

```dart
navigationShell.goBranch(
  branchIndex,
  initialLocation: branchIndex == navigationShell.currentIndex,
);
```

Preserve the existing `AppNavigationHistory`, player modal behavior, mini-player placement, connection key, desktop frame, and invalidation-based `ValueKey`s.

- [ ] **Step 5: Add a request-count and state-retention integration test**

In `test/app/app_shell_test.dart`, use mobile dimensions and count `/api/v1/playlists`, `/api/v1/downloads`, and `/api/v1/library/tracks`. After first settlement:

1. record counts;
2. tap 我的音乐;
3. tap 首页;
4. tap 我的音乐 again;
5. assert the second visit did not increase the first-load counts;
6. enter a search query, switch branches, return, and assert the field still contains it;
7. open a playlist detail, switch branches, return, and assert the detail remains on top of its branch.

- [ ] **Step 6: Run router and shell tests**

Run: `flutter test test/app/app_shell_routing_test.dart test/features/more/more_screen_test.dart test/app/app_shell_test.dart`

Expected: PASS with desktop assertions unchanged and mobile persistence assertions satisfied.

---

### Task 5: Wire clickable playlist and album search results to detail routes

**Files:**
- Modify: `lib/features/search/search_mobile_results.dart`
- Modify: `lib/features/search/search_desktop_results.dart`
- Modify: `lib/features/search/search_screen.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `test/features/search/search_screen_test.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: `AlbumDetailScreen`, `CatalogCollection.kind`, search-branch Navigator, and existing online-playlist route.
- Produces: `SearchScreen.onOpenCollection: ValueChanged<CatalogCollection>`.
- Produces: `SearchMobileResults.onOpenCollection` and the equivalent desktop-results callback.
- Produces: named route `album-detail` with `source` and `albumId` path parameters and `AlbumDetailRouteArgs` in `state.extra`.

- [ ] **Step 1: Write failing search-card interaction tests**

Build search results containing one album and one playlist. Pass a callback that records collections, tap each keyed card, and assert the callback receives the exact item. Inspect the rendered `Semantics` and `InkWell`:

```dart
final card = find.byKey(const Key('search-collection-wy-album-1'));
expect(card, findsOneWidget);
expect(
  find.descendant(of: card, matching: find.byType(InkWell)),
  findsOneWidget,
);
await tester.tap(card);
expect(opened?.id, 'album-1');
```

Run the same contract for playlist results and for the desktop result component.

- [ ] **Step 2: Run the search tests and confirm failure**

Run: `flutter test test/features/search/search_screen_test.dart`

Expected: failure because collection result widgets have no open callback.

- [ ] **Step 3: Add the collection callback through every search layout**

Add `required ValueChanged<CatalogCollection> onOpenCollection` to the relevant widgets. Wrap `_CollectionCard` in a semantic button and `Material`/`InkWell`; call `onOpenCollection(item)` exactly once. Do not change track actions, paging, filters, or aggregate-source behavior.

- [ ] **Step 4: Add album and playlist route dispatch**

In the search route builder:

```dart
onOpenCollection: (collection) {
  switch (collection.kind) {
    case CatalogSearchKind.playlist:
      context.pushNamed(
        'online-playlist',
        pathParameters: {
          'source': collection.source,
          'playlistId': collection.id,
        },
        extra: collection,
      );
    case CatalogSearchKind.album:
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
    case CatalogSearchKind.track:
      throw StateError('Track is not a collection result.');
  }
},
```

Create the search Controller in a local variable in the route builder so the callback reads the same instance passed to `SearchScreen`. The album route must accept only `AlbumDetailRouteArgs`; if `state.extra` is absent (for example, an unsupported direct deep link), construct a metadata-only seed from the path parameters and set `supported: false` rather than sending an unverified request. Keep the online playlist route reusable from both search and discovery branches without changing its visible path contract.

- [ ] **Step 5: Add route integration assertions**

Extend the app shell test so tapping a playlist search card shows `online-playlist-<source>-<id>`, and tapping an album card shows the album route with seed metadata immediately. Provide `albumDetail: false` in one fixture and assert the unsupported message without an album-detail request; provide `albumDetail: true` in another fixture and assert the exact detail endpoint request.

- [ ] **Step 6: Run focused search and routing tests**

Run: `flutter test test/features/search/search_screen_test.dart test/app/app_shell_test.dart`

Expected: PASS.

---

### Task 6: Freeze the result and run proportional verification

**Files:**
- Review: all files listed above
- Update only if failures reveal an in-scope regression: affected implementation or test file

**Interfaces:**
- Consumes: all earlier task outputs.
- Produces: a verified client tree with no debug residue or unrelated edits introduced by this work.

- [ ] **Step 1: Format only changed Dart files**

Run `dart format` with the explicit list of Dart files changed by Tasks 1–5. Do not format unrelated dirty files.

- [ ] **Step 2: Run the complete focused test set**

Run:

```bash
flutter test \
  test/api/models_test.dart \
  test/features/repositories_test.dart \
  test/features/discovery/album_detail_controller_test.dart \
  test/features/discovery/album_detail_screen_test.dart \
  test/features/discovery/discovery_hub_screen_test.dart \
  test/features/discovery/discovery_screen_test.dart \
  test/features/discovery/playlist_discovery_screen_test.dart \
  test/features/search/search_screen_test.dart \
  test/features/more/more_screen_test.dart \
  test/app/app_shell_routing_test.dart \
  test/app/app_shell_test.dart
```

Expected: all tests PASS.

- [ ] **Step 3: Run static analysis over the affected surface**

Run:

```bash
flutter analyze \
  lib/api/models.dart \
  lib/app/app_shell.dart \
  lib/app/app_router.dart \
  lib/features/discovery \
  lib/features/search \
  lib/features/more/more_screen.dart \
  test/api/models_test.dart \
  test/features/discovery \
  test/features/search/search_screen_test.dart \
  test/features/more/more_screen_test.dart \
  test/app/app_shell_routing_test.dart \
  test/app/app_shell_test.dart
```

Expected: `No issues found!` If the installed Flutter CLI does not accept file/directory mixing, run `flutter analyze` for the package and distinguish pre-existing findings from changed-file findings.

- [ ] **Step 4: Inspect final diff and working tree**

Run:

```bash
git diff --check
git status --short
git diff -- \
  lib/api/models.dart \
  lib/app/app_shell.dart \
  lib/app/app_router.dart \
  lib/features/discovery \
  lib/features/search \
  lib/features/more/more_screen.dart \
  test/api/models_test.dart \
  test/features/discovery \
  test/features/search/search_screen_test.dart \
  test/features/more/more_screen_test.dart \
  test/app/app_shell_routing_test.dart \
  test/app/app_shell_test.dart
```

Confirm there are no debug prints, no accidental generated files, no overwritten user work, and no changes outside the approved scope.

- [ ] **Step 5: Collect optional Android evidence when a device is available**

Run `adb devices`. If a device is listed, verify:

1. tap through all five bottom destinations;
2. swipe the discovery tabs in both directions;
3. scroll search/discovery, switch away, and confirm position on return;
4. observe Service request logs and confirm no repeat first-load requests;
5. open playlist/album details and verify Android back restores the owning list.

If no device is listed, record these as unverified device behaviors rather than claiming them.

- [ ] **Step 6: Report the verified outcome without Git side effects**

Summarize changed behavior, exact tests/analyzer results, the Service album-detail dependency, device verification status, and any residual risk. Do not stage or commit unless the user has separately authorized those operations.
