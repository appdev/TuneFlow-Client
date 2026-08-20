# Settings Entry, About, and Update Check Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make “更多” the only mobile path to settings, add an About page, and add an explicit GitHub Release update check with clear success, update, and failure feedback.

**Architecture:** Keep version parsing and GitHub response handling in focused, UI-independent files under `features/more`. Inject the update checker, package metadata loader, and external URI opener into the UI/router boundary so tests never use the network, platform package APIs, or a real browser. Preserve the desktop settings branch and route mobile About under `/more`.

**Tech Stack:** Flutter, Dart, `go_router`, `http`, `package_info_plus`, `url_launcher`, `shadcn_ui`, `flutter_test`.

## Global Constraints

- Mobile settings must be reachable only through bottom Tab “更多 → 设置”; remove the Home and Search settings controls.
- Desktop sidebar “设置” remains unchanged and reachable.
- Check only the latest non-draft, non-prerelease GitHub Release through `GET https://api.github.com/repos/appdev/TuneFlow-Client/releases/latest`.
- Do not add background checks, downloads, installation, prerelease checks, tag checks, tokens, or polling.
- Use the existing Lucide icon family and existing TuneFlow design components; do not add another icon library.
- All icon-only controls require at least a 44 px target plus Chinese semantics and tooltip.
- Preserve unrelated dirty-worktree changes, especially the current edits in `lib/features/search/search_screen.dart`, `test/features/search/search_screen_test.dart`, player files, and generated failure artifacts.
- Do not commit unless the user separately authorizes Git commits; checkpoint with `git diff` and test evidence instead.

---

## File Map

- Create `lib/features/more/app_update.dart`: immutable version and update-result domain types plus strict version parsing/update ordering.
- Create `lib/features/more/github_update_checker.dart`: GitHub REST request, response validation, package metadata loading, and update-result construction.
- Create `lib/features/more/about_screen.dart`: project description, installed version, repository links, and link failure feedback.
- Modify `lib/features/more/more_screen.dart`: add About and Check Update entries, async busy state, result sheets, and release-link handoff.
- Modify `lib/app/app.dart`: own production `http.Client`, `PackageInfo.fromPlatform`, and `launchUrl` adapters through Riverpod providers.
- Modify `lib/app/app_router.dart`: inject the adapters, remove Home/Search settings callbacks, add `/more/about`, and wire More actions.
- Modify `lib/features/home/home_screen.dart`: remove all Home settings shortcuts/callback plumbing while preserving all other Home actions.
- Modify `lib/features/search/search_screen.dart`: remove only `onSettings` and `_MobileSearchMasthead`’s settings icon; preserve the user’s unrelated search history/results edits.
- Modify `pubspec.yaml` and `pubspec.lock`: declare `package_info_plus` and `url_launcher` as direct dependencies.
- Create `test/features/more/app_update_test.dart`: version parsing and comparison coverage.
- Create `test/features/more/github_update_checker_test.dart`: GitHub request/response and result coverage with `MockClient`.
- Create `test/features/more/about_screen_test.dart`: content, version loading, and external-link delegation coverage.
- Modify `test/features/more/more_screen_test.dart`: About/check-update entries, busy state, and result UI coverage.
- Modify `test/features/home/home_screen_test.dart`, `test/features/search/search_screen_test.dart`, `test/visual/high_fidelity_gallery_test.dart`, and `test/app/app_shell_test.dart`: update constructor call sites and verify entry consolidation/navigation.

---

### Task 1: Version Domain and GitHub Update Checker

**Files:**

- Create: `lib/features/more/app_update.dart`
- Create: `lib/features/more/github_update_checker.dart`
- Create: `test/features/more/app_update_test.dart`
- Create: `test/features/more/github_update_checker_test.dart`

**Interfaces:**

- Produces: `AppVersion.parse(String)`, `AppVersion.fromPackage({required String version, required String buildNumber})`, `AppVersion.isNewerThan(AppVersion installed)`, and `AppVersion.label`.
- Produces: sealed `UpdateCheckResult`, `UpdateAvailable`, and `UpToDate` carrying local/latest versions and the validated Release URI.
- Produces: `abstract interface class UpdateChecker { Future<UpdateCheckResult> check(); }`.
- Produces: `GitHubUpdateChecker({required http.Client client, required Future<PackageInfo> Function() loadPackageInfo, Uri? endpoint})`.

- [ ] **Step 1: Add failing version-domain tests**

Create table-driven tests that assert:

```dart
expect(AppVersion.parse('v1.2.3').label, '1.2.3');
expect(AppVersion.parse('1.2.3+4').label, '1.2.3+4');
expect(AppVersion.parse('v1.2.4').isNewerThan(AppVersion.parse('1.2.3+9')), isTrue);
expect(AppVersion.parse('1.2.3+5').isNewerThan(AppVersion.parse('1.2.3+4')), isTrue);
expect(AppVersion.parse('1.2.3').isNewerThan(AppVersion.parse('1.2.3+9')), isFalse);
expect(() => AppVersion.parse('release-latest'), throwsFormatException);
```

Also assert that a candidate with the same core and no build number is not newer than an installed build, while a candidate with a larger build number is newer than an installed version whose package metadata has a smaller build.

- [ ] **Step 2: Run the domain test and verify it fails**

Run:

```sh
flutter test test/features/more/app_update_test.dart
```

Expected: FAIL because `app_update.dart` and `AppVersion` do not exist.

- [ ] **Step 3: Implement strict version and result types**

Use a full-match parser equivalent to:

```dart
final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(input.trim());
if (match == null) throw FormatException('Unsupported app version', input);
```

Store numeric `major`, `minor`, `patch`, and nullable `build`. `isNewerThan(installed)` compares core fields first; for equal core versions, a candidate without a build is not newer, while a candidate build is compared with `installed.build ?? 0`. Define results with exact fields:

```dart
sealed class UpdateCheckResult {
  const UpdateCheckResult({required this.local, required this.latest, required this.releaseUri});
  final AppVersion local;
  final AppVersion latest;
  final Uri releaseUri;
}

final class UpdateAvailable extends UpdateCheckResult { const UpdateAvailable({required super.local, required super.latest, required super.releaseUri}); }
final class UpToDate extends UpdateCheckResult { const UpToDate({required super.local, required super.latest, required super.releaseUri}); }
```

- [ ] **Step 4: Run the domain tests and verify they pass**

Run the Task 1 domain test command again. Expected: PASS.

- [ ] **Step 5: Add failing GitHub checker tests**

Use `http/testing.dart` `MockClient` and a loader returning `PackageInfo(appName: 'TuneFlow', packageName: 'musicfree_service_client', version: '1.0.4', buildNumber: '5')`. Cover:

```dart
// 200, tag_name v1.0.5+6, valid HTTPS html_url -> UpdateAvailable
// 200, tag_name v1.0.4, valid HTTPS html_url -> UpToDate
// request path is /repos/appdev/TuneFlow-Client/releases/latest
// Accept is application/vnd.github+json and X-GitHub-Api-Version is present
// 403/404/500 -> UpdateCheckException
// malformed JSON, missing tag_name/html_url, non-HTTPS html_url -> UpdateCheckException
// unparsable tag_name -> UpdateCheckException
```

- [ ] **Step 6: Run checker tests and verify they fail**

Run:

```sh
flutter test test/features/more/github_update_checker_test.dart
```

Expected: FAIL because `GitHubUpdateChecker` is undefined.

- [ ] **Step 7: Implement the checker**

Send one GET request with headers:

```dart
const {
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
}
```

Decode only a JSON object; require non-empty string `tag_name`, parseable HTTPS `html_url`, and a successful 2xx status. Convert all transport, status, decode, shape, URI, and remote-version errors to an `UpdateCheckException` with a safe Chinese-facing fallback such as `暂时无法检查更新，请稍后重试。`; never include the response body. Load package info, combine `version` and numeric `buildNumber` only when the version does not already contain `+`, and return `UpdateAvailable` only when `latest.isNewerThan(local)` is true.

- [ ] **Step 8: Run both Task 1 suites**

Run:

```sh
flutter test test/features/more/app_update_test.dart test/features/more/github_update_checker_test.dart
```

Expected: PASS.

- [ ] **Step 9: Review Task 1 checkpoint without committing**

Run `git diff --check` and inspect `git diff -- lib/features/more/app_update.dart lib/features/more/github_update_checker.dart test/features/more/app_update_test.dart test/features/more/github_update_checker_test.dart`. Do not commit without separate authorization.

---

### Task 2: About Page and External Link Boundary

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/more/about_screen.dart`
- Create: `test/features/more/about_screen_test.dart`

**Interfaces:**

- Consumes: `AppVersion.fromPackage(...)` from Task 1.
- Produces: `typedef AppPackageInfoLoader = Future<PackageInfo> Function()`.
- Produces: `typedef ExternalUriOpener = Future<bool> Function(Uri uri)`.
- Produces: `AboutScreen({required AppPackageInfoLoader loadPackageInfo, required ExternalUriOpener openExternalUri})`.

- [ ] **Step 1: Declare direct runtime dependencies**

Run:

```sh
flutter pub add package_info_plus url_launcher
```

Expected: `pubspec.yaml` lists both under `dependencies`, and `pubspec.lock` resolves platform implementations compatible with Dart `^3.9.0`. Do not manually upgrade unrelated packages.

- [ ] **Step 2: Add failing About screen tests**

Pump `AboutScreen` with a fake package loader and an opener that records URIs. Assert:

```dart
expect(find.byKey(const Key('about-screen')), findsOneWidget);
expect(find.text('TuneFlow · 音流'), findsOneWidget);
expect(find.textContaining('跨平台音乐客户端'), findsOneWidget);
expect(find.text('版本 1.0.4+5'), findsOneWidget);
expect(find.text('https://github.com/appdev/TuneFlow-Client'), findsOneWidget);
expect(find.text('https://github.com/appdev/TuneFlow'), findsOneWidget);
```

Tap keys `about-client-repository` and `about-service-repository`; assert the exact HTTPS URIs were passed to the opener. Add a test where the opener returns `false` and assert the UI shows `无法打开链接`.

- [ ] **Step 3: Run the About test and verify it fails**

Run:

```sh
flutter test test/features/more/about_screen_test.dart
```

Expected: FAIL because `AboutScreen` does not exist.

- [ ] **Step 4: Implement the About page**

Build a scrollable, token-based page using `AppMobilePageHeader`, the TuneFlow asset, existing surface/card patterns, and Lucide `externalLink` glyphs. Use a `FutureBuilder<PackageInfo>` for the installed version, displaying `版本读取失败` if the platform loader fails. Include the approved project description and legal/self-hosting note verbatim in meaning. Use 44 px minimum link rows with Chinese semantics/tooltip. When the opener returns false or throws, call:

```dart
showAppMessage(
  context,
  title: '无法打开链接',
  message: '请稍后重试，或复制项目地址到浏览器打开。',
  destructive: true,
);
```

- [ ] **Step 5: Run About tests and verify they pass**

Run the Task 2 test command again. Expected: PASS.

- [ ] **Step 6: Review Task 2 checkpoint without committing**

Run `dart format lib/features/more/about_screen.dart test/features/more/about_screen_test.dart`, `git diff --check`, and inspect only Task 2 paths. Do not commit without separate authorization.

---

### Task 3: More Page Update Interaction

**Files:**

- Modify: `lib/features/more/more_screen.dart`
- Modify: `test/features/more/more_screen_test.dart`

**Interfaces:**

- Consumes: `UpdateChecker`, `UpdateAvailable`, `UpToDate`, and `ExternalUriOpener` from Tasks 1–2.
- Produces: `MoreScreen` constructor additions `required VoidCallback onAbout`, `required UpdateChecker updateChecker`, and `required ExternalUriOpener openExternalUri`.

- [ ] **Step 1: Add failing More page tests**

Extend the existing harness and constructor calls with fakes. Assert:

```dart
expect(find.byKey(const Key('more-settings')), findsOneWidget);
expect(find.byKey(const Key('more-about')), findsOneWidget);
expect(find.byKey(const Key('more-check-update')), findsOneWidget);
```

Cover these behaviors:

- Tapping About calls `onAbout` exactly once.
- A pending checker changes the update row text to `正在检查更新…` and a second tap does not invoke the checker again.
- `UpToDate` shows `已是最新版本` and the local version.
- `UpdateAvailable` shows local/latest versions and `前往下载`; choosing it passes `releaseUri` to the opener.
- `UpdateCheckException` shows `检查更新失败` and the safe fallback.
- A failed release-page opener shows `无法打开下载页面`.

- [ ] **Step 2: Run the More test and verify it fails**

Run:

```sh
flutter test test/features/more/more_screen_test.dart
```

Expected: FAIL because constructor fields and new entries do not exist.

- [ ] **Step 3: Implement More as a stateful async owner**

Convert `MoreScreen` to `StatefulWidget` and add `_checkingUpdate`. In `_checkForUpdate`, return immediately when busy, set busy before awaiting, and clear it in `finally` only when mounted. Use `AppBottomSheet.showActions<bool>` for update results:

```dart
// Up to date: title “已是最新版本”; one “知道了” action or dismiss.
// Available: title “发现新版本”; message includes local/latest;
//            one keyed action `more-open-release`, label “前往下载”.
// Failure: `showAppMessage(... destructive: true)`.
```

Order normal entries as 下载管理、音源管理、设置、关于、检查更新, then keep disconnect and Service state. Give About and Check Update Lucide icons only if the existing tile style is updated consistently for every row; otherwise retain the current text-and-chevron style to avoid a partial visual family.

- [ ] **Step 4: Run More tests and verify they pass**

Run the Task 3 test command again. Expected: PASS.

- [ ] **Step 5: Review Task 3 checkpoint without committing**

Run `dart format` on both Task 3 paths, `git diff --check`, and inspect the focused diff. Do not commit without separate authorization.

---

### Task 4: Router Wiring and Settings-Entry Consolidation

**Files:**

- Modify: `lib/app/app.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/search/search_screen.dart`
- Modify: `test/features/home/home_screen_test.dart`
- Modify: `test/features/search/search_screen_test.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**

- Consumes: `GitHubUpdateChecker`, `UpdateChecker`, `AppPackageInfoLoader`, `ExternalUriOpener`, and `AboutScreen`.
- Produces: router branch name `more-about` at `/more/about`.
- Changes: `HomeScreen` no longer accepts `onSettings`; `SearchScreen` no longer accepts `onSettings`.

- [ ] **Step 1: Add/adjust failing navigation and entry tests**

Before production edits, update focused assertions:

```dart
// Mobile Home/Search
expect(find.byTooltip('设置'), findsNothing);
expect(find.byKey(const Key('search-settings')), findsNothing);

// More
await tester.tap(find.bySemanticsLabel('更多'));
await tester.tap(find.byKey(const Key('more-settings')));
expect(find.byKey(const Key('settings-route')), findsOneWidget);

// About
// Return to More, tap more-about, expect about-screen.

// Desktop
expect(find.text('设置'), findsWidgets);
await tester.tap(find.text('设置').last);
expect(find.byKey(const Key('settings-route')), findsOneWidget);
```

Remove `onSettings` arguments from Home/Search test call sites, including the visual gallery. In the dirty Search test file, change only constructor arguments and assertions related to the removed control.

- [ ] **Step 2: Run focused UI tests and verify they fail**

Run:

```sh
flutter test test/features/home/home_screen_test.dart test/features/search/search_screen_test.dart test/app/app_shell_test.dart
```

Expected: FAIL because current screens still expose settings callbacks/buttons and `/more/about` is absent.

- [ ] **Step 3: Remove Home settings plumbing**

Delete `HomeScreen.onSettings`, `_WideHome.onSettings`, `_WideHero.onSettings`, `_MobileHome.onSettings`, `_MobileHomeMasthead.onSettings`, the `home-settings` hidden shortcut, and the mobile settings `IconButton`. Keep Home search, playlists, downloads, player, timestamp, and all existing responsive behavior unchanged.

- [ ] **Step 4: Remove Search settings plumbing without disturbing user edits**

Delete `SearchScreen.onSettings`, remove the argument passed to `_MobileSearchMasthead`, and simplify `_MobileSearchMasthead` to brand logo plus title with no trailing settings surface. Do not alter the existing `TapRegion`/`ShadPortal` history dropdown work, playback behavior, result layout, or unrelated Search tests.

- [ ] **Step 5: Add production providers/adapters**

In `app.dart`, create providers with lifecycle ownership:

```dart
final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GitHubUpdateChecker(client: client, loadPackageInfo: PackageInfo.fromPlatform);
});

final externalUriOpenerProvider = Provider<ExternalUriOpener>(
  (_) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
```

Pass these plus `PackageInfo.fromPlatform` into `buildAppRouter`. Do not initiate any request in a provider constructor.

- [ ] **Step 6: Wire routes and More actions**

Extend `buildAppRouter` with required `UpdateChecker updateChecker`, `AppPackageInfoLoader loadPackageInfo`, and `ExternalUriOpener openExternalUri`. Remove `openSettings` if no remaining caller needs responsive redirection; keep the desktop `/settings` branch intact. In `/more`, pass `onAbout: () => context.pushNamed('more-about')` and the injected dependencies. Add:

```dart
GoRoute(
  path: 'about',
  name: 'more-about',
  builder: (context, state) => AboutScreen(
    loadPackageInfo: loadPackageInfo,
    openExternalUri: openExternalUri,
  ),
),
```

Do not add About to the desktop sidebar; this feature remains under mobile More as approved.

- [ ] **Step 7: Run focused UI and visual-constructor tests**

Run:

```sh
flutter test test/features/home/home_screen_test.dart test/features/search/search_screen_test.dart test/features/more/about_screen_test.dart test/features/more/more_screen_test.dart test/app/app_shell_test.dart test/visual/high_fidelity_gallery_test.dart
```

Expected: PASS.

- [ ] **Step 8: Verify icon and navigation constraints**

Run:

```sh
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
rg -n "home-settings|search-settings|tooltip: '设置'|onSettings" lib/features/home lib/features/search --glob '*.dart'
```

Expected: first and third commands return no matches; direct Material glyph matches remain only in `lib/design/components/app_playback_button.dart`.

- [ ] **Step 9: Review Task 4 checkpoint without committing**

Run `dart format` on changed Dart paths and inspect `git diff` carefully, especially the pre-existing Search diff. Confirm no user-owned history dropdown or playback changes were reverted. Do not commit without separate authorization.

---

### Task 5: Final Integration Verification and Handoff

**Files:**

- Verify all files changed by Tasks 1–4.

**Interfaces:**

- Consumes the complete approved implementation.
- Produces test, analysis, dependency, icon-policy, and final-diff evidence.

- [ ] **Step 1: Run all feature-focused tests**

Run:

```sh
flutter test test/features/more/app_update_test.dart test/features/more/github_update_checker_test.dart test/features/more/about_screen_test.dart test/features/more/more_screen_test.dart test/features/home/home_screen_test.dart test/features/search/search_screen_test.dart test/app/app_shell_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run project-required icon suites and scans**

Run:

```sh
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: both suites PASS; the Lucide transport scan returns no matches; raw Material glyphs appear only in `lib/design/components/app_playback_button.dart`.

- [ ] **Step 3: Run static analysis**

Run:

```sh
flutter analyze
```

Expected: exit 0 with no new analyzer issues. If unrelated pre-existing issues appear, record exact paths/messages and prove they are outside this diff.

- [ ] **Step 4: Inspect the final frozen diff and worktree**

Run:

```sh
git diff --check
git status --short
git diff --stat
git diff -- pubspec.yaml lib/app/app.dart lib/app/app_router.dart lib/features/home/home_screen.dart lib/features/search/search_screen.dart lib/features/more test/features/more test/features/home/home_screen_test.dart test/features/search/search_screen_test.dart test/app/app_shell_test.dart test/visual/high_fidelity_gallery_test.dart
```

Confirm there are no secrets, response dumps, debug prints, unrelated refactors, accidental generated files, or reversions of user-owned changes. Do not include `android/build/`, the HPROF file, failure screenshots, or unrelated docs in this feature’s handoff.

- [ ] **Step 5: Report the evidence-backed result**

Lead with the behavior delivered, list exact files/areas changed, report every verification command and outcome, identify any pre-existing failures separately, and state that changes remain uncommitted unless the user later authorizes a commit.
