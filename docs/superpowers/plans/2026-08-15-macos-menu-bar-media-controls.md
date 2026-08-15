# macOS Menu Bar Media Controls Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native macOS `NSStatusItem` that shows TuneFlow playback controls and keeps the app resident after its last window closes, while reusing the existing Dart player and `audio_service` media-key path.

**Architecture:** A Dart coordinator owns the menu-bar state, favorite state, and command routing. A narrow MethodChannel port sends immutable snapshots to a Swift `NSStatusItem` controller and receives semantic commands; Swift owns only AppKit presentation and application/window lifecycle. Existing `PlayerController`, `PlaylistRepository`, and `ServiceAudioHandler` remain the authoritative business and playback layers.

**Tech Stack:** Flutter 3.47/Dart 3.9, Riverpod 3, MethodChannel, AppKit (`NSStatusItem`, `NSStackView`, `NSMenu`), XCTest, Flutter test.

## Global Constraints

- Phase one supports macOS only; Windows media controls and Linux MPRIS are out of scope.
- Search for a suitable plugin before native work; `system_tray`, `tray_manager`, and `mac_menu_bar` were evaluated and do not expose the required multi-button custom status-item view.
- Do not add a tray, hotkey, or icon dependency.
- Flutter remains the only playback state source; Swift must not call `just_audio` directly.
- Hardware media keys continue through the existing `audio_service` `MPRemoteCommandCenter` bridge; do not register a second global media-key listener.
- Favorite maps to the built-in playlist id `love` and matches tracks by `source + id`.
- Closing the final window keeps the process, Flutter engine, audio, Dock icon, and status item alive; only `Command-Q` or “退出 TuneFlow” terminates the app.
- Full layout is used at widths of at least 1440 points with a 160-point maximum title; narrower screens use compact layout, and an invisible item retries in icon-only layout.
- Native transport artwork must preserve the existing Material Rounded family and native favorite artwork the existing Lucide family. Add no third icon family; document the native-asset boundary in `design.md`.
- Preserve all unrelated dirty-worktree changes. Do not commit, stage, or discard files unless the user separately authorizes it.

## File Map

- Create `lib/platform/macos_menu_bar.dart`: channel protocol, immutable snapshot, command enum, active and no-op ports.
- Create `lib/platform/macos_menu_bar_coordinator.dart`: player/favorite synchronization, stale-request protection, command serialization.
- Create `lib/app/app_message_center.dart`: queue menu-bar operation failures until the Flutter window becomes active.
- Modify `lib/app/app_providers.dart`: injectable menu-bar and pending-message ports.
- Modify `lib/app/runtime_providers.dart`: macOS coordinator provider and `PlaylistRepository` adapter wiring.
- Modify `lib/app/app.dart`: activate the coordinator and render queued errors through the existing Shad toast surface.
- Create `macos/Runner/MacOSMenuBarController.swift`: AppKit status item, layouts, context menu, MethodChannel bridge, window restore, termination.
- Modify `macos/Runner/MainFlutterWindow.swift`: attach the native controller to the Flutter engine and existing main window.
- Modify `macos/Runner/AppDelegate.swift`: menu-bar residency and activation notification.
- Add `macos/Runner/Assets.xcassets/MenuBar*.imageset`: template artwork for TuneFlow, transport, and favorite states.
- Modify `macos/Runner.xcodeproj/project.pbxproj`: include the Swift controller in Runner sources.
- Modify `design.md`: record the native status-item icon exception and exact family mapping.
- Create `test/platform/macos_menu_bar_test.dart`: protocol and channel tests.
- Create `test/platform/macos_menu_bar_coordinator_test.dart`: snapshot, routing, favorite, race, and failure tests.
- Create `test/app/app_message_center_test.dart`: queued-message activation behavior.
- Modify `test/app/app_shell_test.dart`: provider activation remains harmless on non-macOS widget tests.
- Replace `macos/RunnerTests/RunnerTests.swift`: AppKit model/controller tests.
- Modify `test/features/player/service_audio_handler_test.dart`: media-control callback coverage.

---

### Task 1: Define and test the Dart/native protocol

**Files:**
- Create: `lib/platform/macos_menu_bar.dart`
- Create: `test/platform/macos_menu_bar_test.dart`

**Interfaces:**
- Produces: `MacOSMenuBarCommand`, `MacOSMenuBarSnapshot`, `MacOSMenuBarPort`, `MethodChannelMacOSMenuBarPort`, and `InactiveMacOSMenuBarPort`.
- Channel name: `com.musicfree.serviceclient/macos_menu_bar`.
- Dart-to-Swift methods: `initialize`, `updateState`, `showWindow`, `terminate`, `dispose`.
- Swift-to-Dart callback: `command` with one of `previous`, `playPause`, `next`, `toggleFavorite`, `showWindow`, `quit`, `applicationActivated`.

- [ ] **Step 1: Write failing serialization and channel tests**

Add tests that assert the exact primitive map sent to Swift and command parsing behavior:

```dart
const snapshot = MacOSMenuBarSnapshot(
  trackId: '42',
  source: 'wy',
  title: '夜曲',
  artist: '周杰伦',
  playing: true,
  loading: false,
  canPlayPause: true,
  canGoPrevious: false,
  canGoNext: true,
  favorite: true,
  favoritePending: false,
  canToggleFavorite: true,
);
expect(snapshot.toMap(), {
  'trackId': '42',
  'source': 'wy',
  'title': '夜曲',
  'artist': '周杰伦',
  'playing': true,
  'loading': false,
  'canPlayPause': true,
  'canGoPrevious': false,
  'canGoNext': true,
  'favorite': true,
  'favoritePending': false,
  'canToggleFavorite': true,
});
```

Use `TestDefaultBinaryMessengerBinding` to assert `initialize` and `updateState` calls, then simulate `command('playPause')` and assert the typed stream emits `MacOSMenuBarCommand.playPause`. Assert an unknown command is ignored and reported with `FlutterError.reportError`, not added to the stream.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `flutter test test/platform/macos_menu_bar_test.dart`

Expected: FAIL because the protocol types do not exist.

- [ ] **Step 3: Implement the protocol and ports**

Define the snapshot as an immutable value with `idle`, `toMap`, `==`, and `hashCode`. Define the port as:

```dart
abstract interface class MacOSMenuBarPort {
  Stream<MacOSMenuBarCommand> get commands;
  Future<void> initialize();
  Future<void> updateState(MacOSMenuBarSnapshot state);
  Future<void> showWindow();
  Future<void> terminate();
  Future<void> dispose();
}
```

`MethodChannelMacOSMenuBarPort` owns a broadcast `StreamController`, installs one method-call handler in `initialize`, and clears it plus closes the stream in `dispose`. `InactiveMacOSMenuBarPort` exposes an empty stream and completes every method without platform calls.

- [ ] **Step 4: Run and format the focused files**

Run:

```sh
dart format lib/platform/macos_menu_bar.dart test/platform/macos_menu_bar_test.dart
flutter test test/platform/macos_menu_bar_test.dart
```

Expected: PASS.

### Task 2: Coordinate player state, commands, and favorites

**Files:**
- Create: `lib/platform/macos_menu_bar_coordinator.dart`
- Create: `test/platform/macos_menu_bar_coordinator_test.dart`

**Interfaces:**
- Consumes: `MacOSMenuBarPort` and `MacOSMenuBarSnapshot` from Task 1; `PlayerController`; `Track`; `PlaylistRepository` methods `get`, `addTracks`, and `removeTracks`.
- Produces: `FavoritePlaylistPort`, `LovePlaylistFavorites`, `MacOSMenuBarCoordinator.start()`, and `MacOSMenuBarCoordinator.dispose()`.

- [ ] **Step 1: Write failing snapshot synchronization tests**

Use the existing fake player/audio patterns from `test/features/player/player_controller_test.dart`. Add a fake menu-bar port that records states. Assert:

- no player publishes `MacOSMenuBarSnapshot.idle`;
- a current track publishes its exact `trackId` and `source`;
- queue index zero disables previous and the final index disables next;
- loading/buffering sets `loading` and disables play/pause;
- position-only snapshots do not produce a second identical menu-bar state.

- [ ] **Step 2: Write failing command-routing tests**

Emit each command through the fake port and assert it calls the exact player method. `playPause` calls `pause` while playing and `resume` while paused. Commands are processed through one future chain so rapid duplicate input cannot overlap. `showWindow` calls `port.showWindow`; `quit` calls `port.terminate`; `applicationActivated` invokes an injected `revealPendingMessages` callback.

- [ ] **Step 3: Write failing favorite and race tests**

Define the adapter boundary:

```dart
abstract interface class FavoritePlaylistPort {
  Future<bool> contains(Track track);
  Future<void> setFavorite(Track track, bool favorite);
}
```

Test `LovePlaylistFavorites` uses `get('love')`, matches both `source` and `id`, adds with `addTracks('love', [track])`, and removes with `removeTracks('love', [track.id])`. Test optimistic state, `favoritePending`, failure rollback, duplicate-click suppression, and a delayed old-track query that completes after a new track is selected.

- [ ] **Step 4: Run the coordinator tests and confirm failure**

Run: `flutter test test/platform/macos_menu_bar_coordinator_test.dart`

Expected: FAIL because the coordinator and favorite adapter do not exist.

- [ ] **Step 5: Implement the minimal coordinator**

The coordinator constructor is:

```dart
MacOSMenuBarCoordinator({
  required PlayerController? player,
  required FavoritePlaylistPort? favorites,
  required MacOSMenuBarPort menuBar,
  required void Function(String title, String message) reportFailure,
  required VoidCallback revealPendingMessages,
})
```

`start` initializes the port, subscribes to commands, adds a player listener, publishes the initial state, and starts a favorite lookup for the current `${track.source}:${track.id}` identity. Track a monotonically increasing lookup generation and discard results whose generation or track identity no longer matches. On favorite failure, restore the previous value and call `reportFailure('收藏失败', appErrorMessage(error, fallback: '操作未完成，请稍后重试。'))`.

- [ ] **Step 6: Run, format, and analyze the coordinator**

Run:

```sh
dart format lib/platform/macos_menu_bar_coordinator.dart test/platform/macos_menu_bar_coordinator_test.dart
flutter test test/platform/macos_menu_bar_coordinator_test.dart
flutter analyze lib/platform/macos_menu_bar.dart lib/platform/macos_menu_bar_coordinator.dart
```

Expected: tests PASS and analysis reports no issues.

### Task 3: Wire Riverpod and queue hidden-window failures

**Files:**
- Create: `lib/app/app_message_center.dart`
- Create: `test/app/app_message_center_test.dart`
- Modify: `lib/app/app_providers.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: coordinator and port types from Tasks 1-2; `connectionProvider`; `playerControllerProvider`; `PlaylistRepository`; `showAppMessage`.
- Produces: `AppMessageCenter.enqueue`, `AppMessageCenter.revealPending`, `macOSMenuBarPortProvider`, and `macOSMenuBarCoordinatorProvider`.

- [ ] **Step 1: Write failing pending-message tests**

Test that `AppMessageCenter.enqueue(title, message)` stores messages without notifying the UI, `revealPending()` emits queued messages in insertion order exactly once, and messages enqueued after reveal are emitted immediately until `hide()` is called.

- [ ] **Step 2: Implement `AppMessageCenter`**

Use a broadcast stream of immutable `AppMessage` records and an internal FIFO. Expose `messages`, `enqueue`, `revealPending`, `hide`, and `dispose`. Do not retain `BuildContext` in the controller.

- [ ] **Step 3: Write failing provider and widget-host tests**

Override `macOSMenuBarPortProvider` with a fake. Pump `MusicFreeServiceApp`, verify non-macOS tests receive `InactiveMacOSMenuBarPort`, and verify one queued destructive message is shown only after `revealPending` emits it. Ensure rebuilding `_AppView` does not create a second coordinator subscription.

- [ ] **Step 4: Wire providers and the app host**

In `app_providers.dart`, provide an inactive port by default so widget/unit tests never invoke a native channel. In `runtime_providers.dart`, enable the active MethodChannel port only when `defaultTargetPlatform == TargetPlatform.macOS` and create `LovePlaylistFavorites(PlaylistRepository(connected.api))` when connected. Dispose the coordinator through `ref.onDispose`.

In `_AppView`, watch `macOSMenuBarCoordinatorProvider` to activate it. Add a small stateful `_AppMessageHost` below `ShadAppBuilder`; subscribe to `AppMessageCenter.messages` and call existing `showAppMessage(context, title:, message:, destructive: true)` after the current frame.

- [ ] **Step 5: Run the focused app tests**

Run:

```sh
dart format lib/app/app_message_center.dart lib/app/app_providers.dart lib/app/runtime_providers.dart lib/app/app.dart test/app/app_message_center_test.dart test/app/app_shell_test.dart
flutter test test/app/app_message_center_test.dart test/app/app_shell_test.dart test/platform/macos_menu_bar_coordinator_test.dart
```

Expected: PASS with no missing plugin exceptions.

### Task 4: Build the native AppKit status item and lifecycle bridge

**Files:**
- Create: `macos/Runner/MacOSMenuBarController.swift`
- Modify: `macos/Runner/MainFlutterWindow.swift`
- Modify: `macos/Runner/AppDelegate.swift`
- Modify: `macos/Runner.xcodeproj/project.pbxproj`
- Replace: `macos/RunnerTests/RunnerTests.swift`

**Interfaces:**
- Consumes: channel contract from Task 1 and template image names from Task 5.
- Produces: `MacOSMenuBarState`, `MacOSMenuBarLayoutMode`, and singleton `MacOSMenuBarController.shared` with `attach(binaryMessenger:window:)` and `applicationDidBecomeActive()`.

- [ ] **Step 1: Write failing Swift model/layout tests**

Replace the placeholder Runner test with `@testable import TuneFlow` tests for:

```swift
XCTAssertEqual(MacOSMenuBarLayoutMode(screenWidth: 1439), .compact)
XCTAssertEqual(MacOSMenuBarLayoutMode(screenWidth: 1440), .full)
```

Decode an idle and populated `[String: Any]` snapshot; assert malformed required booleans are rejected without replacing the last valid state. Assert the full model exposes all six surfaces, compact exposes app plus play/pause, and icon-only exposes only the app icon.

- [ ] **Step 2: Add the controller to the Xcode project and confirm test failure**

Add `MacOSMenuBarController.swift` to the Runner group and Runner Sources build phase, then run:

```sh
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'
```

Expected: FAIL because the native types do not exist.

- [ ] **Step 3: Implement snapshot decoding and deterministic layout**

Create a value-type `MacOSMenuBarState` with the exact Task 1 keys and an `idle` value. Create `MacOSMenuBarLayoutMode.full`, `.compact`, and `.iconOnly`; choose full for `NSScreen.main?.frame.width >= 1440`, otherwise compact. Apply a 160-point maximum width with tail truncation to the title field.

- [ ] **Step 4: Implement the status item UI and context menu**

Create one variable-length item and host a horizontal `NSStackView` in its button area. Configure template images, button targets, `toolTip`, and `setAccessibilityLabel` values in Chinese. Rebuild only when layout mode changes; ordinary snapshots update labels, images, and enabled states in place.

Right-click presents an `NSMenu` containing the current track label, previous, play/pause, next, favorite, separator, “显示 TuneFlow”, and “退出 TuneFlow”. Left-click on the app icon/title sends `showWindow`. Button clicks send semantic commands through `channel.invokeMethod("command", arguments: command)`.

After applying layout, check `statusItem.isVisible` on the next main-loop turn. If false and the current mode is not icon-only, switch once to icon-only and recompute `statusItem.length`; avoid an infinite retry loop.

- [ ] **Step 5: Implement the MethodChannel and window/application lifecycle**

Handle `initialize`, `updateState`, `showWindow`, `terminate`, and `dispose`. `showWindow` calls `window.makeKeyAndOrderFront(nil)` and `NSApp.activate(ignoringOtherApps: true)`. `terminate` calls `NSApp.terminate(nil)` only after returning success to Dart on the next main-loop turn.

In `MainFlutterWindow.awakeFromNib`, attach the singleton after `RegisterGeneratedPlugins`. In `AppDelegate`, return `false` from `applicationShouldTerminateAfterLastWindowClosed` and forward `applicationDidBecomeActive` to the controller so Dart can reveal queued failures. Keep `applicationSupportsSecureRestorableState` unchanged.

- [ ] **Step 6: Run native tests**

Run:

```sh
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'
```

Expected: PASS, including decoding, layout threshold, enabled-state, semantic-command, restore-window, and termination-path tests. Use injected command/window/termination closures so tests do not terminate the runner.

### Task 5: Add menu-bar artwork and document the icon boundary

**Files:**
- Create: `macos/Runner/Assets.xcassets/MenuBarTuneFlow.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarPrevious.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarPlay.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarPause.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarNext.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarHeart.imageset/Contents.json`
- Create: `macos/Runner/Assets.xcassets/MenuBarHeartFilled.imageset/Contents.json`
- Create: matching single-scale vector PDF files in each imageset.
- Modify: `design.md`

**Interfaces:**
- Consumes: native image names referenced by Task 4.
- Produces: monochrome template images loadable through `NSImage(named:)`.

- [ ] **Step 1: Export and add exact-family vector assets**

Export previous, play, pause, and next from the same Material Rounded glyphs represented by `AppPlaybackIcons`; export heart and filled-heart from the Lucide heart geometry; derive the TuneFlow mark from `assets/branding/TuneFlow.png`. Use monochrome vector PDFs with transparent backgrounds and set each image set to a single universal scale with `preserves-vector-representation: true`.

Set `image.isTemplate = true` in Swift so macOS supplies the correct menu-bar foreground for light, dark, increased-contrast, hover, disabled, and selected appearances. Do not bake the app theme colors into these assets.

- [ ] **Step 2: Record the native boundary in `design.md`**

Add a narrow exception stating that AppKit surfaces cannot consume Flutter `IconData`; native status-item transport assets must be exported from the Material Rounded transport family and ordinary assets from Lucide, with semantic names matching `previous`, `play`, `pause`, `next`, and `favorite`. Explicitly forbid SF Symbols or raw Material glyph selection at feature call sites.

- [ ] **Step 3: Validate asset loading and icon policy**

Add a Swift test that loads every named `NSImage` and asserts `isTemplate == true` after controller configuration. Run:

```sh
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: XCTest PASS; first `rg` returns no matches; second returns matches only in `lib/design/components/app_playback_button.dart`.

### Task 6: Prove media keys, integrate, and run the frozen verification pass

**Files:**
- Modify: `test/features/player/service_audio_handler_test.dart`
- Modify only if a test exposes a defect: `lib/features/player/service_audio_handler.dart`

**Interfaces:**
- Consumes: existing `ServiceAudioHandler.bindQueueCallbacks`, `skipToPrevious`, `skipToNext`, `play`, `pause`, and playback-state publication.
- Produces: regression evidence that `audio_service` remains the only macOS media-key path.

- [ ] **Step 1: Add focused handler regression tests**

Bind counters through `bindQueueCallbacks`, call `skipToPrevious` and `skipToNext`, and assert each callback fires once. Assert a published playing state contains previous, pause, and next controls; a paused state contains previous, play, and next. Keep the test at the handler boundary—do not simulate global keyboard events in Flutter.

- [ ] **Step 2: Run the focused Dart and native suites**

Run:

```sh
flutter test test/platform/macos_menu_bar_test.dart test/platform/macos_menu_bar_coordinator_test.dart test/app/app_message_center_test.dart test/features/player/service_audio_handler_test.dart test/features/player/player_controller_test.dart
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS'
```

Expected: all tests PASS.

- [ ] **Step 3: Run static and build verification**

Run:

```sh
flutter analyze lib/platform/macos_menu_bar.dart lib/platform/macos_menu_bar_coordinator.dart lib/app/app_message_center.dart lib/app/app.dart lib/app/app_providers.dart lib/app/runtime_providers.dart
flutter build macos --debug
git diff --check
```

Expected: analysis and build succeed; `git diff --check` prints nothing.

- [ ] **Step 4: Perform real macOS acceptance checks**

Launch the debug app in a graphical macOS session and verify:

1. No track: one TuneFlow status icon; playback and favorite items disabled.
2. Active track: correct title, previous/play-or-pause/next/favorite state, and no duplicate update flicker.
3. Hardware play/pause, previous, and next keys each trigger exactly one player action; Control Center state stays synchronized.
4. Left-click icon/title restores the existing window; no duplicate window appears.
5. Right-click exposes all commands; compact and icon-only layouts retain the same menu commands.
6. Closing the final window leaves playback and the status item alive; Dock click restores the window.
7. Favorite success updates immediately; forced request failure rolls back and appears as a toast after the window becomes active.
8. `Command-Q` and “退出 TuneFlow” terminate cleanly.

- [ ] **Step 5: Freeze and report the verified tree**

Record `git status --short`, the exact test/build commands, and their outcomes. Do not stage or commit the implementation without separate user authorization. Report any acceptance item that could not be exercised and the resulting residual risk.
