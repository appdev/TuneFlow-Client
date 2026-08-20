# Connection Settings and Resume Behavior Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify Service status presentation, add a secondary client connection-settings page backed by shared Service origins, and prevent foreground resume or connection diagnostics from refreshing music data.

**Architecture:** The connection coordinator remains the single source of live connection state and records the selected endpoint role separately from the device transport. Client-local bootstrap persistence and shared Service origin persistence are coordinated through one save-and-probe operation that preserves the active API on failure. Routing observes only connected/disconnected transitions, while small status widgets observe diagnostics locally.

**Tech Stack:** Flutter 3.47, Dart 3.13, Riverpod 3, go_router, shadcn_ui, Flutter widget tests, TypeScript 5.9, Vue 3, Playwright.

## Global Constraints

- Follow `/Volumes/ext/MusicFree/flutter-client/AGENTS.md` and `/Volumes/ext/lx-music-server-web/AGENTS.md` in their respective repositories.
- Preserve all unrelated dirty-worktree changes; inspect overlapping diffs before every edit.
- The settings overview shows only a Service summary and never displays URL, latency, API version, check time, or a reconnect action.
- The secondary client page edits local bootstrap origin plus shared `service.lanOrigin` and `service.externalOrigin`; Service Web edits the same two shared fields.
- Foreground resume performs zero health probes. Only cold start, an actual normalized network-transport change, or explicit “保存并检测” may probe.
- Wi-Fi/Ethernet candidates remain LAN → external → bootstrap; non-Wi-Fi candidates remain external → bootstrap; each candidate receives three attempts with two seconds between failures.
- Automatic switching keeps the same `ServiceApi` identity and must not rebuild routing, home controllers, repositories, playback, or music-management state.
- Failed explicit save/probe preserves the current live connection and restores the previous shared origins if they were already written.
- Do not commit, push, publish, deploy, or alter NAS state.

---

### Task 1: Record the selected endpoint role and remove resume probing

**Files:**

- Modify: `lib/features/connection/endpoint_selector.dart`
- Modify: `lib/features/connection/connection_repository.dart`
- Modify: `lib/features/connection/connection_controller.dart`
- Delete: `lib/features/connection/connection_lifecycle_host.dart`
- Modify: `lib/app/app.dart`
- Test: `test/features/connection/endpoint_selector_test.dart`
- Test: `test/features/connection/connection_controller_test.dart`
- Delete: `test/features/connection/connection_lifecycle_host_test.dart`

**Interfaces:**

- Produces `enum EndpointRole { lan, external, bootstrap }`.
- Produces `EndpointCatalog.roleOf(ServiceOrigin origin, NetworkRoute route): EndpointRole` using the same ordered roles as candidate selection.
- Adds `EndpointSelection.role` and `ConnectionDiagnostics.endpointRole`.
- Removes the lifecycle `onResume` callback and `ConnectionController.resume()`; `handleNetworkChange` remains the only runtime re-evaluation entry.

- [x] **Step 1: Add failing endpoint-role tests**

Add assertions that role resolution follows route priority, including duplicate URLs:

```dart
expect(catalog.roleOf(origin('http://lan.local'), NetworkRoute.lan), EndpointRole.lan);
expect(catalog.roleOf(origin('https://public.example'), NetworkRoute.external), EndpointRole.external);
expect(catalog.roleOf(origin('https://bootstrap.example'), NetworkRoute.external), EndpointRole.bootstrap);
```

Assert `EndpointSelection.role` is the role of the candidate that actually succeeded.

- [x] **Step 2: Add failing lifecycle tests**

Add a controller test showing two identical transport sets cause no extra probe, while Wi-Fi → mobile causes exactly one debounced selection. Remove the lifecycle-host widget test with the production wrapper because foreground lifecycle is no longer part of connection coordination.

Run:

```sh
flutter test test/features/connection/endpoint_selector_test.dart test/features/connection/connection_controller_test.dart
```

Expected: FAIL because endpoint role is absent and resume currently calls `_reevaluate`.

- [x] **Step 3: Implement endpoint-role propagation**

Add an ordered helper in `EndpointCatalog` whose role precedence matches `candidates(route)`, carry the selected role through `EndpointSelection`, and build diagnostics with:

```dart
ConnectionDiagnostics(
  origin: health.origin.uri.toString(),
  connected: true,
  latency: health.latency,
  apiVersion: connected.capabilities.apiVersion,
  networkRoute: route,
  endpointRole: role,
  checkedAt: DateTime.now(),
)
```

For an unreachable re-evaluation, retain `current.diagnostics?.endpointRole` while setting `connected: false`.

- [x] **Step 4: Remove foreground probing**

Delete `ConnectionController.resume()`, delete `ConnectionLifecycleHost` and its test file, and return the app widget directly from `MusicFreeServiceApp`. Do not replace this with a timer or settings-screen probe.

- [x] **Step 5: Verify Task 1**

Run the three focused test files and:

```sh
rg -n "\.resume\(\)|onResume|refreshDiagnostics" lib/features/connection lib/app/app.dart
git diff --check -- lib/features/connection lib/app/app.dart test/features/connection
```

Expected: focused tests pass; no connection lifecycle resume hook remains.

### Task 2: Isolate routing and music controllers from diagnostics updates

**Files:**

- Modify: `lib/app/app.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/app/runtime_providers.dart`
- Test: `test/app/app_shell_test.dart`
- Test: `test/features/connection/connection_controller_test.dart`

**Interfaces:**

- Routing refresh consumes only a connection navigation state such as `(hasValue: bool, connected: bool, hasError: bool)`.
- `AppShell` identity must not depend on the `ConnectedService` snapshot object.
- Providers needing the transport consume `connection.value?.api`, not diagnostics-bearing `ConnectedService` identity.
- `SettingsController.syncConnection(ConnectionDiagnostics? value)` receives diagnostics changes without recreating the controller.

- [x] **Step 1: Add a failing no-refresh regression test**

In `app_shell_test.dart`, record `/api/v1/playlists`, `/api/v1/downloads`, `/api/v1/library/tracks`, and playback-history request counts after the home page settles. Publish a diagnostics-only update or cause a same-origin network re-evaluation, pump, and assert all counts are unchanged and the original home widget state remains mounted.

- [x] **Step 2: Add a failing real-switch stability test**

Extend the automatic-switch controller test to observe router/provider identity before and after Wi-Fi → mobile selection. Assert the same `ServiceApi` is retained, the active base URL changes, and music repositories do not refetch until a domain invalidation or explicit refresh.

- [x] **Step 3: Narrow Riverpod dependencies**

Remove the whole `ConnectedService` watch that recreates `appRouterProvider`. Listen only for transitions that affect `/connect` redirects. Remove `ObjectKey(connected)` from `AppShell` or replace it with stable API identity. In `runtime_providers.dart`, select `connection.value?.api` wherever only API access is required. Construct `SettingsController` from the stable API dependency, then use `ref.listen(connectionProvider.select((value) => value.value?.diagnostics), ...)` to call `syncConnection`; this updates only the settings UI and does not recreate repositories or routes.

- [x] **Step 4: Verify Task 2**

Run:

```sh
flutter test test/app/app_shell_test.dart test/features/connection/connection_controller_test.dart
git diff --check -- lib/app/app.dart lib/app/app_router.dart lib/app/app_shell.dart lib/app/runtime_providers.dart test/app/app_shell_test.dart test/features/connection/connection_controller_test.dart
```

Expected: diagnostics and base-URL changes do not issue music-management requests; disconnect still redirects to `/connect`.

### Task 3: Add shared Service-origin reads and transactional save-and-probe

**Files:**

- Modify: `lib/features/settings/service_settings_repository.dart`
- Modify: `lib/features/settings/settings_controller.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/features/connection/connection_controller.dart`
- Test: `test/features/settings/settings_controller_test.dart`
- Test: `test/features/repositories_test.dart`
- Test: `test/features/connection/connection_controller_test.dart`

**Interfaces:**

- Produces immutable `ServiceAccessOrigins(lanOrigin: String, externalOrigin: String)`.
- Produces `ServiceSettingsRepository.getAccessOrigins()` and `updateAccessOrigins(ServiceAccessOrigins value)`.
- Produces `ConnectionController.applyEndpoints({required String bootstrapOrigin, required String lanOrigin, required String externalOrigin})`.
- Produces `SettingsController.saveConnectionSettings(...)` and exposes busy/error state for the secondary page.

- [x] **Step 1: Add failing repository parsing tests**

Assert GET and PATCH parse the exact keys and reject missing/non-string responses:

```dart
expect(await repository.getAccessOrigins(), const ServiceAccessOrigins(
  lanOrigin: 'http://192.168.1.20:3124',
  externalOrigin: 'https://music.example.com',
));
```

- [x] **Step 2: Add failing connection transaction tests**

Cover success and failure:

- success switches the stable API only after a proposed candidate passes and persists bootstrap/LAN/external/last-connected roles;
- selection failure throws while leaving `state.value`, current API origin, and persisted client endpoints unchanged;
- a connected manual `connect` failure restores the previous `AsyncData` instead of replacing it with `AsyncError`.

- [x] **Step 3: Add failing settings-controller rollback tests**

Use recording callbacks to assert this order:

```text
read old shared origins → PATCH proposed shared origins → apply/probe proposed endpoints
```

If apply/probe fails, assert a compensating PATCH restores the old shared origins, local bootstrap remains unchanged, and the error is exposed without disconnecting.

- [x] **Step 4: Implement the repository and transaction**

Parse and patch both shared keys together. Validate all non-empty origins with `ServiceOrigin.parse` before the first write. Implement `applyEndpoints` without setting global connection state to `AsyncLoading`; commit the stable API base URL, diagnostics, and local persistence only after selection succeeds. Have `SettingsController.saveConnectionSettings` coordinate shared PATCH, connection apply, and compensating rollback.

- [x] **Step 5: Verify Task 3**

Run:

```sh
flutter test test/features/repositories_test.dart test/features/settings/settings_controller_test.dart test/features/connection/connection_controller_test.dart
git diff --check -- lib/features/settings/service_settings_repository.dart lib/features/settings/settings_controller.dart lib/features/connection/connection_controller.dart lib/app/runtime_providers.dart test/features
```

Expected: repository parsing, successful save, failed save rollback, and live-connection preservation all pass.

### Task 4: Build the compact summary, secondary route, and non-destructive sidebar link

**Files:**

- Create: `lib/features/settings/connection_settings_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/app/app_router.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/features/settings/settings_screen_test.dart`
- Create: `test/features/settings/connection_settings_screen_test.dart`
- Modify: `test/app/app_shell_routing_test.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**

- `SettingsScreen` receives `VoidCallback onConnectionSettings`.
- `ConnectionSettingsScreen` receives `SettingsController controller` and `VoidCallback? onBack`.
- Desktop footer receives `VoidCallback onConnectionSettings`; disconnect remains available only through the existing explicit disconnect action elsewhere.
- Status copy maps `EndpointRole.lan` → `内网连接`, `external` → `外网连接`, `bootstrap` → `备用地址连接`, and disconnected/unreachable → `暂不可达`.

- [x] **Step 1: Replace diagnostics-heavy widget expectations with failing summary tests**

Assert the settings overview contains `Service 连接`, one status label, and a tappable entry. Assert it does not contain the active URL, `延迟`, `API`, `最近检查`, `重新连接`, or any address input.

- [x] **Step 2: Add failing secondary-page tests**

Assert all three permanent labels and their initial values are visible, invalid origins show a user-facing error, and tapping `保存并检测` calls `saveConnectionSettings` once without calling disconnect. Cover both wide `/settings/connection` and mobile `/more/settings/connection` navigation paths.

- [x] **Step 3: Add a failing sidebar navigation test**

Tap `Service 已连接`, assert the router reaches the connection-settings route, and assert the connection remains non-null with the same API identity.

- [x] **Step 4: Implement the two-level UI**

Replace `_ConnectionCard` with a compact 44 px-or-larger semantic navigation row using existing design tokens and Lucide navigation glyphs. Move the three fields and save action into `connection_settings_screen.dart`. Add nested named routes for desktop and mobile, and change the footer callback from `onDisconnect` to `onConnectionSettings`.

- [x] **Step 5: Verify Task 4**

Run:

```sh
flutter test test/features/settings/settings_screen_test.dart test/features/settings/connection_settings_screen_test.dart test/app/app_shell_routing_test.dart test/app/app_shell_test.dart
git diff --check -- lib/features/settings lib/app/app_router.dart lib/app/app_shell.dart test/features/settings test/app
```

Expected: summary, secondary navigation, field editing, and non-destructive sidebar behavior pass at mobile and desktop sizes.

### Task 5: Make Service Web address fields explicit

**Files:**

- Modify: `/Volumes/ext/lx-music-server-web/src/renderer/views/Setting/components/SettingNetwork.vue`
- Modify: `/Volumes/ext/lx-music-server-web/src/lang/zh-cn.json`
- Modify: `/Volumes/ext/lx-music-server-web/src/lang/zh-tw.json`
- Modify: `/Volumes/ext/lx-music-server-web/src/lang/en-us.json`
- Modify: `/Volumes/ext/lx-music-server-web/tests/e2e/settings-theme.spec.ts`

**Interfaces:**

- Preserves `settings-service-lan-origin` and `settings-service-external-origin` selectors.
- Adds visible label and description translation keys for both shared origins.

- [x] **Step 1: Strengthen the Playwright test**

Before editing fields, assert visible localized text for the LAN label, external label, and their usage descriptions. Keep the existing persistence poll as the contract boundary.

- [x] **Step 2: Verify the test fails against placeholder-only markup**

Run:

```sh
npx playwright test tests/e2e/settings-theme.spec.ts -g "persists Service access origins"
```

Expected: FAIL because placeholders are not permanent labels/descriptions.

- [x] **Step 3: Add permanent labels and descriptions**

Wrap each `base-input` in a labeled field using the page's existing typography/classes. Add Chinese, Traditional Chinese, and English translations explaining that LAN is preferred on Wi-Fi/Ethernet and external is used outside the LAN; state that an empty value disables that candidate.

- [x] **Step 4: Verify Task 5**

Run:

```sh
npx playwright test tests/e2e/settings-theme.spec.ts -g "persists Service access origins"
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts
npm run lint -- --quiet
git diff --check -- src/renderer/views/Setting/components/SettingNetwork.vue src/lang tests/e2e/settings-theme.spec.ts
```

Expected: visible-copy, persistence, API contract, and lint checks pass.

### Task 6: Final cross-project verification

**Files:**

- Verify all files changed by Tasks 1–5.
- Update checkbox state in this plan after each successful checkpoint.

**Interfaces:**

- Consumes the completed client and Service Web behavior.
- Produces final evidence only; no deploy, commit, or unrelated cleanup.

- [x] **Step 1: Run the focused Flutter regression suite**

```sh
flutter test test/features/connection test/features/settings test/app/app_shell_test.dart test/app/app_shell_routing_test.dart test/features/home/home_screen_test.dart
flutter analyze
```

- [x] **Step 2: Run the focused Service regression suite**

```sh
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts
npx playwright test tests/e2e/settings-theme.spec.ts -g "persists Service access origins"
npm run lint -- --quiet
npm run build:web
```

- [x] **Step 3: Check frozen diffs and forbidden regressions**

```sh
git -C /Volumes/ext/MusicFree/flutter-client diff --check
git -C /Volumes/ext/lx-music-server-web diff --check
rg -n "refreshDiagnostics\(|ConnectionLifecycleHost|onResume" /Volumes/ext/MusicFree/flutter-client/lib
```

Expected: all checks pass; settings opening and foreground resume have no health-probe path; no files outside the approved scope were modified by this execution.
