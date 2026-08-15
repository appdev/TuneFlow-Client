# Player Download and Favorite Actions Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add direct, synchronized favorite and download actions for the current track to the desktop mini player, desktop full player, and mobile full player without navigating away.

**Architecture:** A shared `CurrentTrackActionsController` listens to the existing `PlayerController`, owns favorite/download request state, and guards asynchronous results by current-track generation. A reusable `CurrentTrackActionButtons` widget renders the two actions and existing app feedback in all three surfaces. Riverpod creates one controller per active Service connection and injects it into both the app shell and full-player route.

**Tech Stack:** Flutter/Dart, `ChangeNotifier`, Riverpod providers, `shadcn_ui`/`LucideIcons`, existing `PlaylistRepository`, `DownloadRepository`, `AppMessage` feedback, Flutter widget/unit tests.

## Global Constraints

- Favorite directly toggles the Service built-in `love` playlist; it never opens a playlist or navigation screen.
- Download directly calls `DownloadRepository.create` with the current track and `PlayerState.quality`; it never opens download management.
- Add actions only to the desktop mini player, desktop full player, and mobile full player. Keep the mobile mini player unchanged.
- Keep the mobile top “更多操作” entry for “添加到歌单”, but remove its duplicate download action.
- Every icon-only action has a minimum 44 px target, Chinese semantic label, and tooltip.
- Use `LucideIcons` for favorite/download; keep previous/play/pause/next exclusively behind `AppPlaybackIcons`/`AppPlaybackGlyph`.
- Favorite state must not rely on color alone: selected state uses a distinct button surface in addition to accent color and the “取消收藏” semantic label.
- Preserve unrelated dirty-worktree changes. Do not commit unless the user separately authorizes commits; any commit checkpoint below is skipped and reported when authorization is absent.
- Do not add dependencies or change the Service API.

---

## File Structure

- Create `lib/features/playlists/favorite_playlist.dart`: feature-owned `FavoritePlaylistPort` and `LovePlaylistFavorites` adapter, moved out of the macOS platform coordinator.
- Create `lib/features/player/current_track_actions_controller.dart`: shared current-track identity, favorite state, download state, optimistic update, rollback, and stale-result protection.
- Create `lib/features/player/current_track_action_buttons.dart`: reusable two-button UI and success/error feedback.
- Modify `lib/platform/macos_menu_bar_coordinator.dart`: import/re-export the moved favorite adapter without changing menu-bar behavior or existing imports.
- Modify `lib/app/player_providers.dart`: construct and dispose one shared action controller per connected player.
- Modify `lib/app/app.dart`, `lib/app/app_router.dart`, and `lib/app/app_shell.dart`: inject the shared action controller into the persistent desktop mini player and full-player route.
- Modify `lib/features/player/mini_player.dart`: render the desktop mini-player action group near track identity; leave mobile mini layout unchanged.
- Modify `lib/features/player/player_screen.dart`: inject shared actions, pass them to desktop/mobile controls, and reduce the mobile more menu to “添加到歌单”.
- Modify `lib/features/player/desktop_player_controls.dart`: render the full-player action group at bottom left.
- Modify `lib/features/player/mobile_player_controls.dart`: render actions between metadata/quality and playback progress.
- Create `test/features/player/current_track_actions_controller_test.dart`: controller concurrency and state tests.
- Create `test/features/player/current_track_action_buttons_test.dart`: action semantics, feedback, loading, and selected-shape tests.
- Modify `test/features/player/player_screen_test.dart`: three-surface layout/action tests and replacement of obsolete mobile-more download tests.
- Modify `test/platform/macos_menu_bar_coordinator_test.dart` only if its import needs updating; behavior assertions remain unchanged.

---

### Task 1: Extract the favorite adapter and build the shared action controller

**Files:**
- Create: `lib/features/playlists/favorite_playlist.dart`
- Create: `lib/features/player/current_track_actions_controller.dart`
- Modify: `lib/platform/macos_menu_bar_coordinator.dart:1-38`
- Create: `test/features/player/current_track_actions_controller_test.dart`
- Test: `test/platform/macos_menu_bar_coordinator_test.dart`

**Interfaces:**
- Consumes: `PlayerController.state.current`, `PlayerController.state.quality`, `PlaylistRepository.get/addTracks/removeTracks`, and `DownloadRepository.create` through an injected callback.
- Produces:
  - `abstract interface class FavoritePlaylistPort { Future<bool> contains(Track track); Future<void> setFavorite(Track track, bool favorite); }`
  - `final class LovePlaylistFavorites implements FavoritePlaylistPort`
  - `typedef DownloadCurrentTrack = Future<void> Function(Track track, String quality);`
  - `final class CurrentTrackActionsController extends ChangeNotifier`
  - Controller getters: `track`, `favorite`, `favoriteKnown`, `favoritePending`, `downloadPending`, `canToggleFavorite`, and `canDownload`.
  - Controller methods: `Future<void> toggleFavorite()`, `Future<void> downloadCurrent()`, and `dispose()`.

- [x] **Step 1: Write controller tests for initial favorite state and stale lookups**

Create fakes that expose completers and recorded calls, then add these exact behaviors:

```dart
test('loads favorite state for the current track', () async {
  final player = await playerWithTracks([track('a')]);
  final favorites = FakeFavorites()..containsResult = true;
  final actions = CurrentTrackActionsController(
    player: player,
    favorites: favorites,
    download: (_, _) async {},
  );
  addTearDown(actions.dispose);

  await favorites.flushContains();

  expect(actions.track?.id, 'a');
  expect(actions.favoriteKnown, isTrue);
  expect(actions.favorite, isTrue);
  expect(actions.canToggleFavorite, isTrue);
});

test('ignores a stale favorite lookup after the current track changes', () async {
  final player = await playerWithTracks([track('a'), track('b')]);
  final favorites = DeferredFavorites();
  final actions = CurrentTrackActionsController(
    player: player,
    favorites: favorites,
    download: (_, _) async {},
  );
  addTearDown(actions.dispose);

  await player.next();
  favorites.complete('b', true);
  favorites.complete('a', false);
  await Future<void>.delayed(Duration.zero);

  expect(actions.track?.id, 'b');
  expect(actions.favorite, isTrue);
});
```

The local `playerWithTracks` helper uses the same fake resolver/audio pattern as `player_screen_test.dart`; `track(id)` returns `Track.fromJson({'id': id, 'name': id, 'source': 'kw'})`.

- [x] **Step 2: Write controller tests for optimistic favorite, rollback, quality, and duplicate suppression**

```dart
test('optimistically toggles favorite and rolls back on failure', () async {
  final player = await playerWithTracks([track('a')]);
  final favorites = FakeFavorites()
    ..containsResult = false
    ..setError = StateError('favorite failed');
  final actions = CurrentTrackActionsController(
    player: player,
    favorites: favorites,
    download: (_, _) async {},
  );
  addTearDown(actions.dispose);
  await favorites.flushContains();

  final pending = actions.toggleFavorite();
  expect(actions.favorite, isTrue);
  expect(actions.favoritePending, isTrue);
  await expectLater(pending, throwsStateError);

  expect(actions.favorite, isFalse);
  expect(actions.favoritePending, isFalse);
  expect(favorites.setCalls, ['kw:a:true']);
});

test('downloads once with the current player quality', () async {
  final player = await playerWithTracks([track('a')], quality: 'flac');
  final favorites = FakeFavorites()..containsResult = false;
  final gate = Completer<void>();
  final calls = <String>[];
  final actions = CurrentTrackActionsController(
    player: player,
    favorites: favorites,
    download: (value, quality) async {
      calls.add('${value.source}:${value.id}:$quality');
      await gate.future;
    },
  );
  addTearDown(actions.dispose);

  final first = actions.downloadCurrent();
  final second = actions.downloadCurrent();
  expect(actions.downloadPending, isTrue);
  expect(calls, ['kw:a:flac']);
  gate.complete();
  await Future.wait([first, second]);
  expect(actions.downloadPending, isFalse);
});
```

Also assert a successful favorite toggle records `setFavorite(track, true)` and leaves `favorite == true` after completion.

- [x] **Step 3: Run the new tests and verify the missing-type failure**

Run:

```sh
flutter test test/features/player/current_track_actions_controller_test.dart
```

Expected: compilation fails because `favorite_playlist.dart` and `CurrentTrackActionsController` do not exist.

- [x] **Step 4: Move the favorite adapter into the feature layer**

Create `favorite_playlist.dart` with the current production behavior:

```dart
abstract interface class FavoritePlaylistPort {
  Future<bool> contains(Track track);
  Future<void> setFavorite(Track track, bool favorite);
}

final class LovePlaylistFavorites implements FavoritePlaylistPort {
  const LovePlaylistFavorites(this._repository);
  final PlaylistRepository _repository;

  @override
  Future<bool> contains(Track track) async {
    final playlist = await _repository.get('love');
    return playlist.tracks.any(
      (item) => item.source == track.source && item.id == track.id,
    );
  }

  @override
  Future<void> setFavorite(Track track, bool favorite) async {
    if (favorite) {
      await _repository.addTracks('love', [track]);
    } else {
      await _repository.removeTracks('love', [track.id]);
    }
  }
}
```

Remove these declarations from `macos_menu_bar_coordinator.dart`, import the new file, and add:

```dart
export '../features/playlists/favorite_playlist.dart';
```

The export preserves existing callers/tests that import the coordinator file for `LovePlaylistFavorites`.

- [x] **Step 5: Implement `CurrentTrackActionsController` minimally**

Use a monotonically increasing `_generation` and compare `${track.source}:${track.id}` before applying async results. The implementation contract is:

```dart
typedef DownloadCurrentTrack = Future<void> Function(
  Track track,
  String quality,
);

final class CurrentTrackActionsController extends ChangeNotifier {
  CurrentTrackActionsController({
    required PlayerController player,
    required FavoritePlaylistPort favorites,
    required DownloadCurrentTrack download,
  });

  Track? get track;
  bool get favorite;
  bool get favoriteKnown;
  bool get favoritePending;
  bool get downloadPending;
  bool get canToggleFavorite;
  bool get canDownload;

  Future<void> toggleFavorite();
  Future<void> downloadCurrent();

  @override
  void dispose();
}
```

Constructor behavior:

```dart
_player.addListener(_syncTrack);
_syncTrack();
```

`_syncTrack` resets favorite-known/pending/download-pending state only when the `source:id` identity changes, increments `_generation`, notifies listeners, and starts `_loadFavorite(track, generation)` without awaiting it. `toggleFavorite` updates `favorite` before awaiting `setFavorite`, rolls back and rethrows on failure, and never lets an old generation update the current track. `downloadCurrent` reads `_player.state.quality` at click time, suppresses a second call while pending, clears pending in `finally` only for the same generation, and rethrows repository failures for UI feedback.

- [x] **Step 6: Run focused controller and existing menu-bar tests**

Run:

```sh
dart format lib/features/playlists/favorite_playlist.dart lib/features/player/current_track_actions_controller.dart lib/platform/macos_menu_bar_coordinator.dart test/features/player/current_track_actions_controller_test.dart
flutter test test/features/player/current_track_actions_controller_test.dart
flutter test test/platform/macos_menu_bar_coordinator_test.dart
```

Expected: all tests pass; menu-bar favorite behavior is unchanged.

- [x] **Step 7: Review checkpoint / optional commit**

Inspect `git diff --check` and the Task 1 diff. If and only if commit authorization exists:

```sh
git add lib/features/playlists/favorite_playlist.dart lib/features/player/current_track_actions_controller.dart lib/platform/macos_menu_bar_coordinator.dart test/features/player/current_track_actions_controller_test.dart
git commit -m "feat: add shared current track actions"
```

Without commit authorization, leave changes unstaged and continue.

---

### Task 2: Build the reusable favorite/download action buttons

**Files:**
- Create: `lib/features/player/current_track_action_buttons.dart`
- Create: `test/features/player/current_track_action_buttons_test.dart`

**Interfaces:**
- Consumes: `CurrentTrackActionsController`, `showAppMessage`, `appErrorMessage`, `ShadButton.raw`, `LucideIcons.heart`, and `LucideIcons.download`.
- Produces:
  - `CurrentTrackActionButtons({required CurrentTrackActionsController controller, required String keyPrefix, Color? foreground, Color? selectedForeground, Color? selectedBackground})`.
  - Stable keys: `<keyPrefix>-favorite`, `<keyPrefix>-download`, `<keyPrefix>-favorite-loading`, and `<keyPrefix>-download-loading`.

- [x] **Step 1: Write widget tests for semantics, selected shape, and actions**

Use a real `CurrentTrackActionsController` with fake ports inside the existing Shad/Material harness:

```dart
testWidgets('renders direct favorite and download actions with 44px targets', (
  tester,
) async {
  final fixture = await pumpActions(tester, favorite: false);

  for (final key in ['test-favorite', 'test-download']) {
    expect(tester.getSize(find.byKey(Key(key))), const Size.square(44));
  }
  expect(find.bySemanticsLabel('收藏当前歌曲'), findsOneWidget);
  expect(find.bySemanticsLabel('下载当前歌曲'), findsOneWidget);

  await tester.tap(find.byKey(const Key('test-favorite')));
  await tester.pump();
  expect(fixture.favorites.setCalls, ['kw:a:true']);
  expect(find.bySemanticsLabel('取消收藏'), findsOneWidget);
  expect(
    tester.widget<ShadButton>(find.byKey(const Key('test-favorite'))).variant,
    ShadButtonVariant.secondary,
  );
});
```

Add a download test that taps `test-download`, asserts one recorded `kw:a:128k` call, completes the fake request, and finds `已加入下载队列`.

- [x] **Step 2: Write widget tests for pending and failure feedback**

```dart
testWidgets('blocks duplicate downloads and restores the button on failure', (
  tester,
) async {
  final fixture = await pumpActions(tester, deferDownload: true);

  await tester.tap(find.byKey(const Key('test-download')));
  await tester.pump();

  expect(fixture.downloadCalls, ['kw:a:128k']);
  expect(find.byKey(const Key('test-download-loading')), findsOneWidget);
  fixture.downloadCompleter.completeError(StateError('download failed'));
  await tester.pumpAndSettle();
  expect(find.text('下载失败'), findsOneWidget);
  expect(find.byKey(const Key('test-download-loading')), findsNothing);
});
```

Add the matching favorite-failure assertion: the selected state rolls back, the label returns to `收藏当前歌曲`, and the message title is `收藏失败`.

- [x] **Step 3: Run the new widget test and verify failure**

Run:

```sh
flutter test test/features/player/current_track_action_buttons_test.dart
```

Expected: compilation fails because `CurrentTrackActionButtons` does not exist.

- [x] **Step 4: Implement the reusable button group**

Implement a `ListenableBuilder` around the controller and two fixed 44×44 `ShadButton.raw` controls. The favorite button uses `ShadButtonVariant.secondary` when selected and `ghost` otherwise; download always uses `ghost`. Each control is wrapped in `Tooltip` and `Semantics`:

```dart
final favoriteLabel = controller.favorite ? '取消收藏' : '收藏当前歌曲';

Semantics(
  button: true,
  enabled: controller.canToggleFavorite,
  selected: controller.favorite,
  label: favoriteLabel,
  child: Tooltip(
    message: favoriteLabel,
    child: ShadButton.raw(
      key: Key('$keyPrefix-favorite'),
      variant: controller.favorite
          ? ShadButtonVariant.secondary
          : ShadButtonVariant.ghost,
      width: 44,
      height: 44,
      padding: EdgeInsets.zero,
      enabled: controller.canToggleFavorite,
      onPressed: _toggleFavorite,
      child: controller.favoritePending
          ? _ActionProgress(key: Key('$keyPrefix-favorite-loading'))
          : const Icon(LucideIcons.heart, size: 20),
    ),
  ),
)
```

The download button follows the same structure with `下载当前歌曲`, `LucideIcons.download`, and `controller.downloadPending`. `_toggleFavorite` and `_download` catch `Object`, verify `context.mounted`, and use:

Apply the optional palette overrides directly on `ShadButton.raw`: ordinary icons use `foregroundColor: foreground`; the selected favorite uses `foregroundColor: selectedForeground ?? foreground` and `backgroundColor: selectedBackground` in addition to `ShadButtonVariant.secondary`. When overrides are null, allow the active Shad theme variant to supply its normal colors.

```dart
showAppMessage(
  context,
  title: '收藏失败',
  message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
  destructive: true,
);
```

```dart
showAppMessage(context, title: '已加入下载队列');
```

Download failure uses title `下载失败`. `_ActionProgress` is an 18×18 `CircularProgressIndicator(strokeWidth: 2)` so the button geometry never changes.

- [x] **Step 5: Run and format the component tests**

Run:

```sh
dart format lib/features/player/current_track_action_buttons.dart test/features/player/current_track_action_buttons_test.dart
flutter test test/features/player/current_track_action_buttons_test.dart
```

Expected: all tests pass.

- [x] **Step 6: Review checkpoint / optional commit**

Inspect `git diff --check` and the Task 2 diff. If and only if commit authorization exists:

```sh
git add lib/features/player/current_track_action_buttons.dart test/features/player/current_track_action_buttons_test.dart
git commit -m "feat: add current track action buttons"
```

Without commit authorization, leave changes unstaged and continue.

---

### Task 3: Integrate the actions into all three approved player surfaces

**Files:**
- Modify: `lib/features/player/mini_player.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Modify: `lib/features/player/mobile_player_controls.dart`
- Modify: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `CurrentTrackActionButtons`, optional `CurrentTrackActionsController? actions`, and current `PlayerScreen` playlist-selection behavior.
- Produces:
  - `MiniPlayer(..., CurrentTrackActionsController? actions)`.
  - `PlayerScreen(..., CurrentTrackActionsController? actions)`.
  - `DesktopPlayerControls(..., CurrentTrackActionsController? actions)`.
  - `MobilePlayerControls(..., CurrentTrackActionsController? actions)`.
  - Surface keys `desktop-mini-favorite/download`, `desktop-full-favorite/download`, and `mobile-full-favorite/download`.

- [x] **Step 1: Replace obsolete mobile-more tests with direct-action tests**

Change the current test `mobile player header opens only playlist and download actions` to assert that the direct buttons exist and the more sheet retains only playlist selection:

```dart
expect(find.byKey(const Key('mobile-full-favorite')), findsOneWidget);
expect(find.byKey(const Key('mobile-full-download')), findsOneWidget);
await tester.tap(find.byKey(const Key('player-mobile-more')));
await pumpFiniteAnimations(tester);
expect(find.byKey(const Key('track-action-addToPlaylist')), findsOneWidget);
expect(find.byKey(const Key('track-action-download')), findsNothing);
```

Update the existing download success/failure tests to tap `mobile-full-download` directly. Add a local `FakeFavorites implements FavoritePlaylistPort` whose `contains` returns the configured boolean and whose `setFavorite` records calls. Construct `CurrentTrackActionsController` from the fixture player, `FakeFavorites(false)`, and a callback that awaits `repositories.downloads.create(track, quality)`, then pass it as `actions:` to `PlayerScreen`. This keeps the favorite-state lookup independent from the existing playlist-list HTTP handler.

- [x] **Step 2: Add desktop mini and desktop full placement tests**

Extend the persistent desktop test:

```dart
expect(find.byKey(const Key('desktop-mini-favorite')), findsOneWidget);
expect(find.byKey(const Key('desktop-mini-download')), findsOneWidget);
await tester.tap(find.byKey(const Key('desktop-mini-favorite')));
await tester.pump();
expect(opened, isFalse);
```

Extend the full-player test:

```dart
expect(find.byKey(const Key('desktop-full-favorite')), findsOneWidget);
expect(find.byKey(const Key('desktop-full-download')), findsOneWidget);
final actionRect = tester.getRect(
  find.byKey(const Key('desktop-full-favorite')),
);
final coreRect = tester.getRect(find.byKey(const Key('player-desktop-core')));
expect(actionRect.center.dx, lessThan(coreRect.left));
```

Keep the existing right-side quality/queue assertions so the test proves that group was not replaced.

- [x] **Step 3: Add shared-state and mobile-mini exclusion assertions**

In a widget test that rebuilds from desktop `MiniPlayer` to desktop `PlayerScreen` using the same action controller, favorite from `desktop-mini-favorite`, then assert `find.bySemanticsLabel('取消收藏')` in the full player. In the existing mobile mini test add:

```dart
expect(find.byKey(const Key('mobile-full-favorite')), findsNothing);
expect(find.byKey(const Key('mobile-full-download')), findsNothing);
```

This proves shared state and the explicit mobile-mini non-goal.

- [x] **Step 4: Run focused widget tests and verify missing-button failures**

Run:

```sh
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile player exposes direct actions and keeps playlist selection in more'
flutter test test/features/player/player_screen_test.dart --plain-name 'desktop player exposes the persistent transport surface'
flutter test test/features/player/player_screen_test.dart --plain-name 'full player exposes controls and scopes keep-awake to route'
```

Expected: tests fail because the three surfaces do not render `CurrentTrackActionButtons` yet.

- [x] **Step 5: Add desktop mini-player actions without changing mobile mini**

Add optional `actions` to `MiniPlayer` and `_DesktopMiniPlayer`, passing it only through the desktop branch. In the desktop left `Expanded(flex: 7)` group, keep artwork/title/artist and add:

```dart
if (actions != null)
  CurrentTrackActionButtons(
    controller: actions!,
    keyPrefix: 'desktop-mini',
  ),
```

Place the action row under the title/artist inside the identity area, maintaining the 96 px shell height. Do not add `actions` to the mobile `Row`, and ensure tapping either child button wins the gesture arena instead of invoking `onOpen`.

- [x] **Step 6: Add bottom-left desktop full-player actions**

Add optional `actions` to `DesktopPlayerControls`. Inside its existing `Stack`, add an `Align(alignment: Alignment.bottomLeft)` with `Padding(left: AppSpacing.lg, bottom: 8)` and:

```dart
CurrentTrackActionButtons(
  controller: actions,
  keyPrefix: 'desktop-full',
  foreground: palette.foreground,
  selectedForeground: palette.foreground,
  selectedBackground: palette.vinylAccent.withValues(alpha: .18),
)
```

Keep `player-desktop-core` centered and the quality/queue group aligned bottom right.

- [x] **Step 7: Add mobile full-player actions**

Add optional `actions` to `MobilePlayerControls`. After the metadata/quality row and before `PlaybackProgress`, render a right-aligned or centered `CurrentTrackActionButtons(controller: actions, keyPrefix: 'mobile-full')` with 44 px targets. Preserve current progress and transport spacing without changing the mobile mini player.

In `PlayerScreen`, add optional `actions`, pass it to `DesktopPlayerControls` and `MobilePlayerControls`, and keep the action controller external rather than constructing repositories in the widget.

- [x] **Step 8: Remove the duplicate download item from mobile more**

Keep `_choosePlaylist` and `PlaylistRepository? playlists`. Change `_more` so it requires only playlists and builds exactly one `TrackAction`:

```dart
TrackAction(
  id: TrackActionId.addToPlaylist,
  label: '添加到歌单',
  icon: LucideIcons.heartPlus,
  invoke: () async {
    selectedAction = () => _run(() => _choosePlaylist(track));
    Navigator.of(context).pop();
  },
)
```

Remove direct `DownloadRepository` ownership/import and the `downloads` constructor field from `PlayerScreen`; download is now owned by the shared controller. Remove `downloads:` from every `PlayerScreen` call site. Tests that exercise direct actions pass `actions:`; all other existing tests continue to omit the optional action controller.

- [x] **Step 9: Format and run the complete player widget suite**

Run:

```sh
dart format lib/features/player/mini_player.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: all player widget tests pass, including direct actions, more-menu playlist selection, mobile-mini exclusion, and existing playback/layout assertions.

- [x] **Step 10: Review checkpoint / optional commit**

Inspect `git diff --check` and the Task 3 diff. If and only if commit authorization exists:

```sh
git add lib/features/player/mini_player.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart test/features/player/player_screen_test.dart
git commit -m "feat: add player favorite and download actions"
```

Without commit authorization, leave changes unstaged and continue.

---

### Task 4: Wire one shared controller through production providers and routes

**Files:**
- Modify: `lib/app/player_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: `connectionProvider`, `playerControllerProvider`, `LovePlaylistFavorites`, `PlaylistRepository`, and `DownloadRepository`.
- Produces:
  - `currentTrackActionsProvider: Provider<CurrentTrackActionsController?>`.
  - `buildAppRouter(..., required CurrentTrackActionsController? Function() readCurrentTrackActions)`.
  - `_PlayerRouteCanvas(..., required CurrentTrackActionsController actions)`.
  - `AppShell(..., CurrentTrackActionsController? currentTrackActions)`.

- [x] **Step 1: Add production-wiring assertions to the connected desktop app test**

Extend the existing `connects and enters the route-based home shell` test. In its `MockClient`, handle these requests before the current path switch:

```dart
if (request.method == 'GET' &&
    request.url.path == '/api/v1/playlists/love') {
  return http.Response(
    jsonEncode({
      'data': {'id': 'love', 'name': '我的收藏', 'tracks': <Object?>[]},
    }),
    200,
  );
}
if (request.method == 'POST' &&
    request.url.path == '/api/v1/playlists/love/tracks') {
  return http.Response(
    jsonEncode({
      'data': [
        {'id': 'desktop-inset', 'name': '遮挡测试', 'source': 'kw'},
      ],
    }),
    200,
  );
}
```

The test already obtains the `ProviderContainer` and calls `playerControllerProvider.playTracks` for `desktop-inset`. After that call, use `pumpAndSettle()` so the favorite lookup completes, then assert:

```dart
expect(find.byKey(const Key('desktop-mini-favorite')), findsOneWidget);
expect(find.byKey(const Key('desktop-mini-download')), findsOneWidget);
```

Tap `desktop-mini-favorite`, pump to complete the POST, then use the test's existing `router.go('/player')` transition and assert:

```dart
expect(find.byKey(const Key('desktop-full-favorite')), findsOneWidget);
expect(find.byKey(const Key('desktop-full-download')), findsOneWidget);
expect(find.bySemanticsLabel('取消收藏'), findsOneWidget);
```

These assertions prove the router and shell receive the same action-controller instance.

- [x] **Step 2: Run the production-wiring test and verify failure**

Run the existing test name changed in Step 1:

```sh
flutter test test/app/app_shell_test.dart --plain-name 'connects and enters the route-based home shell'
```

Expected: failure because no provider or router injection exists.

- [x] **Step 3: Add `currentTrackActionsProvider`**

In `player_providers.dart`:

```dart
final currentTrackActionsProvider =
    Provider<CurrentTrackActionsController?>((ref) {
  final connected = ref.watch(connectionProvider).value;
  final player = ref.watch(playerControllerProvider);
  if (connected == null || player == null) return null;
  final playlists = PlaylistRepository(connected.api);
  final downloads = DownloadRepository(connected.api);
  final controller = CurrentTrackActionsController(
    player: player,
    favorites: LovePlaylistFavorites(playlists),
    download: (track, quality) async {
      await downloads.create(track, quality);
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});
```

Do not construct another action controller inside a widget or route.

- [x] **Step 4: Pass the provider through app/router boundaries**

In `app.dart`, make `appRouterProvider` watch the shared controller and pass a read callback:

```dart
ref.watch(currentTrackActionsProvider);
// ...
readCurrentTrackActions: () => ref.read(currentTrackActionsProvider),
```

Add the callback to `buildAppRouter`. In connected routes, require the non-null controller once:

```dart
CurrentTrackActionsController requireCurrentTrackActions() =>
    readCurrentTrackActions()!;
```

Pass it to `AppShell(currentTrackActions: ...)` and `_PlayerRouteCanvas(actions: ...)`; `_PlayerRouteCanvas` passes the same instance to `PlayerScreen(actions: ...)`. Remove the old `_PlayerRouteCanvas.downloads` field and `PlayerScreen(downloads: ...)` argument because direct downloads now use the shared controller. Keep `PlaylistRepository` on `PlayerScreen` for “添加到歌单”.

- [x] **Step 5: Pass shared actions to the persistent desktop mini player**

Add nullable `currentTrackActions` to `AppShell` so isolated previews remain source compatible. Pass it to the desktop `MiniPlayer(actions: currentTrackActions)`. Do not pass it into `AppMobileDock` or change the mobile mini-player layout.

- [x] **Step 6: Run app wiring and focused UI tests**

Run:

```sh
dart format lib/app/player_providers.dart lib/app/app.dart lib/app/app_router.dart lib/app/app_shell.dart test/app/app_shell_test.dart
flutter test test/app/app_shell_test.dart --plain-name 'connects and enters the route-based home shell'
flutter test test/features/player/current_track_actions_controller_test.dart
flutter test test/features/player/current_track_action_buttons_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: all commands pass.

- [x] **Step 7: Run the icon-system checks required by `AGENTS.md`**

Run:

```sh
flutter test test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: both widget suites pass; the first `rg` returns no matches; the second returns only matches in `lib/design/components/app_playback_button.dart`.

- [x] **Step 8: Run final static and diff verification**

Run:

```sh
flutter analyze
git diff --check
git status --short
git diff -- lib/features/playlists/favorite_playlist.dart lib/features/player/current_track_actions_controller.dart lib/features/player/current_track_action_buttons.dart lib/features/player/mini_player.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart lib/platform/macos_menu_bar_coordinator.dart lib/app/player_providers.dart lib/app/app.dart lib/app/app_router.dart lib/app/app_shell.dart test/features/player/current_track_actions_controller_test.dart test/features/player/current_track_action_buttons_test.dart test/features/player/player_screen_test.dart test/app/app_shell_test.dart
```

Expected: analyzer and diff check pass. The scoped diff contains only the approved action feature plus necessary constructor/test updates; unrelated dirty files remain untouched.

- [x] **Step 9: Final review checkpoint / optional commit**

If and only if commit authorization exists, stage exactly the reviewed feature files and commit:

```sh
git add lib/features/playlists/favorite_playlist.dart lib/features/player/current_track_actions_controller.dart lib/features/player/current_track_action_buttons.dart lib/features/player/mini_player.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart lib/platform/macos_menu_bar_coordinator.dart lib/app/player_providers.dart lib/app/app.dart lib/app/app_router.dart lib/app/app_shell.dart test/features/player/current_track_actions_controller_test.dart test/features/player/current_track_action_buttons_test.dart test/features/player/player_screen_test.dart test/app/app_shell_test.dart
git commit -m "feat: add direct player download and favorite actions"
```

Without commit authorization, leave all feature changes uncommitted and report the verified working-tree state.
