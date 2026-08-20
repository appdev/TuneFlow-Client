# System Serif Typography Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incomplete bundled display-font subset with the platform `serif` family so dynamic Chinese titles render consistently without increasing APK size.

**Architecture:** `AppTypography` remains the single typography owner. Display roles use the platform generic `serif` family, body roles inherit platform defaults, and numeric roles retain IBM Plex Mono. No runtime font selection logic or new dependency is introduced.

**Tech Stack:** Flutter 3.47, Dart 3.13, Android API 35/36, Android generic font families.

## Global Constraints

- Preserve current sizes, weights, line heights, letter spacing, colors, and unrelated dirty-worktree changes.
- Keep the Android artifact signed and ARM64-only.
- Do not commit or expose local signing configuration.

---

### Task 1: Lock the system-serif contract

**Files:**
- Modify: `test/design/app_theme_test.dart`

- [x] Change the display-family expectations from `NotoSerifSCSubset` to `serif`.
- [x] Run `flutter test test/design/app_theme_test.dart` and confirm it fails because production still uses the subset family.

### Task 2: Remove the display subset

**Files:**
- Modify: `lib/design/design_tokens.dart`
- Modify: `pubspec.yaml`
- Modify: `test/visual/full_ui_gallery_test.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Remove: `assets/fonts/NotoSerifSC-UI-Subset.ttf`

- [x] Set `AppTypography.displayFontFamily` to `serif`.
- [x] Remove the `NotoSerifSCSubset` registration and test font loaders.
- [x] Move the subset font to a recoverable temporary backup.
- [x] Run focused typography, component, online playlist, album, playlist-detail, and player tests.

### Task 3: Verify and deliver

**Files:**
- Build: `build/app/outputs/flutter-apk/app-release.apk`
- Deliver: `/Volumes/备份/app-release.apk`
- Deliver: `/Volumes/备份/TuneFlow-1.0.4+5-arm64-release.apk`

- [x] Run `flutter analyze` and `git diff --check`.
- [x] Build `flutter build apk --release`.
- [x] Verify APK v2 signature, signer certificate, ARM64-only ABI, and absence of the subset font.
- [ ] Install with `adb install -r` on the connected Pixel API 35 ARM64 emulator. (Blocked: the installed debug-signed package has a different certificate; removing it would erase emulator app data.)
- [ ] Back up the previous delivered APK, copy the new APK, and verify SHA-256 equality.

Delivery is currently blocked because the previously recorded `/Volumes/备份` volume is not mounted.
