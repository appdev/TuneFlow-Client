# Recommendation Home Integration Flutter Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make daily personalized recommendations a first-class part of the Flutter Home experience on macOS, Android, and Web, while exposing MusicBrainz endpoint controls in settings and retaining the full recommendation page as a secondary route.

**Architecture:** The Service remains the sole owner of recommendation generation and daily consistency. Flutter models the extended daily contract, keeps its existing per-Service display cache only as a fast/offline presentation layer, and lets `HomeController` coordinate a shared recommendation controller for the Home lifecycle. Home renders a responsive recommendation section and dynamic hero; settings edits and tests the MusicBrainz base URL; primary recommendation navigation is removed without deleting the full detail route.

**Tech Stack:** Flutter/Dart, shadcn_ui, Lucide icons, go_router, existing repository/controller patterns, flutter_test.

## Global Constraints

- Preserve all pre-existing tracked and untracked changes; this repository is already dirty and already contains uncommitted recommendation work.
- Do not commit, push, deploy, regenerate unrelated goldens, or change Service code from this repository plan.
- Start this plan only after the Service contract in `/Volumes/ext/lx-music-server-web/docs/superpowers/plans/2026-08-30-musicbrainz-personal-recommendation.md` has been frozen and its route tests pass.
- The Service owns one daily snapshot shared by all clients. Flutter must never generate recommendations locally or vary the list per platform.
- A client cache hit may render immediately, but Flutter must still make one cheap daily Service read so it can learn about a manual refresh performed by another client. The read must not cause regeneration when the Service already has today's snapshot.
- Manual refresh is the only Flutter action that calls the refresh endpoint.
- Preserve the full recommendation screen as a secondary route reachable from Home, but remove it from desktop primary navigation and the mobile discovery tab set.
- Home card counts: 6 on narrow/mobile layouts, 8 on medium/tablet layouts, and 10 on desktop layouts.
- The Home hero prefers unfinished playback; otherwise it uses the first visible daily recommendation.
- Follow `design.md` and the repository icon rules: Lucide for ordinary actions, shared Material Rounded abstraction for transport controls, 44 px icon targets, Chinese labels/tooltips.
- Treat the approved Service design as normative: `/Volumes/ext/lx-music-server-web/docs/superpowers/specs/2026-08-30-musicbrainz-personal-recommendation-home-design.md`.

---

## Task 1: Adopt the Frozen Service Contract

**Files:**

- Modify: `lib/features/recommendations/recommendation_models.dart`
- Modify: `lib/features/recommendations/recommendation_repository.dart`
- Modify: `lib/features/settings/service_settings_repository.dart`
- Test: `test/features/recommendations/recommendation_repository_test.dart`
- Test: `test/features/settings/service_settings_repository_test.dart`

- [ ] Add `stale` and `disabled` to the recommendation status model and parse `snapshotLocalDate` and `lastErrorCode` defensively.
- [ ] Define complete/displayable semantics so `ready`, `degraded`, and `stale` with a version can be cached and displayed; `warming`, `generating`, and `disabled` are not written as complete snapshots.
- [ ] Extend `ServiceFunctionSettings` with `musicBrainzBaseUrl`, defaulting to the official URL only when the Service response omits the field; preserve an explicit empty string as disabled.
- [ ] Add a typed repository method for `POST /api/v1/recommendations/musicbrainz/test` and map its stable diagnostic fields without surfacing raw network bodies.
- [ ] Do not add a platform-specific source of truth or a local recommendation algorithm.

```dart
enum RecommendationStatus {
  warming,
  generating,
  ready,
  degraded,
  stale,
  disabled,
}

bool get isDisplayable =>
    version != null &&
    const {
      RecommendationStatus.ready,
      RecommendationStatus.degraded,
      RecommendationStatus.stale,
    }.contains(status);
```

```dart
class MusicBrainzConnectionTestResult {
  const MusicBrainzConnectionTestResult({
    required this.ok,
    required this.normalizedBaseUrl,
    required this.errorCode,
  });

  final bool ok;
  final String normalizedBaseUrl;
  final String? errorCode;
}
```

```dart
test('preserves an explicit empty MusicBrainz URL', () async {
  server.enqueueJson({'recommendation.musicBrainzBaseUrl': ''});
  final settings = await repository.loadFunctionSettings();
  expect(settings.musicBrainzBaseUrl, isEmpty);
});
```

- [ ] Run:

```sh
flutter test \
  test/features/recommendations/recommendation_repository_test.dart \
  test/features/settings/service_settings_repository_test.dart
```

## Task 2: Extend Recommendation Controller State Without Changing Service Ownership

**Files:**

- Modify: `lib/features/recommendations/recommendation_controller.dart`
- Modify: `lib/features/recommendations/recommendation_models.dart`
- Test: `test/features/recommendations/recommendation_controller_test.dart`
- Test: `test/features/recommendations/recommendation_test_data.dart`

- [ ] Keep the existing per-Service-origin display cache and emit it before the daily network response when available.
- [ ] Always perform one daily read per controller load/invalidation, even after a client cache hit; rely on the Service's stable snapshot contract to make that read cheap.
- [ ] Replace cached content only when the Service returns a displayable snapshot with a different date/version or changed feedback-filtered items.
- [ ] Preserve visible cached items when a transient request fails. If the returned status is `stale`, show the Service-provided stale snapshot and its date rather than presenting a generic error.
- [ ] Represent `disabled` as an intentional empty state with a settings action, not as a retrying failure.
- [ ] Keep refresh explicit: one call to the refresh endpoint, then adopt the returned/new daily version; never auto-refresh because the screen rebuilt.
- [ ] Keep recommendation events/SSE invalidation idempotent so Home and the secondary screen do not issue refresh calls.

```dart
Future<void> load() async {
  final cached = await repository.readCachedDaily();
  if (cached?.isDisplayable == true) _adopt(cached!);

  try {
    final remote = await repository.fetchDaily();
    _adopt(remote);
    if (remote.isDisplayable) await repository.writeCachedDaily(remote);
  } catch (error) {
    if (state.snapshot == null) _setLoadError(error);
  }
}
```

```dart
test('cache renders first but daily endpoint is still checked once', () async {
  repository.cached = recommendationSnapshot(version: 3);
  repository.daily = recommendationSnapshot(version: 3);
  await controller.load();
  expect(repository.fetchDailyCalls, 1);
  expect(controller.state.snapshot?.version, 3);
});
```

- [ ] Run:

```sh
flutter test test/features/recommendations/recommendation_controller_test.dart
```

## Task 3: Add MusicBrainz Controls to Service Function Settings

**Files:**

- Modify: `lib/features/settings/service_function_settings_controller.dart`
- Modify: `lib/features/settings/service_function_settings_screen.dart`
- Test: `test/features/settings/service_function_settings_controller_test.dart`
- Create: `test/features/settings/service_function_settings_screen_test.dart`

- [ ] Add a MusicBrainz URL editor below the existing daily recommendation/time-zone controls.
- [ ] Provide Chinese helper text explaining that the official service is the default, a compatible self-hosted/third-party `/ws/2/` endpoint may be used, and clearing the field disables recommendations.
- [ ] Add ordinary Lucide actions for “测试连接”, “恢复官方地址”, and “关闭推荐/清空地址” with minimum 44 px targets where icon-only.
- [ ] Test the draft URL without saving it first. On success, replace the editor value with the normalized URL returned by the Service; on failure, map the stable error code to concise Chinese UI text.
- [ ] Save the MusicBrainz field and time zone in the same existing settings transaction/update path. Preserve explicit empty string.
- [ ] Avoid live MusicBrainz calls in widget/controller tests by faking the Service repository.

```dart
Future<void> testMusicBrainzConnection() async {
  final result = await repository.testMusicBrainzConnection(
    musicBrainzBaseUrlController.text,
  );
  if (result.ok) {
    musicBrainzBaseUrlController.text = result.normalizedBaseUrl;
  }
  state = state.copyWith(connectionTest: result);
}
```

```dart
testWidgets('clearing the address saves recommendation disabled state', (tester) async {
  await pumpFunctionSettings(tester, musicBrainzBaseUrl: officialUrl);
  await tester.enterText(find.byKey(const Key('musicbrainz-url-field')), '');
  await tester.tap(find.text('保存'));
  expect(repository.saved.musicBrainzBaseUrl, isEmpty);
});
```

- [ ] Run:

```sh
flutter test \
  test/features/settings/service_function_settings_controller_test.dart \
  test/features/settings/service_function_settings_screen_test.dart
```

## Task 4: Make Home Own the Recommendation Lifecycle

**Files:**

- Modify: `lib/features/home/home_controller.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/app/runtime_providers.dart` only if repository/controller construction already belongs there
- Test: `test/features/home/home_controller_test.dart`

- [ ] Inject a `RecommendationController` into `HomeController`, register one listener, and forward meaningful state changes through the Home controller.
- [ ] Load recommendations alongside existing Home resources without allowing a recommendation error to fail playlists, downloads, library, or playback-history loading.
- [ ] Dispose the nested controller/listener exactly once with Home.
- [ ] Expose the nested state and explicit operations needed by the UI: load, refresh, feedback, play context, and retry. Do not duplicate recommendation state inside Home.
- [ ] Construct the controller from the same authenticated Service client/origin used by the secondary recommendation route so both consume the same server snapshot and cache namespace.

```dart
class HomeController extends ChangeNotifier {
  HomeController({required this.recommendations}) {
    recommendations.addListener(_onRecommendationsChanged);
  }

  final RecommendationController recommendations;

  void _onRecommendationsChanged() => notifyListeners();

  @override
  void dispose() {
    recommendations.removeListener(_onRecommendationsChanged);
    recommendations.dispose();
    super.dispose();
  }
}
```

```dart
test('recommendation failure does not hide other home content', () async {
  recommendations.failDaily();
  await controller.load();
  expect(controller.playlists, isNotEmpty);
  expect(controller.recommendations.state.hasError, isTrue);
});
```

- [ ] Run:

```sh
flutter test test/features/home/home_controller_test.dart
```

## Task 5: Merge Recommendations Into the Responsive Home UI

**Files:**

- Modify: `lib/features/home/home_screen.dart`
- Create: `lib/features/home/home_recommendation_section.dart`
- Modify: `lib/features/recommendations/recommendation_screen.dart` only to reuse extracted presentation pieces rather than duplicate them
- Test: `test/features/home/home_screen_test.dart`
- Test: `test/features/recommendations/recommendation_screen_test.dart`

- [ ] Add a dynamic hero decision function: unfinished playback with a resumable track wins; otherwise the first visible recommendation is used; if neither exists, retain the current neutral Home hero/fallback.
- [ ] Render a “每日推荐” Home section with 6/8/10 visible cards according to the existing responsive breakpoints for narrow/medium/desktop layouts.
- [ ] Reuse one recommendation card/presentation component between Home and the full screen where practical. Keep item IDs and playback context so play events continue to record `recommendationItemId`.
- [ ] Provide section actions for explicit refresh and “查看全部”. Refresh must call the recommendation refresh endpoint once; “查看全部” opens the secondary route.
- [ ] Preserve existing feedback controls. A disliked item disappears immediately because controller state reflects the Service's feedback-filtered view.
- [ ] Render bounded states locally inside the section: skeleton/progress for warming/generating, stale date notice, degraded notice, disabled-with-settings action, and retryable error. Do not replace the entire Home screen.
- [ ] Use semantic Chinese labels/tooltips and the existing design tokens. Do not introduce another icon library or raw transport `Icons.*`.

```dart
int homeRecommendationLimit(double width) {
  if (width >= 1200) return 10;
  if (width >= 720) return 8;
  return 6;
}

RecommendationItem? selectRecommendationHero({
  required bool hasUnfinishedPlayback,
  required List<RecommendationItem> recommendations,
}) {
  if (hasUnfinishedPlayback || recommendations.isEmpty) return null;
  return recommendations.first;
}
```

```dart
testWidgets('unfinished playback wins over a daily recommendation hero', (tester) async {
  await pumpHome(
    tester,
    unfinishedTrack: historyTrack,
    recommendations: [recommendedTrack],
  );
  expect(find.text(historyTrack.title), findsWidgets);
  expect(find.byKey(const Key('resume-playback-hero')), findsOneWidget);
});

testWidgets('desktop home shows no more than ten recommendation cards', (tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 960));
  await pumpHome(tester, recommendations: recommendationItems(30));
  expect(find.byKey(const Key('home-recommendation-card')), findsNWidgets(10));
});
```

- [ ] Run:

```sh
flutter test \
  test/features/home/home_screen_test.dart \
  test/features/recommendations/recommendation_screen_test.dart
```

## Task 6: Demote Recommendation Navigation Without Removing the Route

**Files:**

- Modify: `lib/app/app_shell.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/features/discovery/discovery_hub_screen.dart`
- Test: `test/app/app_shell_test.dart`
- Test: `test/app/app_shell_routing_test.dart`
- Test: `test/features/discovery/discovery_hub_screen_test.dart`

- [ ] Remove the desktop primary recommendation destination and its selected-index mapping.
- [ ] Remove the optional recommendation tab from the mobile discovery hub and update tab/controller lengths deterministically.
- [ ] Keep `/recommendations` navigable from the Home “查看全部” action. Prefer retaining it as a hidden shell branch if that is required to preserve the mini-player and existing route state; do not expose a blank primary destination.
- [ ] Add a Home callback/route action for the secondary screen and verify back navigation returns to Home.
- [ ] Update route tests for the new visible destination count and eliminate tests that expect a recommendation primary tab.

```dart
testWidgets('recommendations are absent from primary navigation but reachable from home', (tester) async {
  await pumpApp(tester);
  expect(find.byKey(const Key('primary-recommendations-destination')), findsNothing);
  await tester.tap(find.text('查看全部'));
  expect(find.byType(RecommendationScreen), findsOneWidget);
});
```

- [ ] Run:

```sh
flutter test \
  test/app/app_shell_test.dart \
  test/app/app_shell_routing_test.dart \
  test/features/discovery/discovery_hub_screen_test.dart
```

## Task 7: Visual and Regression Verification

**Files:**

- Review: `design.md`
- Review/update only if behavior intentionally changes: `test/visual/goldens/home-desktop-light.png`
- Review/update only if behavior intentionally changes: `test/visual/goldens/home-desktop-dark.png`
- Review/update only if behavior intentionally changes: Home/settings files under `test/visual/full_goldens/` and `test/visual/design_baselines/`

- [ ] Run formatting only on changed Dart files, then inspect the diff to ensure formatting did not touch unrelated user work.
- [ ] Run all focused recommendation, Home, settings, navigation, and discovery tests from Tasks 1–6 in one frozen-tree pass.
- [ ] Run analyzer on the changed Dart surface using the repository's project-native analyzer command.
- [ ] Run the required icon-system checks because `app_shell.dart` and Home actions change:

```sh
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

The first `rg` command must return no matches. The second may match only `lib/design/components/app_playback_button.dart`.

- [ ] Run the existing Home/settings visual suite at 360×800, 390×844, 1024×768, and 1440×960. Inspect rendered failures before updating any expected image.
- [ ] Update only the intentionally changed Home/settings baselines, then rerun the same visual tests. Do not use a broad golden-update command that rewrites unrelated screens.
- [ ] Run the repository's Flutter Web build as a compatibility check after focused tests pass:

```sh
flutter build web
```

- [ ] Inspect `git diff --check`, `git status --short`, and the final diff. Separate pre-existing modifications from this implementation and report any overlap that had to be merged.

## Completion Gate

- [ ] macOS, Android, and Web all display the Service's same local-date/version snapshot.
- [ ] Opening Home with cached data renders quickly and performs at most one daily read, never an implicit refresh.
- [ ] Manual refresh is explicit and adopts the Service's new version.
- [ ] Home hero priority is unfinished playback, then daily recommendation, then existing fallback.
- [ ] Home shows 6/8/10 cards at the agreed breakpoints and retains recommendation playback/feedback context.
- [ ] Stale, degraded, warming/generating, disabled, and error states remain localized to the recommendation section.
- [ ] MusicBrainz settings can test, normalize, restore official, save custom, and clear/disable the endpoint.
- [ ] Recommendation is absent from desktop primary navigation and mobile discovery tabs but remains reachable as a secondary route.
- [ ] Focused tests, analyzer, icon checks, intentional visual baselines, and `flutter build web` pass, or every unrelated pre-existing failure is documented with evidence.
- [ ] No commit, push, deployment, or unrelated golden regeneration was performed.
