# TuneFlow Client Build Workflow Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and upload Android, iOS, macOS, Windows, and Linux TuneFlow client artifacts in GitHub Actions, with Android Release APK signing supplied only through GitHub Secrets.

**Architecture:** A single matrix-style workflow uses native runners for each platform. Android signing is configured through a temporary `key.properties` file backed by encrypted GitHub Secrets; Apple builds explicitly produce unsigned artifacts.

**Tech Stack:** Flutter, Gradle Kotlin DSL, GitHub Actions, GitHub CLI

## Global Constraints

- Android produces only a signed Release APK, never an AAB.
- iOS and macOS artifacts are unsigned.
- Workflow artifacts are uploaded to Actions and do not create a GitHub Release.
- No signing secret or keystore content is committed or printed.

---

### Task 1: Freeze the build contract

**Files:**
- Modify: `test/branding/five_platform_build_contract_test.dart`

- [ ] Expand the test to require Android APK signing, unsigned iOS/macOS builds, Windows/Linux Release builds, and five artifact uploads.
- [ ] Run the focused test and confirm it fails against the current desktop-only workflow.

### Task 2: Configure Android Release signing

**Files:**
- Modify: `android/app/build.gradle.kts`
- Verify: `android/.gitignore`

- [ ] Load `android/key.properties` only when present and define a Release signing config without a debug-key fallback.
- [ ] Assign the Release build type to that signing config.

### Task 3: Implement the five-platform workflow

**Files:**
- Replace: `.github/workflows/flutter-desktop-platforms.yml`
- Create: `.github/workflows/build-clients.yml`

- [ ] Add Android signed APK build and artifact upload.
- [ ] Add iOS and macOS unsigned Release builds and artifact uploads.
- [ ] Add Windows and Linux Release builds and artifact uploads.
- [ ] Run the focused contract test and static analysis.

### Task 4: Store secrets and verify GitHub execution

**External state:**
- GitHub repository secrets in `appdev/TuneFlow-Client`

- [ ] Store the base64 JKS, store password, key alias, and key password with `gh secret set`.
- [ ] Commit and push the workflow changes.
- [ ] Trigger `workflow_dispatch` and inspect all five jobs and artifact names.
