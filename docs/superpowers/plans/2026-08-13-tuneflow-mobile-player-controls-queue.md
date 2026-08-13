# TuneFlow Mobile Player Controls and Queue Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mobile full-player lower controls with the approved continuous A layout and move queue browsing and management into the approved draggable C bottom sheet.

**Architecture:** Keep `PlayerController` as the only owner of queue mutations and extend `AudioPort` with a reusable playback-stop command that does not dispose the handler. Split mobile controls and mobile queue content into focused widgets, while `PlayerScreen` remains the coordinator for PageView navigation and modal presentation. Extend the existing app sheet helper with optional draggable extents so current callers remain unchanged.

**Tech Stack:** Flutter, Dart, Riverpod-adjacent controller patterns, shadcn_ui, just_audio, flutter_test, Golden tests.

## Global Constraints

- Follow `/Volumes/ext/MusicFree/flutter-client/design.md`; use Mist Sea semantic tokens and `glassClear` / `glassSheet`, never page-local raw colours.
- Mobile Player PageView contains exactly artwork and lyrics; queue is not a third horizontal page.
- Queue Sheet extents are `initialChildSize: 0.64`, `minChildSize: 0.48`, and `maxChildSize: 0.90` of the safe available height.
- Touch targets are at least 44 px. Standard motion is at most 280 ms; reduced-motion transitions are opacity-only and at most 150 ms.
- Queue removal chooses the original next track first, otherwise the previous track. Removing the final track and clearing the queue stop playback and close the Sheet.
- Clear queue requires destructive confirmation. Individual removal uses silent success.
- Do not add shuffle, repeat, drag sorting, history, VIP content, advertising, or unimplemented favourite/download actions.
- Keep desktop player layout and behavior unchanged.
- Preserve all unrelated dirty-worktree changes. Do not delete production files.
- Do not commit, push, or publish unless the user separately authorizes it.

---

## File Structure

### Create

- `lib/features/player/mobile_player_controls.dart` — the continuous A control surface; renders metadata, available secondary controls, progress, and transport.
- `lib/features/player/mobile_queue_sheet.dart` — the C queue Sheet body; owns confirmation UI and delegates queue commands to `PlayerController`.

### Modify

- `lib/features/player/service_audio_handler.dart` — add reusable `AudioPort.stopPlayback()` without disposing streams or the handler.
- `lib/features/player/player_controller.dart` — add `removeAt(int)` and `clearQueue()` commands.
- `lib/features/player/player_state.dart` — retain `PlayerView.queue` as the desktop mini-player's transient entry intent while keeping the mobile PageView at two pages.
- `lib/features/player/player_screen.dart` — coordinate two-page mobile content, A controls, and C Sheet.
- `lib/design/design_tokens.dart` — add semantic player transition duration and easing constants used by the two-page navigation.
- `lib/design/components/app_feedback.dart` — add optional draggable extents to `showAppSheet` while preserving existing behavior for all existing callers.
- `test/features/player/player_controller_test.dart` — unit coverage for stop and all queue mutation branches.
- `test/features/player/player_screen_test.dart` — structure, gestures, Sheet, removal, confirmation, errors, and narrow-width coverage.
- `test/design/app_components_test.dart` — draggable sheet helper coverage.
- `test/features/search/search_screen_test.dart` — add the new `AudioPort` test-double method only.
- `test/features/discovery/online_playlist_detail_screen_test.dart` — add the new `AudioPort` test-double method only.
- `test/visual/high_fidelity_fixtures.dart` — add the new fixture audio method.
- `test/visual/high_fidelity_gallery_test.dart` — update player assertions and Golden capture.
- `test/visual/goldens/player-mobile-dark.png` — approved A-layout Golden.
- `test/visual/full_ui_gallery_test.dart` and affected mobile player Goldens — update only if this suite captures `PlayerScreen` directly.

## Interfaces

```dart
abstract interface class AudioPort {
  Stream<AudioSnapshot> get snapshots;
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  });
  Future<bool> playCachedTrack(Track track, String quality);
  Future<void> playTrack(Track track, Uri streamUri, String quality);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stopPlayback();
}

final class PlayerController extends ChangeNotifier {
  Future<bool> removeAt(int index);
  Future<bool> clearQueue();
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  double? initialChildSize,
  double minChildSize = 0.48,
  double maxChildSize = 0.90,
});
```

`removeAt` and `clearQueue` return `true` only when the requested mutation has been accepted. An invalid index or a failed final-track stop returns `false`. A successful removal that advances to a track whose playback later fails still returns `true`; the controller exposes that playback failure through `PlayerState.error`.

---

### Task 1: Add a reusable audio stop command

**Files:**

- Modify: `lib/features/player/service_audio_handler.dart:21-49, 56-220`
- Modify: `test/features/player/player_controller_test.dart:29-70`
- Modify: `test/features/player/player_screen_test.dart:30-86`
- Modify: `test/features/search/search_screen_test.dart:50`
- Modify: `test/features/discovery/online_playlist_detail_screen_test.dart:36`
- Modify: `test/visual/high_fidelity_fixtures.dart:445`

**Interfaces:**

- Consumes: `just_audio.AudioPlayer.stop()`.
- Produces: `Future<void> AudioPort.stopPlayback()` that stops current playback but leaves snapshots, callbacks, and the handler reusable.

- [ ] **Step 1: Add a failing contract test to the controller fake**

Add stop observability to `FakeAudio` and a test that demonstrates the desired reusable command:

```dart
class FakeAudio implements AudioPort {
  int stopPlaybackCalls = 0;
  Object? stopPlaybackError;

  @override
  Future<void> stopPlayback() async {
    stopPlaybackCalls++;
    if (stopPlaybackError case final error?) throw error;
  }
}

test('audio stop command is available without disposing the port', () async {
  final fake = FakeAudio();
  final AudioPort audio = fake;
  await audio.stopPlayback();
  await audio.resume();

  expect(fake.stopPlaybackCalls, 1);
  expect(fake.resumeCalls, 1);
});
```

- [ ] **Step 2: Run the focused test and confirm the interface mismatch**

Run:

```bash
flutter test test/features/player/player_controller_test.dart --plain-name "audio stop command is available without disposing the port"
```

Expected: FAIL before `AudioPort.stopPlayback()` exists, or analyzer failure showing the fake/interface mismatch.

- [ ] **Step 3: Add `stopPlayback()` to production implementations**

Add the method to `AudioPort`, `SilentAudioPort`, and `ServiceAudioHandler`:

```dart
abstract interface class AudioPort {
  Stream<AudioSnapshot> get snapshots;
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  });
  Future<bool> playCachedTrack(Track track, String quality);
  Future<void> playTrack(Track track, Uri streamUri, String quality);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stopPlayback();
}

final class SilentAudioPort implements AudioPort {
  @override
  Future<void> stopPlayback() async {}
}

final class ServiceAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements AudioPort {
  @override
  Future<void> stopPlayback() async {
    await _player.stop();
    _publishSnapshot(position: Duration.zero);
  }
}
```

Do not call or modify the lifecycle `stop()` method; it must continue cancelling subscriptions and disposing `_player`.

- [ ] **Step 4: Make every test/visual `AudioPort` implementation compile**

Add a no-op `stopPlayback()` to simple fakes and the observable form above to player fakes. Do not change any other fake behavior.

- [ ] **Step 5: Run focused tests**

Run:

```bash
flutter test test/features/player/player_controller_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Inspect the scoped diff**

Run `git diff -- lib/features/player/service_audio_handler.dart test/features/player test/features/search/search_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/visual/high_fidelity_fixtures.dart` and verify that no lifecycle-disposal behavior changed. Leave changes uncommitted.

---

### Task 2: Implement queue mutations in `PlayerController`

**Files:**

- Modify: `lib/features/player/player_controller.dart:29-120`
- Modify: `lib/features/player/player_state.dart:1-90`
- Test: `test/features/player/player_controller_test.dart`

**Interfaces:**

- Consumes: `AudioPort.stopPlayback()` from Task 1 and existing `_playCurrent()`.
- Produces: `Future<bool> removeAt(int index)` and `Future<bool> clearQueue()`.

- [ ] **Step 1: Write failing tests for non-current removals**

```dart
test('removing before current preserves the current track', () async {
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  await controller.playTracks(
    [track('a'), track('b'), track('c')],
    startIndex: 1,
  );

  expect(await controller.removeAt(0), isTrue);
  expect(controller.state.queue.map((item) => item.id), ['b', 'c']);
  expect(controller.state.current?.id, 'b');
  expect(controller.state.currentIndex, 0);
});

test('removing after current keeps its index and playback', () async {
  final audio = FakeAudio();
  final controller = PlayerController(resolver: FakeResolver(), audio: audio);
  await controller.playTracks([track('a'), track('b'), track('c')]);
  final playCalls = audio.playCalls;

  expect(await controller.removeAt(2), isTrue);
  expect(controller.state.current?.id, 'a');
  expect(controller.state.currentIndex, 0);
  expect(audio.playCalls, playCalls);
});
```

- [ ] **Step 2: Write failing tests for the three current-track branches**

```dart
test('removing current prefers the original next track', () async {
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  await controller.playTracks(
    [track('a'), track('b'), track('c')],
    startIndex: 1,
  );

  expect(await controller.removeAt(1), isTrue);
  expect(controller.state.queue.map((item) => item.id), ['a', 'c']);
  expect(controller.state.current?.id, 'c');
  expect(controller.state.currentIndex, 1);
});

test('removing current tail falls back to the previous track', () async {
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  await controller.playTracks([track('a'), track('b')], startIndex: 1);

  expect(await controller.removeAt(1), isTrue);
  expect(controller.state.queue.map((item) => item.id), ['a']);
  expect(controller.state.current?.id, 'a');
  expect(controller.state.currentIndex, 0);
});

test('removing the final track stops and empties the player', () async {
  final audio = FakeAudio();
  final controller = PlayerController(resolver: FakeResolver(), audio: audio);
  await controller.play(track('a'));

  expect(await controller.removeAt(0), isTrue);
  expect(audio.stopPlaybackCalls, 1);
  expect(controller.state.queue, isEmpty);
  expect(controller.state.current, isNull);
  expect(controller.state.currentIndex, -1);
});
```

- [ ] **Step 3: Write failing tests for invalid indices, clear, and stop failure**

```dart
test('invalid removal is ignored', () async {
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  expect(await controller.removeAt(0), isFalse);
});

test('clear queue stops audio and preserves player preferences', () async {
  final audio = FakeAudio();
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: audio,
    quality: '320k',
    showTranslation: false,
  );
  await controller.playTracks([track('a'), track('b')]);

  expect(await controller.clearQueue(), isTrue);
  expect(audio.stopPlaybackCalls, 1);
  expect(controller.state.queue, isEmpty);
  expect(controller.state.quality, '320k');
  expect(controller.state.showTranslation, isFalse);
});

test('failed stop keeps the queue and exposes an error', () async {
  final audio = FakeAudio()..stopPlaybackError = StateError('stop failed');
  final controller = PlayerController(resolver: FakeResolver(), audio: audio);
  await controller.play(track('a'));

  expect(await controller.clearQueue(), isFalse);
  expect(controller.state.current?.id, 'a');
  expect(controller.state.error, isA<StateError>());
});

test('failed final-track removal keeps the track', () async {
  final audio = FakeAudio()..stopPlaybackError = StateError('stop failed');
  final controller = PlayerController(resolver: FakeResolver(), audio: audio);
  await controller.play(track('a'));

  expect(await controller.removeAt(0), isFalse);
  expect(controller.state.current?.id, 'a');
  expect(controller.state.queue.map((track) => track.id), ['a']);
});
```

- [ ] **Step 4: Run tests and confirm missing commands**

Run `flutter test test/features/player/player_controller_test.dart`.

Expected: FAIL because `removeAt` and `clearQueue` do not exist.

- [ ] **Step 5: Implement mutation commands with one empty-state helper**

Use a helper that preserves non-queue preferences:

```dart
PlayerState _emptyState({Object? error}) => PlayerState(
  quality: state.quality,
  showTranslation: state.showTranslation,
  view: PlayerView.artwork,
  error: error,
);

Future<bool> clearQueue() async {
  if (state.queue.isEmpty) return false;
  try {
    await audio.stopPlayback();
  } on Object catch (error) {
    state = state.copyWith(error: error);
    notifyListeners();
    return false;
  }
  state = _emptyState();
  notifyListeners();
  return true;
}

Future<bool> removeAt(int index) async {
  if (index < 0 || index >= state.queue.length) return false;
  if (state.queue.length == 1) return clearQueue();

  final removingCurrent = index == state.currentIndex;
  final queue = [...state.queue]..removeAt(index);
  if (!removingCurrent) {
    final nextIndex = index < state.currentIndex
        ? state.currentIndex - 1
        : state.currentIndex;
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: nextIndex,
    );
    notifyListeners();
    return true;
  }

  final nextIndex = index < queue.length ? index : queue.length - 1;
  state = state.copyWith(
    queue: List.unmodifiable(queue),
    currentIndex: nextIndex,
    processing: PlayerProcessing.loading,
    position: Duration.zero,
    duration: Duration.zero,
    buffered: Duration.zero,
    clearLyrics: true,
    error: null,
    lyricsError: null,
  );
  notifyListeners();
  await _playCurrent();
  return true;
}
```

If `copyWith` cannot explicitly reset one of the duration fields because null and zero are conflated, pass `Duration.zero` as above and verify the resulting state in tests.

- [ ] **Step 6: Preserve queue as an entry intent, not a mobile page**

Keep the existing enum because the desktop mini-player uses `queue` to request that the full player opens its Sheet:

```dart
enum PlayerView { artwork, lyrics, queue }
```

Retain a compatibility test:

```dart
test('queue remains available as a full-player entry intent', () {
  final controller = PlayerController(
    resolver: FakeResolver(),
    audio: FakeAudio(),
  );
  controller.setView(PlayerView.queue);
  expect(controller.state.view, PlayerView.queue);
});
```

`PlayerScreen` must clamp `PageController.initialPage` to artwork or lyrics and convert an initial `PlayerView.queue` into an opened queue Sheet after the first frame.

- [ ] **Step 7: Run the controller suite**

Run `flutter test test/features/player/player_controller_test.dart`.

Expected: PASS.

- [ ] **Step 8: Inspect the scoped diff**

Run `git diff -- lib/features/player/player_controller.dart lib/features/player/player_state.dart test/features/player/player_controller_test.dart`. Confirm only queue commands and the two-view model changed. Leave changes uncommitted.

---

### Task 3: Extend the app sheet helper with draggable extents

**Files:**

- Modify: `lib/design/components/app_feedback.dart:97-118`
- Test: `test/design/app_components_test.dart`

**Interfaces:**

- Consumes: Material `showModalBottomSheet`, `DraggableScrollableSheet`, and existing `AppGlassSurface(role: AppGlassRole.sheet)`.
- Produces: backward-compatible optional extents on `showAppSheet`.

- [ ] **Step 1: Write a failing draggable-sheet widget test**

Add a test that opens the helper with player extents and measures initial height:

```dart
testWidgets('app sheet supports bounded draggable mobile extents', (
  tester,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    harness(
      Builder(
        builder: (context) => AppButton(
          onPressed: () => showAppSheet<void>(
            context,
            title: '播放队列',
            initialChildSize: .64,
            minChildSize: .48,
            maxChildSize: .90,
            child: const SizedBox(key: Key('sheet-content')),
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();

  expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  expect(find.byKey(const Key('sheet-content')), findsOneWidget);
  expect(find.byType(AppGlassSurface), findsOneWidget);
});
```

- [ ] **Step 2: Run the test and confirm signature failure**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name "app sheet supports bounded draggable mobile extents"
```

Expected: FAIL because the extent parameters do not exist.

- [ ] **Step 3: Implement the optional draggable branch**

Keep the existing `showShadSheet` branch exactly as-is when `initialChildSize == null`. For the draggable branch, validate `0 < min <= initial <= max <= 1`, then use `showModalBottomSheet` with `isScrollControlled: true`, `useSafeArea: true`, transparent background, and a `DraggableScrollableSheet`:

```dart
if (initialChildSize != null) {
  assert(0 < minChildSize);
  assert(minChildSize <= initialChildSize);
  assert(initialChildSize <= maxChildSize);
  assert(maxChildSize <= 1);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (context, scrollController) {
        final tokens = AppTokens.of(context);
        return AppGlassSurface(
          role: AppGlassRole.sheet,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.border,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTypography.title),
                    ),
                    Semantics(
                      button: true,
                      label: '关闭',
                      child: ShadButton.ghost(
                        width: 44,
                        height: 44,
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(LucideIcons.x, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PrimaryScrollController(
                  controller: scrollController,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
```

- [ ] **Step 4: Verify draggable and legacy sheet paths**

Run:

```bash
flutter test test/design/app_components_test.dart
flutter test test/features/search/search_screen_test.dart
```

Expected: PASS, including existing `ShadSheet` expectations for callers that did not pass extents.

- [ ] **Step 5: Inspect the scoped diff**

Run `git diff -- lib/design/components/app_feedback.dart test/design/app_components_test.dart` and verify the default branch remains source-compatible. Leave changes uncommitted.

---

### Task 4: Build the A continuous mobile control surface

**Files:**

- Create: `lib/features/player/mobile_player_controls.dart`
- Modify: `lib/features/player/player_screen.dart:207-472`
- Modify: `lib/design/design_tokens.dart`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**

- Consumes: `PlayerState`, `PlaybackProgress`, `AppGlassSurface`, and callbacks from `PlayerScreen`.
- Produces: `MobilePlayerControls` with stable keys `player-mobile-controls`, `player-mobile-progress`, `player-mobile-transport`, `player-mobile-lyrics`, `player-mobile-quality`, and `player-mobile-queue`.

- [ ] **Step 1: Replace the existing mobile hierarchy assertion with a failing A-layout assertion**

Update the mobile test to require one continuous surface and two pages:

```dart
expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-progress')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-transport')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-artwork')), findsOneWidget);
expect(find.byType(PageView), findsOneWidget);
expect(find.text('One'), findsOneWidget);
expect(find.text('kw'), findsNothing);
```

Add a swipe test proving there are only artwork and lyrics pages:

```dart
await tester.drag(find.byType(PageView), const Offset(-320, 0));
await tester.pumpAndSettle();
expect(controller.state.view, PlayerView.lyrics);

await tester.drag(find.byType(PageView), const Offset(-320, 0));
await tester.pumpAndSettle();
expect(controller.state.view, PlayerView.lyrics);
```

Add state assertions for the stable controls:

```dart
expect(
  tester.getSize(find.byKey(const Key('player-previous'))),
  const Size(48, 48),
);
expect(
  tester.widget<Semantics>(
    find.ancestor(
      of: find.byKey(const Key('player-previous')),
      matching: find.byType(Semantics),
    ).first,
  ).properties.enabled,
  isFalse,
);
expect(find.bySemanticsLabel('播放队列'), findsOneWidget);
```

In a loading snapshot, assert the play button keeps its measured size and exposes the semantic label “正在加载”. In an error snapshot, assert the local retry remains reachable without hiding the queue control.

- [ ] **Step 2: Add failing 320 and 390 px overflow tests**

Use the existing harness at `Size(320, 700)` and `Size(390, 844)`. For each size, pump the player and assert `tester.takeException()` is null and all transport targets are at least 44 x 44.

- [ ] **Step 3: Run focused screen tests**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name "mobile player uses the immersive glass hierarchy"
```

Expected: FAIL because `player-mobile-controls` and queue button keys do not exist.

- [ ] **Step 4: Implement `MobilePlayerControls`**

Create a stateless widget with this public interface:

```dart
final class MobilePlayerControls extends StatelessWidget {
  const MobilePlayerControls({
    super.key,
    required this.state,
    required this.onSeek,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onLyrics,
    required this.onQualityChanged,
    required this.onQueue,
  });

  final PlayerState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onLyrics;
  final ValueChanged<String> onQualityChanged;
  final VoidCallback onQueue;
}
```

Its root is one `AppGlassSurface(role: AppGlassRole.clear)`. Inside, render in this exact order:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _TrackMetadata(state: state),
    const SizedBox(height: AppSpacing.sm),
    _SecondaryActions(
      quality: state.quality,
      onLyrics: onLyrics,
      onQualityChanged: onQualityChanged,
    ),
    const SizedBox(height: AppSpacing.sm),
    PlaybackProgress(
      position: state.position,
      duration: state.duration,
      onSeek: onSeek,
    ),
    const SizedBox(height: AppSpacing.sm),
    _TransportRow(
      state: state,
      onPrevious: onPrevious,
      onPlayPause: onPlayPause,
      onNext: onNext,
      onQueue: onQueue,
    ),
  ],
)
```

Only Lyrics and Quality appear in `_SecondaryActions`; do not render fake favourite/download buttons. The play button is the sole prominent circle. Keep disabled previous/next controls in place.

- [ ] **Step 5: Add semantic transition constants**

Append to `design_tokens.dart`:

```dart
abstract final class AppDurations {
  static const Duration state = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 280);
  static const Duration reducedMotion = Duration(milliseconds: 150);
}

abstract final class AppCurves {
  static const Curve out = Cubic(0.16, 1, 0.3, 1);
  static const Curve inOut = Cubic(0.65, 0, 0.35, 1);
}
```

- [ ] **Step 6: Integrate the component and reduce PageView to two children**

In `_MobilePlayer`:

- Keep top bar and local playback error.
- Keep `_MobileNowPlaying` and `LyricsView` as the two PageView children.
- Delete the inline queue third child.
- Replace separate progress and transport glass surfaces with `MobilePlayerControls`.
- `onLyrics` calls `pages.animateToPage(1, duration: AppDurations.page, curve: AppCurves.out)` and updates `PlayerView.lyrics`.
- `onPlayPause` delegates to `pause` or `resume` from `state.playing`.
- `onQualityChanged` delegates to `controller.setQuality`.

- [ ] **Step 7: Run mobile and desktop player tests**

Run `flutter test test/features/player/player_screen_test.dart`.

Expected: PASS. The desktop tests in the same file must remain unchanged and pass.

- [ ] **Step 8: Inspect the scoped diff**

Run `git diff -- lib/features/player/mobile_player_controls.dart lib/features/player/player_screen.dart lib/design/design_tokens.dart test/features/player/player_screen_test.dart`. Confirm the desktop `_DesktopPlayer` and desktop `_Controls` branches were not visually reorganized. Leave changes uncommitted.

---

### Task 5: Build and integrate the C queue management Sheet

**Files:**

- Create: `lib/features/player/mobile_queue_sheet.dart`
- Modify: `lib/features/player/player_screen.dart:40-160`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**

- Consumes: `PlayerController.removeAt`, `PlayerController.clearQueue`, `showAppDestructiveDialog`, and draggable `showAppSheet` extents.
- Produces: `MobileQueueSheet(controller: controller)` and player Sheet keys `player-mobile-queue-sheet`, `player-mobile-queue-clear`, `player-mobile-queue-remove-<id>`.

- [ ] **Step 1: Write failing Sheet-open and selection tests**

```dart
await tester.tap(find.byKey(const Key('player-mobile-queue')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
expect(find.text('播放队列'), findsOneWidget);
expect(find.text('3 首'), findsOneWidget);

await tester.tap(find.byKey(const Key('mobile-queue-track-b')));
await tester.pump();
expect(controller.state.current?.id, 'b');
expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
```

- [ ] **Step 2: Write failing removal event-isolation tests**

```dart
await tester.tap(
  find.byKey(const Key('player-mobile-queue-remove-c')),
);
await tester.pump();

expect(controller.state.queue.map((track) => track.id), ['a', 'b']);
expect(controller.state.current?.id, 'a');
expect(find.byKey(const Key('player-mobile-queue-sheet')), findsOneWidget);
```

Also remove the only track and assert both the Sheet and full player empty state close/appear as specified:

```dart
await tester.tap(
  find.byKey(const Key('player-mobile-queue-remove-a')),
);
await tester.pumpAndSettle();
expect(find.byKey(const Key('player-mobile-queue-sheet')), findsNothing);
expect(find.text('播放队列为空'), findsOneWidget);
```

- [ ] **Step 3: Write failing destructive-clear tests**

Open the Sheet, tap clear, assert the confirmation text “清空播放队列？” and “当前播放将停止，此操作无法撤销。”; cancel and verify the queue remains. Repeat, confirm, then verify `queue` is empty, `stopPlaybackCalls == 1`, and the Sheet closes.

- [ ] **Step 4: Write failing local-error tests**

Use `SnapshotAudio` or an observable fake whose `stopPlayback()` throws. Confirm clearing leaves the Sheet open, preserves the queue, and shows a local notice with title “无法清空队列” and a retry action; do not expose `StateError.toString()`.

- [ ] **Step 5: Run focused Sheet tests**

Run `flutter test test/features/player/player_screen_test.dart`.

Expected: FAIL because the mobile queue component and callbacks do not exist.

- [ ] **Step 6: Implement `MobileQueueSheet`**

Use this public boundary:

```dart
final class MobileQueueSheet extends StatefulWidget {
  const MobileQueueSheet({super.key, required this.controller});
  final PlayerController controller;

  @override
  State<MobileQueueSheet> createState() => _MobileQueueSheetState();
}

final class _MobileQueueSheetState extends State<MobileQueueSheet> {
  bool clearing = false;
  bool clearFailed = false;
}
```

Internally use `ListenableBuilder` and a single `CustomScrollView(primary: true)`. Render a pinned/non-scrolling header row followed by Sliver queue rows. A row must use:

```dart
Semantics(
  button: true,
  selected: active,
  label: active
      ? '${track.title}，${track.artist}，正在播放'
      : '${track.title}，${track.artist}',
  child: InkWell(
    key: Key('mobile-queue-track-${track.id}'),
    onTap: active ? null : () => controller.playIndex(index),
    child: Row(
      children: [
        if (active && state.processing == PlayerProcessing.loading)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (active)
          const Icon(LucideIcons.audioLines),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title.isEmpty ? track.id : track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(fontSize: 14),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.metadata.copyWith(
                  color: AppTokens.of(context).muted,
                ),
              ),
            ],
          ),
        ),
        ShadButton.ghost(
          key: Key('player-mobile-queue-remove-${track.id}'),
          width: 44,
          height: 44,
          onPressed: () async {
            final removed = await controller.removeAt(index);
            if (removed && controller.state.queue.isEmpty && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Icon(LucideIcons.x),
        ),
      ],
    ),
  ),
)
```

Use semantic tokens for active fill and dividers. Do not add artwork, cards, VIP badges, history tabs, or nested glass.

- [ ] **Step 7: Implement clear confirmation and local failure**

The header clear action must delegate to this state method:

```dart
Future<void> clearQueue() async {
  final confirmed = await showAppDestructiveDialog(
    context,
    title: '清空播放队列？',
    message: '当前播放将停止，此操作无法撤销。',
    cancelLabel: '取消',
    confirmLabel: '清空',
  );
  if (!confirmed || !mounted) return;
  setState(() {
    clearing = true;
    clearFailed = false;
  });
  final cleared = await widget.controller.clearQueue();
  if (!mounted) return;
  if (cleared) {
    Navigator.of(context).pop();
    return;
  }
  setState(() {
    clearing = false;
    clearFailed = true;
  });
}
```

When `clearFailed` is true, render this local row before the list:

```dart
Row(
  children: [
    const Expanded(
      child: AppNotice.error(
        title: '无法清空队列',
        message: '播放器未能停止，请重试。',
      ),
    ),
    const SizedBox(width: AppSpacing.xs),
    AppButton(
      onPressed: clearing ? null : clearQueue,
      child: const Text('重试'),
    ),
  ],
)
```

Disable clear while the queue is empty or `clearing` is true. When `state.error != null`, `clearFailed` is false, and the current track failed to start, show “当前歌曲暂时无法播放” with a “重试” button that calls `widget.controller.resume()`; never render the raw exception string.

- [ ] **Step 8: Open the component through draggable `showAppSheet`**

Replace `_queue()` with:

```dart
Future<void> _queue() => showAppSheet<void>(
  context,
  title: '播放队列',
  initialChildSize: .64,
  minChildSize: .48,
  maxChildSize: .90,
  child: MobileQueueSheet(controller: widget.controller),
);
```

- [ ] **Step 9: Run full player widget tests**

Run `flutter test test/features/player/player_screen_test.dart`.

Expected: PASS with no overflow or leaked exception.

- [ ] **Step 10: Inspect the scoped diff**

Run `git diff -- lib/features/player/mobile_queue_sheet.dart lib/features/player/player_screen.dart test/features/player/player_screen_test.dart`. Verify queue logic remains in the controller, not the widget. Leave changes uncommitted.

---

### Task 6: Visual verification and regression pass

**Files:**

- Modify: `test/visual/high_fidelity_gallery_test.dart:226-259`
- Modify: `test/visual/goldens/player-mobile-dark.png`
- Test without expected source changes: `test/visual/full_ui_gallery_test.dart`
- Modify: `test/visual/full_goldens/mobile-player-360x800.png`
- Modify: `test/visual/full_goldens/mobile-player-390x844.png`

**Interfaces:**

- Consumes: completed A controls and C Sheet.
- Produces: stable visual evidence at 360×800, 390×844, and narrow macOS runtime width.

- [ ] **Step 1: Update high-fidelity structural assertions before Golden generation**

Replace assertions for separate progress/transport glass islands with:

```dart
expect(find.byKey(const Key('player-mobile-controls')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-progress')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-transport')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-queue')), findsOneWidget);
expect(find.byKey(const Key('player-mobile-artwork')), findsOneWidget);
expect(tester.takeException(), isNull);
```

- [ ] **Step 2: Generate only affected Goldens**

Run:

```bash
flutter test --update-goldens test/visual/high_fidelity_gallery_test.dart --plain-name "player mobile dark"
flutter test --update-goldens test/visual/full_ui_gallery_test.dart
```

Only retain the two `mobile-player-*` full-gallery PNG changes from this command; discard no user files and do not regenerate or stage unrelated Goldens.

- [ ] **Step 3: Inspect generated images**

Open the affected PNG files and verify:

- one continuous bottom control surface;
- no nested glass;
- artwork/lyrics retain enough height;
- metadata, progress times, and all transport controls are visible;
- 360×800 and 390×844 have no clipping;
- accent remains limited to selection, progress, focus, and playing state.

If any criterion fails, adjust semantic spacing in the new mobile components and regenerate only the affected files.

- [ ] **Step 4: Run focused logical and visual suites**

Run:

```bash
flutter test test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/design/app_components_test.dart
flutter test test/visual/high_fidelity_gallery_test.dart test/visual/full_ui_gallery_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run static analysis**

Run `flutter analyze`.

Expected: `No issues found!`

- [ ] **Step 6: Build the macOS debug application**

Run `flutter build macos --debug`.

Expected: exit code 0 and a debug app under `build/macos/Build/Products/Debug/`.

- [ ] **Step 7: Perform runtime viewport validation on macOS**

Launch the macOS build against the configured Service, resize to approximately 390×844 and 360×800, then validate:

1. A control layer remains fully visible.
2. Artwork ↔ lyrics swipe works; a second left swipe does not reveal queue.
3. Queue opens as the C draggable Sheet at 64% and can resize between 48% and 90%.
4. Row selection, single removal, current removal, cancel clear, and confirm clear follow the spec.
5. System back and downward dismissal close the Sheet without stopping playback.

- [ ] **Step 8: Final diff and scope audit**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Review every changed path against this plan. Confirm there are no debug prints, unrelated generated files, raw theme colors, desktop layout changes, or accidental modifications to the user's existing redesign work. Leave all work uncommitted unless the user authorizes a commit.
