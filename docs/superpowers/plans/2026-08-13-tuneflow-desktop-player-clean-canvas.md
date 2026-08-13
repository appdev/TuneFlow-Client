# TuneFlow Desktop Player Clean Canvas Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean, continuous desktop player canvas with truly centered transport controls, compact quality selection, a bounded long-queue popover, and matching progress/long-queue refinements on mobile.

**Architecture:** Keep `PlayerController` as the sole playback and queue command boundary. Split the desktop foreground into a focused stage, centered control group, quality popover, and desktop queue popover; keep mobile on the existing A-control/C-sheet structure. Extend the shared progress component with explicit visual and hit extents so desktop and mobile share geometry without sharing unsuitable interaction containers.

**Tech Stack:** Flutter, Dart, shadcn_ui, Material overlay/scroll primitives, Flutter widget tests, golden tests, macOS desktop build.

## Global Constraints

- The accepted design source is `docs/superpowers/specs/2026-08-13-tuneflow-desktop-player-clean-canvas-design.md` plus the repository `design.md` Mist Sea system.
- Desktop keeps one continuous cover-derived backdrop; do not add a top panel, bottom panel, or horizontal divider.
- Desktop retains only back, artwork, one metadata group, lyrics, progress, previous/play/next, quality, and queue.
- The progress track is 4 px, the resting thumb is 12 px, desktop hit height is at least 28 px, and mobile hit height is at least 44 px.
- Previous/play/next and progress are anchored to the window horizontal center and must not move when quality or queue UI opens.
- Desktop queue is a non-modal lower-right popover with a maximum height near 68% of available player height; only its lazy list scrolls.
- Mobile queue remains the existing draggable sheet with initial extent 64%, range 48%–90%, and a lazy internal list.
- All color, typography, spacing, radii, durations, curves, and glass values must consume semantic project tokens; no page-local raw palette.
- No new dependencies, routes, persistence, audio-service APIs, or unconfirmed player actions.
- Preserve the dirty worktree and unrelated redesign changes. Do not commit, push, or discard changes unless the user separately authorizes it.

---

## File Structure

### Create

- `lib/features/player/desktop_player_stage.dart` — desktop artwork/metadata/lyrics foreground with compact lyric failure state.
- `lib/features/player/desktop_player_controls.dart` — centered desktop progress/transport and independent quality/queue anchors.
- `lib/features/player/desktop_queue_popover.dart` — bounded desktop queue surface, lazy list, current-item reveal, remove/clear/error behavior.
- `test/features/player/desktop_player_controls_test.dart` — direct geometry and quality-popover widget tests.
- `test/features/player/desktop_queue_popover_test.dart` — long-list, selection, removal, current-item reveal, keyboard close, and error tests.

### Modify

- `lib/design/components/playback_progress.dart` — explicit track/thumb/hit geometry and drag-state styling.
- `lib/features/player/player_controller.dart` — transactional quality change result with rollback on replay failure.
- `lib/features/player/player_screen.dart` — wire new desktop stage/controls/popover and remove the old desktop bottom panel.
- `lib/features/player/mobile_player_controls.dart` — request the 44 px shared progress hit extent.
- `lib/features/player/mobile_queue_sheet.dart` — add one-time current-item reveal and keep the lazy Sliver list as the sole scrolling body.
- `test/design/playback_progress_test.dart` — geometry and drag behavior coverage.
- `test/features/player/player_controller_test.dart` — quality success, no-op, and rollback behavior.
- `test/features/player/player_screen_test.dart` — integration, no-panel/no-duplicate metadata, responsive, and mobile gesture coverage.
- `test/visual/high_fidelity_fixtures.dart` — provide a long queue fixture where required.
- `test/visual/high_fidelity_gallery_test.dart` — desktop default, quality, queue, and mobile long-queue structural/golden coverage.
- `test/visual/full_ui_gallery_test.dart` — refresh 1440×960, 1024×768, 390×844, and 360×800 player captures.
- `test/visual/goldens/player-desktop-dark.png` — new high-fidelity desktop default reference.
- `test/visual/goldens/player-desktop-quality-dark.png` — desktop quality-menu reference.
- `test/visual/goldens/player-desktop-queue-dark.png` — desktop long-queue reference.
- `test/visual/goldens/player-mobile-dark.png` — updated progress geometry.
- `test/visual/goldens/player-mobile-queue-dark.png` — updated mobile queue/progress reference.
- `test/visual/full_goldens/desktop-player-1440x960.png` — integrated wide desktop reference.
- `test/visual/full_goldens/desktop-player-1024x768.png` — integrated compact desktop reference.
- `test/visual/full_goldens/mobile-player-390x844.png` — integrated mobile reference.
- `test/visual/full_goldens/mobile-player-360x800.png` — integrated compact mobile reference.

---

### Task 1: Shared Progress Geometry and Seek Interaction

**Files:**
- Modify: `lib/design/components/playback_progress.dart`
- Test: `test/design/playback_progress_test.dart`

**Interfaces:**
- Consumes: `position`, `duration`, and `ValueChanged<Duration> onSeek` from existing callers.
- Produces: `PlaybackProgress({double hitExtent = 28, double trackHeight = 4, double thumbDiameter = 12, bool compact = false, ...})` and keys `playback-progress-hit-area`, `playback-progress-track`, `playback-progress-thumb`.

- [ ] **Step 1: Write failing geometry tests**

Add tests that require the desktop defaults and mobile override:

```dart
expect(
  tester.getSize(find.byKey(const Key('playback-progress-hit-area'))).height,
  28,
);
expect(
  tester.getSize(find.byKey(const Key('playback-progress-track'))).height,
  4,
);
expect(
  tester.getSize(find.byKey(const Key('playback-progress-thumb'))),
  const Size.square(12),
);

await tester.pumpWidget(progressHarness(hitExtent: 44));
expect(
  tester.getSize(find.byKey(const Key('playback-progress-hit-area'))).height,
  44,
);
```

Retain the existing 25%→75% drag assertion and add a pointer-down assertion proving a click above the visible 4 px rail but inside the hit area still seeks.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/design/playback_progress_test.dart
```

Expected: FAIL because `trackHeight`, `thumbDiameter`, and the new keyed visual geometry do not exist.

- [ ] **Step 3: Implement the explicit visual and hit geometry**

Keep the time labels and listener behavior, but make the interaction box independent from the visible rail:

```dart
const PlaybackProgress({
  super.key,
  required this.position,
  required this.duration,
  required this.onSeek,
  this.compact = false,
  this.hitExtent = 28,
  this.trackHeight = 4,
  this.thumbDiameter = 12,
});

final double hitExtent;
final double trackHeight;
final double thumbDiameter;
```

Use a `SizedBox(height: hitExtent)` as the pointer target. Configure `ShadSlider.trackHeight` with `trackHeight` and its thumb radius with `thumbDiameter / 2`; if ShadSlider cannot expose a stable keyed thumb for testing, compose the semantic/keyed visual layer around it while keeping a single pointer listener and a single slider semantics node.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
flutter test test/design/playback_progress_test.dart
```

Expected: all progress tests PASS with no duplicate seek callbacks per pointer event.

- [ ] **Step 5: Review the scoped diff without committing**

Run:

```bash
git diff --check -- lib/design/components/playback_progress.dart test/design/playback_progress_test.dart
```

Expected: no whitespace errors. Leave changes uncommitted per the global constraint.

---

### Task 2: Continuous Desktop Split-Studio Stage

**Files:**
- Create: `lib/features/player/desktop_player_stage.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `PlayerState state`, `AppArtworkSource artworkSource`, and `VoidCallback onRetryLyrics`.
- Produces: `DesktopPlayerStage` with keys `player-desktop-stage`, `player-desktop-artwork`, `player-desktop-metadata`, `desktop-lyrics-viewport`, and `player-desktop-lyrics-error`.

- [ ] **Step 1: Write failing desktop hierarchy tests**

At 1200×800, assert the new stage and the deliberate absence of old duplication:

```dart
expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-artwork')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-metadata')), findsOneWidget);
expect(find.byKey(const Key('desktop-player-bottom-panel')), findsNothing);
expect(find.byKey(const Key('desktop-player-duplicate-artwork')), findsNothing);
expect(find.text('One'), findsOneWidget);
```

For an album-less track, assert `find.textContaining(' · ')` does not match the metadata line. For lyric failure, require `player-desktop-lyrics-error`, text `歌词暂不可用`, and a `重试` action without the raw exception.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'desktop player'
```

Expected: FAIL because `DesktopPlayerStage` and its keys are absent and the old bottom panel duplicates metadata.

- [ ] **Step 3: Implement `DesktopPlayerStage`**

Build the accepted 42/58 structure with bounded square artwork:

```dart
final class DesktopPlayerStage extends StatelessWidget {
  const DesktopPlayerStage({
    super.key,
    required this.state,
    required this.artworkSource,
    required this.onRetryLyrics,
  });

  final PlayerState state;
  final AppArtworkSource artworkSource;
  final VoidCallback onRetryLyrics;
}
```

Use one `Row` with `Expanded(flex: 42)` and `Expanded(flex: 58)`, constrain the artwork to a square maximum derived from both width and height, format metadata with a helper that omits blank album data, and keep the lyrics viewport vertically centered. The failure state is text plus retry only; do not add a decorative empty-state icon or panel.

- [ ] **Step 4: Wire the stage into the desktop branch**

Replace `_DesktopPlayer`/`_DesktopArtworkStage` foreground ownership in `player_screen.dart` with `DesktopPlayerStage`. Keep `PlayerBackdrop` as the only full-canvas background and keep the desktop foreground transparent.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'desktop player'
```

Expected: desktop hierarchy, album omission, and compact lyric-failure tests PASS.

- [ ] **Step 6: Review the scoped diff without committing**

Run:

```bash
git diff --check -- lib/features/player/desktop_player_stage.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
```

Expected: no whitespace errors.

---

### Task 3: Truly Centered Desktop Controls and Quality Popover

**Files:**
- Create: `lib/features/player/desktop_player_controls.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/player_controller.dart`
- Test: `test/features/player/desktop_player_controls_test.dart`
- Test: `test/features/player/player_controller_test.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `PlayerController controller` and `VoidCallback onQueue`.
- Produces: `DesktopPlayerControls`, keys `player-desktop-controls`, `player-desktop-core`, `player-desktop-progress`, `player-desktop-transport`, `player-desktop-quality`, `player-desktop-quality-popover`, and `player-desktop-queue`.
- Calls: `controller.previous()`, `pause()`, `resume()`, `next()`, `seek(Duration)`, and `Future<bool> setQuality(String)`.

- [ ] **Step 1: Write failing transactional quality tests**

In `player_controller_test.dart`, require a successful change to return `true`, a no-op to avoid replay, and a replay failure to restore the prior quality while retaining the playback error:

```dart
expect(await controller.setQuality('320k'), isTrue);
expect(controller.state.quality, '320k');

audio.nextPlayError = StateError('quality failed');
expect(await controller.setQuality('flac'), isFalse);
expect(controller.state.quality, '320k');
expect(controller.state.error, isA<StateError>());
```

- [ ] **Step 2: Run the controller quality tests and verify RED**

Run:

```bash
flutter test test/features/player/player_controller_test.dart --plain-name 'quality'
```

Expected: FAIL because `setQuality` returns `Future<void>` and leaves the requested quality selected after replay failure.

- [ ] **Step 3: Implement transactional `setQuality`**

Change `_playCurrent()` to return `Future<bool>` while preserving all current call sites, and use its result to commit or roll back quality:

```dart
Future<bool> setQuality(String quality) async {
  if (quality == state.quality) return true;
  final previous = state.quality;
  state = state.copyWith(quality: quality, error: null);
  notifyListeners();
  if (state.current == null) return true;
  if (await _playCurrent()) return true;
  state = state.copyWith(quality: previous);
  notifyListeners();
  return false;
}
```

Return `true` from every successful `_playCurrent` branch and `false` after publishing its existing error state. Existing playback commands may ignore the boolean; do not change their external signatures.

- [ ] **Step 4: Run the controller quality tests and verify GREEN**

Run:

```bash
flutter test test/features/player/player_controller_test.dart --plain-name 'quality'
```

Expected: quality success, no-op, and rollback tests PASS.

- [ ] **Step 5: Write a failing center-invariance test**

Pump the controls in a 1200 px surface, record the center before and after opening quality UI, and compare it to the host center:

```dart
final hostCenter = tester.getCenter(find.byKey(const Key('controls-host'))).dx;
final before = tester.getCenter(
  find.byKey(const Key('player-desktop-play-pause')),
).dx;
expect(before, closeTo(hostCenter, .5));

await tester.tap(find.byKey(const Key('player-desktop-quality')));
await tester.pumpAndSettle();
final after = tester.getCenter(
  find.byKey(const Key('player-desktop-play-pause')),
).dx;
expect(after, closeTo(before, .5));
```

Also assert the progress center equals the host center and that the quality and queue buttons are at least 44×44.

- [ ] **Step 6: Write failing quality-menu behavior tests**

Require three options, selected semantics, successful selection, and local error:

```dart
expect(find.byKey(const Key('player-desktop-quality-popover')), findsOneWidget);
expect(find.text('128k'), findsOneWidget);
expect(find.text('320k'), findsOneWidget);
expect(find.text('无损'), findsWidgets);
await tester.tap(find.byKey(const Key('player-quality-flac')));
await tester.pump();
expect(controller.state.quality, 'flac');
```

Use a resolver/audio fake that fails the replay to assert the original error object is not rendered and the popover surface offers `重试`.

- [ ] **Step 7: Run the new tests and verify RED**

Run:

```bash
flutter test test/features/player/desktop_player_controls_test.dart
```

Expected: FAIL because the new controls and keys do not exist.

- [ ] **Step 8: Implement the independent center and action anchors**

Use a `Stack` rather than a three-column Row:

```dart
Stack(
  key: const Key('player-desktop-controls'),
  alignment: Alignment.bottomCenter,
  children: [
    Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        key: const Key('player-desktop-core'),
        width: coreWidth,
        child: _DesktopCoreControls(...),
      ),
    ),
    Align(
      alignment: Alignment.bottomRight,
      child: _DesktopSecondaryActions(...),
    ),
  ],
)
```

The component has no background fill and no top border. Use the shared progress defaults from Task 1. Preserve disabled previous/next geometry and use semantic tooltips.

- [ ] **Step 9: Implement the compact quality popover**

Use `ShadPopoverController` and `ShadPopover`, anchored to the 44 px quality button. Render only supported current options (`128k`, `320k`, `flac` for the current product contract), mark the selected option with semantics plus `LucideIcons.check`, and close after a `true` result from `setQuality`. On `false`, keep the menu open with the restored prior selection and render `AppNotice.error` plus a retry that reissues the last requested value.

- [ ] **Step 10: Wire controls into `PlayerScreen` and remove the old desktop panel**

Place `DesktopPlayerControls` as a bottom-aligned transparent foreground inside the same `Stack` as `DesktopPlayerStage`. Delete the desktop-only `Container(height: 92, color: surface, border: top...)` path and its duplicate artwork/title/artist block. Keep the mobile branch on `MobilePlayerControls`.

- [ ] **Step 11: Run controls and integration tests and verify GREEN**

Run:

```bash
flutter test test/features/player/player_controller_test.dart test/features/player/desktop_player_controls_test.dart test/features/player/player_screen_test.dart
```

Expected: center invariance, menu, touch target, hierarchy, and existing mobile tests PASS.

- [ ] **Step 12: Review the scoped diff without committing**

Run:

```bash
git diff --check -- lib/features/player/player_controller.dart lib/features/player/desktop_player_controls.dart lib/features/player/player_screen.dart test/features/player/player_controller_test.dart test/features/player/desktop_player_controls_test.dart test/features/player/player_screen_test.dart
```

Expected: no whitespace errors.

---

### Task 4: Bounded Desktop Long-Queue Popover

**Files:**
- Create: `lib/features/player/desktop_queue_popover.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Test: `test/features/player/desktop_queue_popover_test.dart`

**Interfaces:**
- Consumes: `PlayerController controller`, `VoidCallback onDismiss`, and an optional `ScrollController` for deterministic tests.
- Produces: `DesktopQueuePopover`, keys `player-desktop-queue-popover`, `player-desktop-queue-list`, `player-desktop-queue-clear`, `desktop-queue-track-<id>`, and `player-desktop-queue-remove-<id>`.
- Reuses: `controller.playIndex(int)`, `removeAt(int)`, `clearQueue()`, and `resume()`.

- [ ] **Step 1: Write failing long-list and bounded-height tests**

Create 86 tracks and require a lazy `ListView.builder` bounded below 68% of an 800 px host:

```dart
expect(find.byKey(const Key('player-desktop-queue-popover')), findsOneWidget);
expect(find.text('播放队列 · 86'), findsOneWidget);
expect(
  tester.getSize(find.byKey(const Key('player-desktop-queue-popover'))).height,
  lessThanOrEqualTo(544),
);
expect(find.byType(ListView), findsOneWidget);
expect(find.text('Track 85'), findsNothing);
```

Scroll the internal list and assert `Track 85` becomes visible while the title and clear action remain in the same positions.

- [ ] **Step 2: Write failing current-item reveal and isolated-action tests**

Start at queue index 70 and require the current row to become visible once after open. Then tap a row and a remove button separately:

```dart
expect(find.byKey(const Key('desktop-queue-track-70')), findsOneWidget);
await tester.tap(find.byKey(const Key('desktop-queue-track-71')));
expect(controller.state.currentIndex, 71);
await tester.tap(find.byKey(const Key('player-desktop-queue-remove-72')));
expect(controller.state.currentIndex, 71);
```

Assert Escape calls `onDismiss`, clear uses the existing confirmation dialog, and stop/removal failure stays local with `重试` and no raw exception string.

- [ ] **Step 3: Run the new queue tests and verify RED**

Run:

```bash
flutter test test/features/player/desktop_queue_popover_test.dart
```

Expected: FAIL because `DesktopQueuePopover` does not exist.

- [ ] **Step 4: Implement the bounded lazy queue**

Use a `ConstrainedBox` calculated from the player viewport, a fixed header, and an `Expanded(ListView.builder(...))` body:

```dart
ConstrainedBox(
  key: const Key('player-desktop-queue-popover'),
  constraints: BoxConstraints(
    minWidth: 320,
    maxWidth: 390,
    maxHeight: availableHeight * .68,
  ),
  child: Column(
    children: [
      _QueueHeader(...),
      Expanded(
        child: ListView.builder(
          key: const Key('player-desktop-queue-list'),
          controller: scrollController,
          itemExtent: 56,
          itemCount: state.queue.length,
          itemBuilder: _buildRow,
        ),
      ),
    ],
  ),
)
```

Wrap the surface in `AppGlassSurface(role: AppGlassRole.sheet)`, not a nested card. Use one post-frame `ScrollController.animateTo`/`jumpTo` on initial open only; do not re-center when playback naturally advances.

- [ ] **Step 5: Implement row, clear, retry, and dismissal behavior**

Port the tested mutation behavior from `MobileQueueSheet` into the desktop container without duplicating controller logic. Use `Focus`/`Shortcuts` or the supported Shad popover escape path for dismissal. Prevent list scroll from propagating to any ancestor by ensuring the player itself is not scrollable and the list owns its pointer-scroll region.

- [ ] **Step 6: Anchor the queue popover independently from the core controls**

Connect `DesktopPlayerControls` queue action to the desktop popover. The queue overlay is right/bottom anchored and overlays the same backdrop; it must not insert into layout or alter `player-desktop-core` bounds.

- [ ] **Step 7: Run queue and control tests and verify GREEN**

Run:

```bash
flutter test test/features/player/desktop_queue_popover_test.dart test/features/player/desktop_player_controls_test.dart
```

Expected: long list, lazy build, initial current reveal, selection/removal isolation, clear/error, Escape dismissal, and center invariance PASS.

- [ ] **Step 8: Review the scoped diff without committing**

Run:

```bash
git diff --check -- lib/features/player/desktop_queue_popover.dart lib/features/player/desktop_player_controls.dart test/features/player/desktop_queue_popover_test.dart test/features/player/desktop_player_controls_test.dart
```

Expected: no whitespace errors.

---

### Task 5: Mobile Progress Hit Area and Long-Queue Current Reveal

**Files:**
- Modify: `lib/features/player/mobile_player_controls.dart`
- Modify: `lib/features/player/mobile_queue_sheet.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: the Task 1 `PlaybackProgress.hitExtent` interface and existing `MobileQueueSheet(controller:)` contract.
- Produces: mobile 44 px progress hit area, key `player-mobile-queue-list`, and one-time reveal of `mobile-queue-track-<current-id>`.

- [ ] **Step 1: Write a failing mobile progress gesture test**

At 390×844, start on artwork, drag horizontally inside `player-mobile-progress`, and assert seek changes while `PlayerView` remains artwork:

```dart
final progress = tester.getRect(find.byKey(const Key('player-mobile-progress')));
final gesture = await tester.startGesture(
  Offset(progress.left + 30, progress.center.dy),
);
await gesture.moveTo(Offset(progress.right - 30, progress.center.dy));
await gesture.up();
await tester.pump();
expect(controller.state.view, PlayerView.artwork);
expect(audio.lastSeek, isNotNull);
expect(
  tester.getSize(find.byKey(const Key('playback-progress-hit-area'))).height,
  44,
);
```

Extend the audio fake with `Duration? lastSeek` to make the assertion deterministic.

- [ ] **Step 2: Write a failing 86-track mobile queue test**

Set current index to 70, open the sheet, and assert current item visibility, lazy list type, fixed header, and internal scroll:

```dart
expect(find.byKey(const Key('player-mobile-queue-list')), findsOneWidget);
expect(find.byKey(const Key('mobile-queue-track-track-70')), findsOneWidget);
expect(find.text('86 首'), findsOneWidget);
await tester.fling(
  find.byKey(const Key('player-mobile-queue-list')),
  const Offset(0, -500),
  1000,
);
await tester.pumpAndSettle();
expect(find.text('86 首'), findsOneWidget);
```

- [ ] **Step 3: Run the mobile tests and verify RED**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile'
```

Expected: FAIL because mobile still uses the shared 28 px hit extent and the queue does not reveal the current item by key.

- [ ] **Step 4: Apply the 44 px mobile progress hit extent**

Pass the explicit mobile interaction size:

```dart
PlaybackProgress(
  key: const Key('player-mobile-progress'),
  position: state.position,
  duration: state.duration,
  hitExtent: 44,
  onSeek: onSeek,
)
```

Keep the progress control outside the `PageView` child gesture arena as it is today; do not add a second horizontal drag recognizer.

- [ ] **Step 5: Add one-time current-item reveal to the mobile sheet**

Read the draggable sheet controller with `PrimaryScrollController.of(context)`. Restructure `MobileQueueSheet` as a fixed count/clear/error header plus `Expanded(ListView.builder(itemExtent: 56))` using that controller. Jump once after the first frame to `currentIndex * 56`, clamped to scroll extent. This keeps count and clear fixed while allowing `DraggableScrollableSheet` to coordinate extent changes with the list.

- [ ] **Step 6: Run mobile tests and verify GREEN**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name 'mobile'
```

Expected: progress seek does not switch pages, 44 px hit area passes, long queue initially shows the current item, and existing select/remove/clear/error tests PASS.

- [ ] **Step 7: Review the scoped diff without committing**

Run:

```bash
git diff --check -- lib/features/player/mobile_player_controls.dart lib/features/player/mobile_queue_sheet.dart test/features/player/player_screen_test.dart
```

Expected: no whitespace errors.

---

### Task 6: Responsive Integration and Accessibility Boundaries

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/desktop_player_stage.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Modify: `lib/features/player/desktop_queue_popover.dart`
- Test: `test/features/player/player_screen_test.dart`
- Test: `test/features/player/desktop_player_controls_test.dart`
- Test: `test/features/player/desktop_queue_popover_test.dart`

**Interfaces:**
- Consumes: all components and keys from Tasks 1–5.
- Produces: stable desktop layouts at 1440×960 and 1024×768, mobile layout at 768 and below per current breakpoint classification, and complete keyboard/semantics behavior.

- [ ] **Step 1: Write failing responsive and semantics tests**

For 1440×960 and 1024×768, assert no exception, visible controls, and queue bounds inside the player. For 768, assert only `player-mobile-layout` exists. Add semantics expectations:

```dart
for (final label in ['返回', '上一首', '播放', '下一首', '音质', '播放队列']) {
  expect(find.bySemanticsLabel(label), findsOneWidget);
}
final playerRect = tester.getRect(find.byKey(const Key('player-screen-root')));
final queueRect = tester.getRect(
  find.byKey(const Key('player-desktop-queue-popover')),
);
expect(queueRect.left, greaterThanOrEqualTo(playerRect.left));
expect(queueRect.top, greaterThanOrEqualTo(playerRect.top));
expect(queueRect.right, lessThanOrEqualTo(playerRect.right));
expect(queueRect.bottom, lessThanOrEqualTo(playerRect.bottom));
```

Use these explicit edge comparisons rather than introducing a matcher package.

- [ ] **Step 2: Run the responsive tests and verify RED**

Run:

```bash
flutter test test/features/player/player_screen_test.dart test/features/player/desktop_player_controls_test.dart test/features/player/desktop_queue_popover_test.dart
```

Expected: at least the new queue-bound and semantics expectations FAIL before final integration tuning.

- [ ] **Step 3: Tune size constraints without adding panels or dividers**

Use `LayoutBuilder` to derive artwork maximum, core progress width, and popover maximum height. Under low height, shrink artwork and vertical gaps first; never hide or move the core controls. Preserve `classifyLayout(...)` as the single desktop/mobile decision.

- [ ] **Step 4: Complete keyboard and reduced-motion behavior**

Ensure Tab order follows return → main content controls → quality → queue; Enter/Space activates buttons; Escape closes the active popover. Use `MediaQuery.disableAnimations`/existing glass policy to switch popover transitions to opacity-only at `AppDurations.reducedMotion` or less. Do not animate focus rings.

- [ ] **Step 5: Run the responsive tests and verify GREEN**

Run:

```bash
flutter test test/features/player/player_screen_test.dart test/features/player/desktop_player_controls_test.dart test/features/player/desktop_queue_popover_test.dart
```

Expected: all responsive, semantics, keyboard, queue-bound, and existing player behavior tests PASS.

- [ ] **Step 6: Review the integration diff without committing**

Run:

```bash
git diff --check -- lib/features/player test/features/player test/design/playback_progress_test.dart
```

Expected: no whitespace errors.

---

### Task 7: High-Fidelity and Full-UI Visual Baselines

**Files:**
- Modify: `test/visual/high_fidelity_fixtures.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Modify: `test/visual/full_ui_gallery_test.dart`
- Create/Modify: player golden files listed in File Structure.

**Interfaces:**
- Consumes: stable widget keys and components from Tasks 1–6.
- Produces: deterministic references for default desktop, desktop quality, desktop long queue, mobile default, and mobile long queue.

- [ ] **Step 1: Add structural visual assertions before updating images**

Add tests at 1440×960 and 1024×768 that assert:

```dart
expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-core')), findsOneWidget);
expect(find.byKey(const Key('desktop-player-bottom-panel')), findsNothing);
expect(find.byKey(const Key('player-desktop-queue-popover')), queueOpen ? findsOneWidget : findsNothing);
```

Add an 86-track queue fixture and require the high-fidelity queue screenshot to show the fixed header plus a partial lazy list, not the entire queue.

- [ ] **Step 2: Run named visual tests and verify RED**

Run:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart --plain-name 'player desktop dark'
flutter test test/visual/high_fidelity_gallery_test.dart --plain-name 'player desktop quality dark'
flutter test test/visual/high_fidelity_gallery_test.dart --plain-name 'player desktop queue dark'
```

Expected: FAIL because new goldens are missing or differ from the old split-panel player.

- [ ] **Step 3: Update only approved player golden files**

Run the same named tests with `--update-goldens`. Then update only the four full UI player captures:

```bash
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name 'desktop player 1440x960'
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name 'desktop player 1024x768'
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name 'mobile player 390x844'
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name 'mobile player 360x800'
```

- [ ] **Step 4: Inspect every changed player image**

Open the default desktop, quality menu, long queue, 1024×768 desktop, 390×844 mobile, and mobile queue images. Confirm manually:

- backdrop is continuous through top and bottom;
- no whole-width top/bottom panel or divider appears;
- metadata appears once;
- progress/transport remain centered with popovers open;
- desktop queue stays within the window and scroll content is visibly clipped;
- mobile sheet respects safe area and fixed header;
- controls remain readable over both light and dark cover fixtures.

- [ ] **Step 5: Run the complete visual suites and verify GREEN**

Run:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart test/visual/full_ui_gallery_test.dart
```

Expected: all visual tests PASS with zero unexpected non-player golden changes.

- [ ] **Step 6: Review visual scope without committing**

Run:

```bash
git status --short -- test/visual
git diff --check -- test/visual
```

Expected: only intended player tests/fixtures/references changed during this task; preserve pre-existing unrelated golden changes already present in the dirty worktree.

---

### Task 8: Final Verification and macOS Real-Service Acceptance

**Files:**
- Verify all files changed in Tasks 1–7.
- No new production files unless verification finds a concrete defect.

**Interfaces:**
- Consumes: frozen implementation tree and existing Service configuration.
- Produces: analyzer, widget, visual, macOS build, and runtime evidence for handoff.

- [ ] **Step 1: Format only touched Dart files**

Run `dart format` with the explicit touched file list from File Structure. Do not format unrelated dirty files.

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: exit 0 and `No issues found`.

- [ ] **Step 3: Run focused player and design tests**

Run:

```bash
flutter test \
  test/design/playback_progress_test.dart \
  test/features/player/player_controller_test.dart \
  test/features/player/player_screen_test.dart \
  test/features/player/desktop_player_controls_test.dart \
  test/features/player/desktop_queue_popover_test.dart \
  test/design/app_components_test.dart
```

Expected: all tests PASS.

- [ ] **Step 4: Run visual suites**

Run:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart test/visual/full_ui_gallery_test.dart
```

Expected: all tests PASS.

- [ ] **Step 5: Build the macOS debug app**

Run:

```bash
flutter build macos --debug
```

Expected: exit 0 and `Built build/macos/Build/Products/Debug/TuneFlow.app`.

- [ ] **Step 6: Launch a fresh build against the real Service**

Terminate only the confirmed old TuneFlow debug process, then launch the newly built app. Use the existing configured origin or enter `http://192.168.0.172:3124` through the approved connection UI. Do not alter network/security settings.

- [ ] **Step 7: Validate desktop wide and compact windows**

At a wide window approximating 1440×960 and a compact desktop window approximating 1024×768, verify:

- artwork/lyrics/control canvas is continuous;
- transport center does not shift when quality or queue opens;
- progress click and drag are easy across the 28 px hit region;
- quality selection re-resolves playback and closes normally;
- an 86+ item queue scrolls internally, reveals current item on first open, and preserves user scroll afterward;
- selection, removal, clear confirmation, Escape/outside dismissal, and retry paths behave as specified;
- no overflow or inaccessible control appears.

- [ ] **Step 8: Validate the mobile path through a narrow macOS window**

Resize the same macOS app into the mobile breakpoint and verify the 44 px progress hit area, horizontal swipe isolation, draggable queue sheet, long-list internal scroll, current-item reveal, and safe-area behavior. Android installation is not required.

- [ ] **Step 9: Run Hallmark handoff audit and final diff checks**

Read `references/slop-test.md` and `references/contract.md` from the Hallmark skill at handoff time. Score Philosophy, Hierarchy, Execution, Specificity, Restraint, and Variety; revise anything below 3. Run all applicable slop gates, then:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; report the exact scoped changes while explicitly preserving unrelated dirty-worktree state.

- [ ] **Step 10: Hand off without committing**

Report changed files, test counts/commands, build result, runtime observations, golden previews, and any residual risk. Do not commit or push because the user has not authorized either action.
