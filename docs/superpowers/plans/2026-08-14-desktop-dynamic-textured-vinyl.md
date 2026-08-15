# Desktop Dynamic Textured Vinyl Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the desktop player's fixed black left-side vinyl portal with a right-top cropped record whose center is the current song artwork and whose textured translucent outer vinyl and backdrop are generated locally from that artwork.

**Architecture:** Keep palette state out of the playback domain. A deterministic extractor converts cached artwork bytes into an immutable semantic palette, and a small controller owns async selection, stale-result protection, fallback, and an in-memory LRU. The desktop backdrop and a new textured record consume the palette; the existing mobile `VinylRecord`, playback controller, lyrics, controls, and cache ownership remain unchanged.

**Tech Stack:** Flutter/Dart, `dart:ui` image decoding, existing `cached_network_image_ce` cache manager, `CustomPainter`, `ShaderMask`/ring clipping, Flutter widget and golden tests.

## Global Constraints

- The center circular area must display the current song's original `AppArtwork`; only circular clipping and `BoxFit.cover` are permitted.
- The outer record must combine a translucent palette-derived base, a low-opacity refracted copy of the artwork, concentric grooves, and fixed highlights; it must not degrade to a flat solid disc.
- The center artwork, outer material, inner ring, and spindle must share one `RotationTransition` and one preserved rotation angle.
- Palette extraction is local-only, uses a maximum `24×24` sample, does not upload artwork, does not issue a second bare HTTP request, and does not block the first frame.
- Normal color transitions last 450–650ms; reduced-motion transitions last no more than 150ms and continuous rotation is disabled.
- Desktop layouts at 1024×768 and 1440×960 must keep lyrics and bottom controls reachable; mobile player visuals and behavior must remain unchanged.
- Preserve all unrelated dirty-worktree changes. Do not delete the existing untracked portal implementation or commit/stage files without explicit user authorization.
- Add no new runtime dependency; implement deterministic sampling with Flutter/Dart and the existing cache manager.

---

## File Structure

**Create**

- `lib/features/player/artwork_palette.dart` — immutable semantic palette, contrast helpers, and deterministic fallback palette.
- `lib/features/player/artwork_palette_extractor.dart` — encoded-image downsampling and deterministic HSB/luminance bucket selection.
- `lib/features/player/artwork_palette_controller.dart` — cache-backed byte loading, LRU reuse, stale-result protection, and presentation state.
- `lib/features/player/desktop_dynamic_player_backdrop.dart` — palette-driven desktop-only background gradients and transitions.
- `lib/features/player/desktop_orbit_vinyl.dart` — right-top textured record with the original artwork at its center.
- `test/features/player/artwork_palette_extractor_test.dart` — pure palette and fallback coverage.
- `test/features/player/artwork_palette_controller_test.dart` — LRU, cache loading, failure, and rapid-switch coverage.
- `test/features/player/desktop_dynamic_player_backdrop_test.dart` — desktop gradient, duration, and semantics coverage.
- `test/features/player/desktop_orbit_vinyl_test.dart` — layer structure, semantics, and shared rotation coverage.

**Modify**

- `lib/features/player/player_screen.dart` — own the presentation-only palette controller and route one palette to desktop backdrop and stage.
- `lib/features/player/desktop_player_stage.dart` — implement the right-top Orbit Crop composition and use `DesktopOrbitVinyl`.
- `test/features/player/player_screen_test.dart` — update desktop structure/layout assertions and add stale-palette integration coverage.
- `test/visual/high_fidelity_fixtures.dart` — ensure desktop player fixtures exercise warm/cool artwork-driven palettes.
- `test/visual/full_ui_gallery_test.dart` — inject deterministic palette inputs for stable desktop screenshots.
- `test/visual/full_goldens/desktop-player-1024x768-light.png`
- `test/visual/full_goldens/desktop-player-1024x768.png`
- `test/visual/full_goldens/desktop-player-1440x960-light.png`
- `test/visual/full_goldens/desktop-player-1440x960.png`

The existing `desktop_vinyl_portal.dart`, `desktop_vinyl_record.dart`, and their tests remain untouched because they are untracked user work. Production code simply stops routing through them.

---

### Task 1: Deterministic Artwork Palette Model and Extractor

**Files:**
- Create: `lib/features/player/artwork_palette.dart`
- Create: `lib/features/player/artwork_palette_extractor.dart`
- Create: `test/features/player/artwork_palette_extractor_test.dart`

**Interfaces:**
- Produces:
  - `ArtworkPalette({required Color backgroundBase, required Color backgroundCompanion, required Color vinylAccent, required Color foreground})`
  - `ArtworkPalette fallbackArtworkPalette(String seed, {required Brightness brightness})`
  - `double contrastRatio(Color first, Color second)`
  - `abstract interface class ArtworkPaletteDecoding` with the same `extract` signature as the concrete extractor
  - `ArtworkPaletteExtractor.extract(Uint8List encodedBytes, {required String fallbackSeed, required Brightness brightness})`
  - `ArtworkPaletteExtractor.extractRgba(Uint8List rgba, {required int width, required int height, required String fallbackSeed, required Brightness brightness})`

- [ ] **Step 1: Write failing pure-color tests**

Create table-driven tests that feed deterministic RGBA buffers without file I/O:

```dart
test('warm artwork keeps a warm vinyl accent and readable foreground', () {
  final palette = const ArtworkPaletteExtractor().extractRgba(
    rgbaPixels(const [
      Color(0xFFE67E3A),
      Color(0xFFF2C5A8),
      Color(0xFF2A6C72),
    ]),
    width: 3,
    height: 1,
    fallbackSeed: 'warm',
    brightness: Brightness.light,
  );

  expect(HSVColor.fromColor(palette.vinylAccent).saturation, greaterThan(.45));
  expect(
    contrastRatio(palette.foreground, palette.backgroundBase),
    greaterThanOrEqualTo(4.5),
  );
});
```

Define the test helper in the same file so every referenced byte buffer is concrete:

```dart
Uint8List rgbaPixels(List<Color> colors) => Uint8List.fromList([
  for (final color in colors)
    ...[
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
      (color.a * 255).round(),
    ],
]);
```

Add cases for cool, grayscale, near-black, near-white, transparent, and single-color buffers. Assert deterministic equality for identical inputs and hue/brightness separation between background roles.

- [ ] **Step 2: Run the extractor test and confirm the intended failure**

Run:

```bash
flutter test test/features/player/artwork_palette_extractor_test.dart
```

Expected: compilation fails because `ArtworkPaletteExtractor`, `ArtworkPalette`, and `contrastRatio` do not exist.

- [ ] **Step 3: Implement the immutable palette and fallback**

Implement `ArtworkPalette` with value equality and a `lerp` helper used by animated UI:

```dart
@immutable
final class ArtworkPalette {
  const ArtworkPalette({
    required this.backgroundBase,
    required this.backgroundCompanion,
    required this.vinylAccent,
    required this.foreground,
  });

  final Color backgroundBase;
  final Color backgroundCompanion;
  final Color vinylAccent;
  final Color foreground;

  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) =>
      ArtworkPalette(
        backgroundBase: Color.lerp(a.backgroundBase, b.backgroundBase, t)!,
        backgroundCompanion:
            Color.lerp(a.backgroundCompanion, b.backgroundCompanion, t)!,
        vinylAccent: Color.lerp(a.vinylAccent, b.vinylAccent, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
      );
}
```

Define the decoder boundary in `artwork_palette_extractor.dart` and make the
production extractor implement it so controller tests can inject deterministic
results without manufacturing PNG files:

```dart
abstract interface class ArtworkPaletteDecoding {
  Future<ArtworkPalette> extract(
    Uint8List encodedBytes, {
    required String fallbackSeed,
    required Brightness brightness,
  });
}
```

Declare `ArtworkPaletteExtractor implements ArtworkPaletteDecoding`; Steps 4
and 5 provide its complete pixel and encoded-image implementations.

Generate fallback hue from a stable UTF-16 hash of `seed`; use theme-appropriate lightness and verify foreground contrast before returning.

- [ ] **Step 4: Implement deterministic sampling**

In `extractRgba`, ignore pixels with alpha below 128; compute HSV plus WCAG relative luminance; bucket hue into 24 bins and brightness into 4 bins. Weight each sample by:

```dart
final chromaWeight = .25 + saturation * .75;
final middleLightWeight = 1 - ((luminance - .5).abs() * 1.2).clamp(0, .72);
final weight = chromaWeight * middleLightWeight;
```

Select the dominant stable bucket for `backgroundBase`, the best separated real bucket for `backgroundCompanion`, and the highest representative chroma bucket for `vinylAccent`. If separation is insufficient, derive a weak complement from the dominant hue. Normalize light-theme backgrounds to HSV value `.86...96` and saturation `.08...30`; normalize dark-theme backgrounds to value `.10...22` and saturation `.12...38`; normalize vinyl to saturation `.48...82` and value `.52...88`. Choose black or white foreground by the higher contrast ratio.

- [ ] **Step 5: Implement encoded-image decoding at 24×24 maximum**

Use `ui.ImmutableBuffer.fromUint8List`, `ui.ImageDescriptor.encoded`, and `instantiateCodec(targetWidth: ..., targetHeight: ...)`. Read `ImageByteFormat.rawRgba`, forward to `extractRgba`, and dispose the image, codec, descriptor, and buffer in `finally` blocks. Any decode error returns `fallbackArtworkPalette(fallbackSeed, brightness: brightness)`.

- [ ] **Step 6: Run focused tests and static checks**

Run:

```bash
dart format lib/features/player/artwork_palette.dart lib/features/player/artwork_palette_extractor.dart test/features/player/artwork_palette_extractor_test.dart
flutter test test/features/player/artwork_palette_extractor_test.dart
flutter analyze lib/features/player/artwork_palette.dart lib/features/player/artwork_palette_extractor.dart test/features/player/artwork_palette_extractor_test.dart
git diff --check -- lib/features/player/artwork_palette.dart lib/features/player/artwork_palette_extractor.dart test/features/player/artwork_palette_extractor_test.dart
```

Expected: all tests and analysis pass. Leave the checkpoint uncommitted unless the user separately authorizes a commit.

---

### Task 2: Cache-Backed Palette Controller

**Files:**
- Create: `lib/features/player/artwork_palette_controller.dart`
- Create: `test/features/player/artwork_palette_controller_test.dart`
- Read/Reuse: `lib/storage/app_image_cache.dart`
- Read/Reuse: `test/support/test_image_cache_manager.dart`

**Interfaces:**
- Consumes: `ArtworkPalette`, `fallbackArtworkPalette`, and `ArtworkPaletteExtractor.extract` from Task 1.
- Produces:
  - `typedef ArtworkBytesLoader = Future<Uint8List?> Function(AppArtworkSource source);`
  - `ArtworkPaletteController({required ArtworkBytesLoader loadBytes, ArtworkPaletteDecoding decoder = const ArtworkPaletteExtractor(), int capacity = 48})`
  - `ArtworkPalette get palette`
  - `Future<void> select(AppArtworkSource source, {required Brightness brightness})`
  - `void dispose()` inherited from `ChangeNotifier`
  - `Future<Uint8List?> loadArtworkBytes(BaseCacheManager manager, AppArtworkSource source)`

- [ ] **Step 1: Write failing controller tests**

Cover these exact scenarios:

```dart
test('late result from the previous track cannot replace the current palette', () async {
  final first = Completer<Uint8List?>();
  final second = Completer<Uint8List?>();
  const firstPalette = ArtworkPalette(
    backgroundBase: Color(0xFFFFE4E4),
    backgroundCompanion: Color(0xFFFFF0E8),
    vinylAccent: Color(0xFFCC3344),
    foreground: Color(0xFF211818),
  );
  const secondPalette = ArtworkPalette(
    backgroundBase: Color(0xFFE2ECFF),
    backgroundCompanion: Color(0xFFE8F7F3),
    vinylAccent: Color(0xFF3366CC),
    foreground: Color(0xFF172033),
  );
  final controller = ArtworkPaletteController(
    loadBytes: (source) => source.fallbackSeed == 'first'
        ? first.future
        : second.future,
    decoder: _FakePaletteDecoder({1: firstPalette, 2: secondPalette}),
  );

  final firstCall = controller.select(
    const AppArtworkSource.fallback(fallbackSeed: 'first'),
    brightness: Brightness.light,
  );
  final secondCall = controller.select(
    const AppArtworkSource.fallback(fallbackSeed: 'second'),
    brightness: Brightness.light,
  );
  second.complete(Uint8List.fromList([2]));
  await secondCall;
  final selected = controller.palette;
  first.complete(Uint8List.fromList([1]));
  await firstCall;
  expect(controller.palette, selected);
});

final class _FakePaletteDecoder implements ArtworkPaletteDecoding {
  const _FakePaletteDecoder(this.results);
  final Map<int, ArtworkPalette> results;

  @override
  Future<ArtworkPalette> extract(
    Uint8List encodedBytes, {
    required String fallbackSeed,
    required Brightness brightness,
  }) async => results[encodedBytes.single]!;
}
```

Also test initial fallback availability, identical cache-key reuse, bounded LRU eviction at capacity 2, loader failure, null bytes, and brightness as part of the result key.

- [ ] **Step 2: Run the controller test and verify it fails**

Run:

```bash
flutter test test/features/player/artwork_palette_controller_test.dart
```

Expected: compilation fails because the controller and loader do not exist.

- [ ] **Step 3: Implement cache-manager byte loading**

For network sources, call the existing manager with the same URL/cache key and headers:

```dart
final response = await manager
    .getFileStream(
      source.url!,
      key: source.url!,
      headers: artworkRequestHeaders,
      withProgress: false,
    )
    .whereType<FileInfo>()
    .first;
return response.file.readAsBytes();
```

For a fallback source, return `null` so the controller uses the deterministic seed palette. Propagate no loader exception to callers.

- [ ] **Step 4: Implement selection, stale-result protection, and LRU**

Increment an integer generation on every `select`. Set the immediate palette to either the LRU hit or `fallbackArtworkPalette`. Await bytes and extraction; before publishing, require both the generation and normalized source key to still match. Store at most `capacity` entries in a `LinkedHashMap<String, ArtworkPalette>`, moving hits to the newest position and removing the oldest key after insertion.

- [ ] **Step 5: Run focused tests and checks**

Run:

```bash
dart format lib/features/player/artwork_palette_controller.dart test/features/player/artwork_palette_controller_test.dart
flutter test test/features/player/artwork_palette_controller_test.dart test/storage/app_image_cache_test.dart
flutter analyze lib/features/player/artwork_palette_controller.dart test/features/player/artwork_palette_controller_test.dart
git diff --check -- lib/features/player/artwork_palette_controller.dart test/features/player/artwork_palette_controller_test.dart
```

Expected: controller and existing cache tests pass. Leave the checkpoint uncommitted unless separately authorized.

---

### Task 3: Desktop-Only Palette-Driven Backdrop

**Files:**
- Create: `lib/features/player/desktop_dynamic_player_backdrop.dart`
- Create: `test/features/player/desktop_dynamic_player_backdrop_test.dart`
- Read/Preserve: `lib/features/player/player_backdrop.dart`

**Interfaces:**
- Consumes: `ArtworkPalette` from Task 1.
- Produces: `DesktopDynamicPlayerBackdrop({required ArtworkPalette palette, required Object transitionKey})`.

- [ ] **Step 1: Replace backdrop tests with palette behavior tests**

Assert that a supplied palette creates keys `player-desktop-backdrop-gradient-base` and `player-desktop-backdrop-gradient-companion`, that changing the transition key uses an `AnimatedContainer`/`TweenAnimationBuilder` duration within 450–650ms, and that reduced motion uses at most 150ms. Assert that the desktop backdrop is excluded from semantics and ignores pointer events. Keep the existing `player_backdrop_test.dart` passing unchanged to prove that mobile still uses the current artwork blur.

- [ ] **Step 2: Run the backdrop test and verify it fails**

Run:

```bash
flutter test test/features/player/desktop_dynamic_player_backdrop_test.dart
```

Expected: compilation fails because `DesktopDynamicPlayerBackdrop` does not exist.

- [ ] **Step 3: Replace full-cover blur with animated gradients**

Create a desktop-only background that draws a theme-neutral base plus two low-contrast radial/linear gradient layers derived from `palette.backgroundBase` and `palette.backgroundCompanion`. Use `ExcludeSemantics`, `IgnorePointer`, and the key `player-desktop-backdrop`. Use the motion policy for duration:

```dart
final duration = policy.reduceMotion
    ? const Duration(milliseconds: 150)
    : const Duration(milliseconds: 560);
```

Do not animate layout properties and do not apply a full-screen runtime blur. Do not modify the existing `PlayerBackdrop`; it remains the mobile implementation.

- [ ] **Step 4: Run focused tests and checks**

Run:

```bash
dart format lib/features/player/desktop_dynamic_player_backdrop.dart test/features/player/desktop_dynamic_player_backdrop_test.dart
flutter test test/features/player/desktop_dynamic_player_backdrop_test.dart test/features/player/player_backdrop_test.dart
flutter analyze lib/features/player/desktop_dynamic_player_backdrop.dart test/features/player/desktop_dynamic_player_backdrop_test.dart
git diff --check -- lib/features/player/desktop_dynamic_player_backdrop.dart test/features/player/desktop_dynamic_player_backdrop_test.dart
```

Expected: all backdrop tests pass.

---

### Task 4: Textured Orbit Vinyl With Original Center Artwork

**Files:**
- Create: `lib/features/player/desktop_orbit_vinyl.dart`
- Create: `test/features/player/desktop_orbit_vinyl_test.dart`
- Read/Reuse: `lib/features/player/vinyl_record.dart`

**Interfaces:**
- Consumes: `AppArtworkSource`, `ArtworkPalette`, `rotating`, seed, semantic label, and the existing reduced-motion policy.
- Produces: `DesktopOrbitVinyl({required AppArtworkSource source, required ArtworkPalette palette, required String seed, required String semanticLabel, required bool rotating})`.

- [ ] **Step 1: Write failing structure and rotation tests**

Assert the component contains exactly one semantic artwork node and these keys beneath one `RotationTransition`:

```dart
expect(find.byKey(const Key('player-desktop-orbit-turn')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-vinyl-base')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-vinyl-refraction')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-vinyl-grooves')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-vinyl-artwork')), findsOneWidget);
expect(find.byKey(const Key('player-desktop-vinyl-spindle')), findsOneWidget);
```

Verify center artwork diameter is between 58% and 62% of the disc, the refraction layer is clipped to an annulus and excluded from semantics, and ready/pause/reduced-motion preserves the existing angle behavior.

- [ ] **Step 2: Run the vinyl test and verify it fails**

Run:

```bash
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

Expected: compilation fails because `DesktopOrbitVinyl` does not exist.

- [ ] **Step 3: Implement one shared rotation container**

Adapt the existing 18-second controller lifecycle from `VinylRecord`. Place the complete visual stack under one `RotationTransition` and one `RepaintBoundary`. Keep stopping behavior `stop(canceled: false)` so pause does not reset the angle.

- [ ] **Step 4: Implement the five visual layers**

Build, in order:

1. A circular palette-derived base using radial and sweep gradients with alpha variants of `vinylAccent`.
2. A second `AppArtwork` copy inside an annular clip (`PathFillType.evenOdd`), transformed to 1.15–1.25 scale, blurred only within the disc boundary, opacity `.12...22`, and excluded from semantics.
3. `CustomPaint` grooves and fixed highlight arcs using palette-derived light/dark colors.
4. The original `AppArtwork` at `diameter * .60`, circularly clipped, with no blur or color filter.
5. A small spindle with no duplicate semantics.

The center `AppArtwork` must receive `source` unchanged and use the supplied song title semantic label.

- [ ] **Step 5: Run focused tests and checks**

Run:

```bash
dart format lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart test/features/player/mobile_vinyl_record_test.dart
flutter analyze lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
git diff --check -- lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
```

Expected: desktop textured-vinyl and unchanged mobile-vinyl tests pass.

---

### Task 5: Integrate Palette State and Orbit Crop Desktop Layout

**Files:**
- Modify: `lib/features/player/player_screen.dart:49-190`
- Modify: `lib/features/player/desktop_player_stage.dart:1-185`
- Modify: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `ArtworkPaletteController` from Task 2, palette-driven `PlayerBackdrop` from Task 3, and `DesktopOrbitVinyl` from Task 4.
- Produces:
  - `DesktopPlayerStage({required PlayerState state, required AppArtworkSource artworkSource, required ArtworkPalette palette, required VoidCallback onRetryLyrics})`
  - one current palette routed to both backdrop and desktop record.

- [ ] **Step 1: Update desktop integration tests first**

Replace portal-specific assertions with Orbit Crop assertions:

- `player-desktop-orbit-vinyl` exists and `player-desktop-vinyl-portal` is absent from the production player tree.
- `player-desktop-track-title` and `desktop-lyrics-viewport` are left of the visible center-artwork boundary.
- At 1024×768 and 1440×960, the record does not intersect `desktop-lyrics-viewport` or `desktop-player-controls`.
- A cached cover URL still produces a real center artwork with no fallback key.
- Injected delayed palette requests cannot recolor the next track.
- Mobile assertions and keys remain unchanged.

- [ ] **Step 2: Run the player test and verify the structural failure**

Run:

```bash
flutter test test/features/player/player_screen_test.dart
```

Expected: Orbit Crop keys and the palette dependency are absent.

- [ ] **Step 3: Own palette presentation state in `PlayerScreen`**

Create the palette controller after `AppImageCacheScope` becomes available in `didChangeDependencies`; dispose it with the screen. When `_sourceFor(track)` changes or platform brightness changes, call `select` once after the current build using a guarded post-frame callback. Listen to the palette controller alongside `PlayerController`. On desktop, pass `palette` to `DesktopDynamicPlayerBackdrop` and the desktop stage; on mobile, continue building the existing `PlayerBackdrop(source: artworkSource, ...)` and do not start palette extraction. Do not add palette fields to `PlayerState`.

For testability, add an optional `ArtworkPaletteController? paletteController` constructor parameter to `PlayerScreen`; production creates and owns a controller only when none is supplied.

- [ ] **Step 4: Implement the right-top responsive stage**

Remove the production import/use of `DesktopVinylPortal`. Place title and metadata at the left top, lyrics in the left middle, and `DesktopOrbitVinyl` at a negative top/right offset. Compute diameter from both dimensions:

```dart
final diameter = math.min(
  constraints.maxHeight * .86,
  constraints.maxWidth * (constraints.maxWidth >= 1200 ? .54 : .60),
);
```

At 1024px, increase the right overflow and cap the visible center-artwork left edge so it stays right of the lyric safety column. Keep the existing `Padding(... bottom: 142)` and bottom controls untouched.

- [ ] **Step 5: Use palette foreground in desktop reading content**

Apply `palette.foreground` to title and active lyric presentation through a narrow desktop-only foreground override or an explicit `foreground` parameter on `LyricsView`. If changing `LyricsView`, default the new parameter to `null` and preserve all existing mobile behavior and tests. Secondary text uses the same foreground at reduced opacity, not an independently extracted color.

- [ ] **Step 6: Run player, layout, and mobile regression tests**

Run:

```bash
dart format lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart test/features/player/mobile_vinyl_record_test.dart test/features/player/lyrics_view_test.dart
flutter analyze lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
git diff --check -- lib/features/player/player_screen.dart lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
```

Expected: desktop Orbit Crop behavior passes and mobile layout/output tests remain green.

---

### Task 6: Stable Visual Fixtures and Final Verification

**Files:**
- Modify: `test/visual/high_fidelity_fixtures.dart`
- Modify: `test/visual/full_ui_gallery_test.dart`
- Update: `test/visual/full_goldens/desktop-player-1024x768-light.png`
- Update: `test/visual/full_goldens/desktop-player-1024x768.png`
- Update: `test/visual/full_goldens/desktop-player-1440x960-light.png`
- Update: `test/visual/full_goldens/desktop-player-1440x960.png`

**Interfaces:**
- Consumes: the complete palette/backdrop/record/stage implementation from Tasks 1–5.
- Produces: deterministic warm and cool desktop visual evidence plus the final focused verification result.

- [ ] **Step 1: Make desktop fixtures deterministic**

Provide encoded warm and cool artwork bytes through the fake image cache and inject a palette controller whose loader reads those bytes. The 1024 fixture must exercise the compact overflow rule; the 1440 fixture must show the full right-top record. Do not make production code depend on test assets.

- [ ] **Step 2: Generate only the four affected desktop baselines**

Use the project-native golden command already used by `full_ui_gallery_test.dart`, filtered to the desktop player cases. If the harness accepts Flutter's standard update flag, run:

```bash
flutter test test/visual/full_ui_gallery_test.dart \
  --update-goldens \
  --plain-name 'desktop-player'
```

Expected: exactly the four listed desktop player PNGs change; mobile and unrelated screens remain untouched. If the test names split by size/theme, use their exact names from `flutter test ... --reporter expanded` rather than broadening the update.

- [ ] **Step 3: Inspect all four rendered images**

Open each PNG and verify:

- the center circle visibly contains the song artwork;
- the outer disc shows translucent color variation, refracted image content, grooves, and highlights;
- the record is cropped by top/right window edges only;
- lyrics and controls remain unobstructed;
- warm/cool inputs produce meaningfully different palettes;
- dark and light text remain readable.

Do not accept a baseline merely because the golden test can be updated.

- [ ] **Step 4: Run the focused final suite on the frozen tree**

Run:

```bash
dart format --set-exit-if-changed \
  lib/features/player/artwork_palette.dart \
  lib/features/player/artwork_palette_extractor.dart \
  lib/features/player/artwork_palette_controller.dart \
  lib/features/player/desktop_dynamic_player_backdrop.dart \
  lib/features/player/desktop_orbit_vinyl.dart \
  lib/features/player/desktop_player_stage.dart \
  lib/features/player/player_screen.dart \
  test/features/player/artwork_palette_extractor_test.dart \
  test/features/player/artwork_palette_controller_test.dart \
  test/features/player/desktop_dynamic_player_backdrop_test.dart \
  test/features/player/desktop_orbit_vinyl_test.dart \
  test/features/player/player_screen_test.dart

flutter test \
  test/features/player/artwork_palette_extractor_test.dart \
  test/features/player/artwork_palette_controller_test.dart \
  test/features/player/desktop_dynamic_player_backdrop_test.dart \
  test/features/player/player_backdrop_test.dart \
  test/features/player/desktop_orbit_vinyl_test.dart \
  test/features/player/player_screen_test.dart \
  test/features/player/mobile_vinyl_record_test.dart \
  test/visual/full_ui_gallery_test.dart

flutter analyze lib/features/player test/features/player
git diff --check
git status --short
```

Expected: formatting is unchanged, all focused tests and analysis pass, no whitespace errors exist, and `git status` shows only the intended player/palette/test/baseline changes plus the user's pre-existing dirty files.

- [ ] **Step 5: Report the handoff without committing**

Summarize changed files, commands and results, visual evidence, and any residual platform/performance risk. Do not stage, commit, push, delete the previous portal files, or touch unrelated dirty changes unless the user separately authorizes those actions.
