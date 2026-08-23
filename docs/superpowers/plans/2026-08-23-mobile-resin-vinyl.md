# Mobile Resin Vinyl Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the centered mobile full-cover record with the completed translucent resin vinyl while preserving the existing mobile size, playback-gated rotation, pause/resume angle, swipe navigation, and reduced-motion behavior.

**Architecture:** Parameterize the existing `DesktopOrbitVinyl` entry point with platform-specific structural keys so both desktop and mobile render one shared resin implementation. Keep `MobileVinylRecord` as a thin mobile-facing wrapper, pass the existing `ArtworkPalette` through the mobile player hierarchy, and avoid copying any painter or texture stack.

**Tech Stack:** Flutter, Dart, `CustomPainter`, `Image.asset`, `AnimationController`, widget tests, Android Pixel 8 emulator.

## Global Constraints

- Retain the mobile record diameter of 148–264 px and its centered page layout.
- Center artwork remains sharp, borderless, opaque, and approximately 60% of the record diameter.
- Rotation remains 18 seconds and occurs only on the artwork page while playback is active and processing is ready.
- Pausing preserves the current angle; resuming continues from that angle.
- Reduced-motion policy disables rotation; `accessibleNavigation` alone does not.
- Reuse the existing QQ-derived resin texture and groove highlight; do not duplicate the desktop painters or assets.
- Preserve unrelated dirty-worktree changes.
- Verify the final behavior in the real app on the existing `QingYu_API_35_Pixel_8_ARM64` emulator.

---

### Task 1: Share the Resin Vinyl Entry Point

**Files:**
- Modify: `lib/features/player/desktop_orbit_vinyl.dart`
- Test: `test/features/player/desktop_orbit_vinyl_test.dart`

**Interfaces:**
- Consumes: existing `DesktopOrbitVinyl` source, palette, seed, semantic label, and `rotating` inputs.
- Produces: optional `Key vinylKey`, `Key turnKey`, `Key artworkKey`, and `Key spindleKey` constructor parameters with current desktop keys as defaults.

- [ ] **Step 1: Establish desktop behavior**

Run:

```sh
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

Expected: the current focused desktop resin suite passes before the shared-key refactor.

- [ ] **Step 2: Parameterize only platform-specific structural keys**

Add constructor fields equivalent to:

```dart
this.vinylKey = const Key('player-desktop-orbit-vinyl'),
this.turnKey = const Key('player-desktop-orbit-turn'),
this.artworkKey = const Key('player-desktop-vinyl-artwork'),
this.spindleKey = const Key('player-desktop-vinyl-spindle'),
```

Use those fields at the existing root `SizedBox`, `RotationTransition`, center
`AppArtwork`, and spindle `Container`. Keep all resin material, asset, lighting,
palette, animation, and repaint behavior unchanged.

- [ ] **Step 3: Cover default and overridden keys**

Retain existing desktop assertions and add one widget case that supplies custom
keys and verifies they identify the actual root, rotation, artwork, and spindle
widgets. The test must also confirm the shared resin texture and groove asset
layers remain descendants of the custom rotation node.

- [ ] **Step 4: Verify the shared entry point**

Run:

```sh
flutter analyze lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

Expected: no analyzer issues and all desktop resin tests pass.

### Task 2: Replace the Mobile Record Surface

**Files:**
- Modify: `lib/features/player/mobile_vinyl_record.dart`
- Modify: `test/features/player/mobile_vinyl_record_test.dart`

**Interfaces:**
- Consumes: shared `DesktopOrbitVinyl`, `ArtworkPalette`, and existing mobile source, seed, semantic label, and `rotating` values.
- Produces: `MobileVinylRecord` with a required `ArtworkPalette palette` and preserved mobile root, turn, artwork, and spindle keys.

- [ ] **Step 1: Update mobile structural expectations**

Change the focused test harness to provide a deterministic `ArtworkPalette`.
Update the structure test to expect a 240 px record with a 144 px opaque center
artwork, the two resin assets, both circular clips, and the existing mobile
semantic label and structural keys.

- [ ] **Step 2: Replace the legacy mobile painter with the shared resin**

Reduce `MobileVinylRecord` to a thin stateless wrapper equivalent to:

```dart
DesktopOrbitVinyl(
  vinylKey: const Key('player-mobile-vinyl'),
  turnKey: const Key('player-mobile-vinyl-turn'),
  artworkKey: const Key('player-mobile-vinyl-artwork'),
  spindleKey: const Key('player-mobile-vinyl-spindle'),
  source: source,
  palette: palette,
  seed: seed,
  semanticLabel: semanticLabel,
  rotating: rotating,
)
```

Remove the obsolete mobile-only animation controller, full-cover artwork stack,
and `_VinylGroovesPainter`. Do not add another animation controller.

- [ ] **Step 3: Preserve motion regression coverage**

Keep and pass tests proving rotation advances while `rotating` is true, stops
at the current angle while false, resumes from that angle, stops for reduced
motion, and continues when only `accessibleNavigation` is enabled.

- [ ] **Step 4: Verify the mobile component**

Run:

```sh
flutter analyze lib/features/player/mobile_vinyl_record.dart test/features/player/mobile_vinyl_record_test.dart
flutter test test/features/player/mobile_vinyl_record_test.dart
```

Expected: no analyzer issues and all focused mobile vinyl tests pass.

### Task 3: Deliver the Artwork Palette to Mobile

**Files:**
- Modify: `lib/features/player/player_screen.dart`
- Modify: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: the `ArtworkPalette` already produced by `ArtworkPaletteController`.
- Produces: required `ArtworkPalette palette` parameters on `_MobilePlayer` and `_MobileNowPlaying`, passed unchanged into `MobileVinylRecord`.

- [ ] **Step 1: Select the palette for both layout classes**

Call `_selectPalette(artworkSource, brightness)` for mobile and desktop. Preserve
the existing desktop-only `_reportAccent` behavior unless a mobile consumer
already requires it.

- [ ] **Step 2: Thread the palette through the private mobile widgets**

Add `palette` to `_MobilePlayer` and `_MobileNowPlaying`, then construct the
mobile record with:

```dart
MobileVinylRecord(
  source: artworkSource,
  palette: palette,
  seed: '${track.source}:${track.id}',
  semanticLabel: '${track.title}封面',
  rotating: rotating,
)
```

- [ ] **Step 3: Add mobile integration coverage**

In the mobile player widget test, inject an `ArtworkPaletteController` backed
by the existing deterministic fake decoder pattern and verify
`PressedVinylPainter.baseColor` matches the selected `vinylAccent`. Also verify
the existing `rotating` condition still depends on
artwork view, active playback, and ready processing rather than becoming
unconditional.

- [ ] **Step 4: Verify the player integration**

Run:

```sh
flutter analyze lib/features/player/player_screen.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: no analyzer issues and the player screen suite passes, including the
new mobile palette assertion and existing desktop layout assertions.

### Task 4: Align Documentation and Run Final Automated Checks

**Files:**
- Modify: `design.md`
- Verify: all production and test files changed by Tasks 1–3

**Interfaces:**
- Consumes: the completed shared mobile/desktop resin behavior.
- Produces: design documentation that no longer prohibits mobile from using the pressed resin material.

- [ ] **Step 1: Update the immersive-player mobile rule**

Replace the old statement that mobile does not inherit the desktop pressed
material or Ambilight. State that mobile reuses the shared translucent resin
material, artwork palette, continuous texture, circular masks, and fixed light
layers while preserving its centered sizing and playback-gated rotation.

- [ ] **Step 2: Run the focused integration gate**

Run:

```sh
dart format lib/features/player/desktop_orbit_vinyl.dart lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/desktop_orbit_vinyl_test.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
flutter analyze lib/features/player/desktop_orbit_vinyl.dart lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/desktop_orbit_vinyl_test.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart test/features/player/mobile_vinyl_record_test.dart
flutter test test/features/player/player_screen_test.dart
git diff --check -- design.md lib/features/player/desktop_orbit_vinyl.dart lib/features/player/mobile_vinyl_record.dart lib/features/player/player_screen.dart test/features/player/desktop_orbit_vinyl_test.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/player_screen_test.dart
```

Expected: formatting is stable, analyzer reports no issues, all focused tests
pass, and the scoped diff contains no whitespace errors.

### Task 5: Validate the Real Android Application

**Files:**
- No source changes expected.
- Inspect: final Android runtime rendered from the frozen worktree.

**Interfaces:**
- Consumes: the final verified Flutter tree and `QingYu_API_35_Pixel_8_ARM64` emulator.
- Produces: runtime evidence for the real mobile player.

- [ ] **Step 1: Launch the existing Android emulator**

Run:

```sh
flutter emulators --launch QingYu_API_35_Pixel_8_ARM64
flutter devices
```

Expected: the Pixel 8 emulator appears as an Android device.

- [ ] **Step 2: Build and start the actual application**

Run:

```sh
flutter run -d emulator-5554
```

If Android assigns a different emulator port, use the exact Android device ID
reported by Step 1; this is a non-behavioral environment substitution. Wait for
the application to finish installing and reach its interactive UI; do not
substitute a simulated painter test.

- [ ] **Step 3: Inspect mobile behavior**

Open the full mobile player and inspect blue, dark, and warm covers. Confirm:

- centered record remains within the existing mobile size;
- center artwork is opaque and approximately 60% of the record;
- resin color follows each cover and the continuous texture has no square edge;
- the record rotates during ready playback;
- pause freezes the current angle and resume continues from it;
- swiping to lyrics preserves the existing page behavior.

- [ ] **Step 4: Freeze and report final evidence**

After runtime inspection, do not edit product code without invalidating the
affected automated and runtime evidence. Record build status, test counts,
device used, visual observations, and any unverified boundary in the final
review.
