# Unified Record Default Artwork Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both light and dark missing-track covers use the same centered vinyl-record geometry with a filled single music note, using the approved balanced dark-theme colors.

**Architecture:** Keep `AppArtwork` as the only real/fallback artwork boundary. Replace the light-record/dark-waveform split with one `_RecordFallback` whose geometry is brightness-independent and whose semantic colors come from `AppTokens`; draw the default track note with a small filled custom painter while preserving non-track `AppArtwork.icon` values through the existing `Icon` path.

**Tech Stack:** Flutter 3, Dart 3.9, `shadcn_ui`, Flutter `CustomPainter`, `flutter_test`, and Flutter golden tests.

## Global Constraints

- Both themes use identical record radius, groove positions, center-label size, note shape, and alignment.
- Light colors: `surfaceWarm` sleeve, `border` boundary, `foreground` record, `accent` center label, and `accentForeground` filled note.
- Approved dark A “balanced” colors: `surface` sleeve, `border` boundary, near-black `accentForeground` record, quiet `foreground` grooves through opacity, `accent` center label, and `accentForeground` filled note.
- The default track mark is a filled single note, not an outline glyph, TuneFlow logo, waveform, or wordmark.
- Every coverless track renders identical pixels within one brightness mode; `seed` remains identity only.
- Preserve valid remote/cached artwork behavior, URL normalization, cache acquisition/repair/retry, semantics, dimensions, radii, layout, and `showFallback: false`.
- Preserve playlist callers' existing `AppArtwork.icon` distinction in both themes.
- Keep the already-implemented neutral player backdrop for missing artwork unchanged.
- Add no dependencies and no page-local raw colors.
- Preserve unrelated dirty-worktree changes. Do not stage, commit, or overwrite an already-modified broad gallery baseline without explicit authorization.

---

## File Map

- `lib/design/components/artwork.dart` — replace the brightness-specific fallback split with the unified record widget and filled-note painter.
- `test/design/artwork_test.dart` — encode unified geometry, filled-note, dark-mode, playlist-icon, theme-switch, and removed-waveform behavior.
- `test/design/default_artwork_golden_test.dart` — retain the isolated 44 px and 192 px fixtures for both themes.
- `test/design/goldens/default-artwork-*.png` — regenerate and review the four isolated baselines.
- `design.md` — replace the obsolete dark-waveform contract with the approved unified record contract.
- `docs/superpowers/specs/2026-08-14-unified-default-track-artwork-design.md` — mark the reviewed specification approved for implementation.
- `lib/features/player/player_backdrop.dart` and `test/features/player/player_backdrop_test.dart` — verification-only; the neutral missing-artwork backdrop must remain unchanged.
- `test/visual/high_fidelity_gallery_test.dart` — run the affected player fixtures without updating user-owned broad baselines.

---

### Task 1: Unified record structure and filled note

**Files:**
- Modify: `test/design/artwork_test.dart:85-215`
- Modify: `lib/design/components/artwork.dart:239-420`

**Interfaces:**
- Consumes: `AppTokens`, active brightness, `AppArtwork.icon`, `AppArtwork.seed`, and `AppArtwork.showFallback`.
- Produces: `_RecordFallback({required String seed, required IconData icon, required AppTokens tokens, required bool dark})`, `_VinylArtworkPainter`, and `_FilledMusicNotePainter`.
- Produces stable keys: `artwork-fallback-record-<seed>`, `artwork-fallback-symbol-<seed>`, and `artwork-fallback-filled-note-<seed>`.

- [x] **Step 1: Replace waveform expectations with failing unified-record tests**

Update the existing fallback tests so both brightness modes require the same structural keys, the default mark requires the filled-note painter, and the removed dark marks are absent:

```dart
testWidgets('both themes use the same record and filled-note structure', (
  tester,
) async {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    await tester.pumpWidget(
      fallbackHarness(mode: mode, seed: mode.name, size: 120),
    );

    expect(
      find.byKey(Key('artwork-fallback-record-${mode.name}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('artwork-fallback-symbol-${mode.name}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('artwork-fallback-filled-note-${mode.name}')),
      findsOneWidget,
    );
    expect(find.text('TUNEFLOW'), findsNothing);
  }
});

testWidgets('dark fallback removes the waveform at every size', (tester) async {
  for (final size in [44.0, 96.0, 192.0]) {
    await tester.pumpWidget(
      fallbackHarness(mode: ThemeMode.dark, seed: 'dark', size: size),
    );
    expect(
      find.byKey(const Key('artwork-fallback-record-dark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('artwork-fallback-dark-waveform-dark')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('artwork-fallback-dark-wordmark-dark')),
      findsNothing,
    );
  }
});
```

Update the theme-switching test to require `artwork-fallback-record-switch` and `artwork-fallback-filled-note-switch` before and after switching. Update the playlist-icon test to run in both themes, require `artwork-fallback-symbol-playlist`, find its descendant `Icon`, and assert `icon.icon == LucideIcons.listMusic`.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/design/artwork_test.dart
```

Expected: the new record/symbol/filled-note keys fail in dark mode and the old waveform still appears; existing cache/source tests remain green.

- [x] **Step 3: Route both themes through one record widget**

Replace the `dark ? _DarkWaveformFallback(...) : _LightRecordFallback(...)` branch with:

```dart
child: _RecordFallback(
  seed: seed,
  icon: icon,
  tokens: tokens,
  dark: dark,
),
```

Rename `_LightRecordFallback` to `_RecordFallback`, add `final bool dark`, and keep the exact record geometry already approved: record radius `.36`, center-label factors `.24`, and groove factors `[.78, .58, .38]`.

- [x] **Step 4: Apply semantic light and balanced-dark colors without changing geometry**

Construct the vinyl painter as follows:

```dart
painter: _VinylArtworkPainter(
  recordColor: dark ? tokens.accentForeground : tokens.foreground,
  grooveColor: dark ? tokens.foreground : tokens.accentForeground,
),
```

Keep the sleeve selection at the outer fallback boundary (`dark ? tokens.surface : tokens.surfaceWarm`), the semantic border at `tokens.border`, and the center label at `tokens.accent`.

- [x] **Step 5: Draw the default track mark as a filled single note**

Inside the center-label `DecoratedBox`, key the symbol boundary and select the filled painter only for the default track icon:

```dart
child: SizedBox.expand(
  key: Key('artwork-fallback-symbol-$seed'),
  child: icon == LucideIcons.music2
      ? CustomPaint(
          key: Key('artwork-fallback-filled-note-$seed'),
          painter: _FilledMusicNotePainter(tokens.accentForeground),
        )
      : Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(icon, color: tokens.accentForeground),
          ),
        ),
),
```

Implement `_FilledMusicNotePainter` with a filled `Path` matching the approved preview: one oval note head, one vertical stem, and one short right-facing flag. Normalize all coordinates against the painter size, fill with one `Paint()..color = color`, add no stroke, and repaint only when `color` changes.

- [x] **Step 6: Delete dark-only artwork and verify GREEN**

Remove `_DarkWaveformFallback` and `_WaveformArtworkPainter`. Then run:

```bash
dart format lib/design/components/artwork.dart test/design/artwork_test.dart
flutter test test/design/artwork_test.dart test/design/app_components_test.dart
```

Expected: all focused artwork/component tests pass; the dark waveform/wordmark no longer exists; cache/source and playlist behavior remain green.

---

### Task 2: Isolated visual baselines and written contract

**Files:**
- Verify: `test/design/default_artwork_golden_test.dart`
- Update: `test/design/goldens/default-artwork-light-44.png`
- Update: `test/design/goldens/default-artwork-light-192.png`
- Update: `test/design/goldens/default-artwork-dark-44.png`
- Update: `test/design/goldens/default-artwork-dark-192.png`
- Modify: `design.md:288-298`
- Modify: `docs/superpowers/specs/2026-08-14-unified-default-track-artwork-design.md:4`

**Interfaces:**
- Consumes: the public `AppArtwork` constructor and active app themes.
- Produces: four reviewed baselines for small and large unified record artwork.

- [x] **Step 1: Run isolated goldens before updating and verify expected RED**

Run:

```bash
flutter test test/design/default_artwork_golden_test.dart
```

Expected: dark 44 and dark 192 fail because they still encode the waveform design; light baselines may fail because the outline note changes to a filled note.

- [x] **Step 2: Regenerate only the four isolated component baselines**

Run:

```bash
flutter test --update-goldens test/design/default_artwork_golden_test.dart
flutter test test/design/default_artwork_golden_test.dart
```

Expected: exactly the four `default-artwork-{light,dark}-{44,192}.png` files update and the non-update run passes.

- [x] **Step 3: Inspect all four images**

Verify each baseline directly:

- Both themes show the same record radius, three groove positions, center-label size, and filled single-note shape.
- The 44 px note is visually substantial, centered, unclipped, and recognizable.
- Light mode uses the neutral sleeve, dark record, green center, and light note.
- Dark mode uses the charcoal sleeve, near-black record, restrained light grooves, Mist Mint center, and dark note.
- No TuneFlow logo, waveform, `TUNEFLOW` text, seeded colors, or unrelated layout appears.

If any check fails, change only painter proportions, rerun Task 1's focused tests, regenerate these four files, and inspect again.

- [x] **Step 4: Synchronize the authoritative design text**

Replace the fallback rule in `design.md` with:

```markdown
- Missing or failed track artwork: use one centered vinyl-record structure in
  both brightness modes, with a filled single music note in the center label.
  Light and dark modes keep identical geometry and use their semantic palette;
  dark mode uses the approved balanced charcoal/near-black/Mist Mint treatment.
  The seed never changes fallback pixels. Do not show a logo, waveform, or
  `TUNEFLOW` wordmark.
- Missing player artwork: show the default cover only in the foreground. The
  player backdrop remains the normal theme canvas and veil; never enlarge or
  blur placeholder graphics.
```

Verify the reviewed spec status remains `approved for implementation`.

- [x] **Step 5: Validate the isolated contract**

Run:

```bash
git diff --check -- design.md docs/superpowers/specs/2026-08-14-unified-default-track-artwork-design.md test/design/default_artwork_golden_test.dart
flutter test test/design/artwork_test.dart test/design/default_artwork_golden_test.dart test/features/player/player_backdrop_test.dart
```

Expected: no whitespace errors and all unified-artwork and neutral-backdrop tests pass.

---

### Task 3: Runtime and integration verification

**Files:**
- Verify: `lib/design/components/artwork.dart`
- Verify: `lib/features/player/player_backdrop.dart`
- Verify: `test/visual/high_fidelity_gallery_test.dart`
- Do not update: existing dirty files under `test/visual/goldens/` and `test/visual/full_goldens/`

**Interfaces:**
- Consumes: the frozen implementation and current visual fixtures.
- Produces: current analysis/test evidence, focused broad-gallery impact, and a live runtime preview where the app can reach a coverless track.

- [x] **Step 1: Record user-owned gallery state**

Run:

```bash
git status --short -- test/visual/goldens test/visual/full_goldens
```

Do not run any broad `--update-goldens` command. Treat every listed path as user-owned.

- [x] **Step 2: Run the frozen static and focused integration gate**

Run:

```bash
dart format --output=none --set-exit-if-changed \
  lib/design/components/artwork.dart \
  lib/features/player/player_backdrop.dart \
  test/design/artwork_test.dart \
  test/design/default_artwork_golden_test.dart \
  test/features/player/player_backdrop_test.dart \
  test/features/player/player_screen_test.dart
flutter analyze
flutter test \
  test/design/artwork_test.dart \
  test/design/app_components_test.dart \
  test/design/default_artwork_golden_test.dart \
  test/features/player/player_backdrop_test.dart \
  test/features/player/player_screen_test.dart
```

Expected: formatting exits 0, analysis reports no issues, and all focused suites pass.

- [x] **Step 3: Discover affected player-gallery differences without overwriting baselines**

Run:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart --plain-name 'player mobile light'
flutter test test/visual/high_fidelity_gallery_test.dart --plain-name 'player mobile dark'
```

Record pass/fail and pixel-difference output. Expected mismatches are limited to the default foreground cover and the already-approved neutral no-cover backdrop. Leave the baselines untouched because they overlap existing user modifications.

- [x] **Step 4: Run and inspect the app**

Launch the project's existing macOS target, or its temporary Flutter web-server target when the native target is unavailable. Navigate to a fixture or connected service state containing a coverless track, then verify light and dark themes show the same record geometry and filled note. If no music service is running, report that live data-dependent inspection is blocked and use the four reviewed isolated goldens as the runtime-equivalent visual evidence; do not invent or persist fake production data.

- [x] **Step 5: Review the final scoped diff and hand off without Git mutation**

Run:

```bash
git diff --check
rg -n "Waveform|waveform|TUNEFLOW|wordmark|TuneFlow\\.png|HSLColor|_palette" \
  lib/design/components/artwork.dart design.md
git diff -- \
  design.md \
  docs/superpowers/specs/2026-08-14-unified-default-track-artwork-design.md \
  lib/design/components/artwork.dart \
  test/design/artwork_test.dart \
  test/design/default_artwork_golden_test.dart
git status --short
```

Confirm the scoped production diff contains no waveform/wordmark/logo fallback, no seed palette, no cache/source changes, and no unrelated edits. Leave all changes unstaged and uncommitted unless the user separately authorizes Git actions.
