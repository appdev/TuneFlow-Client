# Player More Menu Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile player header's duplicate queue action with a two-item current-track menu for adding to a playlist and downloading.

**Architecture:** Keep queue presentation owned by `PlayerScreen`, and add playlist/download repositories as optional screen dependencies so existing preview and focused-test constructors remain source compatible. The production player route must always provide both repositories. Reuse the existing mobile track action sheet and repository-driven feedback patterns; do not create a second menu component.

**Tech Stack:** Flutter/Dart, `shadcn_ui`, existing `showAppSheet`/`TrackActionSheet`, `PlaylistRepository`, `DownloadRepository`, Flutter widget tests, `http` `MockClient`.

## Global Constraints

- The mobile footer list button remains the only direct playback-queue entry.
- The mobile header ellipsis menu contains exactly `添加到歌单` and `下载`.
- Use the existing mobile bottom-sheet visual language and existing success/error feedback.
- Do not change desktop player behavior, playback state, queue contents, or the current artwork/lyrics view.
- Do not add dependencies or refactor unrelated track-action code.
- Preserve all pre-existing dirty-worktree changes; do not commit unless the user separately authorizes it.

---

## File Structure

- Modify `lib/features/player/player_screen.dart`: own the two menu actions, playlist selection, repository calls, and operation feedback; expose `onMore` to the mobile header.
- Modify `lib/app/app_router.dart`: inject repositories created from the active connected service into the real player route.
- Modify `test/features/player/player_screen_test.dart`: prove menu contents, repository calls, feedback, failure containment, and retained queue behavior.

### Task 1: Lock the Mobile Header Menu Contract with Widget Tests

**Files:**
- Modify: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: existing `PlayerScreen`, `PlayerController`, `PlaylistRepository`, `DownloadRepository`, `ServiceApi`, and `MockClient`.
- Produces: failing tests for `PlayerScreen({PlaylistRepository? playlists, DownloadRepository? downloads})`, the semantic label `更多操作`, keys `player-mobile-more`, `player-playlist-<id>`, and existing action keys `track-action-addToPlaylist` / `track-action-download`.

- [x] **Step 1: Add HTTP-backed action repository fixtures**

Add imports for `dart:convert`, `package:http/http.dart` as `http`, `package:http/testing.dart`, `ServiceApi`, `ServiceOrigin`, `PlaylistRepository`, and `DownloadRepository`. Add a helper that creates both repositories from one handler:

```dart
({PlaylistRepository playlists, DownloadRepository downloads})
playerActionRepositories(
  Future<http.Response> Function(http.Request) handler,
) {
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  );
  return (
    playlists: PlaylistRepository(api),
    downloads: DownloadRepository(api),
  );
}
```

- [x] **Step 2: Write the failing menu-shape test**

Create a 390×844 widget test that starts one track, supplies repositories, opens the header action through `player-mobile-more`, and asserts the menu contains exactly the two intended action keys while the footer queue button remains present:

```dart
testWidgets('mobile player header opens only playlist and download actions', (
  tester,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repositories = playerActionRepositories(
    (_) async => http.Response(jsonEncode({'data': <Object?>[]}), 200),
  );
  final controller = PlayerController(resolver: FakeResolver(), audio: FakeAudio());
  await controller.playTracks([
    Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
  ]);

  await tester.pumpWidget(harness(PlayerScreen(
    controller: controller,
    lyricsLoader: (_) async => const Lyrics(original: ''),
    wakeLock: FakeWakeLock(),
    keepAwake: false,
    playlists: repositories.playlists,
    downloads: repositories.downloads,
  )));
  await tester.tap(find.byKey(const Key('player-mobile-more')));
  await pumpFiniteAnimations(tester);

  expect(find.bySemanticsLabel('更多操作'), findsOneWidget);
  expect(find.byKey(const Key('track-action-addToPlaylist')), findsOneWidget);
  expect(find.byKey(const Key('track-action-download')), findsOneWidget);
  expect(find.byKey(const Key('track-action-enqueue')), findsNothing);
  expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
});
```

- [x] **Step 3: Write failing action and error-containment tests**

Add focused tests using a recorded `List<http.Request>`:

```dart
// Playlist handler responses:
// GET /api/v1/playlists -> {'data': [{'id': 'daily', 'name': '每日收藏'}]}
// POST /api/v1/playlists/daily/tracks -> {'data': [trackJson]}
// Assert the selected action sends the current track id and shows `已添加到 每日收藏`.

// Download handler response:
// POST /api/v1/downloads -> a valid DownloadJob data object with id/status/
// musicInfo/quality/extension/fileName/downloaded/total/progress/
// queuePosition/createdAt/updatedAt.
// Assert request body musicInfo.id == `one`, quality matches
// SearchTrackMetadata.fromTrack(currentTrack).qualityKey, and feedback is
// `已加入下载队列`.

// Failure handler response:
// HTTP 500 with {'error': {'code': 'DOWNLOAD_FAILED', 'message': 'failed'}}.
// Assert `操作失败` is visible and controller.state.current?.id is still `one`.
```

Use `player-mobile-more`, `track-action-addToPlaylist`, `player-playlist-daily`, and `track-action-download` keys rather than text-only taps.

- [x] **Step 4: Run the new tests and confirm the contract fails**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile player header opens only playlist and download actions'
```

Expected: compilation fails because `PlayerScreen` does not yet accept `playlists` and `downloads`, or the `player-mobile-more` finder is absent.

### Task 2: Implement the Current-Track More Menu

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `PlaylistRepository.list()`, `PlaylistRepository.addTracks(String, List<Track>)`, `DownloadRepository.create(Track, String)`, `SearchTrackMetadata.fromTrack(Track)`, `showMobileTrackActions`, and `TrackAction`.
- Produces: nullable constructor properties `PlaylistRepository? playlists` and `DownloadRepository? downloads`; `_MobilePlayer.onMore`; widget keys `player-mobile-more` and `player-playlist-<playlist.id>`.

- [x] **Step 1: Add repository and track-action dependencies to `PlayerScreen`**

Import `app_button.dart`, the playlist/download repositories, `adaptive_track_actions.dart`, `search_track_metadata.dart`, and `track_action.dart`. Add source-compatible nullable properties:

```dart
final PlaylistRepository? playlists;
final DownloadRepository? downloads;
```

and constructor parameters:

```dart
this.playlists,
this.downloads,
```

The production route will supply both; null is retained only for existing previews/tests that never invoke the menu.

- [x] **Step 2: Add shared operation feedback and playlist selection**

Add `_run` and `_choosePlaylist` to `_PlayerScreenState`, following the same mounted checks and user-facing copy already used by `SearchScreen`:

```dart
Future<void> _run(
  Future<void> Function() operation, {
  String? success,
  String? successTitle,
}) async {
  try {
    await operation();
    if (mounted && successTitle != null) {
      showAppMessage(context, title: successTitle);
    } else if (mounted && success != null) {
      showAppMessage(context, title: '完成', message: success);
    }
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
```

`_choosePlaylist(Track track)` must call `widget.playlists!.list()`, show `AppEmptyState(message: '还没有歌单')` for an empty list, render ghost `AppButton`s keyed as `player-playlist-${playlist.id}`, and call `addTracks(playlist.id, [track])` with success text `已添加到 ${playlist.name}`.

- [x] **Step 3: Build and show exactly two actions for the latest current track**

Add `_more(Track track)` that constructs only these actions. Each item records its operation and closes the current menu; `_more` waits for the menu route to finish closing before running the selected operation, so “添加到歌单” can safely open the playlist sheet without overlapping Shad routes:

```dart
Future<void> _more(Track track) async {
  final playlists = widget.playlists;
  final downloads = widget.downloads;
  if (playlists == null || downloads == null) return;
  final metadata = SearchTrackMetadata.fromTrack(track);
  Future<void> Function()? selectedAction;
  await showMobileTrackActions(
    context,
    track: track,
    metadata: metadata,
    actions: [
      TrackAction(
        id: TrackActionId.addToPlaylist,
        label: '添加到歌单',
        icon: LucideIcons.heartPlus,
        invoke: () async {
          selectedAction = () => _run(() => _choosePlaylist(track));
          Navigator.of(context).pop();
        },
      ),
      TrackAction(
        id: TrackActionId.download,
        label: '下载',
        icon: LucideIcons.download,
        invoke: () async {
          selectedAction = () => _run(
            () => downloads.create(track, metadata.qualityKey),
            successTitle: '已加入下载队列',
          );
          Navigator.of(context).pop();
        },
      ),
    ],
  );
  await selectedAction?.call();
}
```

Pass `onMore: () => unawaited(_more(track))` when building `_MobilePlayer`; because `track` is read inside each current `ListenableBuilder` build, reopening after a track change uses the latest track.

- [x] **Step 4: Separate the header callback from queue behavior**

Add `VoidCallback onMore` to `_MobilePlayer` while retaining `onLyrics` for lyric retry. Also add `super.key` to `_MobileGlassIconButton` so the header control can expose a stable test key, then bind the header button as:

```dart
_MobileGlassIconButton(
  key: const Key('player-mobile-more'),
  label: '更多操作',
  icon: LucideIcons.ellipsis,
  onPressed: onMore,
),
```

The `_MobileGlassIconButton` constructor becomes:

```dart
const _MobileGlassIconButton({
  super.key,
  required this.label,
  required this.icon,
  required this.onPressed,
});
```

Do not change the `player-mobile-queue` footer button or its `onQueue` callback.

- [x] **Step 5: Run formatter and the focused player tests**

Run:

```bash
dart format lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: formatting completes without changes on a second pass, and all player screen tests pass including the new action tests.

### Task 3: Wire Production Repositories and Verify the Boundary

**Files:**
- Modify: `lib/app/app_router.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `_PlayerRouteCanvas`, active `ConnectedService.api`, `PlaylistRepository`, and `DownloadRepository`.
- Produces: a production `PlayerScreen` that always receives non-null action repositories.

- [x] **Step 1: Thread repositories through the player route canvas**

Add required `_PlayerRouteCanvas` fields and constructor parameters:

```dart
final PlaylistRepository playlists;
final DownloadRepository downloads;
```

In `playerRoute`, construct both from the already-resolved `connected.api`:

```dart
playlists: PlaylistRepository(connected.api),
downloads: DownloadRepository(connected.api),
```

Pass them from `_PlayerRouteCanvasState.build` into `PlayerScreen` as `playlists: widget.playlists` and `downloads: widget.downloads`.

- [x] **Step 2: Re-run the queue regression assertion**

Within the existing mobile player hierarchy test, tap `player-mobile-queue`, settle, and assert the `播放队列` sheet appears. This proves the footer behavior was not displaced by the new header menu.

- [x] **Step 3: Run targeted static analysis and tests**

Run:

```bash
dart format lib/app/app_router.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
flutter analyze lib/app/app_router.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: analyzer exits with no issues and all focused tests pass.

- [x] **Step 4: Review the final diff without touching unrelated changes**

Run:

```bash
git diff -- lib/app/app_router.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart docs/superpowers/specs/2026-08-15-player-more-menu-design.md docs/superpowers/plans/2026-08-15-player-more-menu.md
```

Confirm the diff contains only the menu behavior, production dependency wiring, focused tests, and the two documents. Do not stage or commit.
