# Mobile Vinyl Record and Expanded Lyrics Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile player's inline lyric preview with a playback-aware rotating record, while keeping the app chrome and controls visible around a swipe-accessible full-height lyrics page.

**Architecture:** Keep the existing two-page `PageView`. Add a focused stateful `MobileVinylRecord` widget that owns only its rotation controller and decorative rendering; keep playback and page state in `PlayerController`. Simplify the first page to record/title/artist, and make the second page own lyric empty/error/retry states across the full available center viewport.

**Tech Stack:** Flutter widgets and animations, existing `AppArtwork`/`AppGlassPolicyScope`/`LyricsView`, `flutter_test` widget tests.

## Global Constraints

- Mobile player entry always starts on `PlayerView.artwork`, even when the controller previously held `PlayerView.lyrics`.
- The app top bar and `MobilePlayerControls` remain visible on both pages.
- The lyrics page fills only the center area between those fixed regions; it does not hide system or app UI.
- The record rotates only while playback is active, processing is `PlayerProcessing.ready`, the artwork page is active, and reduced motion is disabled.
- Pausing, loading, buffering, completion, error, leaving the artwork page, or enabling reduced motion stops at the current angle without resetting it.
- One revolution lasts approximately 18 seconds and uses a linear curve.
- No desktop-player, lyric API/parser, queue sheet, or playback-controller command behavior changes.
- Preserve all pre-existing dirty-worktree changes, especially current edits in `player_screen.dart`, `player_screen_test.dart`, and visual golden files.
- Do not commit, stage, or overwrite already-dirty golden images without explicit user authorization.

---

## File Map

- Create `lib/features/player/mobile_vinyl_record.dart`: responsive circular record rendering and isolated rotation lifecycle.
- Create `test/features/player/mobile_vinyl_record_test.dart`: focused rotation, pause, reduced-motion, semantics, and geometry tests.
- Modify `lib/features/player/player_screen.dart`: mobile default-page synchronization, record-page composition, full-height lyrics-page state handling, and lyric retry wiring.
- Modify `test/features/player/player_screen_test.dart`: mobile page behavior, error locality, swipe-back, usable lyric viewport, and responsive regression coverage.
- Inspect, but do not automatically overwrite, `test/visual/full_goldens/mobile-player-*.png`: visual evidence for the redesigned default page.

---

### Task 1: Playback-aware mobile vinyl record

**Files:**

- Create: `lib/features/player/mobile_vinyl_record.dart`
- Create: `test/features/player/mobile_vinyl_record_test.dart`

**Interfaces:**

- Consumes: `AppArtworkSource`, `AppArtwork`, `AppGlassPolicyScope.policyOf(context).reduceMotion`, and a boolean supplied by the player page.
- Produces:

```dart
final class MobileVinylRecord extends StatefulWidget {
  const MobileVinylRecord({
    super.key,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
  });

  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;
}
```

- Stable test keys: `player-mobile-vinyl`, `player-mobile-vinyl-turn`, `player-mobile-vinyl-artwork`, and `player-mobile-vinyl-spindle`.

- [x] **Step 1: Write failing record structure and animation tests**

Create a small `ShadApp`/`MaterialApp` harness with `AppGlassPolicyScope`. Render the record inside `SizedBox.square(dimension: 240)` with a fallback artwork source. Assert the exact geometry and keys:

```dart
expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
expect(
  tester.getSize(find.byKey(const Key('player-mobile-vinyl'))),
  const Size.square(240),
);
expect(find.byKey(const Key('player-mobile-vinyl-artwork')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-vinyl-spindle')), findsOneWidget);
expect(find.bySemanticsLabel('One封面'), findsOneWidget);
```

For rotation, read the `RotationTransition` keyed `player-mobile-vinyl-turn`, pump one second, and assert its `turns.value` advances when `rotating: true`. Rebuild with `rotating: false`, pump another second, and assert the value stays within `1e-6` of the stopped value. Re-enable rotation and assert it advances from that value rather than resetting to zero.

Add a second test using `MediaQueryData(disableAnimations: true)`. With `rotating: true`, pump one second and assert the turn value does not change.

- [x] **Step 2: Run the focused tests and confirm the expected failure**

Run:

```bash
flutter test test/features/player/mobile_vinyl_record_test.dart
```

Expected: compilation fails because `mobile_vinyl_record.dart` and `MobileVinylRecord` do not exist.

- [x] **Step 3: Implement the minimal record widget**

Use `SingleTickerProviderStateMixin` and one 18-second `AnimationController`. Synchronize it from `initState`, `didChangeDependencies`, and `didUpdateWidget`:

```dart
static const _period = Duration(seconds: 18);

void _syncRotation() {
  final reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
  final shouldRotate = widget.rotating && !reduceMotion;
  if (shouldRotate && !_rotation.isAnimating) {
    _rotation.repeat(period: _period);
  } else if (!shouldRotate && _rotation.isAnimating) {
    _rotation.stop(canceled: false);
  }
}
```

Do not call inherited-widget APIs from `initState`; initialize the controller there, then call `_syncRotation` from `didChangeDependencies`. In `didUpdateWidget`, schedule or directly perform the non-inherited part using the already-resolved reduced-motion value stored by `didChangeDependencies`.

Build a `RepaintBoundary` containing a keyed `RotationTransition`. Inside it:

- use `LayoutBuilder` and `constraints.biggest.shortestSide` as the diameter;
- fill the complete circle with `AppArtwork`, using the record diameter for its width, height, size, and border radius;
- paint low-contrast concentric groove circles and a slight highlight over the artwork in a private `CustomPainter`;
- overlay a small circular spindle above the artwork;
- wrap decorative layers in `ExcludeSemantics` while leaving `AppArtwork` as the single image semantic.

Give the painter explicit `grooveColor` and `highlightColor` fields. Its `shouldRepaint` compares those two fields with the old delegate so a runtime theme change repaints correctly without repainting unchanged frames.

- [x] **Step 4: Run and refine the focused tests**

Run:

```bash
dart format lib/features/player/mobile_vinyl_record.dart test/features/player/mobile_vinyl_record_test.dart
flutter test test/features/player/mobile_vinyl_record_test.dart
flutter analyze lib/features/player/mobile_vinyl_record.dart test/features/player/mobile_vinyl_record_test.dart
```

Expected: all record tests pass and analysis reports no issues. Confirm the paused and reduced-motion tests do not rely on `pumpAndSettle`, because a correctly repeating animation intentionally prevents settling.

---

### Task 2: Default record page and full-height lyric page

**Files:**

- Modify: `lib/features/player/player_screen.dart:47-85`
- Modify: `lib/features/player/player_screen.dart:191-406`
- Modify: `test/features/player/player_screen_test.dart:464-527`
- Modify: `test/features/player/player_screen_test.dart:813-846`

**Interfaces:**

- Consumes: `MobileVinylRecord` from Task 1 and existing `PlayerController.setView(PlayerView)`.
- Produces: `_MobileNowPlaying` with a simple `bool rotating` input instead of lyric-state inputs; the second `PageView` child keyed `player-mobile-lyrics-page`; retry action keyed `player-mobile-lyric-error`; stable full-center viewport key `player-mobile-pages`.

- [x] **Step 1: Add failing default-page and composition tests**

Extend the existing `mobile player uses the immersive glass hierarchy` test so it asserts:

```dart
expect(find.byKey(const Key('player-mobile-vinyl')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-artwork')), findsNothing);
expect(find.text('Line').hitTestable(), findsNothing);
expect(find.text('暂无歌词').hitTestable(), findsNothing);
expect(find.byKey(const Key('player-mobile-topbar')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
```

Before pumping another mobile player, call `controller.setView(PlayerView.lyrics)`. After the first frame and one follow-up pump, assert both `controller.state.view == PlayerView.artwork` and the vinyl key is visible. This proves mobile entry does not inherit an old lyric page.

After a left drag, assert `PlayerView.lyrics`, visible lyric text, visible topbar/controls, and:

```dart
expect(
  tester.getRect(find.byKey(const Key('player-mobile-lyrics-page'))),
  tester.getRect(find.byKey(const Key('player-mobile-pages'))),
);
```

Then drag right and assert `PlayerView.artwork` and the vinyl is visible again.

- [x] **Step 2: Add failing lyric-empty/error locality tests**

Change `mobile player keeps lyric errors compact and local` to verify that the error is not hit-test-visible on the default record page. Swipe left, then assert `歌词暂不可用` and a `重试` action are visible, raw exception text is absent, and topbar/controls remain.

Tap `重试` with a loader that fails once and then returns `[00:01]Line`; pump the async completion and assert `Line` replaces the error.

Add or extend the empty-lyrics case: `暂无歌词` is not hit-test-visible before the swipe and becomes visible only on the lyric page.

- [x] **Step 3: Run the new player tests and confirm behavioral failures**

Run each new test by exact plain name, for example:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile player uses the immersive glass hierarchy'
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile player keeps lyric errors compact and local'
```

Expected: failures show the existing square artwork/inline lyrics, inherited lyric initial page, missing retry action, or missing viewport keys.

- [x] **Step 4: Reset only the mobile page on entry**

Change the screen-owned `PageController` to `PageController(initialPage: 0)`. Convert `_MobilePlayer` to a `StatefulWidget`. In its state `initState`, schedule a post-frame synchronization only when necessary:

```dart
if (widget.controller.state.view != PlayerView.artwork) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    widget.controller.setView(PlayerView.artwork);
  });
}
```

Keep the existing queue-entry behavior in `_PlayerScreenState.initState`; opening a stored queue view still opens the queue Sheet after resetting the controller. Do not reset view from every `build`, because controller notifications would otherwise fight user swipes.

- [x] **Step 5: Replace the first page with the record composition**

Import `mobile_vinyl_record.dart`. Key the `Expanded` page viewport as `player-mobile-pages`. In `_MobileNowPlaying`, replace `PlayerState state` and `VoidCallback onRetryLyrics` with `required bool rotating`, then remove every lyric/error/empty branch. Compute a responsive record size from both constraints:

```dart
final recordSize = math.min(
  constraints.maxWidth * .78,
  constraints.maxHeight * .62,
).clamp(148.0, 264.0);
```

Add `dart:math` only if this exact computation is used. When constructing `_MobileNowPlaying` from the first `PageView` child, pass:

```dart
rotating:
    state.view == PlayerView.artwork &&
    state.playing &&
    state.processing == PlayerProcessing.ready,
```

Inside `_MobileNowPlaying`, render `MobileVinylRecord` in a `SizedBox.square` and forward `rotating: rotating`.

Keep title and artist beneath the record. Preserve two-line title truncation, secondary artist color, fallback seed, and artwork semantics.

- [x] **Step 6: Make the second page own all lyric states**

Use a keyed `SizedBox.expand` or `KeyedSubtree` so `player-mobile-lyrics-page` has the exact `PageView` page bounds. Its content is:

```dart
state.lyricsError != null
    ? AppRetryState(
        key: const Key('player-mobile-lyric-error'),
        message: '歌词暂不可用',
        retryLabel: '重试',
        onRetry: onLyrics,
      )
    : LyricsView(
        state: state,
        verticalPadding: 28,
        edgeFade: true,
      )
```

Do not change `LyricsView` defaults, because desktop consumers retain their current spacing. The mobile page opts into `verticalPadding: 28` locally. Keep the `PageView.onPageChanged` mapping limited to indexes 0 and 1.

- [x] **Step 7: Run the mobile player regression suite**

Run:

```bash
dart format lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
flutter analyze lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
```

Expected: all player-screen tests pass, including existing 320/375/414/768 px overflow and progress-drag tests. If a test uses `pumpAndSettle` while the visible record is rotating, replace only that wait with a fixed number of `pump` calls sufficient for the tested page or control animation; do not weaken its assertions.

---

### Task 3: Frozen-tree integration and visual review

**Files:**

- Verify: `lib/features/player/mobile_vinyl_record.dart`
- Verify: `lib/features/player/player_screen.dart`
- Verify: `test/features/player/mobile_vinyl_record_test.dart`
- Verify: `test/features/player/player_screen_test.dart`
- Inspect only unless separately authorized: `test/visual/full_goldens/mobile-player-360x800.png`
- Inspect only unless separately authorized: `test/visual/full_goldens/mobile-player-390x844.png`
- Inspect only unless separately authorized: corresponding `*-light.png` files

**Interfaces:**

- Consumes: completed record widget and mobile page composition.
- Produces: final evidence for animation behavior, responsive behavior, static analysis, and the exact remaining golden-snapshot boundary.

- [x] **Step 1: Run focused functional verification on the frozen code tree**

Run:

```bash
flutter test test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
flutter analyze lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
git diff --check -- lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
```

Expected: zero test failures, no analyzer issues, and no whitespace errors.

- [x] **Step 2: Check the mobile-player golden cases without overwriting user files**

Record the current status of the four mobile-player golden files, then run:

```bash
git status --short -- test/visual/full_goldens/mobile-player-*.png
flutter test test/visual/full_ui_gallery_test.dart --plain-name 'mobile player'
```

The default-page redesign is expected to change these snapshots. If they are already dirty, do not run `--update-goldens`; inspect generated failure images or the running app and report the golden mismatch as an intentionally unupdated verification boundary. If they are clean and the user separately authorizes snapshot updates, update only the four mobile-player cases and rerun the same command.

- [x] **Step 3: Review the final scoped diff**

Run:

```bash
git diff -- lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart docs/superpowers/specs/2026-08-14-mobile-vinyl-lyrics-design.md docs/superpowers/plans/2026-08-14-mobile-vinyl-lyrics.md
git status --short
```

Confirm the final diff contains only the approved mobile record/lyrics behavior plus its spec, plan, and tests. Distinguish pre-existing modifications from this task in the handoff. Do not stage, commit, push, or regenerate dirty snapshots without new authorization.
