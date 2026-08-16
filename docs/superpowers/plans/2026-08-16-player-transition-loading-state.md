# Player Transition Loading State Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every new-source request immediately present the player as Loading until that request either starts playback or fails, regardless of snapshots still arriving from the previous source.

**Architecture:** Represent “a new playback command is still in flight” explicitly in `PlayerState` instead of inferring it from the backend's `processing` snapshot. `PlayerController` owns this flag across session shutdown, cache lookup, Service resolution, and audio-source startup; presentation uses pending-aware derived getters so stale old-source snapshots cannot restore the pause icon or active animation. This avoids timers and avoids guessing snapshot ownership from `ready`/`buffering` values.

**Tech Stack:** Dart, Flutter, `ChangeNotifier`, `flutter_test`, existing `AudioPort`/`AudioSnapshot` abstractions.

## Global Constraints

- Preserve all unrelated user changes in the dirty worktree.
- Keep the fix in the Flutter client; no TuneFlow Service change is required.
- Do not add a timer, debounce, artificial delay, network request, dependency, or new icon.
- Selected-track metadata and pending-loading presentation must be published in the same synchronous controller notification.
- Backend snapshots may update raw playback state, but cannot cancel a controller-owned pending request.
- Pending ends only when the matching `_playCurrent` generation succeeds or fails; a stale request must never clear a newer request's pending state.
- Backend `loading` and `buffering` remain Loading even when no controller command is pending.
- Playback errors continue to expose the existing retry state.
- Do not commit unless the user separately authorizes a commit.

---

### Task 1: Add explicit playback-pending presentation semantics

**Files:**
- Modify: `lib/features/player/player_state.dart:30-119`
- Test: `test/features/player/player_controller_test.dart`

**Interfaces:**
- Consumes: existing `PlayerState.playing` and `PlayerState.processing`.
- Produces: `bool playbackPending`, `bool get isPlaybackLoading`, and `bool get isPlaybackActive`; `copyWith({bool? playbackPending})` preserves the value unless explicitly changed.

- [ ] **Step 1: Write a focused state contract test**

Add this test near the other `PlayerState`/transport-state tests:

```dart
test('pending playback overrides raw ready playback presentation', () {
  const pending = PlayerState(
    playing: true,
    processing: PlayerProcessing.ready,
    playbackPending: true,
  );

  expect(pending.playbackPending, isTrue);
  expect(pending.isPlaybackLoading, isTrue);
  expect(pending.isPlaybackActive, isFalse);

  final started = pending.copyWith(playbackPending: false);
  expect(started.isPlaybackLoading, isFalse);
  expect(started.isPlaybackActive, isTrue);
});
```

- [ ] **Step 2: Run the focused test and confirm the contract is missing**

Run:

```sh
flutter test test/features/player/player_controller_test.dart --plain-name 'pending playback overrides raw ready playback presentation'
```

Expected before implementation: compile failure reporting that `playbackPending`, `isPlaybackLoading`, and `isPlaybackActive` are undefined.

- [ ] **Step 3: Add the immutable state field and derived getters**

Extend `PlayerState` without changing `AudioSnapshot`:

```dart
this.playbackPending = false,

final bool playbackPending;

bool get isPlaybackLoading =>
    playbackPending ||
    processing == PlayerProcessing.loading ||
    processing == PlayerProcessing.buffering;

bool get isPlaybackActive => playing && !isPlaybackLoading;
```

Add `bool? playbackPending` to `copyWith` and forward it:

```dart
playbackPending: playbackPending ?? this.playbackPending,
```

Do not fold errors into `isPlaybackLoading`; error remains a separate presentation branch.

- [ ] **Step 4: Format and rerun the focused check**

Run:

```sh
dart format lib/features/player/player_state.dart test/features/player/player_controller_test.dart
flutter test test/features/player/player_controller_test.dart --plain-name 'pending playback overrides raw ready playback presentation'
```

Expected: PASS, proving both the pending override and the false-valued `copyWith` transition.

---

### Task 2: Own pending lifetime in PlayerController

**Files:**
- Modify: `lib/features/player/player_controller.dart:51-70`
- Modify: `lib/features/player/player_controller.dart:128-229`
- Modify: `lib/features/player/player_controller.dart:382-432`
- Modify: `lib/features/player/player_controller.dart:574-589`
- Modify: `test/features/player/player_controller_test.dart:1109-1194`

**Interfaces:**
- Consumes: `PlayerState.playbackPending` and `_playGeneration`.
- Produces: new-source entry paths publish `playbackPending: true`; only a matching `_playCurrent` success/failure publishes `playbackPending: false`.

- [ ] **Step 1: Replace the inverted stale-ready test**

Replace `ready snapshot during previous session end remains authoritative` with this controlled resolve race:

```dart
test(
  'old ready snapshot keeps a new track pending until playback starts',
  () async {
    final audio = FakeAudio();
    final resolver = DeferredResolver();
    final controller = PlayerController(resolver: resolver, audio: audio);

    final first = controller.play(track('first'));
    await Future<void>.delayed(Duration.zero);
    resolver.requests[0].complete(bundleSource());
    await first;
    audio.controller.add(const AudioSnapshot(
      playing: true,
      processing: PlayerProcessing.ready,
    ));
    await Future<void>.delayed(Duration.zero);

    final second = controller.play(track('second'));
    await Future<void>.delayed(Duration.zero);
    audio.controller.add(const AudioSnapshot(
      playing: true,
      processing: PlayerProcessing.ready,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.current?.id, 'second');
    expect(controller.state.playbackPending, isTrue);
    expect(controller.state.isPlaybackLoading, isTrue);
    expect(controller.state.isPlaybackActive, isFalse);

    resolver.requests[1].complete(bundleSource());
    await second;
    audio.controller.add(const AudioSnapshot(
      playing: true,
      processing: PlayerProcessing.ready,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.playbackPending, isFalse);
    expect(controller.state.isPlaybackLoading, isFalse);
    expect(controller.state.isPlaybackActive, isTrue);
  },
);
```

- [ ] **Step 2: Update the related queue-transition tests**

Rename the neighboring `playIndex` and current-item removal tests so they assert pending remains true after an injected old `ready` snapshot. While `DeferredEndSessions.pendingEnds.single` is held, use:

```dart
expect(controller.state.processing, PlayerProcessing.ready);
expect(controller.state.playbackPending, isTrue);
expect(controller.state.isPlaybackLoading, isTrue);
```

The raw `ready` assertion is intentional: presentation must stay Loading without falsifying the backend snapshot. Complete the deferred end, await the transition, then assert pending is false and preserve the current queue/index assertions.

- [ ] **Step 3: Publish pending synchronously on every new-source path**

Set `playbackPending: true` in the same assignment that publishes `PlayerProcessing.loading` for:

- `playTracks`;
- `playIndex`;
- `removeAt` when removing the current track;
- `resume` when retrying an error through `_playCurrent`;
- `setQuality` before `_playCurrent`;
- repeat-one handling before `_playCurrent`.

Representative code:

```dart
state = state.copyWith(
  processing: PlayerProcessing.loading,
  playbackPending: true,
  error: null,
);
notifyListeners();
```

For `playTracks`, pass `playbackPending: true` to the new `PlayerState`. Do not set it for `pause`, ordinary `resume`, `seek`, `enqueue`, `playNext`, or removal of a non-current item.

- [ ] **Step 4: Clear pending only after the matching generation resolves**

In both successful `_playCurrent` exits, retain `_isCurrent(generation, track)` and clear pending with the success notification:

```dart
if (!_isCurrent(generation, track)) return false;
state = state.copyWith(playbackPending: false, error: null);
notifyListeners();
```

Apply this after cached playback and streamed `audio.playTrack`. In the final error path:

```dart
if (!_isCurrent(generation, track)) return false;
state = state.copyWith(
  playbackPending: false,
  processing: PlayerProcessing.error,
  error: lastError,
);
notifyListeners();
```

Do not clear pending in `_onSnapshot`; snapshots do not identify which request produced them.

- [ ] **Step 5: Cover failure and superseded-request cleanup**

Extend an existing playback-error test with:

```dart
expect(controller.state.playbackPending, isFalse);
expect(controller.state.processing, PlayerProcessing.error);
```

In the existing late-resolve/newer-track test, after completing the first request assert:

```dart
expect(controller.state.current?.id, 'second');
expect(controller.state.playbackPending, isTrue);
```

Complete the second request and assert pending becomes false.

- [ ] **Step 6: Run the controller suite**

Run:

```sh
dart format lib/features/player/player_controller.dart test/features/player/player_controller_test.dart
flutter test test/features/player/player_controller_test.dart
```

Expected: all controller tests pass, including queue replacement, index selection, current-item removal, failure, and superseded-generation cases.

---

### Task 3: Make in-app playback presentation use derived state

**Files:**
- Modify: `lib/features/player/mini_player.dart:58-78`
- Modify: `lib/features/player/mini_player.dart:258-282`
- Modify: `lib/features/player/mini_player.dart:442-475`
- Modify: `lib/features/player/desktop_player_controls.dart:80-113`
- Modify: `lib/features/player/desktop_player_controls.dart:238-290`
- Modify: `lib/features/player/mobile_player_controls.dart:125-176`
- Modify: `lib/features/player/mobile_queue_sheet.dart:240-252`
- Modify: `lib/features/player/player_screen.dart:618-655`
- Modify: `lib/features/player/desktop_player_stage.dart:82-96`
- Test: `test/features/player/player_screen_test.dart:604-660`

**Interfaces:**
- Consumes: `PlayerState.isPlaybackLoading` and `PlayerState.isPlaybackActive`.
- Produces: desktop/mobile transports show Loading during pending, and active animation cannot run for new metadata while an old source snapshot still says playing.

- [ ] **Step 1: Add a pending-plus-ready widget regression**

Extend `desktop loading transport remains available for pause` with a fixture/controller state equivalent to:

```dart
PlayerState(
  queue: [
    Track.fromJson({
      'id': 'pending-track',
      'name': 'Pending Track',
      'source': 'kw',
    }),
  ],
  currentIndex: 0,
  playing: true,
  processing: PlayerProcessing.ready,
  playbackPending: true,
)
```

Assert:

```dart
expect(find.byKey(const Key('desktop-player-loading')), findsOneWidget);
expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
```

Then publish the same `ready + playing` backend state with pending false and assert loading disappears and pause semantics return.

- [ ] **Step 2: Run the widget regression and verify current UI fails**

Run:

```sh
flutter test test/features/player/player_screen_test.dart --plain-name 'desktop loading transport remains available for pause'
```

Expected before UI implementation: failure because `_transportPresentation` checks only raw `processing`.

- [ ] **Step 3: Replace duplicated presentation checks**

Replace UI checks of:

```dart
state.processing == PlayerProcessing.loading ||
state.processing == PlayerProcessing.buffering
```

with:

```dart
state.isPlaybackLoading
```

For `_DesktopMainTransport` and `MobilePlayerControls`, reuse their existing spinner paths. Add `loading` support to the mobile-mini `_TransportButton` and full-player desktop `_ControlButton` by rendering the same bounded `CircularProgressIndicator` pattern already used in `MobilePlayerControls`; pass `loading: state.isPlaybackLoading` only to the main play/pause control. Its Loading tooltip is `正在加载`, its command remains `controller.pause`, and previous/next controls are unchanged.

For animation and active-playback labels, replace presentation-level `state.playing` checks with `state.isPlaybackActive`. Preserve raw `state.playing` only where it decides whether to send `pause` versus `resume`; loading controls remain wired to `controller.pause`.

- [ ] **Step 4: Classify every player-state consumer**

Run:

```sh
rg -n "state\.playing|PlayerProcessing\.(loading|buffering)" lib/features/player --glob '*.dart'
```

Presentation results must use `isPlaybackLoading`/`isPlaybackActive`; control delegation may retain raw `playing`. Do not alter unrelated favorite/download loading state.

- [ ] **Step 5: Format and run focused UI suites**

Run:

```sh
dart format lib/features/player/mini_player.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart lib/features/player/mobile_queue_sheet.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
```

Expected: both suites pass; backend loading/buffering and pending-plus-ready all render Loading.

---

### Task 4: Final verification and diff audit

**Files:**
- Verify: all production and test files from Tasks 1-3.

**Interfaces:**
- Consumes: completed pending-state, controller-lifetime, and presentation work.
- Produces: frozen evidence for behavior and icon-policy compliance.

- [ ] **Step 1: Run the focused playback verification**

Run:

```sh
flutter test test/features/player/player_controller_test.dart
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
```

Expected: all commands pass.

- [ ] **Step 2: Confirm the icon boundary remains unchanged**

Run:

```sh
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: the first returns no matches; the second matches only `lib/design/components/app_playback_button.dart`.

- [ ] **Step 3: Audit the scoped diff**

Run:

```sh
git diff -- lib/features/player/player_state.dart lib/features/player/player_controller.dart lib/features/player/mini_player.dart lib/features/player/desktop_player_controls.dart lib/features/player/mobile_player_controls.dart lib/features/player/mobile_queue_sheet.dart lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart
```

Expected: changes are limited to the pending-state contract, controller lifetime, presentation consumption, and regression tests. There is no Service API, persistence, dependency, timer, delay, or icon-family change; pre-existing user edits remain intact.

## Final Acceptance Criteria

- Selecting a different search result shows new metadata and Loading together.
- Old-source `ready + playing`, `buffering`, `idle`, or position snapshots cannot cancel Loading while the new request is unresolved.
- Successful cached and streamed playback clear pending only for the current generation.
- Failure clears pending and exposes the existing retry state.
- A superseded request cannot clear a newer request's pending state.
- Desktop/mobile transports, tooltips, queue activity, and playback animation consistently use pending-aware state.
- Loading remains pausable, and ready playback restores pause normally.
- No Service, persistence, dependency, or icon-system changes are introduced.
