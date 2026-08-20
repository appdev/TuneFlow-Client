# ARM64 Font Subsetting Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a single ARM64-only Android Release APK while replacing the bundled full CJK fonts with a small title subset and platform fallback for dynamic Chinese text.

**Architecture:** Keep `AppTypography` as the typography owner. Display styles reference a generated Noto Serif SC UI subset, body styles omit an explicit family so Chinese glyphs fall back to the platform, and numeric styles retain IBM Plex Mono. Android `defaultConfig` owns the persistent ABI restriction so ordinary Release builds cannot reintroduce ARMv7 or x86_64.

**Tech Stack:** Flutter 3.47, Dart 3.13, Android Gradle Plugin 9.0.1, Gradle 9.1, FontTools `pyftsubset`, OpenJDK 21.

## Global Constraints

- Android supports exactly `arm64-v8a`; do not include ARMv7 or x86_64 native libraries.
- Dynamic remote and user-generated Chinese content must retain platform font fallback.
- Keep IBM Plex Mono and existing icon/font dependencies.
- Do not change version `1.0.4+5`, signing configuration, typography sizes, weights, colors, or unrelated dirty-worktree changes.
- Do not commit because the user has not authorized commits.

---

### Task 1: Lock the typography behavior with focused tests

**Files:**
- Modify: `test/design/app_components_test.dart`
- Modify: `test/design/app_theme_test.dart`

**Interfaces:**
- Consumes: `AppTypography` static text-style tokens.
- Produces: Assertions that body styles have no explicit font family, display styles use `NotoSerifSCSubset`, and counters use `IBMPlexMono`.

- [x] **Step 1: Replace the bundled-body-font assertion**

Assert:

```dart
expect(AppTypography.body.fontFamily, isNull);
expect(AppTypography.title.fontFamily, isNull);
```

- [x] **Step 2: Update typography-role assertions**

Assert:

```dart
expect(AppTypography.displayFontFamily, 'NotoSerifSCSubset');
expect(AppTypography.pageTitle.fontFamily, 'NotoSerifSCSubset');
expect(AppTypography.body.fontFamily, isNull);
expect(AppTypography.counter.fontFamily, 'IBMPlexMono');
```

- [x] **Step 3: Run the focused tests and confirm they fail before implementation**

Run:

```sh
flutter test test/design/app_components_test.dart test/design/app_theme_test.dart
```

Expected: failure because body styles still use `NotoSansCJKsc` and display styles still use `NotoSerifSC`.

### Task 2: Generate and register the title font subset

**Files:**
- Create: `assets/fonts/NotoSerifSC-UI-Subset.ttf`
- Modify: `pubspec.yaml`
- Modify: `lib/design/design_tokens.dart`
- Modify: `lib/design/app_theme.dart`
- Modify: `test/visual/full_ui_gallery_test.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Modify: `test/design/default_artwork_golden_test.dart`
- Remove: `assets/fonts/NotoSansCJKsc-Regular.otf`
- Remove: `assets/fonts/NotoSerifSC-VariableFont_wght.ttf`

**Interfaces:**
- Consumes: fixed UI characters collected from `lib/**/*.dart` and `lib/l10n/*.arb`.
- Produces: font family `NotoSerifSCSubset`; body `TextStyle` tokens with `fontFamily == null`.

- [x] **Step 1: Generate a deterministic UI-character subset**

Use a temporary FontTools environment and run `pyftsubset` against `NotoSerifSC-VariableFont_wght.ttf`. Include ASCII, Chinese punctuation, full-width forms, and every matching character in Dart and ARB sources. Preserve all layout features, glyph names, symbol/legacy cmap, `.notdef`, and recommended glyphs. Write the result to `assets/fonts/NotoSerifSC-UI-Subset.ttf`.

- [x] **Step 2: Update font registration**

Remove the `NotoSansCJKsc` family from `pubspec.yaml`. Rename the display family to `NotoSerifSCSubset` and point it at `assets/fonts/NotoSerifSC-UI-Subset.ttf` with weight 600. Keep `IBMPlexMono` unchanged.

- [x] **Step 3: Make body styles inherit platform fallback**

Set `AppTypography.displayFontFamily` to `NotoSerifSCSubset`. Remove `bodyFontFamily`/`fontFamily` constants and omit `fontFamily` from `title`, `body`, and `metadata`. Build the Shad text theme without forcing the removed CJK family.

- [x] **Step 4: Update test font loaders**

Remove all `NotoSansCJKsc` loaders. Change display loaders to family `NotoSerifSCSubset` and asset `NotoSerifSC-UI-Subset.ttf`. The default-artwork golden does not require a body font loader after the body family is removed.

- [x] **Step 5: Remove the two full font binaries recoverably**

Move both full fonts out of the worktree to a task-specific temporary backup. Keep the OFL license files in `assets/fonts`.

- [x] **Step 6: Run focused tests**

Run:

```sh
flutter test test/design/app_components_test.dart test/design/app_theme_test.dart
```

Expected: all tests pass.

### Task 3: Persist the ARM64-only Android configuration

**Files:**
- Modify: `android/app/build.gradle.kts`

**Interfaces:**
- Consumes: Android `defaultConfig.ndk.abiFilters`.
- Produces: Release artifacts containing native libraries only under `lib/arm64-v8a/`.

- [x] **Step 1: Add the ABI filter**

Inside `defaultConfig`, add:

```kotlin
ndk {
    abiFilters += "arm64-v8a"
}
```

- [x] **Step 2: Run static and focused verification**

Run:

```sh
flutter analyze
flutter test test/design/app_components_test.dart test/design/app_theme_test.dart
flutter test test/features/player/player_screen_test.dart test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: analysis and tests pass; the first icon scan has no matches, and raw Material icon matches remain confined to `lib/design/components/app_playback_button.dart`.

### Task 4: Build, inspect, and deliver the reduced APK

**Files:**
- Build output: `build/app/outputs/flutter-apk/app-release.apk`
- Deliver: `/Volumes/备份/app-release.apk`
- Deliver: `/Volumes/备份/TuneFlow-1.0.4+5-arm64-release-unsigned.apk`

**Interfaces:**
- Consumes: frozen source tree, OpenJDK 21 Flutter configuration, ABI filter, and subset font.
- Produces: verified ARM64-only unsigned Release APK and checksum.

- [x] **Step 1: Build the ordinary Release APK**

Run:

```sh
flutter build apk --release
```

Expected: exit 0 and a single `app-release.apk`.

- [x] **Step 2: Inspect APK contents**

Verify ZIP entries contain `lib/arm64-v8a/` and contain neither `lib/armeabi-v7a/` nor `lib/x86_64/`. Verify the APK contains `NotoSerifSC-UI-Subset.ttf` and does not contain either deleted full Noto filename.

- [x] **Step 3: Record size and checksum**

Run `stat` and `shasum -a 256` on the build artifact. Compare the result with the previous 54,590,040-byte ARM64 APK.

- [x] **Step 4: Back up and copy the deliverables**

Copy the existing `/Volumes/备份/app-release.apk` to a uniquely named pre-font-subset backup, then copy the verified artifact to both delivery filenames.

- [x] **Step 5: Verify copied bytes**

Run SHA-256 and byte-size checks on the build artifact and both destination files. All three hashes and sizes must match.
