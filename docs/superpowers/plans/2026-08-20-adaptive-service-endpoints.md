# Adaptive Service Endpoints Implementation Plan

> **For agentic workers:** Use the global workflow skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should workflow return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add persisted LAN and external Service origins and make the Flutter client select a verified origin automatically across network changes without rebuilding the playback session.

**Architecture:** The Service validates and publishes two configured origins through /api/v1/health. The client separates endpoint probing, network classification, candidate selection, persistence, and connection coordination; an automatic switch mutates the origin of one stable ServiceApi and publishes a refreshed ConnectedService snapshot so SSE and diagnostics update while the player keeps the same API identity.

**Tech Stack:** TypeScript 5.9, Fastify 5, TypeBox, Vue 3, Vitest, Playwright, Flutter 3.47, Dart 3.13, Riverpod 3, http, shared_preferences, connectivity_plus 7.3.1, Flutter widget tests.

## Global Constraints

- Follow /Volumes/ext/lx-music-server-web/AGENTS.md in the Service and the supplied project rules in /Volumes/ext/MusicFree/flutter-client.
- Preserve both repositories' existing dirty-worktree changes. Inspect every overlapping diff before editing, especially lib/features/settings/settings_screen.dart, pubspec.yaml, generated plugin registrants, and Android build files.
- Keep service.lanOrigin and service.externalOrigin empty by default and accept only normalized pathless HTTP(S) origins.
- Never infer a NAS host address from a Docker bridge and never scan a subnet.
- Wi-Fi and Ethernet use LAN → external → bootstrap; other available transports use external → bootstrap; offline performs no probe.
- Each endpoint health probe makes three total attempts, each with a three-second timeout and two seconds only between failed attempts.
- Cold start tries lastConnectedOrigin first, then re-evaluates the current network priority in the background.
- Existing service_origin remains the bootstrap preference and seeds lastConnectedOrigin when the new key is absent.
- Old Services whose health payload contains only status: ok remain supported.
- Automatic switching never retries arbitrary API mutations, never bypasses HTTPS validation, and never replaces the stable player session.
- Do not commit, push, publish, deploy, or alter NAS state; the user authorized local implementation and verification only.

---

### Task 1: Persist and validate Service origins

**Files:**

- Create: /Volumes/ext/lx-music-server-web/src/server/serviceOrigins.ts
- Modify: /Volumes/ext/lx-music-server-web/src/common/types/app_setting.d.ts
- Modify: /Volumes/ext/lx-music-server-web/src/common/defaultSetting.ts
- Modify: /Volumes/ext/lx-music-server-web/src/server/db/settingsRepository.ts
- Test: /Volumes/ext/lx-music-server-web/src/server/app.test.ts

**Interfaces:**

- Produces normalizeConfiguredServiceOrigin(value: unknown): string.
- Produces service.lanOrigin: string and service.externalOrigin: string.
- Preserves settings precedence and immutable download.savePath behavior.

- [x] **Step 1: Add failing settings tests**

Extend src/server/app.test.ts with exact default, normalization, rejection, and restart assertions:

~~~ts
expect(settings.data).toMatchObject({
  'service.lanOrigin': '',
  'service.externalOrigin': '',
})

const valid = await app.inject({
  method: 'PATCH',
  url: '/api/v1/settings',
  payload: {
    'service.lanOrigin': 'http://192.168.1.20:3124/',
    'service.externalOrigin': 'https://music.example.com/',
  },
})
expect(valid.json().data).toMatchObject({
  'service.lanOrigin': 'http://192.168.1.20:3124',
  'service.externalOrigin': 'https://music.example.com',
})

for (const value of [
  'ftp://192.168.1.20',
  'http://user:pass@192.168.1.20',
  'http://192.168.1.20/base',
  'http://192.168.1.20?mode=lan',
]) {
  const rejected = await app.inject({
    method: 'PATCH',
    url: '/api/v1/settings',
    payload: { 'service.lanOrigin': value },
  })
  expect(rejected.statusCode).toBe(400)
}
~~~

After closing and reopening the test server, assert the two normalized values remain.

- [x] **Step 2: Verify the red state**

Run:

~~~sh
npx vitest run src/server/app.test.ts -t "Service origins|server-safe default settings|persists settings"
~~~

Expected: failures because the settings keys do not exist and arbitrary strings currently pass the generic schema.

- [x] **Step 3: Add typed defaults and strict normalization**

Add both fields to TuneFlow.AppSetting and empty defaults beside the network settings. Implement:

~~~ts
import { ApiError } from './errors'

export const normalizeConfiguredServiceOrigin = (value: unknown): string => {
  if (value === '') return ''
  if (typeof value !== 'string') {
    throw new ApiError(400, 'INVALID_SETTING', 'Service origin must be a string')
  }
  let parsed: URL
  try {
    parsed = new URL(value.trim())
  } catch {
    throw new ApiError(400, 'INVALID_SETTING', 'Service origin must be a valid URL')
  }
  if (
    !['http:', 'https:'].includes(parsed.protocol) ||
    parsed.username !== '' ||
    parsed.password !== '' ||
    parsed.pathname !== '/' ||
    parsed.search !== '' ||
    parsed.hash !== ''
  ) {
    throw new ApiError(400, 'INVALID_SETTING', 'Service origin must be a pathless HTTP(S) origin')
  }
  return parsed.origin
}
~~~

In SettingsRepository.updateSettings, validate and normalize the two keys before any upsert executes so a rejected patch changes nothing.

- [x] **Step 4: Verify green and inspect the checkpoint**

Run:

~~~sh
npx vitest run src/server/app.test.ts -t "Service origins|server-safe default settings|persists settings"
git diff --check -- src/common/types/app_setting.d.ts src/common/defaultSetting.ts src/server/db/settingsRepository.ts src/server/serviceOrigins.ts src/server/app.test.ts
git diff -- src/common/types/app_setting.d.ts src/common/defaultSetting.ts src/server/db/settingsRepository.ts src/server/serviceOrigins.ts src/server/app.test.ts
~~~

Expected: tests pass; the diff contains only the two settings, validation, and tests.

### Task 2: Publish origins through health and expose Service UI fields

**Files:**

- Modify: /Volumes/ext/lx-music-server-web/src/server/routes/health.ts
- Modify: /Volumes/ext/lx-music-server-web/src/server/app.ts
- Modify: /Volumes/ext/lx-music-server-web/src/server/app.test.ts
- Modify: /Volumes/ext/lx-music-server-web/src/server/api/openapi.test.ts
- Modify: /Volumes/ext/lx-music-server-web/src/renderer/views/Setting/components/SettingNetwork.vue
- Modify: /Volumes/ext/lx-music-server-web/src/lang/zh-cn.json
- Modify: /Volumes/ext/lx-music-server-web/src/lang/zh-tw.json
- Modify: /Volumes/ext/lx-music-server-web/src/lang/en-us.json
- Modify: /Volumes/ext/lx-music-server-web/tests/e2e/settings-theme.spec.ts

**Interfaces:**

- Consumes SettingsRepository.getSettings() and Task 1 settings.
- Produces health data { status: 'ok', lanOrigin: string, externalOrigin: string }.
- Produces selectors settings-service-lan-origin and settings-service-external-origin.

- [x] **Step 1: Add failing health, OpenAPI, and settings UI tests**

Use these assertions:

~~~ts
expect((await app.inject({ method: 'GET', url: '/api/v1/health' })).json()).toEqual({
  data: { status: 'ok', lanOrigin: '', externalOrigin: '' },
})

await app.inject({
  method: 'PATCH',
  url: '/api/v1/settings',
  payload: {
    'service.lanOrigin': 'http://192.168.1.20:3124',
    'service.externalOrigin': 'https://music.example.com',
  },
})
expect((await app.inject({ method: 'GET', url: '/api/v1/health' })).json().data).toEqual({
  status: 'ok',
  lanOrigin: 'http://192.168.1.20:3124',
  externalOrigin: 'https://music.example.com',
})

expect(JSON.stringify(document.paths['/api/v1/health'].get.responses['200'])).toContain('lanOrigin')
expect(JSON.stringify(document.paths['/api/v1/health'].get.responses['200'])).toContain('externalOrigin')
~~~

Add a Playwright case named `persists Service access origins` that opens SettingNetwork, expects the two approved data-testid values, fills valid values, and polls /api/v1/settings for normalized persistence.

Run:

~~~sh
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts -t "health|OpenAPI"
npx playwright test tests/e2e/settings-theme.spec.ts -g "persists Service access origins"
~~~

Expected: Vitest fails because the health fields are missing; Playwright fails because the two controls are missing.

- [x] **Step 2: Inject live settings into the health route**

Change the signature and registration:

~~~ts
export const registerHealthRoutes = (
  app: ApiFastifyInstance,
  readSettings: () => TuneFlow.AppSetting,
): void => {
  const HealthDataSchema = Type.Object({
    status: Type.Literal('ok'),
    lanOrigin: Type.String(),
    externalOrigin: Type.String(),
  }, { additionalProperties: false })
  app.get('/api/v1/health', {
    schema: {
      operationId: 'getHealth',
      tags: ['System'],
      summary: 'Get Service health',
      response: { 200: ApiSuccess(HealthDataSchema) },
    },
  }, async() => {
    const settings = readSettings()
    return { data: {
      status: 'ok' as const,
      lanOrigin: settings['service.lanOrigin'],
      externalOrigin: settings['service.externalOrigin'],
    } }
  })
}

registerHealthRoutes(app, () => settings.getSettings())
~~~

Read settings on every request and update the TypeBox schema. Do not cache values.

- [x] **Step 3: Add the two Service UI fields and translations**

Add a Service-address section above the proxy section:

~~~pug
h3#network_service_title {{ $t('setting__network_service_title') }}
div
  .p
    base-input(data-testid="settings-service-lan-origin" :model-value="appSetting['service.lanOrigin']" :placeholder="$t('setting__network_service_lan_origin')" @update:model-value="setLanOrigin")
  .p
    base-input(data-testid="settings-service-external-origin" :model-value="appSetting['service.externalOrigin']" :placeholder="$t('setting__network_service_external_origin')" @update:model-value="setExternalOrigin")
~~~

Use the existing 500 ms debounce and trim before updateSetting. Add translations with these meanings:

~~~text
setting__network_service_title: Service 访问地址 / Service Access Addresses
setting__network_service_lan_origin: 内网访问地址 / LAN access address
setting__network_service_external_origin: 外网访问地址 / External access address
~~~

Use the failing Playwright case from Step 1 as the UI acceptance boundary.

- [x] **Step 4: Verify the Service contract and checkpoint**

Run:

~~~sh
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts
npm run lint -- --quiet
npx playwright test tests/e2e/settings-theme.spec.ts -g "persists Service access origins"
git diff --check -- src/server/routes/health.ts src/server/app.ts src/server/app.test.ts src/server/api/openapi.test.ts src/renderer/views/Setting/components/SettingNetwork.vue src/lang tests/e2e/settings-theme.spec.ts
~~~

Expected: unit tests, lint, and the focused browser acceptance case pass. Task 9 reruns the complete settings-theme browser file against the frozen implementation.

### Task 3: Persist the four client endpoint roles

**Files:**

- Modify: /Volumes/ext/MusicFree/flutter-client/lib/storage/app_preferences.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/storage/app_settings_controller.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/storage/app_preferences_test.dart
- Modify test fakes found by rg -n "implements AppPreferences" test lib --glob '*.dart'

**Interfaces:**

- Preserves AppSettings.origin as the bootstrap origin used by current UI code.
- Produces AppSettings.lastConnectedOrigin, lanOrigin, and externalOrigin.
- Produces copyWith clear flags for each nullable endpoint.
- Makes AppPreferences.clearOrigin() clear all four endpoint keys.

- [x] **Step 1: Add failing migration and round-trip tests**

~~~dart
test('legacy origin seeds bootstrap and last connected origins', () async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        'service_origin': 'http://legacy.local',
      });
  final settings = await SharedAppPreferences().read();
  expect(settings.origin, 'http://legacy.local');
  expect(settings.lastConnectedOrigin, 'http://legacy.local');
  expect(settings.lanOrigin, isNull);
  expect(settings.externalOrigin, isNull);
});

test('round trips and clears all endpoint roles', () async {
  final preferences = SharedAppPreferences();
  const settings = AppSettings(
    origin: 'https://bootstrap.example',
    lastConnectedOrigin: 'http://192.168.1.20:3124',
    lanOrigin: 'http://192.168.1.20:3124',
    externalOrigin: 'https://music.example.com',
  );
  await preferences.write(settings);
  expect(await preferences.read(), settings);
  await preferences.clearOrigin();
  final cleared = await preferences.read();
  expect([
    cleared.origin,
    cleared.lastConnectedOrigin,
    cleared.lanOrigin,
    cleared.externalOrigin,
  ], everyElement(isNull));
});
~~~

Run flutter test test/storage/app_preferences_test.dart and confirm compilation fails on missing fields.

- [x] **Step 2: Implement migration-safe persistence**

Add these keys:

~~~dart
static const _lastConnectedOriginKey = 'service_last_connected_origin';
static const _lanOriginKey = 'service_lan_origin';
static const _externalOriginKey = 'service_external_origin';
~~~

On read, use service_last_connected_origin when present and otherwise seed it in memory from service_origin. Extend write, equality, hashCode, and copyWith. Make clearOrigin remove all four keys with Future.wait.

Add an all-fields-required controller method:

~~~dart
Future<void> setServiceEndpoints({
  required String? bootstrapOrigin,
  required String? lastConnectedOrigin,
  required String? lanOrigin,
  required String? externalOrigin,
}) async {
  final current = state.value ?? await ref.read(appPreferencesProvider).read();
  await saveSettings(current.copyWith(
    origin: bootstrapOrigin,
    clearOrigin: bootstrapOrigin == null,
    lastConnectedOrigin: lastConnectedOrigin,
    clearLastConnectedOrigin: lastConnectedOrigin == null,
    lanOrigin: lanOrigin,
    clearLanOrigin: lanOrigin == null,
    externalOrigin: externalOrigin,
    clearExternalOrigin: externalOrigin == null,
  ));
}
~~~

- [x] **Step 3: Update fakes, verify green, and inspect**

Run:

~~~sh
flutter test test/storage/app_preferences_test.dart test/features/connection/connection_controller_test.dart
git diff --check -- lib/storage/app_preferences.dart lib/storage/app_settings_controller.dart test/storage test/features/connection/connection_controller_test.dart
git diff -- lib/storage/app_preferences.dart lib/storage/app_settings_controller.dart test/storage/app_preferences_test.dart
~~~

Expected: tests pass and theme, language, playback, and cache fields remain unchanged.

### Task 4: Build the retrying health probe and capability boundary

**Files:**

- Create: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/server_endpoint_probe.dart
- Create: /Volumes/ext/MusicFree/flutter-client/test/features/connection/server_endpoint_probe_test.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/connection_repository.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/test/features/repositories_test.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/test/features/connection/connection_controller_test.dart

**Interfaces:**

- Produces HealthSnapshot(origin, lanOrigin, externalOrigin, latency).
- Produces ServerEndpointProbe.probe(String origin, {bool Function()? cancelled}).
- Produces ConnectionRepository.connectProbed(HealthSnapshot snapshot).
- Preserves ConnectionRepository.connect(String).

- [x] **Step 1: Write failing retry, timeout, parsing, and compatibility tests**

~~~dart
test('tries three times with two second gaps and stops on success', () async {
  var attempts = 0;
  final waits = <Duration>[];
  final probe = ServerEndpointProbe(
    requestHealth: (origin) async {
      attempts++;
      if (attempts < 3) {
        throw const ServiceException('NETWORK_ERROR', 'down');
      }
      return {
        'status': 'ok',
        'lanOrigin': 'http://192.168.1.20:3124/',
        'externalOrigin': 'https://music.example.com/',
      };
    },
    delay: (duration) async => waits.add(duration),
  );
  final result = await probe.probe('https://bootstrap.example');
  expect(attempts, 3);
  expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
  expect(result.lanOrigin?.uri.toString(), 'http://192.168.1.20:3124');
  expect(result.externalOrigin?.uri.toString(), 'https://music.example.com');
});
~~~

Add separate tests for three-second timeout, first-attempt success, cancellation before a retry, status-only old payloads, and invalid advertised origins being ignored without invalidating the probed origin.

Run flutter test test/features/connection/server_endpoint_probe_test.dart and confirm the types are missing.

- [x] **Step 2: Implement the probe with injected time**

Use:

~~~dart
typedef HealthRequest = Future<Object?> Function(ServiceOrigin origin);
typedef ProbeDelay = Future<void> Function(Duration duration);

final class HealthSnapshot {
  const HealthSnapshot({
    required this.origin,
    required this.lanOrigin,
    required this.externalOrigin,
    required this.latency,
  });
  final ServiceOrigin origin;
  final ServiceOrigin? lanOrigin;
  final ServiceOrigin? externalOrigin;
  final Duration latency;
}
~~~

The production request creates a short-lived ServiceApi, requests /api/v1/health, and closes it in finally. Each attempt uses a three-second timeout; only failures one and two wait two seconds. Validate status == ok. Parse advertised origins with ServiceOrigin.parse inside an ignore-invalid helper.

- [x] **Step 3: Refactor ConnectionRepository without duplicating health**

Make connect call probe then connectProbed. connectProbed creates the durable ServiceApi, requests /api/v1/capabilities once with a three-second timeout, requires apiVersion == v1, and closes on failure. Update repository tests to assert request order is exactly health then capabilities.

Run:

~~~sh
flutter test test/features/connection/server_endpoint_probe_test.dart test/features/repositories_test.dart test/features/connection/connection_controller_test.dart
git diff --check -- lib/features/connection/server_endpoint_probe.dart lib/features/connection/connection_repository.dart test/features/connection test/features/repositories_test.dart
~~~

Expected: all selected tests pass; only health retries.

### Task 5: Classify network transports and select bounded candidates

**Files:**

- Modify carefully: /Volumes/ext/MusicFree/flutter-client/pubspec.yaml
- Modify mechanically: /Volumes/ext/MusicFree/flutter-client/pubspec.lock
- Modify mechanically if generated: platform registrants under linux, macos, and windows
- Create: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/network_type_monitor.dart
- Create: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/endpoint_selector.dart
- Create: /Volumes/ext/MusicFree/flutter-client/test/features/connection/network_type_monitor_test.dart
- Create: /Volumes/ext/MusicFree/flutter-client/test/features/connection/endpoint_selector_test.dart

**Interfaces:**

- Produces NetworkTransport and NetworkRoute { lan, external, offline }.
- Produces NetworkTypeMonitor.current() and changes.
- Produces EndpointCatalog({ServiceOrigin? bootstrapOrigin, ServiceOrigin? lastConnectedOrigin, ServiceOrigin? lanOrigin, ServiceOrigin? externalOrigin}).
- Produces EndpointSelectionService({required ServerEndpointProbe probe, required ConnectionRepository connections}).
- Produces Future<EndpointSelection?> select({required EndpointCatalog catalog, required NetworkRoute route, required bool Function() generationIsCurrent}).

- [x] **Step 1: Write failing classification and ordering tests**

~~~dart
expect(classifyNetwork({NetworkTransport.wifi}), NetworkRoute.lan);
expect(classifyNetwork({NetworkTransport.ethernet}), NetworkRoute.lan);
expect(classifyNetwork({NetworkTransport.mobile}), NetworkRoute.external);
expect(classifyNetwork({NetworkTransport.vpn}), NetworkRoute.external);
expect(classifyNetwork({NetworkTransport.none}), NetworkRoute.offline);

expect(
  catalog.candidates(NetworkRoute.lan).map((item) => item.uri.toString()),
  ['http://lan.local', 'https://external.example', 'https://bootstrap.example'],
);
~~~

Add tests that an external response advertising a new LAN origin promotes LAN before the healthy external fallback, duplicates are visited once, status-only responses work, cancellation returns no selection, and at most eight unique origins are visited.

Run both new test files and confirm missing types.

- [x] **Step 2: Add connectivity_plus and the platform adapter**

Add connectivity_plus: ^7.3.1, run flutter pub get, and implement:

~~~dart
abstract interface class NetworkTypeMonitor {
  Future<Set<NetworkTransport>> current();
  Stream<Set<NetworkTransport>> get changes;
}

final class ConnectivityNetworkTypeMonitor implements NetworkTypeMonitor {
  ConnectivityNetworkTypeMonitor([Connectivity? connectivity]);
}
~~~

Map List<ConnectivityResult>, discard none when another transport exists, and normalize events to sets. Any set containing Wi-Fi or Ethernet is LAN; only none or empty is offline; all other non-empty sets are external.

- [x] **Step 3: Implement dynamic selection**

Use:

~~~dart
final class EndpointSelection {
  const EndpointSelection({
    required this.connected,
    required this.health,
    required this.catalog,
  });
  final ConnectedService connected;
  final HealthSnapshot health;
  final EndpointCatalog catalog;
}
~~~

The selector accepts probe, repository, route, catalog, and generation-valid callback. Track visited normalized strings in insertion order, stage a healthy fallback, insert newly advertised origins by semantic priority, validate capabilities before return, and stop after eight unique origins. Offline returns null without requests.

Run:

~~~sh
flutter test test/features/connection/network_type_monitor_test.dart test/features/connection/endpoint_selector_test.dart
git diff --check -- pubspec.yaml pubspec.lock linux macos windows lib/features/connection test/features/connection
git diff -- pubspec.yaml pubspec.lock linux macos windows
~~~

Expected: tests pass. Verify generated changes add connectivity_plus without removing the user's current dependency or plugin changes.

### Task 6: Make the active API origin replaceable

**Files:**

- Modify: /Volumes/ext/MusicFree/flutter-client/lib/api/service_api.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/connection_repository.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/api/service_api_test.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/api/sse_transport_test.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/features/repositories_test.dart

**Interfaces:**

- Produces ServiceApi.switchOrigin(ServiceOrigin next).
- Makes ConnectedService.origin a getter backed by api.origin.
- Extends ConnectionDiagnostics with active origin, nullable latency/API, NetworkRoute, reachability, and check time.
- Produces ConnectedService.copyWith({Capabilities? capabilities, ConnectionDiagnostics? diagnostics}) while retaining api identity.

- [x] **Step 1: Add a failing switched-request test**

~~~dart
test('subsequent requests use a switched origin', () async {
  final urls = <String>[];
  final api = ServiceApi(
    ServiceOrigin.parse('https://external.example'),
    client: MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response(jsonEncode({'data': {'ok': true}}), 200);
    }),
  );
  await api.request('GET', '/api/v1/test');
  api.switchOrigin(ServiceOrigin.parse('http://192.168.1.20:3124'));
  await api.request('GET', '/api/v1/test');
  expect(urls, [
    'https://external.example/api/v1/test',
    'http://192.168.1.20:3124/api/v1/test',
  ]);
});
~~~

Run flutter test test/api/service_api_test.dart test/features/repositories_test.dart and confirm switchOrigin, the expanded diagnostics constructor, and ConnectedService.copyWith are missing.

Also add a repository test that constructs unreachable diagnostics with null latency/API and NetworkRoute.lan, then copies the ConnectedService with a reachable snapshot while asserting identical(original.api, copied.api). This test must fail to compile before the diagnostics and copy API exist.

- [x] **Step 2: Implement origin replacement and stable selection**

Replace the final origin field with:

~~~dart
ServiceOrigin _origin;
ServiceOrigin get origin => _origin;

void switchOrigin(ServiceOrigin next) {
  _origin = next;
}
~~~

Keep the HTTP client. Make ConnectedService.origin return api.origin. Add an optional diagnostics field and a copyWith method retaining api. Define diagnostics as:

~~~dart
final class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    required this.origin,
    required this.connected,
    required this.latency,
    required this.apiVersion,
    required this.networkRoute,
    required this.checkedAt,
  });
  final String origin;
  final bool connected;
  final Duration? latency;
  final String? apiVersion;
  final NetworkRoute networkRoute;
  final DateTime checkedAt;
}
~~~

Extend the test to construct ConnectedService around the API, call switchOrigin, and assert connected.origin reports the new normalized origin.

Extend the existing SSE reconnect test so the first stream ends, switch the shared API origin during the injected reconnect delay, and assert the next snapshot and stream requests target the new origin. This proves reconnect uses the active origin without retrying or replaying an API mutation.

- [x] **Step 3: Verify the API and connection snapshot behavior**

Run:

~~~sh
flutter test test/api/service_api_test.dart test/api/sse_transport_test.dart test/features/repositories_test.dart
~~~

Expected: requests and ConnectedService.origin switch without replacing the HTTP client.

### Task 7: Coordinate cold start, network events, and latest-wins switching

**Files:**

- Modify: /Volumes/ext/MusicFree/flutter-client/lib/app/app_providers.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/connection_controller.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/app/player_providers.dart
- Create: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/connection_lifecycle_host.dart
- Modify carefully: /Volumes/ext/MusicFree/flutter-client/lib/app/app.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/features/connection/connection_controller_test.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/app/app_shell_test.dart

**Interfaces:**

- Produces networkTypeMonitorProvider, serverEndpointProbeProvider, and endpointSelectionServiceProvider so tests can override platform and timing dependencies.
- Produces ConnectionController.handleNetworkChange(Set<NetworkTransport>) and resume().
- Produces ConnectionLifecycleHost invoking resume on AppLifecycleState.resumed.
- Makes playerControllerProvider select stable ServiceApi identity instead of the changing ConnectedService snapshot.

- [x] **Step 1: Add failing controller behavior tests**

Write separate tests for:

~~~text
cold start commits lastConnectedOrigin before background LAN preference
Wi-Fi and Ethernet use LAN → external → bootstrap
mobile and VPN use external → bootstrap
an obsolete generation cannot commit after a newer generation
automatic total failure preserves the connected API and marks it unreachable
manual total failure preserves all four persisted endpoint values
disconnect clears all four values and cancels the active generation
~~~

Use fake monitors and Completers. Assert exact probed-origin order, saved AppSettings snapshots, and API identity.

Run flutter test test/features/connection/connection_controller_test.dart and confirm missing providers/methods and behavior failures.

- [x] **Step 2: Implement the state machine**

In build: read preferences, subscribe to normalized monitor changes, start current transport lookup, try lastConnectedOrigin, and schedule background route selection after a successful restore. If last-connected fails, use current route candidates before returning the existing error state.

Manual connect normalizes and stages the entered bootstrap, selects using current route, persists all roles only after health plus API v1 succeeds, then closes the prior API and publishes the new session.

Automatic handling increments _generation, de-duplicates equal transport sets, briefly debounces bursts, and passes a generation predicate to the selector. Before commit, check it again. Commit with:

~~~dart
final stableApi = current.api;
selected.connected.api.close();
stableApi.switchOrigin(selected.health.origin);
state = AsyncData(current.copyWith(
  capabilities: selected.connected.capabilities,
  diagnostics: ConnectionDiagnostics(
    origin: selected.health.origin.uri.toString(),
    connected: true,
    latency: selected.health.latency,
    apiVersion: selected.connected.capabilities.apiVersion,
    networkRoute: route,
    checkedAt: DateTime.now(),
  ),
));
await appSettings.setServiceEndpoints(
  bootstrapOrigin: selected.catalog.bootstrapOrigin?.uri.toString(),
  lastConnectedOrigin: selected.health.origin.uri.toString(),
  lanOrigin: selected.catalog.lanOrigin?.uri.toString(),
  externalOrigin: selected.catalog.externalOrigin?.uri.toString(),
);
~~~

If persistence fails, keep the verified live origin and report a diagnostic error. If all automatic candidates fail, keep the API and mark the snapshot unreachable.

Change playerControllerProvider before running the switching tests:

~~~dart
final api = ref.watch(
  connectionProvider.select((connection) => connection.value?.api),
);
if (api == null) return null;
~~~

Use api for PlaybackRepository and PlaybackHistoryRepository. The automatic-switch test must assert identical(playerBefore, playerAfter); add a manual-server-replacement test asserting the player instance changes when the API identity changes.

- [x] **Step 3: Add resume lifecycle behavior**

Implement ConnectionLifecycleHost as a stateful WidgetsBindingObserver wrapper. Register/unregister correctly and call the supplied callback only on resumed. Wrap the app result in _AppView. Add a widget test that sends paused then resumed and asserts one fresh monitor check.

- [x] **Step 4: Verify connection regressions**

Run:

~~~sh
flutter test test/features/connection/connection_controller_test.dart test/features/connection/connection_screen_test.dart test/app/app_shell_test.dart
git diff --check -- lib/app/app_providers.dart lib/app/app.dart lib/features/connection test/features/connection test/app/app_shell_test.dart
~~~

Expected: cold start, manual connect, routing, latest-wins switching, and lifecycle cases pass.

### Task 8: Surface diagnostics and declare Apple local-network intent

**Files:**

- Modify: /Volumes/ext/MusicFree/flutter-client/lib/features/connection/connection_repository.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/lib/app/runtime_providers.dart
- Modify carefully: /Volumes/ext/MusicFree/flutter-client/lib/features/settings/settings_controller.dart
- Modify carefully: /Volumes/ext/MusicFree/flutter-client/lib/features/settings/settings_screen.dart
- Test: /Volumes/ext/MusicFree/flutter-client/test/features/settings/settings_controller_test.dart
- Test carefully: /Volumes/ext/MusicFree/flutter-client/test/features/settings/settings_screen_test.dart
- Modify: /Volumes/ext/MusicFree/flutter-client/ios/Runner/Info.plist
- Modify: /Volumes/ext/MusicFree/flutter-client/macos/Runner/Info.plist

**Interfaces:**

- Consumes Task 6 ConnectionDiagnostics with nullable latency/API, active origin, NetworkRoute, reachability, and check time.
- Settings UI starts from the current session snapshot; manual refresh still uses ConnectionRepository.diagnostics.
- Uses the local-network explanation: TuneFlow 需要访问局域网中的音乐服务器，以便优先使用内网连接。

- [x] **Step 1: Add failing diagnostics tests**

Create unreachable-LAN and healthy-external fixtures. Assert:

~~~dart
expect(find.text('暂不可达'), findsOneWidget);
expect(find.text('http://192.168.1.20:3124'), findsOneWidget);
expect(find.text('Wi-Fi / 有线网络'), findsOneWidget);
expect(find.text('外网连接'), findsOneWidget);
~~~

Also assert active origin, latency, API v1, and a formatted check time, while raw exception strings stay hidden.

Run the two focused settings test files and confirm current diagnostics cannot represent the approved states.

- [x] **Step 2: Bind diagnostics to the settings UI narrowly**

Pass connected.diagnostics into SettingsController. On manual refresh failure, retain origin/route, construct a snapshot with connected false and nullable latency/API as appropriate, and keep the exception only in diagnosticsError.

Update _ConnectionCard to show the editable bootstrap separately from actual active origin, transport label, connected/unreachable/pending badge, optional latency/API, and HH:mm:ss check time. Reuse AppTextField, AppStatusBadge, AppNotice, current spacing, and current typography. Do not introduce a new icon family or shrink icon targets.

- [x] **Step 3: Add Apple local-network declarations**

In both plist files add:

~~~xml
<key>NSLocalNetworkUsageDescription</key>
<string>TuneFlow 需要访问局域网中的音乐服务器，以便优先使用内网连接。</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
~~~

Do not add NSAllowsArbitraryLoads. Do not change Android's existing usesCleartextTraffic="true".

- [x] **Step 4: Verify settings and plist changes**

Run:

~~~sh
flutter test test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart
plutil -lint ios/Runner/Info.plist macos/Runner/Info.plist
git diff --check -- lib/features/settings lib/features/connection/connection_repository.dart lib/app/runtime_providers.dart ios/Runner/Info.plist macos/Runner/Info.plist test/features/settings
~~~

Expected: widget/controller tests pass and both plists are valid.

### Task 9: Cross-project integration verification and final review

**Files:**

- Review every Task 1–8 file.
- Update this plan's checkboxes as tasks complete.

**Interfaces:**

- Verifies the frozen Service health/settings contract against the Flutter parser and selector.
- Produces no new runtime behavior.

- [ ] **Step 1: Verify Service**

Verification note: the feature-focused Service tests, lint, server build, and full settings Playwright suite pass. The combined OpenAPI suite remains blocked by the pre-existing `/api/v1/catalog/albums/detail` path being present in the dirty implementation but absent from that suite's `expectedPaths` list.

From /Volumes/ext/lx-music-server-web run:

~~~sh
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts
npm run lint -- --quiet
npm run build:server
npx playwright test tests/e2e/settings-theme.spec.ts
~~~

Expected: every command exits zero and the settings fields persist normalized values.

- [x] **Step 2: Verify Flutter**

From /Volumes/ext/MusicFree/flutter-client run:

~~~sh
flutter test test/storage/app_preferences_test.dart test/api/service_api_test.dart test/api/sse_transport_test.dart test/features/connection/server_endpoint_probe_test.dart test/features/connection/network_type_monitor_test.dart test/features/connection/endpoint_selector_test.dart test/features/connection/connection_controller_test.dart test/features/connection/connection_screen_test.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart test/app/app_shell_test.dart test/features/player/player_controller_test.dart
flutter analyze
plutil -lint ios/Runner/Info.plist macos/Runner/Info.plist
~~~

Expected: tests, analysis, and plist checks exit zero.

- [x] **Step 3: Check exact cross-project contracts**

Run:

~~~sh
rg -n "service\.(lanOrigin|externalOrigin)|lanOrigin|externalOrigin" /Volumes/ext/lx-music-server-web/src/server /Volumes/ext/lx-music-server-web/src/common /Volumes/ext/MusicFree/flutter-client/lib
rg -n "Duration\(seconds: (2|3)\)|maxAttempts" /Volumes/ext/MusicFree/flutter-client/lib/features/connection
~~~

Confirm field names and retry constants exactly match the approved specification.

- [x] **Step 4: Freeze and review both diffs**

Run:

~~~sh
git -C /Volumes/ext/lx-music-server-web diff --check
git -C /Volumes/ext/MusicFree/flutter-client diff --check
git -C /Volumes/ext/lx-music-server-web status --short
git -C /Volumes/ext/MusicFree/flutter-client status --short
~~~

Review task-owned hunks only. Confirm there are no credentials, debug logging, broad ATS exceptions, unrelated refactors, accidental generated-file deletions, or overwritten pre-existing changes. Report any command that could not run and its residual risk.
