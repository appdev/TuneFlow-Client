# Local Favorites and Playback Interaction Consistency Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add “收藏到歌单” to local music and unify filled playback controls, splash behavior, progress-track contrast, and system-theme following across Flutter targets.

**Architecture:** Keep Service playlist and local-library data boundaries unchanged. Add playback-specific semantic tokens and shared playback controls in the design layer, apply splash suppression at the Material theme boundary, and connect `LocalLibraryScreen` to the existing `PlaylistRepository` flow. Verify system-theme behavior through the real app widget with simulated platform brightness, while reporting device verification separately.

**Tech Stack:** Flutter 3.47, Dart, Riverpod, GoRouter, shadcn_ui, Material Ink, `flutter_test`, `http/testing`.

## Global Constraints

- Preserve all unrelated dirty-worktree changes; do not regenerate goldens unless a later visual failure proves they are intentionally affected and the user authorizes it.
- Do not modify the Service API, playlist JSON shape, local-library scanning, playback state, or seek data flow.
- Local favorites must call `PlaylistRepository.list()` and `PlaylistRepository.addTracks()` with the existing local `Track` snapshot.
- Filled playback controls use a solid playback glyph and semantic pure-white foreground; ordinary unfilled controls remain neutral.
- White text on `playbackAction` must reach at least `4.5:1`; white graphics must reach at least `3:1`.
- Remove expanding splash only; retain hover, flat pressed, focus-visible, disabled, loading, error, success, semantics, and keyboard activation.
- The inactive playback track reaches at least `3:1` against its supported backgrounds without changing slider geometry or hit targets.
- `ThemeMode.system` follows host `platformBrightness`; forced light and dark modes ignore host changes.
- Do not commit, stage, push, publish, deploy, or delete user data without explicit authorization.

## File Map

- Create `lib/design/components/app_playback_button.dart`: semantic solid play/pause glyphs and the reusable filled icon button.
- Modify `lib/design/design_tokens.dart`: add `playbackAction`, `playbackActionForeground`, and `playbackTrackInactive` to both theme variants.
- Modify `lib/design/app_theme.dart`: expose the no-splash Material theme adapter and map the new semantic roles.
- Modify `lib/design/components/app_button.dart`: add a playback role for labeled primary playback actions.
- Modify `lib/design/components/playback_progress.dart`: use `playbackTrackInactive` by default.
- Modify `lib/app/app.dart`: apply the Material no-splash adapter to the nested `MaterialApp.router`.
- Modify `lib/features/player/artwork_palette.dart`: calculate a dynamic inactive track that reaches `3:1` against both artwork backgrounds.
- Modify player, home, playlist, discovery, search, library, and track-action widgets: replace outline playback glyphs and page-local filled-button colors.
- Modify `lib/features/library/local_library_screen.dart`: add desktop/mobile favorite entry points and the existing playlist-selection flow.
- Modify `lib/app/app_router.dart`: inject `PlaylistRepository` into `LocalLibraryScreen`.
- Modify `design.md`: record playback semantic roles, no-splash behavior, progress contrast, and system-theme behavior.
- Modify focused design, player, home, library, route, and repository-facing Widget tests listed under each task.

---

### Task 1: Add theme-level playback and no-splash primitives

**Files:**
- Create: `lib/design/components/app_playback_button.dart`
- Modify: `lib/design/design_tokens.dart`
- Modify: `lib/design/app_theme.dart`
- Modify: `lib/design/components/app_button.dart`
- Modify: `lib/app/app.dart`
- Test: `test/design/app_theme_test.dart`
- Test: `test/design/app_components_test.dart`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Produces: `AppTokens.playbackAction`, `AppTokens.playbackActionForeground`, `AppTokens.playbackTrackInactive`.
- Produces: `ThemeData buildAppMaterialTheme(ThemeData base)` with `NoSplash.splashFactory`.
- Produces: `AppPlaybackGlyph.play()`, `AppPlaybackGlyph.pause()`, and `AppPlaybackIconButton`.
- Produces: `AppButton.playback(...)` for filled labeled playback actions.

- [ ] **Step 1: Add failing semantic-token, glyph, splash, and system-theme tests**

Extend `test/design/app_theme_test.dart` with exact palette and contrast assertions:

```dart
expect(AppTokens.light.playbackAction, const Color(0xFF14745F));
expect(AppTokens.dark.playbackAction, const Color(0xFF14745F));
expect(AppTokens.light.playbackActionForeground, Colors.white);
expect(AppTokens.dark.playbackActionForeground, Colors.white);
expect(
  _contrastRatio(
    AppTokens.light.playbackActionForeground,
    AppTokens.light.playbackAction,
  ),
  greaterThanOrEqualTo(4.5),
);
expect(
  _contrastRatio(
    AppTokens.light.playbackTrackInactive,
    AppTokens.light.background,
  ),
  greaterThanOrEqualTo(3),
);
```

Add component tests to `test/design/app_components_test.dart`:

```dart
testWidgets('playback controls use solid semantic glyphs and colors', (
  tester,
) async {
  await tester.pumpWidget(
    ShadApp(
      theme: buildLightTheme(),
      home: const Scaffold(
        body: AppPlaybackIconButton(
          key: Key('playback'),
          tooltip: '播放',
          onPressed: null,
          child: AppPlaybackGlyph.play(),
        ),
      ),
    ),
  );

  final glyph = tester.widget<AppPlaybackGlyph>(find.byType(AppPlaybackGlyph));
  expect(glyph.icon, AppPlaybackIcons.play);
  expect(
    IconTheme.of(tester.element(find.byType(AppPlaybackGlyph))).color,
    AppTokens.light.playbackActionForeground,
  );
});
```

Add a real-app test to `test/app/app_shell_test.dart` using `MemoryAppPreferences(const AppSettings(themeMode: ThemeMode.system))`. Set `tester.platformDispatcher.platformBrightnessTestValue` to light, pump `MusicFreeServiceApp`, then change it to dark and pump again. Assert both `ShadTheme.of(context).brightness` and `Theme.of(context).brightness` change, and assert `Theme.of(context).splashFactory == NoSplash.splashFactory`. Add tear-down with `tester.platformDispatcher.clearPlatformBrightnessTestValue()`.

Add two forced-mode cases asserting `ThemeMode.light` stays light and `ThemeMode.dark` stays dark after the simulated host brightness changes.

- [ ] **Step 2: Run the focused tests and verify red failures**

Run:

```bash
flutter test test/design/app_theme_test.dart test/design/app_components_test.dart test/app/app_shell_test.dart
```

Expected: compilation fails because the playback tokens/components and `buildAppMaterialTheme` do not exist; the current app splash factory is not `NoSplash.splashFactory`.

- [ ] **Step 3: Add exact playback semantic tokens**

Extend the `AppTokens` constructor, fields, equality-facing tests, and both constant variants in `lib/design/design_tokens.dart`:

```dart
playbackAction: const Color(0xFF14745F),
playbackActionForeground: Colors.white,
playbackTrackInactive: const Color(0xFF8A8A8A), // light
```

Use this dark inactive track:

```dart
playbackTrackInactive: const Color(0xFF737570), // dark
```

Do not replace `primaryAction`; playback receives a separate semantic role so non-playback save/connect/confirm buttons retain their approved dark-theme behavior.

- [ ] **Step 4: Implement shared solid glyphs and playback buttons**

Create `lib/design/components/app_playback_button.dart` with centralized filled Material playback symbols and a semantic circular button:

```dart
abstract final class AppPlaybackIcons {
  static const play = Icons.play_arrow_rounded;
  static const pause = Icons.pause_rounded;
}

final class AppPlaybackGlyph extends Icon {
  const AppPlaybackGlyph.play({super.key, super.size, super.color})
    : super(AppPlaybackIcons.play);

  const AppPlaybackGlyph.pause({super.key, super.size, super.color})
    : super(AppPlaybackIcons.pause);
}
```

Implement `AppPlaybackIconButton` with `tooltip`, `onPressed`, `child`, `dimension`, `loading`, and optional `key`. Its `IconButton.filled` style must use `tokens.playbackAction` and `tokens.playbackActionForeground`; loading uses a white `CircularProgressIndicator`. Keep a minimum 44×44 target and let the global theme suppress splash.

Add `const AppButton.playback(...)` to `lib/design/components/app_button.dart`. Store an internal `playback` flag and pass these values to `ShadButton.raw` only for that constructor:

```dart
backgroundColor: tokens.playbackAction,
foregroundColor: tokens.playbackActionForeground,
hoverBackgroundColor: Color.lerp(
  tokens.playbackAction,
  tokens.playbackActionForeground,
  .08,
),
pressedBackgroundColor: Color.lerp(
  tokens.playbackAction,
  tokens.playbackActionForeground,
  .16,
),
```

The default `AppButton` constructor and outline/ghost behavior remain unchanged.

- [ ] **Step 5: Apply global no-splash behavior at the Material boundary**

Add to `lib/design/app_theme.dart`:

```dart
ThemeData buildAppMaterialTheme(ThemeData base) => base.copyWith(
  splashFactory: NoSplash.splashFactory,
);
```

Change the nested Material app in `lib/app/app.dart` to:

```dart
theme: buildAppMaterialTheme(Theme.of(context)),
```

Do not set `highlightColor` transparent; the flat pressed highlight remains the non-ripple touch response. Do not alter custom vinyl-paint highlight colors.

- [ ] **Step 6: Run focused tests and inspect the theme boundary**

Run:

```bash
flutter test test/design/app_theme_test.dart test/design/app_components_test.dart test/app/app_shell_test.dart
```

Expected: all pass. The app-level test proves system brightness updates both theme layers and the Material splash factory is `NoSplash`.

- [ ] **Step 7: Review this task without committing**

Run:

```bash
git diff --check -- lib/design/design_tokens.dart lib/design/app_theme.dart lib/design/components/app_button.dart lib/design/components/app_playback_button.dart lib/app/app.dart test/design/app_theme_test.dart test/design/app_components_test.dart test/app/app_shell_test.dart
```

Expected: no whitespace errors. Leave changes unstaged and uncommitted.

---

### Task 2: Strengthen playback-progress contrast

**Files:**
- Modify: `lib/design/components/playback_progress.dart`
- Modify: `lib/features/player/artwork_palette.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Test: `test/design/playback_progress_test.dart`
- Create: `test/features/player/artwork_palette_test.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `AppTokens.playbackTrackInactive` from Task 1.
- Produces: `Color readableArtworkInactiveTrack(ArtworkPalette palette)`.
- Preserves: `PlaybackProgress` dimensions, pointer seeking, and `inactiveTrackColor` override API.

- [ ] **Step 1: Add failing default and dynamic contrast tests**

In `test/design/playback_progress_test.dart`, render light and dark `PlaybackProgress`, read its `ShadSlider`, and assert:

```dart
expect(slider.inactiveTrackColor, AppTokens.light.playbackTrackInactive);
expect(
  contrastRatio(slider.inactiveTrackColor!, AppTokens.light.background),
  greaterThanOrEqualTo(3),
);
```

Create `test/features/player/artwork_palette_test.dart` with representative light and dark palettes. For each result returned by `readableArtworkInactiveTrack`, alpha-blend it over both `backgroundBase` and `backgroundCompanion` and assert both contrast ratios reach `3`.

Extend the existing desktop-player palette test to assert the rendered slider uses `readableArtworkInactiveTrack(expected)` rather than a fixed 16% foreground alpha.

- [ ] **Step 2: Run progress tests and verify failures**

Run:

```bash
flutter test test/design/playback_progress_test.dart test/features/player/artwork_palette_test.dart test/features/player/player_screen_test.dart --plain-name 'desktop player scopes artwork accent and hides lyric scrollbar'
```

If combining file arguments with `--plain-name` is rejected by the installed Flutter CLI, run the two progress/palette files first and the named player test as a second command. Expected: the token assertion fails and the dynamic helper is undefined.

- [ ] **Step 3: Use the semantic inactive track by default**

Change `PlaybackProgress` to:

```dart
inactiveTrackColor:
    inactiveTrackColor ?? tokens.playbackTrackInactive,
```

Do not change `trackHeight`, `thumbRadius`, `hitExtent`, `Listener`, or seek calculations.

- [ ] **Step 4: Implement adaptive artwork-track contrast**

Add to `lib/features/player/artwork_palette.dart`:

```dart
Color readableArtworkInactiveTrack(ArtworkPalette palette) {
  for (final alpha in const [.32, .40, .48, .56, .64, .72, .80, .88, 1.0]) {
    final candidate = palette.foreground.withValues(alpha: alpha);
    final onBase = Color.alphaBlend(candidate, palette.backgroundBase);
    final onCompanion = Color.alphaBlend(
      candidate,
      palette.backgroundCompanion,
    );
    if (contrastRatio(onBase, palette.backgroundBase) >= 3 &&
        contrastRatio(onCompanion, palette.backgroundCompanion) >= 3) {
      return candidate;
    }
  }
  return palette.foreground;
}
```

In `DesktopPlayerControls`, replace the `.16` inactive track override with `readableArtworkInactiveTrack(widget.palette)`.

- [ ] **Step 5: Run progress and player tests**

Run:

```bash
flutter test test/design/playback_progress_test.dart test/features/player/artwork_palette_test.dart
flutter test test/features/player/player_screen_test.dart --plain-name 'desktop player scopes artwork accent and hides lyric scrollbar'
```

Expected: all pass; the existing seek and hit-target tests remain green.

- [ ] **Step 6: Review this task without committing**

Run:

```bash
git diff --check -- lib/design/components/playback_progress.dart lib/features/player/artwork_palette.dart lib/features/player/desktop_player_controls.dart test/design/playback_progress_test.dart test/features/player/artwork_palette_test.dart test/features/player/player_screen_test.dart
```

Expected: no whitespace errors and no slider geometry changes.

---

### Task 3: Migrate every playback glyph and filled playback control

**Files:**
- Modify: `lib/design/components/track_tile.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/playlists/playlist_detail_screen.dart`
- Modify: `lib/features/discovery/online_playlist_detail_screen.dart`
- Modify: `lib/features/discovery/discovery_screen.dart`
- Modify: `lib/features/search/search_desktop_results.dart`
- Modify: `lib/features/search/search_screen.dart`
- Modify: `lib/features/search/track_action.dart`
- Modify: `lib/features/library/local_library_screen.dart`
- Modify: `lib/features/player/mini_player.dart`
- Modify: `lib/features/player/mobile_player_controls.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Test: `test/features/home/home_screen_test.dart`
- Test: `test/features/player/player_screen_test.dart`
- Test: `test/design/app_components_test.dart`
- Test: existing playlist, discovery, search, and library Widget tests touched by constructor or finder changes.

**Interfaces:**
- Consumes: `AppPlaybackIcons`, `AppPlaybackGlyph`, `AppPlaybackIconButton`, and `AppButton.playback` from Task 1.
- Preserves: all playback callbacks, loading/error states, button keys, semantics labels, sizes, and layout.

- [ ] **Step 1: Add failing representative playback-control tests**

Add assertions for both screenshot cases:

```dart
final continueGlyph = tester.widget<AppPlaybackGlyph>(
  find.descendant(
    of: find.byTooltip('继续播放'),
    matching: find.byType(AppPlaybackGlyph),
  ),
);
expect(continueGlyph.icon, AppPlaybackIcons.play);
expect(
  IconTheme.of(tester.element(find.byType(AppPlaybackGlyph).first)).color,
  AppTokens.light.playbackActionForeground,
);
```

In the desktop player test, replace the raw `Icon`/`Colors.white` assertion with `AppPlaybackGlyph` and semantic token assertions. Add a playing-state assertion for `AppPlaybackIcons.pause`. Keep existing loading and retry-state tests.

Add a design test that `AppButton.playback` uses `playbackAction`/white while a normal dark-theme `AppButton` still uses the existing bright primary action and dark foreground.

- [ ] **Step 2: Run representative tests and verify failures**

Run:

```bash
flutter test test/features/home/home_screen_test.dart test/features/player/player_screen_test.dart test/design/app_components_test.dart
```

Expected: new glyph finders fail because pages still use `LucideIcons.play` and page-local colors.

- [ ] **Step 3: Migrate labeled playback actions**

Replace primary playback calls such as:

```dart
AppButton(
  leading: const Icon(LucideIcons.play),
  child: const Text('播放全部'),
)
```

with:

```dart
AppButton.playback(
  leading: const AppPlaybackGlyph.play(size: 18),
  child: const Text('播放全部'),
)
```

Apply this to home “继续播放”, local/ordinary/online playlist “播放全部”, and any other filled labeled playback CTA. Do not change outline import/search/refresh buttons.

- [ ] **Step 4: Migrate circular filled playback controls**

Use `AppPlaybackIconButton` for mobile home “继续收听”, search filled play, full-player center controls, and desktop mini-player main transport. Preserve each existing dimension and key. Pass `AppPlaybackGlyph.pause` when playing and `AppPlaybackGlyph.play` otherwise. Loading remains a white spinner; retry remains a white `LucideIcons.refreshCw` child.

For mobile mini-player controls that are intentionally unfilled, keep the neutral button surface but replace the playback glyph with `AppPlaybackIcons.play/pause`; do not force unrelated next/queue icons to white.

- [ ] **Step 5: Replace remaining outline playback triangles**

Run:

```bash
rg -n "LucideIcons\.(play|pause)" lib --glob '*.dart'
```

Replace remaining playback actions in track menus, neutral rows, and artwork overlays with `AppPlaybackIcons.play/pause` or `AppPlaybackGlyph`. Keep their existing neutral/overlay foreground colors. The final `rg` result must be empty; skip similarly named icons such as `listStart`, `skipBack`, and `skipForward`.

- [ ] **Step 6: Run affected Widget tests**

Run:

```bash
flutter test test/design/app_components_test.dart test/features/home/home_screen_test.dart test/features/player/player_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/discovery/discovery_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/search/search_screen_test.dart test/features/library/local_library_screen_test.dart
```

Expected: all pass; filled controls use semantic white and solid symbols while unfilled controls remain neutral.

- [ ] **Step 7: Review this task without committing**

Run:

```bash
git diff --check -- lib/design/components/track_tile.dart lib/features/home/home_screen.dart lib/features/playlists/playlist_detail_screen.dart lib/features/discovery/online_playlist_detail_screen.dart lib/features/discovery/discovery_screen.dart lib/features/search/search_desktop_results.dart lib/features/search/search_screen.dart lib/features/search/track_action.dart lib/features/library/local_library_screen.dart lib/features/player/mini_player.dart lib/features/player/mobile_player_controls.dart lib/features/player/desktop_player_controls.dart
```

Expected: no whitespace errors. Confirm the diff contains no layout refactor or non-playback color change.

---

### Task 4: Add local-library favorite-to-playlist flow

**Files:**
- Modify: `lib/features/library/local_library_screen.dart`
- Modify: `lib/app/app_router.dart`
- Test: `test/features/library/local_library_screen_test.dart`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: `PlaylistRepository.list()` and `PlaylistRepository.addTracks(String id, List<Track> tracks)`.
- Changes: `LocalLibraryScreen({required LocalLibraryController controller, required PlaylistRepository playlists, required PlayTracks playTracks})`.
- Produces stable keys: `local-library-favorite-<source>-<trackId>` and `local-library-playlist-<playlistId>`.

- [ ] **Step 1: Add failing desktop/mobile favorite-flow tests**

Refactor the local-library test harness to build both `LibraryRepository` and `PlaylistRepository` from one `MockClient`. For each 390×844 and 1200×800 case:

```dart
expect(
  find.byKey(const Key('local-library-favorite-local-a')),
  findsOneWidget,
);
```

Tap the favorite button and assert the row play counter remains zero. Return `love` and a user playlist from `GET /api/v1/playlists?includeBuiltIn=true`, tap `local-library-playlist-love`, and capture the POST body for `/api/v1/playlists/love/tracks`. Assert the submitted track keeps `id == 'a'`, `source == 'local'`, and the original `name`/`singer` fields.

Add separate tests for an empty playlist response and a 500 add-tracks response. Assert “还没有歌单” for empty and a destructive error message for failure; never assert success on failure.

Extend `test/app/app_shell_test.dart` so the production `/library` route can open the favorite picker using its injected repository.

- [ ] **Step 2: Run local-library and route tests and verify failures**

Run:

```bash
flutter test test/features/library/local_library_screen_test.dart test/app/app_shell_test.dart --plain-name 'local library'
```

If the name filter excludes the new screen-level tests, run the local-library test file without `--plain-name`, then the matching route test separately. Expected: constructor and favorite-key failures.

- [ ] **Step 3: Inject PlaylistRepository into the local route**

Change `LocalLibraryScreen` to require:

```dart
final PlaylistRepository playlists;
```

Update `lib/app/app_router.dart`:

```dart
LocalLibraryScreen(
  key: ValueKey('local-library-${readLibraryVersion()}'),
  controller: LocalLibraryController(LibraryRepository(connected.api)),
  playlists: PlaylistRepository(connected.api),
  playTracks: playTracks,
)
```

Update all direct test constructors with the same mock-backed repository.

- [ ] **Step 4: Implement the existing playlist picker flow**

Add `dart:async` and `playlist_repository.dart` imports. Implement `_choosePlaylist(Track track)` in `_LocalLibraryScreenState`:

```dart
Future<void> _choosePlaylist(Track track) async {
  try {
    final playlists = await widget.playlists.list();
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
                  key: Key('local-library-playlist-${playlist.id}'),
                  variant: ShadButtonVariant.ghost,
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(_addToPlaylist(playlist, track));
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(playlist.displayName),
                  ),
                );
              },
            ),
    );
  } on Object catch (error) {
    if (!mounted) return;
    showAppMessage(
      context,
      title: '歌单加载失败',
      message: appErrorMessage(error, fallback: '暂时无法读取歌单，请稍后重试。'),
      destructive: true,
    );
  }
}
```

Implement `_addToPlaylist(PlaylistSummary playlist, Track track)` to call `widget.playlists.addTracks`, show `完成 / 已添加到 ${playlist.displayName}` on success, and `添加失败` with `appErrorMessage` on failure.

- [ ] **Step 5: Wire desktop and mobile favorite buttons without row-play leakage**

Desktop:

```dart
CatalogTrackTableHeader(..., showFavorite: true)
CatalogTrackRow(
  ...,
  onFavorite: () => onFavorite(item.track),
  reserveFavoriteSpace: true,
  rowKeyPrefix: 'local-library',
)
```

Mobile: insert a 44×44 `IconButton` before the delete button, key it `local-library-favorite-${track.source}-${track.id}`, use tooltip `收藏到歌单` and `LucideIcons.heartPlus`, and call only `onFavorite(track)`. Passing the callback directly prevents the surrounding row `InkWell` from receiving the same tap as playback.

- [ ] **Step 6: Run local favorite tests**

Run:

```bash
flutter test test/features/library/local_library_screen_test.dart
flutter test test/app/app_shell_test.dart --plain-name 'local library card uses its read-only production route'
```

Expected: all pass, including request-body, no-row-play, empty, and failure cases.

- [ ] **Step 7: Review this task without committing**

Run:

```bash
git diff --check -- lib/features/library/local_library_screen.dart lib/app/app_router.dart test/features/library/local_library_screen_test.dart test/app/app_shell_test.dart
```

Expected: no whitespace errors. Confirm delete behavior remains unchanged and favorite submits `Track.id`, not `LibraryTrack.id`.

---

### Task 5: Update the locked design system and run the frozen integration gate

**Files:**
- Modify: `design.md`
- Verify all files changed in Tasks 1–4.

**Interfaces:**
- Documents: `playbackAction`, `playbackActionForeground`, `playbackTrackInactive`, no-splash interaction, and system-theme runtime limits.
- Produces no new runtime API.

- [ ] **Step 1: Update `design.md` with exact shipped behavior**

Add the new semantic colors to both theme sections with their implemented values. Add component rules:

```markdown
- Filled playback actions use the playback-action background and pure-white
  foreground; playback and pause symbols are solid.
- Material/Ink controls suppress expanding splash while retaining flat pressed,
  hover, focus-visible, disabled, and loading feedback.
- Playback inactive tracks reach at least 3:1 against supported backgrounds.
- ThemeMode.system follows host platformBrightness when the host reports it;
  unsupported hosts may report light and users can still force dark mode.
```

Do not rewrite unrelated typography, page-family, glass, or navigation sections.

- [ ] **Step 2: Run formatting and static analysis on the changed Dart surface**

Run `dart format` only on changed Dart files from Tasks 1–4, then:

```bash
flutter analyze lib/design lib/app/app.dart lib/app/app_router.dart lib/features/home lib/features/library lib/features/playlists lib/features/discovery lib/features/search lib/features/player
```

Expected: exit 0 with no new analyzer issues. If pre-existing issues outside the changed surface appear, record them and rerun a narrower analysis covering every changed Dart file.

- [ ] **Step 3: Run the focused integration suite**

Run:

```bash
flutter test test/design/app_theme_test.dart test/design/app_components_test.dart test/design/playback_progress_test.dart test/features/player/artwork_palette_test.dart test/features/home/home_screen_test.dart test/features/player/player_screen_test.dart test/features/library/local_library_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/discovery/discovery_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/search/search_screen_test.dart test/app/app_shell_test.dart
```

Expected: all tests pass. Do not claim full-suite coverage from this focused command.

- [ ] **Step 4: Recheck the frozen tree**

After the last code edit, run:

```bash
git diff --check
rg -n "LucideIcons\.(play|pause)" lib --glob '*.dart'
git status --short
```

Expected: `git diff --check` succeeds; the playback-icon search returns no matches; status shows only pre-existing user changes plus the scoped files from this plan. Inspect the final diff for accidental goldens, generated files, credentials, or unrelated refactors.

- [ ] **Step 5: Record runtime verification boundaries**

Run:

```bash
adb devices -l
```

If an authorized device is connected, manually toggle system light/dark while the app is in `ThemeMode.system` and record the actual result. If no device is connected, report exactly: Android device theme switching was not runtime-verified; the shared Flutter path was verified by simulated `platformBrightness` tests. Apply the same evidence boundary to iOS, Windows, macOS, and Linux unless those targets were actually run.

- [ ] **Step 6: Hand off without staging or committing**

Report:

- what changed and the exact files;
- focused tests and analysis commands with exit status;
- whether any platform theme switch was observed on a real device;
- residual risks, especially host platforms that do not report brightness;
- that all changes remain unstaged/uncommitted unless the user separately authorizes Git operations.
