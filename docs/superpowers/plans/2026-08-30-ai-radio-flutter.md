# AI Radio Flutter Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add responsive Flutter support for one-click AI radio and optional sequential end-of-queue continuation while preserving current playback, attribution, device cache, and platform behavior.

**Architecture:** Flutter consumes the frozen Service radio contract through a focused repository/controller layer. A `RadioContinuationCoordinator` observes `PlayerController` queue state, owns radio session lifecycle and prefetch de-duplication, and appends attributed tracks through explicit atomic player APIs; the player never calls HTTP directly. The continuation preference is device-local, while non-secret AI configuration and analysis status remain Service-owned.

**Tech Stack:** Flutter/Dart 3.9, just_audio, audio_service, shared_preferences, shadcn_ui, Lucide icons, go_router, flutter_test.

## Global Constraints

- Preserve all existing tracked and untracked changes in `/Volumes/ext/MusicFree/flutter-client`; the worktree already contains uncommitted recommendation and UI implementation.
- Do not commit, push, deploy, regenerate unrelated artifacts/goldens, or modify `/Volumes/ext/lx-music-server-web` from this plan.
- Start only after Task 10 of `/Volumes/ext/lx-music-server-web/docs/superpowers/plans/2026-08-30-ai-radio-service-web.md` records a frozen passing Service contract.
- Treat `/Volumes/ext/lx-music-server-web/docs/superpowers/specs/2026-08-30-ai-radio-design.md` as normative.
- The Service owns candidate generation, AI use, session persistence, recommendation policy, and final item order. Flutter must never generate or AI-rank tracks locally.
- `player.autoRadioContinuation` is a device-local preference backed by `SharedPreferencesAsync`, defaults to `false`, and is not sent through Service settings.
- AI API keys never enter Flutter models, fields, storage, requests, logs, or tests.
- Independent radio is available even when Service AI status is disabled/unavailable because the Service can return local recommendations.
- Automatic continuation runs only in `PlaybackMode.sequential`; repeat-one and shuffle keep their existing behavior.
- A manual queue clear, explicit stop, Service-origin switch, or replacement by another playlist must not immediately refill the queue.
- Preserve existing `recommendationItemId` attribution for Service resolution and playback-history start/end. Radio adds `radioSessionId` but does not replace the attribution ID.
- Preserve device-cache-first behavior and report playback even when cached audio starts.
- Follow `design.md` and repository icon rules: Lucide for ordinary actions, `AppPlaybackIcons` for previous/play/pause/next, no raw Material transport icons, 44 px minimum icon targets, Chinese labels and tooltips.
- Responsive proof must cover 360 px mobile, 720 px breakpoint, compact desktop/tablet, and width ≥1180 px.

---

## File and Interface Map

New files:

```text
lib/features/radio/radio_models.dart
lib/features/radio/radio_repository.dart
lib/features/radio/radio_preferences.dart
lib/features/radio/radio_controller.dart
lib/features/radio/radio_continuation_coordinator.dart
lib/features/radio/radio_status_strip.dart
test/features/radio/radio_repository_test.dart
test/features/radio/radio_preferences_test.dart
test/features/radio/radio_controller_test.dart
test/features/radio/radio_continuation_coordinator_test.dart
test/features/radio/radio_status_strip_test.dart
```

Stable cross-task interfaces:

```dart
enum RadioMode { dedicated, queueContinuation }
enum RadioBatchStatus { active, degraded }
enum RadioAiStatus { enhanced, profileOnly, local, disabled, unavailable }
enum RadioRankingSource { ai, aiProfileLocalRank, local, dailyFallback, familiarFallback }

final class RadioItem {
  const RadioItem({
    required this.recommendationItemId,
    required this.radioSessionId,
    required this.track,
    required this.rankingSource,
    required this.reason,
  });

  final String recommendationItemId;
  final String radioSessionId;
  final Track track;
  final RadioRankingSource rankingSource;
  final RecommendationReason reason;
}

final class RadioBatch {
  const RadioBatch({
    required this.sessionId,
    required this.mode,
    required this.status,
    required this.aiStatus,
    required this.items,
    this.profileId,
  });

  final String sessionId;
  final RadioMode mode;
  final RadioBatchStatus status;
  final RadioAiStatus aiStatus;
  final String? profileId;
  final List<RadioItem> items;
}
```

Player additions used by later tasks:

```dart
enum PlayerQueueKind { manual, dailyRecommendation, dedicatedRadio, radioContinuation }

final class PlaybackContext {
  const PlaybackContext({this.recommendationItemId, this.radioSessionId});
  final String? recommendationItemId;
  final String? radioSessionId;
}
```

## Task 1: Adopt the Frozen Radio and AI Status Contract

**Files:**

- Create: `lib/features/radio/radio_models.dart`
- Create: `lib/features/radio/radio_repository.dart`
- Modify: `lib/features/recommendations/recommendation_models.dart`
- Test: `test/features/radio/radio_repository_test.dart`
- Modify: `test/features/recommendations/recommendation_test_data.dart`

**Interfaces:**

- Consumes: the frozen Service routes and schemas from Service/Web plan Task 10.
- Produces: `RadioItem`, `RadioBatch`, `RadioAiServiceStatus`, and `RadioRepository` for every later Flutter task.

- [ ] **Step 1: Record frozen contract evidence**

Read the Service handoff and confirm these routes exist with passing OpenAPI tests:

```text
POST   /api/v1/radio/sessions
POST   /api/v1/radio/sessions/{sessionId}/next
GET    /api/v1/radio/sessions/{sessionId}
DELETE /api/v1/radio/sessions/{sessionId}
GET    /api/v1/radio/ai/status
POST   /api/v1/radio/ai/test
POST   /api/v1/radio/ai/reanalyze
```

Expected: exact path/status/enum match. If frozen evidence differs, update this plan through Worker Flow before code changes rather than guessing.

- [ ] **Step 2: Implement strict model parsing**

Reuse `RecommendationReason.fromJson`. Reject unknown mode/status/ranking source, missing IDs, duplicate recommendation IDs, item session mismatch, more than 3 items, and malformed Track objects with `ServiceException('INVALID_RESPONSE', ...)`.

```dart
RadioMode parseRadioMode(String value) => switch (value) {
  'dedicated' => RadioMode.dedicated,
  'queue_continuation' => RadioMode.queueContinuation,
  _ => throw const ServiceException('INVALID_RESPONSE', 'Service returned an invalid radio mode.'),
};

RadioBatchStatus parseRadioBatchStatus(String value) => switch (value) {
  'active' => RadioBatchStatus.active,
  'degraded' => RadioBatchStatus.degraded,
  _ => throw const ServiceException('INVALID_RESPONSE', 'Service returned an invalid radio status.'),
};

RadioAiStatus parseRadioAiStatus(String value) => switch (value) {
  'enhanced' => RadioAiStatus.enhanced,
  'profile_only' => RadioAiStatus.profileOnly,
  'local' => RadioAiStatus.local,
  'disabled' => RadioAiStatus.disabled,
  'unavailable' => RadioAiStatus.unavailable,
  _ => throw const ServiceException('INVALID_RESPONSE', 'Service returned an invalid AI status.'),
};

factory RadioBatch.fromJson(Object? value) {
  final json = jsonObject(value, 'radio.batch');
  final sessionId = jsonString(json['sessionId'], 'radio.sessionId');
  final items = jsonList(json['items'], 'radio.items')
      .map(RadioItem.fromJson)
      .toList(growable: false);
  if (items.length > 3 || items.any((item) => item.radioSessionId != sessionId)) {
    throw const ServiceException('INVALID_RESPONSE', 'Service returned an invalid radio batch.');
  }
  final profileId = json['profileId'];
  return RadioBatch(
    sessionId: sessionId,
    mode: parseRadioMode(jsonString(json['mode'], 'radio.mode')),
    status: parseRadioBatchStatus(jsonString(json['status'], 'radio.status')),
    aiStatus: parseRadioAiStatus(jsonString(json['aiStatus'], 'radio.aiStatus')),
    profileId: profileId == null
        ? null
        : jsonString(profileId, 'radio.profileId'),
    items: items,
  );
}
```

- [ ] **Step 3: Implement repository methods**

```dart
abstract interface class RadioSessionPort {
  Future<RadioBatch> create({
    required RadioMode mode,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 3,
  });
  Future<RadioBatch> next({
    required String sessionId,
    required int queueGeneration,
    required String requestId,
    Track? currentTrack,
    List<Track> queuedTracks = const [],
    int limit = 3,
  });
  Future<RadioBatch> get(String sessionId);
  Future<void> close(String sessionId);
}
```

`RadioRepository` also implements `status`, `testConnection`, and `reanalyze`. Use `ServiceApi.request`, which already unwraps the Service `data` envelope.

- [ ] **Step 4: Add request/response coverage**

Cover create/next bodies, null current track, queued tracks, request IDs, queue generation, all enums, fewer than 3 items, duplicate IDs, mismatch, close, 404 mapping, AI status, test, reanalyze, and the absence of any API-key field.

- [ ] **Step 5: Verify the task**

Run:

```sh
flutter test \
  test/features/radio/radio_repository_test.dart \
  test/features/recommendations/recommendation_repository_test.dart
```

Expected: PASS.

- [ ] **Step 6: Record the task result**

Record exact consumed schemas and focused test output. Do not commit.

## Task 2: Add Device-Local Continuation Preference and Service AI Settings

**Files:**

- Create: `lib/features/radio/radio_preferences.dart`
- Test: `test/features/radio/radio_preferences_test.dart`
- Modify: `lib/features/settings/service_settings_repository.dart`
- Modify: `lib/features/settings/service_function_settings_controller.dart`
- Test: `test/features/settings/service_settings_repository_test.dart`
- Test: `test/features/settings/service_function_settings_controller_test.dart`

**Interfaces:**

- Consumes: existing SharedPreferences and Service function settings patterns.
- Produces: `RadioPreferences` and Service-owned non-secret `AIServiceSettings`.

- [ ] **Step 1: Implement a Service-origin-independent device preference**

```dart
final class RadioPreferences {
  RadioPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'player_auto_radio_continuation_v1';
  final SharedPreferencesAsync _preferences;

  Future<bool> readAutoContinuation() async =>
      await _preferences.getBool(_key) ?? false;

  Future<void> writeAutoContinuation(bool value) async =>
      _preferences.setBool(_key, value);
}
```

The setting follows the device across Service-origin changes because it describes local playback behavior; active radio sessions do not.

- [ ] **Step 2: Extend Service function settings with non-secret AI fields**

```dart
final class AIServiceSettings {
  const AIServiceSettings({
    required this.enabled,
    required this.baseUrl,
    required this.model,
  });
  final bool enabled;
  final String baseUrl;
  final String model;
}
```

Preserve explicit empty URL/model and never infer an API key. Saving enabled with empty required fields surfaces the Service validation error.

- [ ] **Step 3: Add preference and settings coverage**

Cover missing/malformed preference → false, persisted true/false, independence from Service settings, explicit empty AI values, enabled configuration, save payload, and no key/token field in serialized bodies.

- [ ] **Step 4: Verify the task**

Run:

```sh
flutter test \
  test/features/radio/radio_preferences_test.dart \
  test/features/settings/service_settings_repository_test.dart \
  test/features/settings/service_function_settings_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Record the task result**

Record local-vs-Service ownership and test evidence.

## Task 3: Implement Radio Controller Session State

**Files:**

- Create: `lib/features/radio/radio_controller.dart`
- Test: `test/features/radio/radio_controller_test.dart`

**Interfaces:**

- Consumes: `RadioSessionPort` from Task 1.
- Produces: `RadioController`, `RadioState`, and session operations used by Home, player coordinator, status UI, and settings.

```dart
final class RadioState {
  const RadioState({
    this.session,
    this.loading = false,
    this.prefetching = false,
    this.error,
  });
  final RadioBatch? session;
  final bool loading;
  final bool prefetching;
  final Object? error;
  bool get active => session != null;
}
```

- [ ] **Step 1: Implement atomic dedicated start**

`prepareDedicated` creates and validates a new batch without mutating the player or closing the old session. `adoptPrepared` marks it active only after the caller successfully replaces the queue, then closes the previous session best-effort.

```dart
Future<RadioBatch> prepareDedicated(RadioBatchRequestContext context);
Future<void> adoptPrepared(RadioBatch batch);
```

- [ ] **Step 2: Implement coalesced `ensureBuffer`**

Key the pending operation by `(sessionId, queueGeneration)`. Repeated calls return the same future. Discard a response if the active session or generation changed before completion.

```dart
Future<List<RadioItem>> ensureBuffer({
  required int queueGeneration,
  required Track? currentTrack,
  required List<Track> queuedTracks,
});
```

For a continuation with no active session, create `queueContinuation`; for a dedicated session, call `next`.

- [ ] **Step 3: Implement stop, recover, and Service switch**

`stop()` clears local active state first, then closes the old Service session best-effort. `recover(sessionId)` accepts only an active Service batch. `resetForServiceOriginChange()` invalidates pending results and drops the old session without sending it to the new Service.

- [ ] **Step 4: Add controller coverage**

Cover dedicated prepare/adopt success, failed prepare preserving old state, old close after adoption, one in-flight future, stale generation discard, continuation creation, dedicated next, stop, recover active/expired, Service switch, provider errors, and listener notifications.

- [ ] **Step 5: Verify the task**

Run:

```sh
flutter test test/features/radio/radio_controller_test.dart
```

Expected: PASS with no player or widget dependency.

- [ ] **Step 6: Record the task result**

Record state transitions and coalescing evidence.

## Task 4: Add Atomic Dynamic Queue APIs to PlayerController

**Files:**

- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/features/player/player_state.dart`
- Modify: `lib/features/player/playback_repository.dart`
- Test: `test/features/player/player_controller_test.dart`
- Test: `test/features/player/playback_repository_context_test.dart`

**Interfaces:**

- Consumes: existing player/audio/session ports and `RadioItem` context fields.
- Produces: `PlayerQueueKind`, `queueGeneration`, `remainingAfterCurrent`, `appendTracks`, and extended `playTracks` used by Task 5.

- [ ] **Step 1: Separate queue generation from playback generation**

Add a monotonic `_queueGeneration` that increments only when the logical queue is replaced or cleared, not on quality reload, seek, pause/resume, artwork/lyrics update, or playing the next item.

```dart
int get queueGeneration => _queueGeneration;
int get remainingAfterCurrent => state.currentIndex < 0
    ? 0
    : state.queue.length - state.currentIndex - 1;
```

- [ ] **Step 2: Extend queue kind and playback context**

Add `PlayerQueueKind queueKind` to `PlayerState`, defaulting to manual. Add nullable `radioSessionId` to `PlaybackContext`. Preserve existing recommendation context behavior in resolution and playback-history start.

- [ ] **Step 3: Extend `playTracks` atomically**

```dart
Future<void> playTracks(
  List<Track> tracks, {
  int startIndex = 0,
  List<PlaybackContext?>? contexts,
  PlayerQueueKind queueKind = PlayerQueueKind.manual,
});
```

Validate track/context length before ending the old session or mutating state. Increment queue generation once, replace queue/context/kind together, then play. Existing callers compile without changes.

- [ ] **Step 4: Add atomic append**

```dart
bool appendTracks(
  List<Track> tracks, {
  required List<PlaybackContext?> contexts,
  required int expectedQueueGeneration,
  PlayerQueueKind? promoteTo,
});
```

Return false without mutation on empty input, length mismatch, generation mismatch, duplicate `(source,id)` already queued, or a queue cleared since request. On success append Track/context together and optionally promote manual to radioContinuation without changing generation.

- [ ] **Step 5: Preserve completion and attribution semantics**

Natural completion still reports the current session before `playIndex`. Cached and online starts both pass the original `recommendationItemId`; `radioSessionId` remains local queue metadata and does not replace the history API field.

- [ ] **Step 6: Add focused player coverage**

Cover one generation per replacement/clear, no generation change on next/quality/pause, atomic append, generation mismatch, duplicate rejection, Track/Context index alignment after remove/playIndex, queue kind transitions, dedicated contexts, radio completion, cache hit, and existing daily recommendation attribution.

- [ ] **Step 7: Verify the task**

Run:

```sh
flutter test \
  test/features/player/player_controller_test.dart \
  test/features/player/playback_repository_context_test.dart \
  test/features/player/service_audio_handler_test.dart
```

Expected: PASS; no transport regression.

- [ ] **Step 8: Record the task result**

Record public player API and focused evidence.

## Task 5: Coordinate Dedicated Radio and End-of-Queue Prefetch

**Files:**

- Create: `lib/features/radio/radio_continuation_coordinator.dart`
- Test: `test/features/radio/radio_continuation_coordinator_test.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/events/event_coordinator.dart`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**

- Consumes: `RadioController`, `RadioPreferences`, and Player APIs from Task 4.
- Produces: `RadioContinuationCoordinator.startDedicated()`, automatic `ensureBuffer`, and lifecycle cleanup.

- [ ] **Step 1: Bind one coordinator per active Service runtime**

Construct it alongside the active `PlayerController` and `RadioController`, register exactly one listener on each dependency, and dispose listeners with the runtime. Do not create a coordinator per screen rebuild.

- [ ] **Step 2: Implement dedicated start**

```dart
Future<bool> startDedicated() async {
  final generation = player.queueGeneration + 1;
  final batch = await radio.prepareDedicated(contextFor(generation));
  if (batch.items.isEmpty) return false;
  await player.playTracks(
    batch.items.map((item) => item.track).toList(growable: false),
    contexts: batch.items.map(contextForItem).toList(growable: false),
    queueKind: PlayerQueueKind.dedicatedRadio,
  );
  await radio.adoptPrepared(batch);
  return true;
}
```

Validate the non-empty batch and context lengths before calling `playTracks`. If queue replacement throws before mutation, do not adopt the new session and close the prepared session best-effort. Once the radio queue is installed, adopt the session even if the first track later fails to resolve; existing auto-skip plus the second and third batch items provide playback fallback.

- [ ] **Step 3: Implement automatic continuation gate**

Request only when all are true: preference enabled, `PlaybackMode.sequential`, a current track exists, current queue kind is manual/dailyRecommendation/radioContinuation, `remainingAfterCurrent < 2`, and no suppression/in-flight request exists for the current generation.

For manual/daily queues create a continuation session; for dedicated/continuation queues extend the active session. Append with `expectedQueueGeneration`; if false, discard the response.

- [ ] **Step 4: Suppress refill on explicit user actions**

Before clear/stop/playlist replacement/Service switch, invalidate the active coordinator generation and set suppression until the next explicit non-radio `playTracks` succeeds. Repeat-one and shuffle never invoke auto continuation. Changing back to sequential reevaluates normally.

- [ ] **Step 5: Handle Service-origin changes and recovery**

On Service change, call `resetForServiceOriginChange`, cancel/discard pending results, and construct a controller for the new origin. Do not send an old session ID to the new Service. Short app backgrounding keeps the session; full runtime reconstruction may call GET with the locally retained short-lived session ID.

- [ ] **Step 6: Add coordinator coverage**

Cover remaining-buffer thresholds 0/1/2, default-off, sequential on, repeat-one/shuffle off, one request per generation, append success, late response discard, manual clear suppression, playlist replacement, dedicated refill, continuation refill, failed batch, empty batch, Service switch, and notification-next path through the same player.

- [ ] **Step 7: Verify the task**

Run:

```sh
flutter test \
  test/features/radio/radio_continuation_coordinator_test.dart \
  test/app/app_shell_test.dart \
  test/features/player/player_controller_test.dart
```

Expected: PASS; clearing a queue never triggers an immediate radio request.

- [ ] **Step 8: Record the task result**

Record lifecycle ownership and state-transition evidence.

## Task 6: Add the Responsive Home AI Radio Entry

**Files:**

- Modify: `lib/features/home/home_controller.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/app/app_router.dart`
- Test: `test/features/home/home_controller_test.dart`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**

- Consumes: `RadioContinuationCoordinator.startDedicated` and `RadioController.state`.
- Produces: one responsive Home entry without a new navigation branch.

- [ ] **Step 1: Expose Home actions without duplicating radio state**

Inject the coordinator/controller references already owned by runtime providers. Home forwards `startDedicated`, observes radio loading/status, and does not copy the session or candidate list into `HomeState`.

- [ ] **Step 2: Integrate the Hero primary action**

Use one primary action position. When no conflicting action is in progress, label it `AI 随心听`; pressing it intentionally replaces the queue through Task 5. While preparing, show bounded progress and disable duplicate taps. Failure displays an existing `AppNotice`/feedback surface and leaves the old queue intact.

- [ ] **Step 3: Apply responsive layout rules**

- 360–719 px: one full-width primary action under Hero copy; status is a second one-line metadata row.
- 720–1179 px: preserve the existing two-column Hero; action and compact status remain in the text column.
- ≥1180 px: place action and `依据当前时段和收听偏好`/`本地推荐` summary in the existing Hero action group.

Do not add a new Home section that duplicates daily recommendation cards.

- [ ] **Step 4: Add Home behavior and layout coverage**

Cover AI enhanced/local/disabled status, loading double-tap prevention, successful queue replacement, failed first batch preserving the player, existing daily recommendation Hero fallback, and no overflow at 360, 720, 900, 1180, and 1440 px.

- [ ] **Step 5: Verify the task**

Run:

```sh
flutter test \
  test/features/home/home_controller_test.dart \
  test/features/home/home_screen_test.dart
```

Expected: PASS at all explicit test surface sizes.

- [ ] **Step 6: Record the task result**

Record viewport evidence and queue-preservation behavior.

## Task 7: Add Radio Status to Player and Queue Surfaces

**Files:**

- Create: `lib/features/radio/radio_status_strip.dart`
- Test: `test/features/radio/radio_status_strip_test.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/mobile_player_controls.dart`
- Modify: `lib/features/player/desktop_player_controls.dart`
- Modify: `lib/features/player/mobile_queue_sheet.dart`
- Modify: `lib/features/player/desktop_queue_popover.dart`
- Test: `test/features/player/player_screen_test.dart`
- Test: `test/visual/high_fidelity_gallery_test.dart`

**Interfaces:**

- Consumes: radio/controller state, current `PlayerQueueKind`, item reasons, and `stop` action.
- Produces: responsive active/degraded/local radio visibility and a clear stop action.

- [ ] **Step 1: Build a compact reusable status strip**

```dart
RadioStatusStrip(
  status: RadioAiStatus.enhanced,
  message: '正在根据本次收听调整',
  onStop: coordinator.stop,
)
```

Use `LucideIcons.radio` or the closest existing ordinary Lucide icon. The stop action has a 44 px target, Chinese semantic label, and tooltip; it is not a transport icon.

- [ ] **Step 2: Place status without crowding transport controls**

On mobile, render one compact line between track metadata and progress/transport, dropping the explanatory phrase before truncating the status label. On desktop, place a badge beside metadata. Do not add a sixth transport button or change the Material Rounded transport cluster.

- [ ] **Step 3: Annotate queue surfaces**

Show session source at the queue header and one-line localized reason below radio item metadata where space permits. Mobile sheet and desktop popover both expose `停止随心听`; narrow rows ellipsize reason before title/artist.

- [ ] **Step 4: Cover accessibility and responsive rendering**

Test enhanced/profile/local/degraded states, stop action, 44 px hit target, Chinese semantics/tooltip, narrow ellipsis, desktop badge, queue reason, and absence of raw AI factor/model text not mapped by the app.

- [ ] **Step 5: Verify the task**

Run:

```sh
flutter test \
  test/features/radio/radio_status_strip_test.dart \
  test/features/player/player_screen_test.dart \
  test/visual/high_fidelity_gallery_test.dart

rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: widget/visual tests PASS; the first `rg` returns no matches; direct Material icon matches remain confined to `lib/design/components/app_playback_button.dart`.

- [ ] **Step 6: Record the task result**

Record screenshots/golden evidence already produced by project tests and icon scans. Do not regenerate unrelated baselines.

## Task 8: Add AI and Auto-Continuation Settings UI

**Files:**

- Modify: `lib/features/settings/service_function_settings_screen.dart`
- Modify: `lib/features/settings/service_function_settings_controller.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/service_function_settings_screen_test.dart`
- Test: `test/features/settings/service_function_settings_controller_test.dart`
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**

- Consumes: Task 2 settings/preferences and Task 1 AI status/test/reanalyze repository methods.
- Produces: Service AI configuration/status UI and device-local continuation toggle.

- [ ] **Step 1: Add Service AI settings section**

Expose enabled, OpenAI-compatible base URL, model, configured/healthy status, connection test, latest profile time/source, and reanalysis. Include Chinese disclosure that the configured external service may receive the latest 30 days of complete ended playback records plus long-term aggregate preferences.

Do not create an API-key text field or render any secret placeholder. Explain that the key is configured on the Service host with `TUNEFLOW_RECOMMENDATION_AI_API_KEY`.

- [ ] **Step 2: Add device playback toggle**

Place `队列结束后自动续播` in local player settings, default off, with helper text stating it applies only to sequential playback on this device. Toggling it writes `RadioPreferences`, not Service settings.

- [ ] **Step 3: Apply responsive form layout**

Mobile uses a single-column card. At ≥720 px keep the existing settings content width and grouping; do not compress enabled/base URL/model into one row. Allow long model names and stable errors to wrap.

- [ ] **Step 4: Add controller/widget coverage**

Cover explicit empty fields, save validation, configured/healthy status, test success/failure, reanalysis progress, disclosure text, no API-key field, local toggle default/persistence, and 360/720/1180 px no-overflow rendering.

- [ ] **Step 5: Verify the task**

Run:

```sh
flutter test \
  test/features/settings/service_function_settings_controller_test.dart \
  test/features/settings/service_function_settings_screen_test.dart \
  test/features/settings/settings_screen_test.dart
```

Expected: PASS with no live Service or AI dependency.

- [ ] **Step 6: Record the task result**

Record ownership boundaries, viewport evidence, and absence of secret UI.

## Task 9: Run Flutter Integration and Regression Verification

**Files:**

- Modify only if verification finds an in-scope defect: files already listed in Tasks 1–8
- Read: `/Volumes/ext/lx-music-server-web/docs/superpowers/specs/2026-08-30-ai-radio-design.md`
- Read: Service frozen handoff from `/Volumes/ext/lx-music-server-web/docs/superpowers/plans/2026-08-30-ai-radio-service-web.md`

**Interfaces:**

- Consumes: all Flutter tasks and frozen Service contract.
- Produces: final Flutter evidence separate from Service/Web evidence.

- [ ] **Step 1: Run focused radio/player/home/settings tests**

```sh
flutter test \
  test/features/radio \
  test/features/player/player_controller_test.dart \
  test/features/player/playback_repository_context_test.dart \
  test/features/player/player_screen_test.dart \
  test/features/home/home_controller_test.dart \
  test/features/home/home_screen_test.dart \
  test/features/settings/service_function_settings_controller_test.dart \
  test/features/settings/service_function_settings_screen_test.dart \
  test/features/settings/settings_screen_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis and icon-policy scans**

```sh
flutter analyze
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: analysis PASS; first scan has no matches; second scan matches only the shared playback abstraction.

- [ ] **Step 3: Run visual/responsive verification**

```sh
flutter test test/visual/high_fidelity_gallery_test.dart
```

Expected: PASS for mobile and desktop player surfaces, with no overflow at the explicit 360/720/1180+ test sizes.

- [ ] **Step 4: Run a platform build proportional to changed runtime code**

Use the host-supported macOS build after tests:

```sh
flutter build macos --debug
```

Expected: build succeeds. If the environment lacks a required signing/toolchain component, record the exact blocker and retain passing analyze/widget evidence; do not modify signing or generated platform files as a workaround.

- [ ] **Step 5: Check secret and Service-boundary regressions**

```sh
rg -n "TUNEFLOW_RECOMMENDATION_AI_API_KEY|recommendation\.ai\.(apiKey|key|token)|Authorization: Bearer" lib test --glob '*.dart'
```

Expected: no Flutter production code or test fixture contains a real or modeled AI key field. Test-only HTTP authorization unrelated to AI must be reviewed rather than blindly removed.

- [ ] **Step 6: Record final handoff**

Record changed files, focused tests, analysis, visual suite, build result, explicit viewport evidence, and any residual environmental limitation. Report Service/Web and Flutter verification separately. Do not commit, push, or deploy.
