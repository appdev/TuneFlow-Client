# TuneFlow Client Build and Release Workflow Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the five-platform TuneFlow workflow manually triggered only and publish one GitHub Release after every platform build succeeds.

**Architecture:** Keep the five native build jobs and their Actions Artifacts. Add one dependent Ubuntu release job that derives `v<version>` from `pubspec.yaml`, rejects an existing tag or release, downloads all five artifacts, and creates a non-draft, non-prerelease GitHub Release with the packaged files.

**Tech Stack:** Flutter, Dart contract tests, GitHub Actions, GitHub CLI

## Global Constraints

- The only workflow trigger is `workflow_dispatch`.
- Android produces only a signed Release APK, never an AAB.
- iOS and macOS artifacts remain unsigned.
- The release tag and title are the complete `pubspec.yaml` version prefixed with `v`, for example `v1.0.0+1`.
- A release is created only after Android, iOS, macOS, Windows, and Linux all succeed.
- Existing tags and releases are never overwritten.
- No signing secret or keystore content is committed or printed.

---

### Task 1: Extend the build and release contract

**Files:**
- Modify: `test/branding/five_platform_build_contract_test.dart`
- Test: `test/branding/five_platform_build_contract_test.dart`

**Interfaces:**
- Consumes: `.github/workflows/build-clients.yml` as text.
- Produces: a regression contract for the manual trigger and release job.

- [x] **Step 1: Add failing expectations**

Require the workflow to contain `workflow_dispatch`, omit `push:` and `pull_request:`, grant `contents: write`, define a release job with `needs: [android, ios, macos, windows, linux]`, parse the first `version:` value from `pubspec.yaml`, reject existing tags/releases, download five artifacts, and call `gh release create` with five packaged assets.

- [x] **Step 2: Verify the contract fails before implementation**

Run:

```bash
flutter test test/branding/five_platform_build_contract_test.dart
```

Expected: FAIL because the current workflow still has automatic triggers, read-only contents permission, and no release job.

### Task 2: Implement manual build and atomic release

**Files:**
- Modify: `.github/workflows/build-clients.yml`
- Test: `test/branding/five_platform_build_contract_test.dart`

**Interfaces:**
- Consumes: `pubspec.yaml` `version`, five named Actions Artifacts, and `GITHUB_TOKEN` supplied by Actions.
- Produces: tag and GitHub Release `v<pubspec-version>` with five build files.

- [x] **Step 1: Restrict the trigger and permission**

Keep only the manual trigger and preserve the read-only default:

```yaml
on:
  workflow_dispatch:

permissions:
  contents: read
```

Remove the Android pull-request condition because pull requests can no longer trigger the workflow. Grant `contents: write` only inside the release job.

- [x] **Step 2: Add the dependent release job**

Define `release.needs` as all five platform jobs and run it on `ubuntu-latest`. Check out the exact workflow commit, derive `RELEASE_TAG=v<version>` from `pubspec.yaml`, fail when either `refs/tags/$RELEASE_TAG` or a GitHub Release already exists, and download all build artifacts into `release-assets` with merge enabled.

- [x] **Step 3: Validate and publish the five assets**

Require these exact files before publishing:

```text
app-release.apk
tuneflow-ios-unsigned.zip
tuneflow-macos-unsigned.zip
tuneflow-windows.zip
tuneflow-linux.tar.gz
```

Create a normal release with `gh release create "$RELEASE_TAG" release-assets/* --target "$GITHUB_SHA" --title "$RELEASE_TAG" --generate-notes`.

- [x] **Step 4: Verify the focused contract passes**

Run:

```bash
flutter test test/branding/five_platform_build_contract_test.dart
```

Expected: PASS.

### Task 3: Review, commit, and push

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-client-build-workflow-design.md`
- Modify: `docs/superpowers/plans/2026-08-13-client-build-workflow.md`
- Modify: `.github/workflows/build-clients.yml`
- Modify: `test/branding/five_platform_build_contract_test.dart`

**Interfaces:**
- Consumes: the final diff and focused test result.
- Produces: one reviewed commit on the current branch pushed to `origin`.

- [x] **Step 1: Check the frozen diff**

Run `git diff --check`, inspect `git diff`, and confirm no unrelated or sensitive files are included.

- [ ] **Step 2: Run final verification**

Run:

```bash
flutter test test/branding/five_platform_build_contract_test.dart
```

Expected: PASS on the same tree that will be committed.

- [ ] **Step 3: Commit the approved files**

Stage only the four files listed above and commit with:

```text
ci: publish manual client releases
```

- [ ] **Step 4: Push the current branch**

Push the current branch to `origin`, then verify the local branch is synchronized with its upstream. Do not manually dispatch the workflow; publishing a Release remains a separate external action initiated through `workflow_dispatch`.
