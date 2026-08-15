# Flutter Multi-Source Management and Playback Bundle Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Flutter client configure an ordered set of enabled source scripts and consume Service-selected local-first audio/lyrics/artwork bundles without implementing source fallback itself.

**Architecture:** `SourceRepository` sends complete ordered configurations, `SourcesController` owns optimistic reorder/toggle state with rollback, and the source page renders enabled and disabled sections. Service events invalidate the page route. Playback contract parsing adds optional bundle resources; `PlayerController` applies those resources to the active track before avoiding duplicate lyric requests.

**Tech Stack:** Flutter 3.47-compatible SDK, Dart 3.9+, Riverpod 3, GoRouter 17, Shadcn UI Flutter, `http`, `flutter_test`.

## Global Constraints

- This plan depends on the frozen Service handoff contract in `/Volumes/ext/lx-music-server-web/docs/superpowers/plans/2026-08-15-service-multi-source-fallback.md` Task 9.
- The client configures sources but never retries individual scripts or persists health/order changes based on failures.
- Local audio and existing local `pictureUrl/lyricsUrl` remain preferred.
- `active` remains readable for old Service compatibility but means only priority zero in the new contract.
- Toggling sends the complete ordered ID array; dragging sends once after drop.
- A failed mutation restores prior state and refreshes authoritative Service data.
- Existing Service responses without `enabled`, `priority`, `resources`, or `completeness` remain parseable.
- Do not display upstream URLs, request headers, cookies, lyric bodies in diagnostics, or internal exception messages.
- Preserve unrelated dirty-worktree changes across the Flutter project.
- Do not add a Flutter dependency.
- Commit steps are review boundaries and require explicit commit authorization during execution.
- Authoritative design: `/Volumes/ext/lx-music-server-web/docs/superpowers/specs/2026-08-15-multi-source-fallback-design.md`.

---

## File Structure

**Modify**

- `lib/features/sources/source_repository.dart` — extended source model and ordered configuration API.
- `lib/features/sources/sources_controller.dart` — enabled/disabled projections, mutation serialization, rollback, and reorder.
- `lib/features/sources/sources_screen.dart` — switch, enabled/disabled sections, drag handles, labels, and final-disable confirmation.
- `test/features/sources/{sources_controller_test.dart,sources_screen_test.dart}` — repository/controller/widget behavior.
- `lib/events/event_coordinator.dart` and `test/events/event_coordinator_test.dart` — `sources.*` invalidation.
- `lib/app/runtime_providers.dart`, `lib/app/app.dart`, and `lib/app/app_router.dart` — source version propagation and route recreation.
- `test/app/app_shell_routing_test.dart` — event-driven route refresh.
- `lib/api/models.dart` and `test/api/models_test.dart` — optional playback bundle types.
- `lib/features/player/playback_repository.dart` and `test/features/repositories_test.dart` — same-origin resource contract parsing.
- `lib/features/player/player_controller.dart`, `lib/features/player/player_state.dart`, and `test/features/player/player_controller_test.dart` — apply bundle resources and avoid duplicate lyrics.
- `lib/app/app_error.dart` and `test/app/app_error_test.dart` — safe all-sources-unavailable copy.
- `test/visual/high_fidelity_fixtures.dart` and `test/visual/full_ui_gallery_test.dart` — deterministic source/player visual verification fixtures.

---

### Task 1: Parse and Submit the Ordered Source Contract

**Files:**
- Modify: `lib/features/sources/source_repository.dart`
- Modify: `test/features/sources/sources_controller_test.dart`
- Modify: `test/features/repositories_test.dart`

**Interfaces:**
- Consumes: Service source summaries and `PUT /api/v1/sources/enabled`.
- Produces: `InstalledMusicSource.enabled`, nullable `priority`, and `SourceRepository.configureEnabled`.

- [ ] **Step 1: Add failing model/repository tests**

Test new and legacy summaries:

```dart
final enabled = InstalledMusicSource.fromJson({
  ...source('a', active: true),
  'enabled': true,
  'priority': 0,
});
expect((enabled.enabled, enabled.priority, enabled.active), (true, 0, true));

final legacy = InstalledMusicSource.fromJson(source('a', active: true));
expect((legacy.enabled, legacy.priority), (true, 0));
```

Capture the configuration request and assert method, path, and body:

```dart
expect(request.method, 'PUT');
expect(request.url.path, '/api/v1/sources/enabled');
expect(jsonDecode(request.body), {'sourceIds': ['b', 'a']});
```

- [ ] **Step 2: Run focused tests and confirm failure**

```bash
flutter test test/features/sources/sources_controller_test.dart test/features/repositories_test.dart
```

Expected: FAIL because the fields/method do not exist.

- [ ] **Step 3: Extend `InstalledMusicSource` compatibly**

Add:

```dart
final bool enabled;
final int? priority;
```

Parsing rules:

```dart
final active = json['active'] == true;
final enabled = json['enabled'] is bool ? json['enabled']! as bool : active;
final priority = json['priority'] is int
    ? json['priority']! as int
    : active
    ? 0
    : null;
```

Reject negative priorities and `enabled == false` with non-null priority as `INVALID_RESPONSE`. Preserve providers exactly.

- [ ] **Step 4: Add the complete-array repository mutation**

```dart
Future<List<InstalledMusicSource>> configureEnabled(List<String> sourceIds) async =>
    jsonList(
      await api.request(
        'PUT',
        '/api/v1/sources/enabled',
        body: {'sourceIds': sourceIds},
      ),
      'sources',
    ).map(InstalledMusicSource.fromJson).toList(growable: false);
```

Keep `activate` only if another current consumer still needs the legacy promotion API; the new controller must not call it.

- [ ] **Step 5: Verify Task 1**

```bash
dart format lib/features/sources/source_repository.dart test/features/sources/sources_controller_test.dart test/features/repositories_test.dart
flutter test test/features/sources/sources_controller_test.dart test/features/repositories_test.dart
flutter analyze lib/features/sources/source_repository.dart
```

Expected: PASS and analysis exits 0.

- [ ] **Step 6: Commit when authorized**

```bash
git add lib/features/sources/source_repository.dart test/features/sources/sources_controller_test.dart test/features/repositories_test.dart
git commit -m "feat(sources): read ordered source configuration"
```

### Task 2: Manage Enabled, Disabled, Toggle, and Reorder State

**Files:**
- Modify: `lib/features/sources/sources_controller.dart`
- Modify: `test/features/sources/sources_controller_test.dart`

**Interfaces:**
- Consumes: `SourceRepository.configureEnabled` from Task 1.
- Produces: `SourcesState.enabledSources`, `primarySource`, `disabledSources`, `saving`, `toggle`, and `reorder`.

- [ ] **Step 1: Replace single-active tests with failing ordered-state tests**

Cover sorted projections, enabling at the end, disabling while preserving other order, moving B before A, only one mutation at a time, successful authoritative replacement, and failed mutation rollback followed by GET refresh.

```dart
await controller.reorder(1, 0);
expect(submitted, ['b', 'a']);
expect(controller.state.enabledSources.map((item) => item.id), ['b', 'a']);

await controller.toggle('a', false);
expect(submitted, ['b']);
```

- [ ] **Step 2: Run controller tests and confirm failure**

```bash
flutter test test/features/sources/sources_controller_test.dart
```

Expected: FAIL because state assumes one active source.

- [ ] **Step 3: Define immutable state projections**

```dart
List<InstalledMusicSource> get enabledSources => [
  ...items.where((item) => item.enabled),
]..sort((a, b) => a.priority!.compareTo(b.priority!));

InstalledMusicSource? get primarySource => enabledSources.firstOrNull;
List<InstalledMusicSource> get disabledSources =>
    items.where((item) => !item.enabled).toList(growable: false);
```

Replace `switchingId` with `bool saving` and optional `mutatingId`; keep the last confirmed `items` snapshot during a mutation.

- [ ] **Step 4: Implement one serialized mutation helper**

```dart
Future<void> _saveOrder(List<String> ids, {String? mutatingId}) async {
  if (state.saving) return;
  final previous = state.items;
  state = state.copyWith(
    items: _projectOrder(previous, ids),
    saving: true,
    mutatingId: mutatingId,
    clearError: true,
  );
  notifyListeners();
  try {
    state = state.copyWith(
      items: await repository.configureEnabled(ids),
      saving: false,
      clearMutatingId: true,
    );
  } on Object catch (error) {
    state = state.copyWith(items: previous, saving: false, error: error, clearMutatingId: true);
    notifyListeners();
    await refresh();
    return;
  }
  notifyListeners();
}
```

`toggle(id, true)` appends to enabled IDs; `toggle(id, false)` removes it. `reorder(oldIndex, newIndex)` applies Flutter's removal-index adjustment and submits once.

- [ ] **Step 5: Verify Task 2**

```bash
dart format lib/features/sources/sources_controller.dart test/features/sources/sources_controller_test.dart
flutter test test/features/sources/sources_controller_test.dart
flutter analyze lib/features/sources/sources_controller.dart
```

Expected: PASS.

- [ ] **Step 6: Commit when authorized**

```bash
git add lib/features/sources/sources_controller.dart test/features/sources/sources_controller_test.dart
git commit -m "feat(sources): manage ordered enabled sources"
```

### Task 3: Build the Multi-Source Management UI

**Files:**
- Modify: `lib/features/sources/sources_screen.dart`
- Modify: `test/features/sources/sources_screen_test.dart`
- Test fixture: `test/visual/high_fidelity_fixtures.dart`
- Test: `test/visual/full_ui_gallery_test.dart`

**Interfaces:**
- Consumes: Task 2 controller API.
- Produces: enabled/disabled sections, priority labels, switch actions, drag reorder, and final-disable confirmation.

- [ ] **Step 1: Add failing desktop/mobile widget tests**

Pump the screen at wide and mobile sizes. Assert `首选`, `备用 1`, `未启用音源`, switch state, disabled controls while saving, one reorder callback after drop, and a confirmation dialog before disabling the final source. Confirm cancel sends no request and acceptance sends `[]`.

- [ ] **Step 2: Run widget tests and confirm failure**

```bash
flutter test test/features/sources/sources_screen_test.dart
```

Expected: FAIL because the screen has one “启用” button and no reorder UI.

- [ ] **Step 3: Render the enabled section with stable keys**

Use `ReorderableListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics())` inside the page scroll. Each card key is `ValueKey('enabled-source-${source.id}')`; drag handles use `ReorderableDragStartListener`. Labels are `首选` at index zero and `备用 $index` afterward.

- [ ] **Step 4: Render disabled sources and switches**

Use `ShadSwitch(value: source.enabled, onChanged: state.saving ? null : ...)`. Keep provider/action/quality badges. Replace “当前启用” copy with enabled/disabled and priority copy; do not expose request diagnostics on this configuration page.

- [ ] **Step 5: Confirm disabling the final source**

Use `showShadDialog<bool>` with title `禁用最后一个音源？`, description `在线播放和下载将不可用，本地音乐不受影响。`, cancel `取消`, and confirm `仍要禁用`. Only call `controller.toggle(id, false)` after acceptance.

- [ ] **Step 6: Verify Task 3**

```bash
dart format lib/features/sources/sources_screen.dart test/features/sources/sources_screen_test.dart
flutter test test/features/sources/sources_screen_test.dart
flutter analyze lib/features/sources/sources_screen.dart
```

Run affected visual tests only if fixture compilation or actual source-page layout changed:

```bash
flutter test test/visual/full_ui_gallery_test.dart
```

Expected: component tests PASS; visual test PASS without updating unrelated goldens.

- [ ] **Step 7: Commit when authorized**

```bash
git add lib/features/sources/sources_screen.dart test/features/sources/sources_screen_test.dart test/visual/high_fidelity_fixtures.dart test/visual/full_ui_gallery_test.dart
git commit -m "feat(sources): manage source priority in Flutter"
```

### Task 4: Refresh Source Routes from Service Events

**Files:**
- Modify: `lib/events/event_coordinator.dart`
- Modify: `test/events/event_coordinator_test.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `test/app/app_shell_routing_test.dart`

**Interfaces:**
- Consumes: `sources.updated` domain events.
- Produces: `EventInvalidation.sourcesVersion` and source route recreation.

- [ ] **Step 1: Add failing event and routing tests**

```dart
var sources = 0;
final coordinator = EventCoordinator(
  invalidateSources: () => sources++,
  invalidatePlaylists: () {},
  invalidateDownloads: () {},
  invalidateLibrary: () {},
  invalidatePlaylistDetail: (_) {},
);
coordinator.accept(const DomainEvent(type: 'sources.updated', data: null, sequence: 1));
expect(sources, 1);
```

Add a router test proving the source screen key/controller is recreated after `sourcesVersion` changes.

- [ ] **Step 2: Run tests and confirm failure**

```bash
flutter test test/events/event_coordinator_test.dart test/app/app_shell_routing_test.dart
```

Expected: FAIL because source invalidation is absent.

- [ ] **Step 3: Add source invalidation plumbing**

Add required `invalidateSources` to `EventCoordinator`; invoke it for `event.type.startsWith('sources.')`. Add `sourcesVersion` and `sources()` to `EventInvalidation`, wire the callback in `eventSubscriptionProvider`, and pass `readSourceVersion` through `buildAppRouter`.

- [ ] **Step 4: Key both desktop and mobile source routes**

Construct:

```dart
SourcesScreen(
  key: ValueKey('sources-${readSourceVersion()}'),
  controller: SourcesController(SourceRepository(requireConnected().api)),
)
```

Use the same version in `/sources` and `/more/sources`; source mutation responses already update the current controller, while events cover other clients.

- [ ] **Step 5: Verify Task 4**

```bash
dart format lib/events/event_coordinator.dart test/events/event_coordinator_test.dart lib/app/runtime_providers.dart lib/app/app.dart lib/app/app_router.dart test/app/app_shell_routing_test.dart
flutter test test/events/event_coordinator_test.dart test/app/app_shell_routing_test.dart
flutter analyze lib/events/event_coordinator.dart lib/app/runtime_providers.dart lib/app/app.dart lib/app/app_router.dart
```

Expected: PASS.

- [ ] **Step 6: Commit when authorized**

```bash
git add lib/events/event_coordinator.dart test/events/event_coordinator_test.dart lib/app/runtime_providers.dart lib/app/app.dart lib/app/app_router.dart test/app/app_shell_routing_test.dart
git commit -m "feat(sources): refresh configuration from events"
```

### Task 5: Parse and Apply Playback Resource Bundles

**Files:**
- Modify: `lib/api/models.dart`
- Modify: `test/api/models_test.dart`
- Modify: `lib/features/player/playback_repository.dart`
- Modify: `test/features/repositories_test.dart`
- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/features/player/player_state.dart`
- Modify: `test/features/player/player_controller_test.dart`
- Modify: playback fake resolvers identified by `rg "PlaybackRepository|resolvePlayback" test/features test/visual/high_fidelity_fixtures.dart`

**Interfaces:**
- Consumes: optional Service playback `resources` and `completeness`.
- Produces: `ResolvedPlaybackResources`, `PlaybackBundleCompleteness`, and player state application.

- [ ] **Step 1: Add failing model/repository tests**

Use exact types:

```dart
enum PlaybackBundleCompleteness { complete, mixed, audioOnly }

final class ResolvedPlaybackResources {
  const ResolvedPlaybackResources({this.lyrics, this.lyricsUrl, this.pictureUrl});
  final Lyrics? lyrics;
  final String? lyricsUrl;
  final String? pictureUrl;
}
```

Assert old responses parse with null additions; complete online bundle parses embedded lyrics and same-origin picture; local bundle parses same-origin `lyricsUrl/pictureUrl`; simultaneous `lyrics` and `lyricsUrl` throws `INVALID_RESPONSE`; external/file/authority/query/fragment resource URLs are rejected.

- [ ] **Step 2: Run model/repository tests and confirm failure**

```bash
flutter test test/api/models_test.dart test/features/repositories_test.dart
```

Expected: FAIL because resource bundle fields are absent.

- [ ] **Step 3: Extend `ResolvedTrack` with strict optional parsing**

```dart
final ResolvedPlaybackResources? resources;
final PlaybackBundleCompleteness? completeness;
```

Map JSON `audio-only` to `PlaybackBundleCompleteness.audioOnly`. Reuse the playback repository's same-origin path validation for stream, picture, and lyrics paths. Resolve accepted paths against `api.origin` before returning `PlaybackSource` so downstream UI never receives a relative URL.

- [ ] **Step 4: Add normalized bundle data to `PlaybackSource`**

Keep `resolved` and `streamUri`, and add exact normalized fields:

```dart
final class PlaybackSource {
  const PlaybackSource({
    required this.resolved,
    required this.streamUri,
    this.bundleLyrics,
    this.lyricsUri,
    this.pictureUri,
  });

  final ResolvedTrack resolved;
  final Uri streamUri;
  final Lyrics? bundleLyrics;
  final Uri? lyricsUri;
  final Uri? pictureUri;
}
```

Populate these fields only after the repository's same-origin validation and URI resolution. Update every fake `PlaybackSource` constructor with optional defaults so old fixtures remain concise.

- [ ] **Step 5: Add failing controller resource-application tests**

Return a bundle with lyrics/artwork and assert before/after `audio.playTrack`:

```dart
expect(controller.state.current?.raw['pic'], 'http://service.local/api/v1/playback/resources/picture-token/picture');
expect(controller.state.lyrics?.original, '[00:00.00]bundle');
expect(lyricsLoaderCalls, 0);
```

Cover `lyricsUrl` using the delayed loader, no resources preserving current behavior, a stale resolve not mutating a newly selected track, and local cached playback retaining local resources.

- [ ] **Step 6: Apply resources atomically to the current track**

After `resolver.resolve` and before `audio.playTrack`, confirm the current `(source,id)` still matches. Rebuild only that queue entry: set `raw['pic']` from `pictureUri`, and merge `lyricsUri` into `raw['meta']['lyricsUrl']` without dropping existing metadata. Set `bundleLyrics` directly, store completeness for diagnostic presentation, and leave `lyricsError` clear. Add a generation counter so late resolves cannot mutate a later track.

- [ ] **Step 7: Avoid duplicate lyric requests**

`loadLyrics` returns immediately when the current generation already has non-empty bundle lyrics. When only `lyricsUrl` or no lyrics are present, preserve the existing loader path; `SearchRepository.lyrics` already honors local same-origin resource URLs on the updated track metadata.

- [ ] **Step 8: Verify Task 5**

```bash
dart format lib/api/models.dart test/api/models_test.dart lib/features/player/playback_repository.dart test/features/repositories_test.dart lib/features/player/player_controller.dart lib/features/player/player_state.dart test/features/player/player_controller_test.dart
flutter test test/api/models_test.dart test/features/repositories_test.dart test/features/player/player_controller_test.dart
flutter analyze lib/api/models.dart lib/features/player/playback_repository.dart lib/features/player/player_controller.dart lib/features/player/player_state.dart
```

Expected: PASS; existing stream-expiry retry still resolves a fresh complete bundle.

- [ ] **Step 9: Commit when authorized**

```bash
git add lib/api/models.dart test/api/models_test.dart lib/features/player/playback_repository.dart test/features/repositories_test.dart lib/features/player/player_controller.dart lib/features/player/player_state.dart test/features/player/player_controller_test.dart
git commit -m "feat(player): consume Service playback bundles"
```

### Task 6: Present Safe Multi-Source Failure Copy

**Files:**
- Modify: `lib/app/app_error.dart`
- Modify: `test/app/app_error_test.dart`
- Modify: `lib/features/player/player_screen.dart`

**Interfaces:**
- Consumes: `ServiceException('SOURCE_ALL_UNAVAILABLE', details: { attempts: [...] })`.
- Produces: safe user-facing attempt-count copy.

- [ ] **Step 1: Add failing error-copy tests**

```dart
expect(
  appErrorMessage(
    const ServiceException(
      'SOURCE_ALL_UNAVAILABLE',
      'internal',
      details: {
        'attempts': [
          {'sourceId': 'a', 'code': 'SOURCE_TIMEOUT'},
          {'sourceId': 'b', 'code': 'SOURCE_NETWORK_ERROR'},
        ],
      },
    ),
    fallback: '播放失败',
  ),
  '已尝试 2 个音源，均网络不可用。',
);
```

Malformed details must return `已启用的音源当前均不可用，请稍后重试。` without including raw message/details.

- [ ] **Step 2: Run the test and confirm failure**

```bash
flutter test test/app/app_error_test.dart
```

Expected: FAIL because the code falls through to caller text.

- [ ] **Step 3: Add safe structured formatting**

Count only list entries shaped as maps with string `sourceId` and `code`; never interpolate either value. Add the new switch case in `appErrorMessage`. Confirm player error surfaces already use this helper; if not, route the visible error through it without changing controller exception storage.

- [ ] **Step 4: Verify Task 6**

```bash
dart format lib/app/app_error.dart test/app/app_error_test.dart lib/features/player/player_screen.dart
flutter test test/app/app_error_test.dart test/features/player/player_screen_test.dart
flutter analyze lib/app/app_error.dart lib/features/player/player_screen.dart
```

Expected: PASS and no raw Service exception becomes visible.

- [ ] **Step 5: Commit when authorized**

```bash
git add lib/app/app_error.dart test/app/app_error_test.dart lib/features/player/player_screen.dart
git commit -m "feat(errors): explain exhausted source fallback"
```

### Task 7: Freeze and Verify the Flutter Result

**Files:**
- Verify only: files changed by Tasks 1–6.

**Interfaces:**
- Consumes: completed Flutter implementation and frozen Service contract.
- Produces: final cross-repository verification evidence.

- [ ] **Step 1: Inspect scope and formatting**

```bash
git status --short
git diff --check
git diff --stat
git diff -- lib/features/sources lib/events lib/app lib/api/models.dart lib/features/player test/features/sources test/events test/api test/features/player test/features/repositories_test.dart
```

Expected: intended changes only plus identified pre-existing user work.

- [ ] **Step 2: Run the focused Flutter suite on the frozen tree**

```bash
flutter test test/features/sources/sources_controller_test.dart test/features/sources/sources_screen_test.dart test/events/event_coordinator_test.dart test/app/app_shell_routing_test.dart test/api/models_test.dart test/features/repositories_test.dart test/features/player/player_controller_test.dart test/app/app_error_test.dart
```

Expected: zero failed tests.

- [ ] **Step 3: Run analyzer and broad unit coverage**

```bash
flutter analyze
flutter test
```

Expected: exit 0. Preserve and classify failures from unrelated pre-existing dirty changes instead of editing unrelated files.

- [ ] **Step 4: Run a real Service/client integration pass**

Against a temporary Service storage root, install deterministic A/B scripts, configure A then B in Flutter, verify UI order survives restart, make A transiently unavailable, and confirm playback uses B for that request while the next request still starts with A. Verify local downloaded audio remains selected and complete/mixed resource states update lyrics/artwork without external URL exposure.

- [ ] **Step 5: Verify desktop and mobile source layouts**

Run source-page widget/golden coverage at the existing desktop and mobile fixture sizes. Confirm reorder handles, switches, priority labels, saving lockout, empty state, and last-source warning are usable without overflow.

- [ ] **Step 6: Commit verification-only corrections when authorized**

```bash
git add lib/features/sources lib/events/event_coordinator.dart lib/app/runtime_providers.dart lib/app/app.dart lib/app/app_router.dart lib/app/app_error.dart lib/api/models.dart lib/features/player/playback_repository.dart lib/features/player/player_controller.dart lib/features/player/player_state.dart lib/features/player/player_screen.dart test/features/sources test/events/event_coordinator_test.dart test/app/app_shell_routing_test.dart test/app/app_error_test.dart test/api/models_test.dart test/features/repositories_test.dart test/features/player/player_controller_test.dart test/features/player/player_screen_test.dart test/visual/high_fidelity_fixtures.dart test/visual/full_ui_gallery_test.dart
git commit -m "test(flutter): verify multi-source playback"
```

Do not create an empty commit.
