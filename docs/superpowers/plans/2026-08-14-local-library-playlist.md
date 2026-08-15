# Flutter Client Local Library Playlist Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the current Service local library as the first read-only “本地音乐” card in “我的音乐”, with a playable detail page and event-driven refresh.

**Architecture:** Keep playlists, downloads, and the local library as separate Service resources. Aggregate playlists and `LibraryTrack` records only in the “我的音乐” controller, route the local card to a dedicated `/library` read-only controller/screen, and use invalidation versions to reload authoritative data after `downloads.*` or `library.*` events.

**Tech Stack:** Flutter, Dart, Riverpod, GoRouter, `ChangeNotifier`, `flutter_test`, `http/testing`.

## Global Constraints

- The local library source of truth is `GET /api/v1/library/tracks`; never infer it from `GET /api/v1/downloads`.
- The local card is always first, remains visible when empty, and uses the stable key `local-library-card`.
- The local detail is read-only: no rename, list deletion, track removal, metadata editing, or reordering.
- Playing one item passes the complete local queue and selected index; playing all starts at index `0`.
- Do not modify the Service API or persist a client-side copy of the library.
- Preserve all unrelated dirty-worktree changes; use narrow patches and do not update existing goldens unless separately authorized.
- Do not commit, push, deploy, or delete Service data without explicit user authorization.

## File Map

- Modify `lib/features/playlists/playlists_controller.dart`: aggregate playlist details and local library records with independent failure state.
- Modify `lib/features/playlists/playlists_screen.dart`: insert the first local card and expose separate local navigation.
- Modify `lib/features/playlists/playlist_detail_screen.dart`: expose the existing playlist detail root with a stable route-test key.
- Modify `lib/design/components/playlist_card.dart`: support a generic read-only collection presentation without manufacturing a `PlaylistSummary`.
- Create `lib/features/library/local_library_controller.dart`: own authoritative local-library loading and playback queue selection.
- Create `lib/features/library/local_library_screen.dart`: render the read-only local-library hero and adaptive track list.
- Modify `lib/events/event_coordinator.dart`: invalidate the local library for `library.*` and `downloads.*` events.
- Modify `lib/app/runtime_providers.dart`: expose `libraryVersion` and connect the new invalidation callback.
- Modify `lib/app/app.dart`: pass the local-library version reader to the router.
- Modify `lib/app/app_router.dart`: inject `LibraryRepository`, add `/library`, and key both relevant routes by `libraryVersion`.
- Modify `test/features/playlists/playlists_controller_test.dart`: cover aggregation and partial failures.
- Modify `test/features/playlists/playlists_screen_test.dart`: cover first-card ordering, empty state, and separate navigation.
- Modify `test/features/playlists/playlist_detail_screen_test.dart`: assert the stable existing playlist-detail route key.
- Create `test/features/library/local_library_controller_test.dart`: cover loading, stale state, and queue/index behavior.
- Create `test/features/library/local_library_screen_test.dart`: cover read-only UI on mobile and desktop.
- Modify `test/events/event_coordinator_test.dart`: cover library/download invalidation and sequence protection.
- Modify `test/app/app_shell_test.dart`: cover the production route from the local card to `/library`.
- Modify `test/visual/high_fidelity_fixtures.dart` and `test/visual/full_ui_gallery_test.dart`: satisfy the new constructor contract without regenerating goldens.

---

### Task 1: Aggregate playlists and local-library records

**Files:**
- Modify: `lib/features/playlists/playlists_controller.dart`
- Modify: `test/features/playlists/playlists_controller_test.dart`
- Modify: `test/visual/high_fidelity_fixtures.dart`

**Interfaces:**
- Consumes: `PlaylistRepository.listDetails() -> Future<List<PlaylistDetail>>`; `LibraryRepository.list() -> Future<List<LibraryTrack>>`.
- Produces: `PlaylistsController(PlaylistRepository repository, {required LibraryRepository library, String Function()? idFactory})`; `PlaylistsState.library`; `PlaylistsState.playlistError`; `PlaylistsState.libraryError`; compatibility getter `PlaylistsState.error`.

- [ ] **Step 1: Add failing aggregation and partial-failure tests**

Add `LibraryRepository` to the shared test setup and add tests that drive both endpoints from one `MockClient`:

```dart
test('refresh loads playlists and local library independently', () async {
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/library/tracks') {
        return data([
          {
            'id': 'file-1',
            'musicInfo': {'id': 'song-1', 'name': 'Local', 'source': 'kw'},
            'size': 12,
            'extension': 'mp3',
            'streamUrl': '/api/v1/library/tracks/file-1/stream',
          },
        ]);
      }
      if (request.url.path == '/api/v1/playlists') {
        return data([{'id': 'love', 'name': 'list__name_love'}]);
      }
      return data({'id': 'love', 'name': 'love', 'tracks': <Object?>[]});
    }),
  );
  final controller = PlaylistsController(
    PlaylistRepository(api),
    library: LibraryRepository(api),
  );

  await controller.refresh();

  expect(controller.state.items.single.id, 'love');
  expect(controller.state.library.single.track.title, 'Local');
  expect(controller.state.playlistError, isNull);
  expect(controller.state.libraryError, isNull);
});
```

Add two more cases: library fails while playlists remain visible, and playlists fail while library remains visible. In both cases assert `state.stale == true`, only the matching error field is non-null, and previously successful data is retained on a later failed refresh.

- [ ] **Step 2: Run the focused test and confirm failure**

Run:

```bash
flutter test test/features/playlists/playlists_controller_test.dart
```

Expected: compilation fails because the `library` constructor argument and state fields do not exist.

- [ ] **Step 3: Implement independent resource loading**

Change the state and controller boundary to:

```dart
final class PlaylistsState {
  const PlaylistsState({
    this.items = const [],
    this.library = const [],
    this.loading = false,
    this.stale = false,
    this.playlistError,
    this.libraryError,
  });

  final List<PlaylistDetail> items;
  final List<LibraryTrack> library;
  final bool loading;
  final bool stale;
  final Object? playlistError;
  final Object? libraryError;
  Object? get error => playlistError ?? libraryError;
}

final class PlaylistsController extends ChangeNotifier {
  PlaylistsController(
    this.repository, {
    required this.library,
    String Function()? idFactory,
  }) : _idFactory = idFactory ??
            (() => 'flutter_${DateTime.now().microsecondsSinceEpoch}');

  final PlaylistRepository repository;
  final LibraryRepository library;
}
```

In `refresh()`, preserve both existing lists, run two guarded loaders through `Future.wait`, record errors separately, then publish one final state:

```dart
List<PlaylistDetail>? nextItems;
List<LibraryTrack>? nextLibrary;
Object? playlistError;
Object? libraryError;

await Future.wait([
  () async {
    try {
      nextItems = await repository.listDetails();
    } on Object catch (error) {
      playlistError = error;
    }
  }(),
  () async {
    try {
      nextLibrary = await library.list();
    } on Object catch (error) {
      libraryError = error;
    }
  }(),
]);

state = PlaylistsState(
  items: nextItems ?? state.items,
  library: nextLibrary ?? state.library,
  stale: playlistError != null || libraryError != null,
  playlistError: playlistError,
  libraryError: libraryError,
);
notifyListeners();
```

Make `create()`, `delete()`, and `invalidate()` preserve library data and its error state. Update every test/fixture constructor in scope to pass `library: LibraryRepository(api)`.

- [ ] **Step 4: Run controller tests**

Run:

```bash
flutter test test/features/playlists/playlists_controller_test.dart test/features/home/home_controller_test.dart
```

Expected: all tests pass; the new tests prove either Service resource can fail without hiding the other.

- [ ] **Step 5: Review the task diff without committing**

Run:

```bash
git diff --check -- lib/features/playlists/playlists_controller.dart test/features/playlists/playlists_controller_test.dart test/visual/high_fidelity_fixtures.dart
git diff -- lib/features/playlists/playlists_controller.dart test/features/playlists/playlists_controller_test.dart test/visual/high_fidelity_fixtures.dart
```

Expected: no whitespace errors and no unrelated edits. Leave changes uncommitted because commit authorization has not been given.

---

### Task 2: Add the read-only local-library controller

**Files:**
- Create: `lib/features/library/local_library_controller.dart`
- Create: `test/features/library/local_library_controller_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository.list()`; existing `PlayTracks` typedef from `design/components/track_actions.dart`.
- Produces: `LocalLibraryState`; `LocalLibraryController.refresh()`; `playOne(PlayTracks, int)`; `playAll(PlayTracks)`; `loadPicture(Track)`.

- [ ] **Step 1: Write failing controller tests**

Create tests for successful loading, stale-data retention, complete queue selection, and empty-list playback:

```dart
test('playOne keeps the complete local queue and selected index', () async {
  final controller = LocalLibraryController(libraryRepositoryWith([
    libraryJson('file-a', 'a', 'A'),
    libraryJson('file-b', 'b', 'B'),
    libraryJson('file-c', 'c', 'C'),
  ]));
  List<String> queued = const [];
  var selectedIndex = -1;

  await controller.refresh();
  await controller.playOne((tracks, {startIndex = 0}) async {
    queued = tracks.map((track) => track.id).toList(growable: false);
    selectedIndex = startIndex;
  }, 1);

  expect(queued, ['a', 'b', 'c']);
  expect(selectedIndex, 1);
});
```

For the empty case, set a callback counter and assert both `playOne(..., 0)` and `playAll(...)` leave it at zero. For refresh failure, load once successfully, fail the next request, and assert records remain with `stale == true` and `error != null`.

- [ ] **Step 2: Run the test and confirm failure**

Run:

```bash
flutter test test/features/library/local_library_controller_test.dart
```

Expected: compilation fails because `LocalLibraryController` does not exist.

- [ ] **Step 3: Implement the controller**

Create the controller with this public state:

```dart
final class LocalLibraryState {
  const LocalLibraryState({
    this.items = const [],
    this.loading = false,
    this.stale = false,
    this.error,
  });

  final List<LibraryTrack> items;
  final bool loading;
  final bool stale;
  final Object? error;
  List<Track> get tracks =>
      items.map((item) => item.track).toList(growable: false);
}
```

`refresh()` must preserve existing `items` while loading and on failure. `playOne` and `playAll` must read one local `tracks` snapshot before calling `PlayTracks`:

```dart
Future<void> playOne(PlayTracks play, int index) async {
  final tracks = state.tracks;
  if (index < 0 || index >= tracks.length) return;
  await play(tracks, startIndex: index);
}

Future<void> playAll(PlayTracks play) async {
  final tracks = state.tracks;
  if (tracks.isNotEmpty) await play(tracks);
}
```

`loadPicture(Track track)` returns a resolved `http`/`https` `Uri` from `track.raw['pic']`, or `null`; it must not make a catalog request because the library snapshot is authoritative for this page.

- [ ] **Step 4: Run controller tests**

Run:

```bash
flutter test test/features/library/local_library_controller_test.dart
```

Expected: all local-library controller tests pass.

- [ ] **Step 5: Review the task diff without committing**

Run:

```bash
git diff --check -- lib/features/library/local_library_controller.dart test/features/library/local_library_controller_test.dart
```

Expected: no whitespace errors. Leave changes uncommitted.

---

### Task 3: Add a generic local collection card to “我的音乐”

**Files:**
- Modify: `lib/design/components/playlist_card.dart`
- Modify: `lib/features/playlists/playlists_screen.dart`
- Modify: `test/features/playlists/playlists_screen_test.dart`
- Modify: `test/visual/full_ui_gallery_test.dart`

**Interfaces:**
- Consumes: `PlaylistsState.library`, existing playlist grid sizing helpers.
- Produces: `PlaylistCard.collection(...)`; `PlaylistsScreen.onOpenLocal`.

- [ ] **Step 1: Add failing component and screen assertions**

Extend the existing wide-layout widget test so the fake API also returns one `LibraryTrack`, inject `LibraryRepository`, and pass a separate callback:

```dart
var localOpened = false;
await tester.pumpWidget(harness(PlaylistsScreen(
  controller: controller,
  onOpen: (id) => opened = id,
  onOpenLocal: () => localOpened = true,
)));

final local = find.byKey(const Key('local-library-card'));
final love = find.byKey(const Key('playlist-love'));
expect(local, findsOneWidget);
expect(tester.getTopLeft(local).dy, lessThanOrEqualTo(tester.getTopLeft(love).dy));
expect(find.text('本地音乐'), findsOneWidget);
expect(find.text('1 首'), findsOneWidget);
await tester.tap(local);
expect(localOpened, isTrue);
expect(opened, isNull);
```

Add an empty-library case asserting the card remains present with `0 首`, and verify no delete tooltip is found after long-pressing the local card.

- [ ] **Step 2: Run the widget test and confirm failure**

Run:

```bash
flutter test test/features/playlists/playlists_screen_test.dart
```

Expected: compilation fails because `onOpenLocal` and `PlaylistCard.collection` do not exist.

- [ ] **Step 3: Add a non-playlist presentation constructor**

Keep the existing `PlaylistCard` constructor source-compatible and add a named constructor that accepts display-only values without creating a `PlaylistSummary`:

```dart
const PlaylistCard.collection({
  super.key,
  required String id,
  required String name,
  required String metadata,
  required this.onPressed,
  this.imageUrl,
  this.variant = PlaylistCardVariant.row,
}) : playlist = null,
     collectionId = id,
     collectionName = name,
     collectionMetadata = metadata,
     onDelete = null;
```

Add private normalized getters used by both constructors:

```dart
String get _id => playlist?.id ?? collectionId!;
String get _name => playlist?.displayName ?? collectionName!;
String get _metadata => collectionMetadata ??
    (playlist is PlaylistDetail
        ? '${(playlist! as PlaylistDetail).tracks.length} 首'
        : playlist!.source?.isEmpty == false
            ? playlist!.source!
            : 'Service 歌单');
```

Use `_id`, `_name`, and `_metadata` throughout rendering. The named constructor always sets `onDelete` to null.

- [ ] **Step 4: Insert the first local card**

Add `required VoidCallback onOpenLocal` to `PlaylistsScreen`. Change grid item count to `state.items.length + 1`; index `0` builds:

```dart
PlaylistCard.collection(
  key: const Key('local-library-card'),
  id: 'local-library',
  name: '本地音乐',
  metadata: state.libraryError != null && state.library.isEmpty
      ? '暂不可用'
      : '${state.library.length} 首',
  imageUrl: state.library
      .map((item) => item.track.raw['pic'])
      .whereType<String>()
      .map(Uri.tryParse)
      .whereType<Uri>()
      .firstOrNull,
  variant: PlaylistCardVariant.gallery,
  onPressed: widget.onOpenLocal,
)
```

For other indexes use `state.items[index - 1]`. Keep create/delete behavior unchanged. Update the visual fixture constructor and gallery screen call with `onOpenLocal: () {}`; do not regenerate golden images.

- [ ] **Step 5: Run component and screen tests**

Run:

```bash
flutter test test/features/playlists/playlists_screen_test.dart test/design/app_components_test.dart
```

Expected: all tests pass; local card is first, stable when empty, and cannot expose deletion.

- [ ] **Step 6: Review the task diff without committing**

Run:

```bash
git diff --check -- lib/design/components/playlist_card.dart lib/features/playlists/playlists_screen.dart test/features/playlists/playlists_screen_test.dart test/visual/full_ui_gallery_test.dart
```

Expected: no whitespace errors. Leave changes uncommitted.

---

### Task 4: Build the read-only local-library detail screen

**Files:**
- Create: `lib/features/library/local_library_screen.dart`
- Create: `test/features/library/local_library_screen_test.dart`

**Interfaces:**
- Consumes: `LocalLibraryController`; `PlayTracks`; `CatalogTrackTableHeader`; `CatalogTrackRow`; `AppArtwork`; current breakpoint and token APIs.
- Produces: `LocalLibraryScreen({required LocalLibraryController controller, required PlayTracks playTracks})`.

- [ ] **Step 1: Write failing mobile and desktop widget tests**

Create a harness with the existing Shad theme and image-cache test scope. Preload a controller with two library records, then assert:

```dart
expect(find.byKey(const Key('local-library-route')), findsOneWidget);
expect(find.text('本地音乐'), findsOneWidget);
expect(find.text('2 首'), findsOneWidget);
expect(find.byKey(const Key('local-library-play-all')), findsOneWidget);
expect(find.byKey(const Key('playlist-rename')), findsNothing);
expect(find.byKey(const Key('playlist-delete')), findsNothing);
expect(find.byTooltip('从歌单移除'), findsNothing);
expect(find.byTooltip('拖动排序'), findsNothing);
```

Tap the second row and assert the play callback receives both tracks with `startIndex == 1`. Add an empty response case asserting “暂无本地音乐” and a disabled play-all button. Run the same read-only assertions at `390x844` and `1200x800`.

- [ ] **Step 2: Run the screen test and confirm failure**

Run:

```bash
flutter test test/features/library/local_library_screen_test.dart
```

Expected: compilation fails because `LocalLibraryScreen` does not exist.

- [ ] **Step 3: Implement adaptive read-only rendering**

Create a stateful screen that calls `controller.refresh()` from `initState()` only when `state.items` is empty, listens with `ListenableBuilder`, and disposes its controller. The top-level body must use key `local-library-route`.

The hero contains “当前 Service”, “本地音乐”, the count, the first valid artwork, and an `AppButton` keyed `local-library-play-all`:

```dart
AppButton(
  key: const Key('local-library-play-all'),
  onPressed: tracks.isEmpty
      ? null
      : () => widget.controller.playAll(widget.playTracks),
  leading: const Icon(LucideIcons.play),
  child: const Text('播放全部'),
)
```

For desktop, use `CatalogTrackTableHeader(showFavorite: false, ...)` and `CatalogTrackRow` with `onFavorite: null`, `reserveFavoriteSpace: false`, `actions: const []`, `trailing: null`, `rowKeyPrefix: 'local-library'`, and `singleTap: true`. For mobile, render a non-reorderable `ListView.builder` whose rows contain artwork, title, artist, and no action button; tapping a row calls `playOne`.

Show `AppEmptyState(message: '暂无本地音乐')` for an empty successful response. On failure, use `AppNotice.error`; if stale items exist, keep them visible. Expose a refresh button and `RefreshIndicator` without adding scan or delete actions.

- [ ] **Step 4: Run local-library UI tests**

Run:

```bash
flutter test test/features/library/local_library_controller_test.dart test/features/library/local_library_screen_test.dart
```

Expected: all tests pass on both target layouts.

- [ ] **Step 5: Review the task diff without committing**

Run:

```bash
git diff --check -- lib/features/library/local_library_screen.dart test/features/library/local_library_screen_test.dart
```

Expected: no whitespace errors. Leave changes uncommitted.

---

### Task 5: Wire routing and local-library invalidation

**Files:**
- Modify: `lib/events/event_coordinator.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/features/playlists/playlist_detail_screen.dart`
- Modify: `test/events/event_coordinator_test.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `test/features/playlists/playlist_detail_screen_test.dart`

**Interfaces:**
- Consumes: `LocalLibraryController`, `LocalLibraryScreen`, `LibraryRepository`, existing `EventInvalidation` and router builders.
- Produces: `EventInvalidation.libraryVersion`; `EventInvalidation.library()`; `EventCoordinator.invalidateLibrary`; `buildAppRouter(..., required int Function() readLibraryVersion)`; named route `local-library` at `/library`.

- [ ] **Step 1: Add failing event tests**

Update every `EventCoordinator` test constructor with `invalidateLibrary`. Add:

```dart
test('library and download events invalidate authoritative local music', () {
  var downloads = 0;
  var library = 0;
  final coordinator = EventCoordinator(
    invalidatePlaylists: () {},
    invalidateDownloads: () => downloads++,
    invalidateLibrary: () => library++,
    invalidatePlaylistDetail: (_) {},
  );

  coordinator.accept(
    const DomainEvent(type: 'library.updated', data: null, sequence: 1),
  );
  coordinator.accept(
    const DomainEvent(type: 'downloads.completed', data: null, sequence: 2),
  );

  expect(library, 2);
  expect(downloads, 1);
});
```

Keep the existing stale-sequence assertions and verify a rejected download event increments neither counter.

- [ ] **Step 2: Run the event test and confirm failure**

Run:

```bash
flutter test test/events/event_coordinator_test.dart
```

Expected: compilation fails because `invalidateLibrary` is not accepted.

- [ ] **Step 3: Implement the invalidation channel**

Add to `EventInvalidation`:

```dart
int libraryVersion = 0;

void library() {
  libraryVersion++;
  notifyListeners();
}
```

Extend `EventCoordinator` with `required this.invalidateLibrary`. In `accept()` use independent checks so download events invalidate both resources:

```dart
if (event.type.startsWith('downloads.')) {
  invalidateDownloads();
  invalidateLibrary();
}
if (event.type.startsWith('library.')) invalidateLibrary();
```

Pass `invalidation.library` from `eventSubscriptionProvider`.

- [ ] **Step 4: Wire controllers and routes**

Add `readLibraryVersion` to `buildAppRouter` and pass `() => invalidation.libraryVersion` from `app.dart`.

Update the `/playlists` route key and controller:

```dart
key: ValueKey(
  'playlists-${readPlaylistVersion()}-${readLibraryVersion()}',
),
controller: PlaylistsController(
  PlaylistRepository(connected.api),
  library: LibraryRepository(connected.api),
),
onOpenLocal: () => context.goNamed('local-library'),
```

Add a sibling shell route:

```dart
GoRoute(
  path: '/library',
  name: 'local-library',
  builder: (context, state) {
    final connected = requireConnected();
    return LocalLibraryScreen(
      key: ValueKey('local-library-${readLibraryVersion()}'),
      controller: LocalLibraryController(LibraryRepository(connected.api)),
      playTracks: playTracks,
    );
  },
),
```

Include `readLibraryVersion()` in the home route key as well, because the home dashboard displays library counts. Keep `/downloads` keyed only by `readDownloadVersion()`.

- [ ] **Step 5: Add production route assertions**

Add a focused `MusicFreeServiceApp` widget test to `test/app/app_shell_test.dart`. Its `MockClient` must return health, capabilities, empty event snapshot, one `love` playlist detail, and one `/api/v1/library/tracks` record. After the persisted connection settles:

```dart
final shell = tester.element(find.byKey(const Key('main-shell')));
shell.go('/playlists');
await tester.pumpAndSettle();

await tester.tap(find.byKey(const Key('local-library-card')));
await tester.pumpAndSettle();
expect(GoRouterState.of(
  tester.element(find.byKey(const Key('local-library-route'))),
).uri.path, '/library');

shell.go('/playlists');
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('playlist-love')));
await tester.pumpAndSettle();
expect(GoRouterState.of(
  tester.element(find.byKey(const Key('playlist-detail-route'))),
).uri.path, '/playlists/love');
```

Add `key: const Key('playlist-detail-route')` to the existing playlist detail page's top-level route widget, and update `test/features/playlists/playlist_detail_screen_test.dart` to assert that key. Do not introduce another router harness.

- [ ] **Step 6: Run event, router, and affected screen tests**

Run:

```bash
flutter test \
  test/events/event_coordinator_test.dart \
  test/features/playlists/playlists_screen_test.dart \
  test/features/library/local_library_controller_test.dart \
  test/features/library/local_library_screen_test.dart \
  test/app/app_shell_test.dart
```

Expected: all tests pass; events refresh the local resource and navigation remains distinct.

- [ ] **Step 7: Review the task diff without committing**

Run:

```bash
git diff --check -- lib/events/event_coordinator.dart lib/app/runtime_providers.dart lib/app/app.dart lib/app/app_router.dart test/events/event_coordinator_test.dart test/app
```

Expected: no whitespace errors and no unrelated route changes. Leave changes uncommitted.

---

### Task 6: Final integration verification

**Files:**
- Verify all files listed in the File Map.
- Do not modify visual golden baselines.

**Interfaces:**
- Consumes: completed Tasks 1–5.
- Produces: evidence that the frozen working tree satisfies the approved design without regressions.

- [ ] **Step 1: Format only changed Dart sources and tests**

Run:

```bash
dart format \
  lib/design/components/playlist_card.dart \
  lib/features/playlists/playlists_controller.dart \
  lib/features/playlists/playlists_screen.dart \
  lib/features/playlists/playlist_detail_screen.dart \
  lib/features/library/local_library_controller.dart \
  lib/features/library/local_library_screen.dart \
  lib/events/event_coordinator.dart \
  lib/app/runtime_providers.dart \
  lib/app/app.dart \
  lib/app/app_router.dart \
  test/features/playlists/playlists_controller_test.dart \
  test/features/playlists/playlists_screen_test.dart \
  test/features/playlists/playlist_detail_screen_test.dart \
  test/features/library/local_library_controller_test.dart \
  test/features/library/local_library_screen_test.dart \
  test/events/event_coordinator_test.dart \
  test/app/app_shell_test.dart \
  test/visual/high_fidelity_fixtures.dart \
  test/visual/full_ui_gallery_test.dart
```

Expected: only the listed feature files are formatted; no unrelated dirty file is touched.

- [ ] **Step 2: Run the focused feature suite**

Run:

```bash
flutter test \
  test/features/playlists/playlists_controller_test.dart \
  test/features/playlists/playlists_screen_test.dart \
  test/features/library/local_library_controller_test.dart \
  test/features/library/local_library_screen_test.dart \
  test/events/event_coordinator_test.dart \
  test/features/home/home_controller_test.dart \
  test/app/app_shell_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run targeted static analysis**

Run:

```bash
flutter analyze \
  lib/features/playlists \
  lib/features/library \
  lib/design/components/playlist_card.dart \
  lib/events/event_coordinator.dart \
  lib/app \
  test/features/playlists \
  test/features/library \
  test/events \
  test/app
```

Expected: no issues in the changed feature surface.

- [ ] **Step 4: Inspect the final diff and preserve user work**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Inspect each feature hunk, confirm the approved spec is covered, confirm no golden file changed, and distinguish pre-existing user modifications from this feature's files. Do not stage or commit.

- [ ] **Step 5: Perform device/Service verification when available**

With an authorized test Service and connected emulator/device:

1. Open “我的音乐” and verify “本地音乐” is the first card.
2. Open it and verify current Service library songs appear.
3. Tap the second song and confirm the complete local queue starts at index `1`.
4. Complete one test download and verify the card count/detail updates without restarting the client.
5. Confirm there are no rename, delete, remove, or reorder controls.

If no compatible Service is available, report device verification as not run and retain the focused automated evidence; do not fabricate runtime results.

## Handoff Criteria

- “本地音乐” is the stable first card and opens `/library`.
- The card/detail use `LibraryRepository`, not `DownloadRepository` or a synthetic playlist ID.
- The detail is read-only and preserves full-queue playback semantics.
- `downloads.*` and `library.*` invalidate local-library data without weakening event sequence checks.
- Focused tests and targeted analysis pass.
- No unrelated dirty-worktree content or golden baseline is overwritten.
