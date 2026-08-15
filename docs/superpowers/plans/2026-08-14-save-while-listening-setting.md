# Flutter Save While Listening Setting Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Flutter settings switch that reads and updates the connected TuneFlow Service's shared `player.autoDownloadOnPlay` value.

**Architecture:** A focused `ServiceSettingsRepository` owns the Service API contract. `SettingsController` owns transient load/update/error state, while `settingsControllerProvider` injects the repository for the current connection. Desktop and mobile settings render the same Service-backed switch without persisting a local duplicate.

**Tech Stack:** Flutter, Dart, Riverpod, `ServiceApi`, `http/testing.dart`, `shadcn_ui`, `flutter_test`.

## Global Constraints

- The source of truth is `GET /api/v1/settings` and `PATCH /api/v1/settings` key `player.autoDownloadOnPlay`.
- Do not add this setting to `AppSettings` or `SharedPreferences`.
- The switch label is `边听边存`; its description is `播放在线音乐时，按 Service 的下载设置自动保存。`.
- Use stable widget key `settings-auto-download-on-play`.
- Loading, submission, unavailable connection, and read failure disable the switch; errors must not be shown as a false/off value.
- Preserve all existing uncommitted Flutter client changes. Apply narrow patches and inspect overlapping diffs before and after every task.
- Do not modify the Service repository, deploy, stage, or commit unless separately authorized.

---

### Task 1: Service Settings Repository

**Files:**
- Create: `lib/features/settings/service_settings_repository.dart`
- Create: `test/features/settings/service_settings_repository_test.dart`

**Interfaces:**
- Consumes: `ServiceApi.request(String method, String path, {Object? body, Map<String, String>? headers})`.
- Produces: `ServiceSettingsRepository(ServiceApi api)`, `Future<bool> getAutoDownloadOnPlay()`, and `Future<bool> setAutoDownloadOnPlay(bool value)`.

- [x] **Step 1: Write repository parsing and request-shape tests**

Create `test/features/settings/service_settings_repository_test.dart` with a `MockClient`-backed `ServiceApi`. Cover:

```dart
test('reads the Service auto-download setting', () async {
  final repository = repositoryFor((request) async {
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/settings');
    return data({'player.autoDownloadOnPlay': true});
  });

  expect(await repository.getAutoDownloadOnPlay(), isTrue);
});

test('patches only the Service auto-download setting', () async {
  final repository = repositoryFor((request) async {
    expect(request.method, 'PATCH');
    expect(request.url.path, '/api/v1/settings');
    expect(jsonDecode(request.body), {'player.autoDownloadOnPlay': false});
    return data({'player.autoDownloadOnPlay': false});
  });

  expect(await repository.setAutoDownloadOnPlay(false), isFalse);
});
```

Add two rejection tests where the response data omits the key or returns a string instead of a boolean. Expect a `ServiceException` whose code is `INVALID_RESPONSE`.

- [x] **Step 2: Run the repository test and verify the missing implementation fails**

Run:

```bash
flutter test test/features/settings/service_settings_repository_test.dart
```

Expected: compilation failure because `ServiceSettingsRepository` does not exist.

- [x] **Step 3: Implement strict Service setting parsing**

Create `lib/features/settings/service_settings_repository.dart` with this boundary:

```dart
import '../../api/service_api.dart';
import '../../api/service_exception.dart';

const _autoDownloadOnPlayKey = 'player.autoDownloadOnPlay';

final class ServiceSettingsRepository {
  const ServiceSettingsRepository(this.api);
  final ServiceApi api;

  Future<bool> getAutoDownloadOnPlay() async => _readBoolean(
    await api.request('GET', '/api/v1/settings'),
  );

  Future<bool> setAutoDownloadOnPlay(bool value) async => _readBoolean(
    await api.request(
      'PATCH',
      '/api/v1/settings',
      body: {_autoDownloadOnPlayKey: value},
    ),
  );

  bool _readBoolean(Object? value) {
    if (value case final Map data) {
      final setting = data[_autoDownloadOnPlayKey];
      if (setting is bool) return setting;
    }
    throw const ServiceException(
      'INVALID_RESPONSE',
      'Service settings response is missing player.autoDownloadOnPlay.',
    );
  }
}
```

Keep parsing strict: do not default a missing value to `false` and do not coerce strings or numbers.

- [x] **Step 4: Run repository tests and formatting**

Run:

```bash
dart format lib/features/settings/service_settings_repository.dart test/features/settings/service_settings_repository_test.dart
flutter test test/features/settings/service_settings_repository_test.dart
```

Expected: all repository tests pass.

- [x] **Step 5: Inspect the task diff without staging**

Run:

```bash
git diff --check -- lib/features/settings/service_settings_repository.dart test/features/settings/service_settings_repository_test.dart
git status --short -- lib/features/settings/service_settings_repository.dart test/features/settings/service_settings_repository_test.dart
```

Expected: only the two new files are reported; do not commit or stage them.

---

### Task 2: Controller State and Riverpod Wiring

**Files:**
- Modify: `lib/features/settings/settings_controller.dart`
- Modify: `lib/app/runtime_providers.dart`
- Modify: `test/features/settings/settings_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 `ServiceSettingsRepository.getAutoDownloadOnPlay()` and `setAutoDownloadOnPlay(bool)`.
- Produces on `SettingsController`: `bool? autoDownloadOnPlay`, `bool serviceSettingsBusy`, `Object? serviceSettingsError`, `bool get serviceSettingsAvailable`, `Future<void> refreshServiceSettings()`, and `Future<void> setAutoDownloadOnPlay(bool value)`.

- [x] **Step 1: Add controller tests for load, update, failure, and unavailable state**

Extend `test/features/settings/settings_controller_test.dart`. Add helper-injected callbacks to `SettingsController` and cover these exact outcomes:

```dart
test('loads and updates the shared Service auto-download setting', () async {
  var serviceValue = true;
  final updates = <bool>[];
  final controller = controllerForServiceSettings(
    load: () async => serviceValue,
    update: (value) async {
      updates.add(value);
      serviceValue = value;
      return serviceValue;
    },
  );

  await controller.refreshServiceSettings();
  expect(controller.autoDownloadOnPlay, isTrue);

  await controller.setAutoDownloadOnPlay(false);
  expect(updates, [false]);
  expect(controller.autoDownloadOnPlay, isFalse);
  expect(controller.serviceSettingsError, isNull);
});
```

Also test:

- A load exception leaves `autoDownloadOnPlay == null`, stores the error, and clears busy state.
- An update exception preserves the previous boolean and stores the error.
- A second update invoked while the first `Completer<bool>` is pending does not call the update callback twice.
- A controller without callbacks reports `serviceSettingsAvailable == false` and performs no request.

- [x] **Step 2: Run controller tests and verify the new API is absent**

Run:

```bash
flutter test test/features/settings/settings_controller_test.dart
```

Expected: compilation failure for the new constructor arguments and controller properties.

- [x] **Step 3: Add transient Service setting state to `SettingsController`**

Add typedefs and optional constructor parameters without changing existing call sites:

```dart
typedef LoadAutoDownloadOnPlay = Future<bool> Function();
typedef UpdateAutoDownloadOnPlay = Future<bool> Function(bool value);
```

Store them as nullable final fields. Add:

```dart
bool? autoDownloadOnPlay;
bool serviceSettingsBusy = false;
Object? serviceSettingsError;
bool _disposed = false;

bool get serviceSettingsAvailable =>
    _loadAutoDownloadOnPlay != null && _updateAutoDownloadOnPlay != null;
```

Implement `refreshServiceSettings()` so it clears the previous value before loading, sets busy/error consistently, and calls a guarded notification helper only while not disposed. Implement `setAutoDownloadOnPlay(bool value)` so it returns when unavailable, busy, unknown, or unchanged; it must keep the previous value until the Service confirms success and retain that previous value on failure.

Update `dispose()` to set `_disposed = true` before removing listeners and calling `super.dispose()`.

- [x] **Step 4: Inject the repository for the current connected Service**

In `lib/app/runtime_providers.dart`:

```dart
import '../features/settings/service_settings_repository.dart';
```

Watch the current connection so changing or clearing the Service rebuilds the controller:

```dart
final connected = ref.watch(connectionProvider).value;
final serviceSettings = connected == null
    ? null
    : ServiceSettingsRepository(connected.api);
```

Pass:

```dart
loadAutoDownloadOnPlay: serviceSettings?.getAutoDownloadOnPlay,
updateAutoDownloadOnPlay: serviceSettings?.setAutoDownloadOnPlay,
```

Retain the existing app-settings listener, media-cache injection, and controller disposal logic.

- [x] **Step 5: Run controller tests and targeted analysis**

Run:

```bash
dart format lib/features/settings/settings_controller.dart lib/app/runtime_providers.dart test/features/settings/settings_controller_test.dart
flutter test test/features/settings/settings_controller_test.dart
flutter analyze lib/features/settings/settings_controller.dart lib/app/runtime_providers.dart
```

Expected: controller tests pass and analysis reports no issues in these files.

- [x] **Step 6: Inspect overlapping user changes**

Run:

```bash
git diff --check -- lib/features/settings/settings_controller.dart lib/app/runtime_providers.dart test/features/settings/settings_controller_test.dart
git diff -- lib/features/settings/settings_controller.dart lib/app/runtime_providers.dart test/features/settings/settings_controller_test.dart
```

Expected: existing media-cache and settings synchronization edits remain intact; only the Service-setting additions are new. Do not stage or commit.

---

### Task 3: Desktop and Mobile Settings UI

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 controller properties and methods.
- Produces: a `ShadSwitch` keyed `settings-auto-download-on-play`, shared copy, disabled/busy/unavailable behavior, and visible error feedback.

- [x] **Step 1: Add widget tests for desktop, mobile, interaction, and error state**

Extend `test/features/settings/settings_screen_test.dart` with a controller whose load/update callbacks are deterministic.

Desktop test:

```dart
expect(find.text('边听边存'), findsOneWidget);
expect(find.text('播放在线音乐时，按 Service 的下载设置自动保存。'), findsOneWidget);
expect(find.byKey(const Key('settings-auto-download-on-play')), findsOneWidget);
```

After `pumpWidget`, use `pumpAndSettle()` so the initial Service load completes. Tap the keyed switch and assert the update callback receives the inverse value.

Add a mobile-size test at `390x844` asserting the same key and copy are present. Add an error-state test whose load callback throws; assert the switch is disabled and a concise `Service 设置读取失败` notice is visible without rendering the value as a false/off state.

- [x] **Step 2: Run widget tests and verify the switch is missing**

Run:

```bash
flutter test test/features/settings/settings_screen_test.dart
```

Expected: failures because `settings-auto-download-on-play` and its copy are absent.

- [x] **Step 3: Trigger Service setting loading when the page opens**

In `_SettingsScreenState.initState()`, retain diagnostics and add:

```dart
unawaited(widget.controller.refreshServiceSettings());
```

The controller guards unavailable connections and disposal.

- [x] **Step 4: Add a reusable Service-backed switch row**

Create a private `_AutoDownloadOnPlaySetting` widget in `settings_screen.dart` that reads controller state and renders:

```dart
ShadSwitch(
  key: const Key('settings-auto-download-on-play'),
  value: controller.autoDownloadOnPlay ?? false,
  enabled: controller.serviceSettingsAvailable &&
      !controller.serviceSettingsBusy &&
      controller.autoDownloadOnPlay != null,
  onChanged: (value) => unawaited(controller.setAutoDownloadOnPlay(value)),
  label: const Text('边听边存'),
  sublabel: const Text('播放在线音乐时，按 Service 的下载设置自动保存。'),
)
```

If the installed `ShadSwitch` version does not expose `sublabel`, place the description in a `Column` adjacent to the switch while keeping the same semantics and key. Do not add a new UI dependency.

When `serviceSettingsError != null`, render an `AppNotice.error` titled `Service 设置读取失败` before the first successful load and `Service 设置更新失败` when a prior boolean remains available. When the controller is unavailable, show muted text `连接 Service 后可设置` and keep the switch disabled.

- [x] **Step 5: Place the switch in both responsive preference layouts**

Add `_AutoDownloadOnPlaySetting(controller: controller)` to `_MobilePreferences` after default quality and to `_DesktopPreferences` after default quality. Preserve existing theme, transparency, lyrics, cache, and hidden compatibility widgets. Use existing spacing tokens rather than introducing layout constants.

- [x] **Step 6: Run widget tests and formatting**

Run:

```bash
dart format lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
flutter test test/features/settings/settings_screen_test.dart
```

Expected: desktop, mobile, interaction, and error-state tests pass.

- [x] **Step 7: Run the complete focused settings suite**

Run:

```bash
flutter test \
  test/features/settings/service_settings_repository_test.dart \
  test/features/settings/settings_controller_test.dart \
  test/features/settings/settings_screen_test.dart
```

Expected: all focused tests pass with zero failures.

- [x] **Step 8: Run static analysis and final diff checks**

Run:

```bash
flutter analyze
git diff --check
git status --short
git diff -- \
  lib/features/settings/service_settings_repository.dart \
  lib/features/settings/settings_controller.dart \
  lib/features/settings/settings_screen.dart \
  lib/app/runtime_providers.dart \
  test/features/settings/service_settings_repository_test.dart \
  test/features/settings/settings_controller_test.dart \
  test/features/settings/settings_screen_test.dart
```

Expected: analysis and whitespace checks pass. Review the diff to confirm the feature neither adds a `SharedPreferences` field nor overwrites existing cache/settings work. Record unrelated pre-existing dirty files separately in the handoff; do not clean them.
