# Flutter 3.47 Platform Adaptation Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current TuneFlow working tree compile with Flutter 3.47.0 / Dart 3.13.0 on Android, iOS, macOS, Windows, and Linux.

**Architecture:** Keep application behavior unchanged and adapt only the SDK-facing seams: Dart call sites and deprecated callbacks, Android build-tool versions, the Flutter-generated iOS migration, and the existing multi-platform GitHub Actions workflow. Local macOS verifies Android and Apple builds; native Windows and Linux compilation is proven by the existing GitHub-hosted runners with release publication disabled.

**Tech Stack:** Flutter 3.47.0, Dart 3.13.0, Gradle 8.14, AGP 8.11.1, Kotlin Gradle Plugin 2.2.20, Java 17, Xcode, GitHub Actions.

## Global Constraints

- Work directly on the current `main` branch; do not create a temporary branch or worktree.
- Preserve every existing user change and never clean or reset the working tree.
- Commit build-required source, resources, dependency manifests, platform projects, workflow changes, and the adaptation docs; exclude `build/`, heap dumps, failure output, and unrelated local documents.
- Do not upgrade unrelated Dart packages or regenerate the UI/golden baseline.
- Do not use `--android-skip-build-dependency-validation`.
- Do not create a GitHub Release; the validation dispatch must use `publish_release=false`.
- Configuration and generated-project changes use reproduced build/analyzer failures as RED tests; behavior changes use focused Flutter tests first.

---

### Task 1: Repair Dart SDK-facing call sites

**Files:**
- Modify: `integration_test/live_audio_progress_test.dart`
- Modify: `integration_test/macos_preferences_test.dart`

**Interfaces:**
- Consumes: `ServiceAudioHandler({required Uri fallbackArtUri, MediaCache? cache})`.
- Produces: integration-test code that is statically compilable under Dart 3.13.

- [ ] **Step 1: Preserve the analyzer failure as the RED result**

Run: `flutter analyze integration_test/live_audio_progress_test.dart integration_test/macos_preferences_test.dart`

Expected: three failures for missing `fallbackArtUri` and the incompatible constructor tear-off.

- [ ] **Step 2: Give the integration tests an explicit placeholder URI**

Add a top-level value in each affected test file and use it at every handler construction:

```dart
final _fallbackArtUri = Uri.file('/tmp/tuneflow-default-track-artwork.png');

final audio = ServiceAudioHandler(fallbackArtUri: _fallbackArtUri);
```

Change the audio-service builder to a zero-argument closure:

```dart
builder: () => ServiceAudioHandler(fallbackArtUri: _fallbackArtUri),
```

- [ ] **Step 3: Verify the repaired test code compiles**

Run: `flutter analyze integration_test/live_audio_progress_test.dart integration_test/macos_preferences_test.dart`

Expected: no diagnostics in either file.

### Task 2: Migrate reorder callbacks without changing positions

**Files:**
- Modify: `test/features/playlists/playlist_detail_screen_test.dart`
- Modify: `lib/features/playlists/playlist_detail_screen.dart`

**Interfaces:**
- Consumes: Flutter 3.47 `ReorderableListView.onReorderItem`, whose `newIndex` is already adjusted after removal.
- Produces: `PlaylistDetailController.reorder(position: newIndex, trackIds: [...])` for mobile and desktop lists.

- [ ] **Step 1: Add the failing widget regression test**

Extend the playlist screen test with a mock client that returns the two-track detail, captures the reorder request, and then invoke the exposed callback:

```dart
final list = tester.widget<ReorderableListView>(
  find.byType(ReorderableListView).first,
);
expect(list.onReorder, isNull);
expect(list.onReorderItem, isNotNull);

await list.onReorderItem!(0, 1);
await tester.pumpAndSettle();

expect(capturedPosition, 1);
expect(capturedTrackIds, ['one']);
```

Set the test surface to a deterministic mobile size for the mobile callback and repeat at a desktop width for the desktop callback, restoring the surface size in `addTearDown`.

- [ ] **Step 2: Run the regression test and verify RED**

Run: `flutter test test/features/playlists/playlist_detail_screen_test.dart --plain-name 'reorder callbacks use Flutter-adjusted destination indexes'`

Expected: FAIL because the widget still supplies deprecated `onReorder`, so `onReorderItem` is null.

- [ ] **Step 3: Replace both deprecated callbacks**

Use the adjusted destination directly in both builders:

```dart
onReorderItem: (oldIndex, newIndex) {
  controller.reorder(
    position: newIndex,
    trackIds: [detail.tracks[oldIndex].id],
  );
},
```

Delete the old `position` variable and `newIndex > oldIndex` adjustment.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/features/playlists/playlist_detail_screen_test.dart --plain-name 'reorder callbacks use Flutter-adjusted destination indexes'`

Expected: PASS for both mobile and desktop callback checks.

### Task 3: Remove the remaining analyzer warning at its owner

**Files:**
- Modify: `lib/features/player/service_audio_handler.dart`

**Interfaces:**
- Consumes: `just_audio` 0.10.6 `LockCachingAudioSource`, still marked experimental.
- Produces: an intentional, local analyzer suppression attached only to the experimental construction.

- [ ] **Step 1: Confirm the warning remains**

Run: `flutter analyze lib/features/player/service_audio_handler.dart`

Expected: one `experimental_member_use` warning at `LockCachingAudioSource`.

- [ ] **Step 2: Add the narrow suppression with rationale**

Immediately before construction add:

```dart
// just_audio has no stable equivalent that exposes progressive cache download.
// ignore: experimental_member_use
final caching = LockCachingAudioSource(
```

- [ ] **Step 3: Verify the warning is gone**

Run: `flutter analyze lib/features/player/service_audio_handler.dart`

Expected: no diagnostics.

### Task 4: Align the Android build chain

**Files:**
- Modify: `android/gradle/wrapper/gradle-wrapper.properties`
- Modify: `android/settings.gradle.kts`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/gradle.properties`

**Interfaces:**
- Consumes: Flutter 3.47 Android dependency validation and JDK 17 configured by Flutter.
- Produces: Gradle 8.14 + AGP 8.11.1 + KGP 2.2.20 + Java/Kotlin 17.

- [ ] **Step 1: Record the existing RED build evidence**

Run: `flutter build apk --debug`

Expected: FAIL because Gradle 8.12 is below Flutter's required 8.14; `flutter analyze --suggestions` also reports AGP 8.9.1 / KGP 2.1.0 incompatibility.

- [ ] **Step 2: Update the compatible version tuple**

Set the wrapper URL to:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip
```

Set AGP to Flutter 3.47's minimum supported 8.11.1 and KGP to 2.2.20:

```kotlin
id("com.android.application") version "8.11.1" apply false
id("org.jetbrains.kotlin.android") version "2.2.20" apply false
```

Set Android compile targets to Java 17 and Kotlin's typed JVM target:

```kotlin
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlinOptions {
    jvmTarget = JavaVersion.VERSION_17.toString()
}
```

Add the Flutter 3.47 migration guards while staying below AGP 9:

```properties
android.builtInKotlin=false
android.newDsl=false
```

- [ ] **Step 3: Make release signing optional for compile-only CI**

Only attach the release signing config when `android/key.properties` exists:

```kotlin
buildTypes {
    release {
        if (keystorePropertiesFile.exists()) {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

- [ ] **Step 4: Verify the Android tuple and build**

Run: `flutter analyze --suggestions`

Expected: Java/Gradle/AGP/KGP marked compatible.

Run: `flutter build apk --debug`

Expected: `build/app/outputs/flutter-apk/app-debug.apk` exists.

Run: `flutter build apk --release`

Expected: an unsigned release APK compiles without local signing secrets.

### Task 5: Accept and audit the Flutter 3.47 iOS migration

**Files:**
- Modify as generated: `ios/Flutter/AppFrameworkInfo.plist`
- Modify as generated: `ios/Podfile`
- Modify as generated: `ios/Podfile.lock`
- Modify as generated: `ios/Runner.xcodeproj/project.pbxproj`
- Modify as generated: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
- Modify as generated: `ios/Runner/AppDelegate.swift`
- Modify as generated: `ios/Runner/Info.plist`

**Interfaces:**
- Consumes: Flutter 3.47 iOS 15 minimum, implicit Flutter engine delegate, UIScene lifecycle, and generated Swift package.
- Produces: an Xcode project that builds without another source-controlled migration.

- [ ] **Step 1: Run the Flutter migration and simulator build**

Run: `flutter build ios --simulator --debug`

Expected: Flutter reports the iOS 15, UIScene, and Swift Package Manager migrations, then produces `build/ios/iphonesimulator/Runner.app`.

- [ ] **Step 2: Audit generated diffs**

Run: `git diff -- ios`

Expected: only deployment-target, UIScene/AppDelegate, SPM project references, scheme preparation, and Pod lock migration changes; no absolute local paths, credentials, build caches, or unrelated resources.

- [ ] **Step 3: Verify the no-codesign release path used by CI**

Run: `flutter build ios --release --no-codesign`

Expected: `build/ios/iphoneos/Runner.app` exists.

### Task 6: Make the existing workflow a safe Flutter 3.47 build matrix

**Files:**
- Modify: `.github/workflows/build-clients.yml`

**Interfaces:**
- Consumes: manual `workflow_dispatch` with `publish_release` boolean input.
- Produces: five build jobs on Flutter 3.47.0; release/signing steps run only when explicitly requested.

- [ ] **Step 1: Preserve the workflow mismatch as RED evidence**

Run: `rg -n 'FLUTTER_VERSION|Publish GitHub Release|Restore Android signing key' .github/workflows/build-clients.yml`

Expected: Flutter 3.35.2 and unconditional signing/release behavior.

- [ ] **Step 2: Add a safe manual input and update Flutter**

Use:

```yaml
on:
  workflow_dispatch:
    inputs:
      publish_release:
        description: Publish the compiled artifacts as a GitHub Release
        required: false
        type: boolean
        default: false

env:
  FLUTTER_VERSION: 3.47.0
```

Condition the Android signing-key restore step and release job:

```yaml
if: ${{ inputs.publish_release }}
```

- [ ] **Step 3: Validate workflow syntax and safety**

Run: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/build-clients.yml', aliases: true); puts 'valid'"`

Expected: `valid`.

Run: `rg -n 'FLUTTER_VERSION: 3.47.0|publish_release|if:.*inputs.publish_release' .github/workflows/build-clients.yml`

Expected: the SDK pin, input, signing guard, and release-job guard are all present.

### Task 7: Run the local integration gate

**Files:**
- Verify only; do not regenerate goldens.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: frozen local evidence before source control and remote CI.

- [ ] **Step 1: Format touched Dart files**

Run: `dart format integration_test/live_audio_progress_test.dart integration_test/macos_preferences_test.dart lib/features/playlists/playlist_detail_screen.dart lib/features/player/service_audio_handler.dart test/features/playlists/playlist_detail_screen_test.dart`

Expected: formatter exits 0.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`.

- [ ] **Step 3: Run focused behavior tests**

Run: `flutter test test/features/playlists/playlist_detail_screen_test.dart test/features/player/service_audio_handler_test.dart`

Expected: all focused tests pass.

- [ ] **Step 4: Rebuild local host-supported targets from the frozen tree**

Run: `flutter build apk --release`

Run: `flutter build ios --release --no-codesign`

Run: `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO flutter build macos --release`

Expected: all three commands exit 0 and produce their platform artifacts.

### Task 8: Commit the current build inputs and run native CI

**Files:**
- Commit: application build inputs under `lib/`, `assets/`, `android/`, `ios/`, `macos/`, `linux/`, `windows/`; `pubspec.yaml`, `pubspec.lock`, `.github/workflows/build-clients.yml`; the two repaired `integration_test/` files; the focused playlist regression test; and this adaptation spec/plan.
- Exclude: `android/build/`, `android/java_pid24944.hprof`, `build/`, `test/**/failures/`, unrelated plans/specs, and generated golden differences not required by the application build.

**Interfaces:**
- Consumes: a locally verified current working tree and the user's authorization to commit/push current `main`.
- Produces: a pushed commit and successful Android/iOS/macOS/Windows/Linux GitHub Actions jobs without a release.

- [ ] **Step 1: Review the exact commit set**

Run:

```bash
git status --short
git diff --stat -- \
  .github/workflows/build-clients.yml \
  analysis_options.yaml \
  android/gradle.properties \
  android/gradle/wrapper/gradle-wrapper.properties \
  android/settings.gradle.kts \
  android/app/build.gradle.kts \
  ios macos lib assets/artwork/default_track_artwork.png \
  pubspec.yaml pubspec.lock \
  integration_test/live_audio_progress_test.dart \
  integration_test/macos_preferences_test.dart \
  test/features/playlists/playlist_detail_screen_test.dart \
  docs/superpowers/specs/2026-08-14-flutter-3-47-platform-adaptation-design.md \
  docs/superpowers/plans/2026-08-14-flutter-3-47-platform-adaptation.md
```

Expected: every included file participates in application compilation or Flutter 3.47 adaptation; prohibited outputs remain unstaged.

- [ ] **Step 2: Stage with explicit paths and inspect the index**

Run:

```bash
git add -- \
  .github/workflows/build-clients.yml \
  analysis_options.yaml \
  android/gradle.properties \
  android/gradle/wrapper/gradle-wrapper.properties \
  android/settings.gradle.kts \
  android/app/build.gradle.kts \
  ios macos lib assets/artwork/default_track_artwork.png \
  pubspec.yaml pubspec.lock \
  integration_test/live_audio_progress_test.dart \
  integration_test/macos_preferences_test.dart \
  test/features/playlists/playlist_detail_screen_test.dart \
  docs/superpowers/specs/2026-08-14-flutter-3-47-platform-adaptation-design.md \
  docs/superpowers/plans/2026-08-14-flutter-3-47-platform-adaptation.md
git diff --cached --check
git diff --cached --stat
```

Expected: no whitespace errors, heap dumps, build directories, failure images, secrets, or unrelated documents.

- [ ] **Step 3: Commit and push current main**

Run: `git commit -m "build: adapt clients to Flutter 3.47"`

Run: `git push origin main`

Expected: both commands succeed; unrelated unstaged files remain untouched.

- [ ] **Step 4: Trigger build-only validation**

Run: `gh workflow run build-clients.yml --ref main -f publish_release=false`

Resolve and watch the dispatched run with:

```bash
validation_run_id=$(gh run list --workflow build-clients.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
test -n "$validation_run_id"
gh run watch "$validation_run_id" --exit-status
```

Expected: Android, iOS, macOS, Windows, and Linux jobs succeed; `Publish GitHub Release` is skipped and no release/tag is created.

- [ ] **Step 5: Inspect any failing native job before changing code**

If a job fails, run `gh run view "$validation_run_id" --log-failed`, identify the first platform-owned compile error, add the smallest targeted reproduction available on macOS or in the workflow, fix only that owner layer, rerun affected local checks, commit/push, and dispatch again with `publish_release=false`.

### Task 9: Final review and handoff

**Files:**
- Review all committed and remaining unstaged files.

**Interfaces:**
- Consumes: local and remote verification evidence.
- Produces: an evidence-backed completion report.

- [ ] **Step 1: Freeze and inspect the final tree identity**

Run: `git rev-parse HEAD`, `git status --short`, `git show --stat --oneline HEAD`, and `git diff --check`.

Expected: the pushed commit matches the CI head SHA; remaining dirty files are pre-existing excluded user files, not accidental adaptation output.

- [ ] **Step 2: Report exact results**

Report changed configuration/API areas, local analyze/test/build results, the GitHub Actions run URL and five job conclusions, the skipped release job, and any residual pre-existing test/golden failures not addressed by this compilation task.
