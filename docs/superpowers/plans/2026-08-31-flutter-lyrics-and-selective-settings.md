# Flutter Lyrics and Selective Settings Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Strengthen Flutter lyrics with romanization, reliable follow/browse behavior, tap-to-seek, per-track timing offsets, and lyric presentation controls, while selectively adding local progress memory and playback-error auto-skip without migrating comments, advanced audio, shortcuts, themes, or unrelated Web preferences.

**Architecture:** Keep Service/Web unchanged because its playback bundle already supplies `lyric`, `tlyric`, `rlyric`, and `verbatimLyric`. Extend the Flutter DTO and pure timeline layer, store bounded per-track state behind an injectable repository, let `PlayerController` coordinate playback-only behavior, and keep rendering/presentation preferences in `AppSettings` and shared lyric controls.

**Tech Stack:** Flutter/Dart, Riverpod, ChangeNotifier, `shared_preferences` async API, `scrollable_positioned_list`, `shadcn_ui`, Flutter widget/unit tests.

## Global Constraints

- Preserve all pre-existing dirty-worktree changes and avoid edits outside the files named by this plan unless the implementation proves a directly coupled file is required.
- Do not modify `/Volumes/ext/lx-music-server-web`; its current API already satisfies this feature.
- Do not add comments, advanced playback/audio features, shortcuts, theme behavior, or word-by-word karaoke highlighting.
- Keep ordinary icons in `LucideIcons` from `shadcn_ui`; do not use Lucide transport icons or raw Material icons outside `app_playback_button.dart`.
- Every icon-only control must have a Chinese semantic label, tooltip where the surrounding component convention supports it, and at least a 44 px target.
- Positive lyric offset means lyrics appear later: active-line lookup uses `position - offset`, while tap-to-seek uses `line.time + offset` and clamps to the known media duration.
- Per-track lyric offsets and playback positions are keyed by `source + trackId`, capped at 500 entries, and stored separately from `AppSettings`.
- New playback settings default off. Existing lyric defaults remain compatible: translation on, romanization off, standard font, adaptive alignment.
- Use `apply_patch` for manual source edits and project-native Dart/Flutter format, analysis, and tests for verification.

---

## Task 1: Extend the Service lyrics DTO without making auxiliary tracks fatal

**Files:**

- Modify: `lib/api/models.dart`
- Modify: `test/api/models_test.dart`

- [x] Add optional `romanization` and `verbatim` fields to `Lyrics`, mapping `rlyric` and `verbatimLyric` respectively.
- [x] Keep `lyric` required and string-validated. Parse each auxiliary field through a helper that returns `null` for absent, non-string, empty, or replacement-character-corrupted input so one bad auxiliary track never rejects usable original lyrics.
- [x] Preserve the existing fatal `lyrics.encoding` validation for replacement characters in the original track.
- [x] Add model tests for all four fields, absent fields, bad auxiliary types/encoding being discarded, and bad original encoding still throwing the existing model error.
- [x] Run:

  ```sh
  dart format lib/api/models.dart test/api/models_test.dart
  flutter test test/api/models_test.dart
  ```

## Task 2: Expand the pure lyric timeline and offset calculations

**Files:**

- Modify: `lib/features/player/lyrics_timeline.dart`
- Modify: `test/features/player/lyrics_timeline_test.dart`

- [x] Add `romanization` to `TimedLyricLine` and align it, like translation, only when its timestamp exactly matches an original-line timestamp.
- [x] Change the LRC parser so duplicate timestamps retain the last non-empty text; an empty duplicate must not erase an earlier usable value.
- [x] Add pure helpers with explicit semantics:

  ```dart
  Duration lyricTimelinePosition(Duration playbackPosition, Duration offset);
  Duration lyricSeekPosition({
    required Duration lineTime,
    required Duration offset,
    required Duration duration,
  });
  ```

  `lyricTimelinePosition` clamps at zero after subtracting the offset. `lyricSeekPosition` adds the offset and clamps between zero and `duration` when duration is known.
- [x] Add tests for romanization alignment, multiple timestamps, duplicate timestamps, negative/positive offsets, before-zero clamping, and duration-end clamping.
- [x] Run:

  ```sh
  dart format lib/features/player/lyrics_timeline.dart test/features/player/lyrics_timeline_test.dart
  flutter test test/features/player/lyrics_timeline_test.dart
  ```

## Task 3: Persist global lyric and selective playback settings

**Files:**

- Modify: `lib/storage/app_preferences.dart`
- Modify: `lib/features/settings/settings_controller.dart`
- Modify: `test/storage/app_preferences_test.dart`
- Modify: `test/storage/app_settings_controller_test.dart`
- Modify: `test/features/settings/settings_controller_test.dart`
- Modify if fixture construction requires explicit coverage: `test/support/memory_app_preferences.dart`

- [x] Define serializable enums in `app_preferences.dart`:

  ```dart
  enum LyricFontSize { small, standard, large }
  enum LyricAlignment { adaptive, left, center }
  ```

- [x] Extend `AppSettings`, `copyWith`, equality, and hash code with:

  ```dart
  showRomanization = false
  lyricFontSize = LyricFontSize.standard
  lyricAlignment = LyricAlignment.adaptive
  rememberPlaybackProgress = false
  autoSkipPlaybackErrors = false
  ```

- [x] Add stable shared-preference keys and enum fallback parsing for every field. Preserve the existing `showLyrics = false` and `showTranslation = true` defaults.
- [x] Add focused `SettingsController` setters for all five new settings. Do not touch theme setters or introduce new theme behavior.
- [x] Extend persistence/controller tests to cover defaults, round trips, invalid stored enum names falling back safely, and each setter saving the expected immutable `AppSettings` value.
- [x] Run:

  ```sh
  dart format lib/storage/app_preferences.dart lib/features/settings/settings_controller.dart test/storage/app_preferences_test.dart test/storage/app_settings_controller_test.dart test/features/settings/settings_controller_test.dart test/support/memory_app_preferences.dart
  flutter test test/storage/app_preferences_test.dart test/storage/app_settings_controller_test.dart test/features/settings/settings_controller_test.dart
  ```

## Task 4: Add a bounded, injectable per-track playback state store

**Files:**

- Create: `lib/features/player/track_playback_state_store.dart`
- Create: `test/features/player/track_playback_state_store_test.dart`
- Modify: `lib/app/app_providers.dart`

- [x] Define value and port types:

  ```dart
  final class TrackPlaybackState {
    const TrackPlaybackState({
      this.lyricOffset = Duration.zero,
      this.resumePosition,
      required this.lastAccessedAt,
    });
  }

  abstract interface class TrackPlaybackStateStore {
    Future<TrackPlaybackState?> read(Track track);
    Future<void> writeLyricOffset(Track track, Duration offset);
    Future<void> writeResumePosition(Track track, Duration position);
    Future<void> clearResumePosition(Track track);
  }
  ```

- [x] Implement a `SharedPreferencesAsync` store using one versioned JSON map key. Encode the logical key with `jsonEncode([track.source, track.id])` so delimiter characters cannot collide.
- [x] Serialize offset and resume positions in integer milliseconds plus a last-access epoch. Treat malformed root data or malformed entries as absent instead of throwing into playback.
- [x] Clamp lyric offsets to `-5000..5000` ms before storage. Remove the offset field when reset to zero and remove an entire entry when it contains neither offset nor resume position.
- [x] After each write, sort by last access and retain the newest 500 entries. Reads update recency best-effort without making playback wait on a failed recency write.
- [x] Register a `trackPlaybackStateStoreProvider` in `app_providers.dart`, allowing tests to override the interface.
- [x] Add tests for source/id collision safety, round-trip offset/progress, reset/clear, malformed data fallback, clamping, and eviction of the oldest entry at 501.
- [x] Run:

  ```sh
  dart format lib/features/player/track_playback_state_store.dart lib/app/app_providers.dart test/features/player/track_playback_state_store_test.dart
  flutter test test/features/player/track_playback_state_store_test.dart
  ```

## Task 5: Add lyric presentation and per-track state to the player model/controller

**Files:**

- Modify: `lib/features/player/player_state.dart`
- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/app/player_providers.dart`
- Modify: `test/features/player/player_controller_test.dart`
- Modify: `test/app/app_shell_test.dart`

- [x] Extend `PlayerState` and `copyWith` with `showRomanization`, `lyricFontSize`, `lyricAlignment`, and `lyricOffset`; preserve these fields when queues are replaced or cleared.
- [x] Extend `PlayerController` constructor with the initial global lyric values, the two playback flags, an optional `TrackPlaybackStateStore`, and a best-effort non-blocking persistence-error callback.
- [x] Add synchronous presentation setters and an async `setLyricOffset(Duration)` that immediately updates session state, clamps the value, notifies, and writes for the current track. Reset to zero uses the same method.
- [x] Whenever current track identity changes, reset the visible offset to zero immediately, then asynchronously load its stored offset. Guard the result with play generation and track identity so stale reads cannot update a newer track.
- [x] In `player_providers.dart`, initialize the controller from `AppSettings`, inject the store provider, and route persistence errors through the existing app message center without interrupting playback.
- [x] In `player_providers.dart`, add a listener that pushes later global setting changes into the existing controller through `applySettings(AppSettings settings)`. Do not recreate the audio controller merely because a lyric/playback preference changes.
- [x] Add controller tests for initial values, live setting application, offset load/reset/persist, stale offset read suppression after rapid track changes, and write failure retaining the current-session value.
- [x] Run:

  ```sh
  dart format lib/features/player/player_state.dart lib/features/player/player_controller.dart lib/app/player_providers.dart test/features/player/player_controller_test.dart test/app/app_shell_test.dart
  flutter test test/features/player/player_controller_test.dart test/app/app_shell_test.dart
  ```

## Task 6: Make the lyric view followable, browsable, seekable, and three-track aware

**Files:**

- Modify: `lib/features/player/lyrics_view.dart`
- Create: `test/features/player/lyrics_view_test.dart`

- [x] Add required `ValueChanged<Duration> onSeek` and optional layout inputs needed to distinguish adaptive desktop/mobile alignment without letting the widget persist settings itself.
- [x] Calculate active lines with `lyricTimelinePosition(state.position, state.lyricOffset)`.
- [x] Track a local `following` boolean. Set it false only for user-originated pointer drags; protect programmatic `jumpTo`/`scrollTo` with an internal flag. Reset following when the `source + trackId` identity or `Lyrics` object changes.
- [x] While browsing, show a layered 44 px `ShadButton` labeled “回到当前歌词”. Its handler restores following and immediately moves the active line to the 35% alignment point.
- [x] Wrap each timed line with `Semantics(button: true, label: '跳转到…')` and an accessible 44 px minimum hit region. On tap, call `onSeek(lyricSeekPosition(...))`, restore following, and scroll to the tapped/current line.
- [x] Render original, then optional translation, then optional romanization. Do not allocate blank line spacing for unavailable auxiliary text.
- [x] Map `LyricFontSize.small/standard/large` to explicit inactive/active sizes while preserving the current standard 20/28 px pair. Resolve `LyricAlignment.adaptive` from the caller's desktop/mobile default.
- [x] Preserve static untimed lyrics as `SelectableText` without tap-to-seek.
- [x] Add widget tests for automatic following, manual-scroll pause, return-to-current, tap seek with offset/clamping, follow reset on track change, translation/romanization toggles, font size, alignment, and untimed selection fallback.
- [x] Run:

  ```sh
  dart format lib/features/player/lyrics_view.dart test/features/player/lyrics_view_test.dart
  flutter test test/features/player/lyrics_view_test.dart
  ```

## Task 7: Add shared lyric controls and integrate mobile/desktop player surfaces

**Files:**

- Create: `lib/features/player/lyric_controls.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/desktop_player_stage.dart`
- Modify: `test/features/player/player_screen_test.dart`
- Modify: `test/design/app_components_test.dart`
- Modify: `design.md`

- [x] Build one shared controls body with callbacks for translation, romanization, font size, alignment, and `-100 ms / reset / +100 ms` current-track offset changes.
- [x] Expose it through the project's existing adaptive interaction patterns: a bottom sheet on mobile and a compact anchored popover on desktop. Use a 44 px `LucideIcons.settings2` entry with Chinese label/tooltip “歌词设置”.
- [x] Persist global lyric-control changes through `appSettingsProvider.notifier.saveSettings`; also update the live `PlayerController` immediately. Route offset changes only through `PlayerController.setLyricOffset`.
- [x] Pass `controller.seek` into each `LyricsView`. Keep desktop adaptive alignment left and mobile adaptive alignment center.
- [x] Place controls so they do not cover the lyric reading column or transport controls at 320/390/1024/1440 widths.
- [x] Document the follow/browse state, auxiliary-track order, offset convention, adaptive alignment, and minimum control target in the immersive-player section of `design.md`.
- [x] Extend player tests to cover opening both adaptive control containers, toggling global options, changing/resetting offset, semantic labels, and no-overflow layouts; run the design suite as an adjacent regression.
- [x] Run:

  ```sh
  dart format lib/features/player/lyric_controls.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart test/design/app_components_test.dart
  flutter test test/features/player/player_screen_test.dart test/design/app_components_test.dart
  ```

## Task 8: Expose the selected local settings on mobile and desktop

**Files:**

- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `test/features/settings/settings_screen_test.dart`

- [x] Replace the hidden/summary-only lyric preference UI with visible controls for default lyrics, translation, romanization, lyric font size, and lyric alignment on both mobile and desktop.
- [x] Add visible local playback switches for “记忆播放进度” and “播放错误时自动跳过”, with concise copy explaining that both are device-local and default off.
- [x] Keep these controls out of `service_function_settings_screen.dart`; do not add theme, shortcut, list, or search preferences.
- [x] Reuse existing `_PreferenceRow`, `_PreferenceSelect`, and `ShadSwitch` conventions. Ensure switch rows remain usable at 320 px without overflow.
- [x] Extend widget tests for labels, defaults, persistence callbacks, mobile/desktop parity, and narrow-width layout.
- [x] Run:

  ```sh
  dart format lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
  flutter test test/features/settings/settings_screen_test.dart
  ```

## Task 9: Implement bounded playback-progress memory

**Files:**

- Modify: `lib/features/player/player_controller.dart`
- Modify: `test/features/player/player_controller_test.dart`

- [x] When `rememberPlaybackProgress` is off, ignore any resume position returned by the combined per-track state read and perform no resume-position writes/clears.
- [x] When on, load the current track's stored progress alongside its lyric offset, but seek only after `playCachedTrack` or `playTrack` succeeds and only if the same generation/track is still current.
- [x] Restore only positions greater than 5 seconds and at least 10 seconds before a known duration. Clamp to duration when necessary; a failed restore seek is best-effort and must not turn successful playback into an error state.
- [x] Persist positions from snapshots only after 5 seconds. Throttle writes by recording at most once per 5-second playback bucket and flush the latest eligible position when switching tracks, clearing the queue, or disposing.
- [x] Clear saved progress on natural completion and whenever a snapshot is within 10 seconds of the known end. Do not clear merely because a user pauses.
- [x] Ensure enabling/disabling the setting at runtime affects subsequent operations without rebuilding the controller; disabling stops new writes but does not destructively erase all stored entries.
- [x] Add tests for default-off no-op, post-ready restore, stale restore suppression, >5 second saving, throttling, track-switch flush, near-end clear, natural-completion clear, and failed seek not breaking playback.
- [x] Run:

  ```sh
  dart format lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
  flutter test test/features/player/player_controller_test.dart
  ```

## Task 10: Implement playback-start error auto-skip with a finite failure chain

**Files:**

- Modify: `lib/features/player/player_controller.dart`
- Modify: `test/features/player/player_controller_test.dart`

- [x] Maintain a private set of failed logical track keys for the active automatic failure chain plus a guard against concurrent skip handling.
- [x] Reset the chain for explicit `playTracks`, `play`, and public/manual `playIndex` calls. Add a private internal index transition that can preserve the chain for auto-skip.
- [x] When `_playCurrent` exhausts cache/resolve/play attempts and `autoSkipPlaybackErrors` is enabled, record the failed key and choose the next untried queue entry in forward queue order. Ignore repeat-one for errors; do not route through shuffle selection.
- [x] Continue until a track starts or every queue entry has failed once. On exhaustion, leave `PlayerProcessing.error` and the last readable error visible; do not wrap to a failed entry or call the radio/sequential queue-end handler.
- [x] Clear the failure chain after a successful playback start and on later explicit track selection. Keep normal completion behavior, shuffle, repeat-one success, recommendation contexts, radio continuation, and session reporting unchanged.
- [x] Add tests for default-off behavior, one failure then successful next track, multiple failures, full exhaustion without looping, repeat-one error advancement, manual-selection reset, no duplicate attempts, and no impact on normal completion/radio continuation.
- [x] Run:

  ```sh
  dart format lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
  flutter test test/features/player/player_controller_test.dart
  ```

## Task 11: Cross-feature regression and contract verification

**Files:**

- Verify all files changed above.
- Review: `docs/superpowers/specs/2026-08-31-flutter-lyrics-and-selective-settings-design.md`
- Review: `docs/superpowers/plans/2026-08-31-flutter-lyrics-and-selective-settings.md`

- [x] Run formatting and ensure no generated or unrelated dirty files were changed by the feature work:

  ```sh
  dart format <touched production and test files>
  git status --short
  git diff --check
  ```

- [x] Run focused static analysis over the touched production and test files. If the Flutter CLI cannot accept all paths in one invocation, split by directory without broadening to generated directories:

  ```sh
  flutter analyze lib/api/models.dart lib/storage/app_preferences.dart lib/features/player lib/features/settings lib/app test/api/models_test.dart test/storage test/features/player test/features/settings
  ```

- [x] Run the focused feature suites:

  ```sh
  flutter test test/api/models_test.dart test/storage/app_preferences_test.dart test/storage/app_settings_controller_test.dart test/features/player/track_playback_state_store_test.dart test/features/player/lyrics_timeline_test.dart test/features/player/lyrics_view_test.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart test/design/app_components_test.dart
  ```

- [x] Run adjacent playback contracts affected by queue transitions and settings propagation:

  ```sh
  flutter test test/features/radio test/features/recommendations test/features/playback_history test/app/app_shell_test.dart test/platform/macos_menu_bar_coordinator_test.dart
  ```

- [x] Verify the project icon rules exactly:

  ```sh
  rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
  rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
  ```

  The first command must return no matches. The second may match only `lib/design/components/app_playback_button.dart`.
- [x] Inspect the final diff against the approved exclusions. Confirm no Service/Web files, comment features, advanced playback/audio features, shortcuts, themes, or word-level lyric rendering entered the change.
- [x] Record any verification command that could not run, its exact blocker, and the remaining risk. Do not claim completion without current passing evidence for every behavior claimed.

## Verification Evidence

Completed on 2026-09-01:

- Focused formatting: 25 touched files, no changes required.
- Focused static analysis: no issues.
- Focused feature suites: 220 tests passed.
- Adjacent radio, recommendations, playback-history, app-shell, and macOS menu-bar contracts: 48 tests passed.
- `git diff --check`: passed.
- Icon rules: no disallowed Lucide transport glyphs; direct Material glyphs remain limited to `lib/design/components/app_playback_button.dart`.
- Scope review: no Service/Web changes were made for this work, and no comments, advanced playback/audio, shortcuts, themes, or word-level lyric rendering were added.
