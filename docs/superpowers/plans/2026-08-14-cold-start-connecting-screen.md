# Cold-Start Service Connecting Screen Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a dedicated branded connecting view while a saved Service origin is restored on cold start, then prefill that origin in the connection form if restoration fails.

**Architecture:** Keep `/connect` and `connectionProvider` unchanged. `ConnectionScreen` observes `appSettingsProvider`, restores the persisted origin into an untouched controller once, and distinguishes cold-start loading from user-triggered loading with local interaction flags; a private view renders the dedicated cold-start state.

**Tech Stack:** Flutter, Dart, Riverpod `AsyncNotifierProvider`, GoRouter, shadcn_ui, Flutter localization generation, flutter_test, http `MockClient`.

## Global Constraints

- Do not add a route, dependency, retry loop, cancellation API, or new global connection state type.
- The cold-start view contains the TuneFlow logo, localized connecting title, saved origin, and an indeterminate progress indicator, with no actions.
- A first launch with no saved origin continues to show the empty connection form and platform-specific placeholder.
- A manual connection attempt remains on the form and uses the existing button loading feedback.
- A persisted origin initializes only an untouched empty input and never overwrites user-entered text.
- Connection success remains the only path that persists a new origin; explicit disconnect continues to clear it.
- Preserve all unrelated dirty-worktree changes.
- Do not commit unless the user separately authorizes a commit.

---

### Task 1: Cold-start connecting state and persisted-origin fallback

**Files:**
- Modify: `test/features/connection/connection_screen_test.dart`
- Modify: `lib/features/connection/connection_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Regenerate: `lib/l10n/app_localizations.dart`
- Regenerate: `lib/l10n/app_localizations_en.dart`
- Regenerate: `lib/l10n/app_localizations_zh.dart`

**Interfaces:**
- Consumes: `appSettingsProvider: AsyncNotifierProvider<AppSettingsController, AppSettings>` and `connectionProvider: AsyncNotifierProvider<ConnectionController, ConnectedService?>`.
- Produces: a private `_ColdStartConnectingView({required String origin})` widget keyed `cold-start-connecting-route`; a new localization getter `AppLocalizations.connectingTitle`.
- Preserves: `ConnectionScreen`, `service-origin-field`, `connect-button`, `connection-route`, `defaultServiceOrigin(TargetPlatform)`, and all connection controller APIs.

- [x] **Step 1: Add a failing test for the dedicated cold-start view**

Add imports for `dart:async`, `musicfree_service_client/design/components/app_button.dart`, and `musicfree_service_client/storage/app_preferences.dart`; the test file already imports `ServiceApi`, `http`, and `MockClient`. Create a `Completer<http.Response>` for the health request so the automatic connection remains in progress. Pump the real `MusicFreeServiceApp` with `MemoryAppPreferences(const AppSettings(origin: 'http://saved.local'))` and a `ConnectionRepository` backed by `MockClient`.

```dart
testWidgets('shows the saved origin in a dedicated cold-start connecting view', (
  tester,
) async {
  final pendingHealth = Completer<http.Response>();
  final repository = ConnectionRepository(
    (origin) => ServiceApi(
      origin,
      client: MockClient((request) => pendingHealth.future),
    ),
  );

  await tester.pumpWidget(
    MusicFreeServiceApp(
      connectionRepository: repository,
      preferences: MemoryAppPreferences(
        const AppSettings(origin: 'http://saved.local'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  expect(find.byKey(const Key('cold-start-connecting-route')), findsOneWidget);
  expect(find.text('正在连接音流服务'), findsOneWidget);
  expect(find.text('http://saved.local'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  expect(find.byKey(const Key('service-origin-field')), findsNothing);
});
```

The production change this test catches is removing the cold-start branch or failing to expose the actual persisted origin while the network request is pending.

- [x] **Step 2: Add a failing test for failure fallback and address prefill**

Use a `MockClient` that throws `http.ClientException` so the persisted automatic attempt fails. Assert on the real input controller rather than mock calls.

```dart
testWidgets('prefills the saved origin after cold-start connection fails', (
  tester,
) async {
  final repository = ConnectionRepository(
    (origin) => ServiceApi(
      origin,
      client: MockClient(
        (request) async =>
            throw http.ClientException('connection refused', request.url),
      ),
    ),
  );

  await tester.pumpWidget(
    MusicFreeServiceApp(
      connectionRepository: repository,
      preferences: MemoryAppPreferences(
        const AppSettings(origin: 'http://offline.local'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('connection-route')), findsOneWidget);
  expect(find.byKey(const Key('connection-error')), findsOneWidget);
  expect(
    tester
        .widget<ShadInputFormField>(
          find.byKey(const Key('service-origin-field')),
        )
        .controller
        ?.text,
    'http://offline.local',
  );
});
```

The production change this test catches is failing to transfer the retained preference into the retry form after the automatic connection errors.

- [x] **Step 3: Add a failing test that manual loading stays on the form**

Start without a saved origin, enter `http://manual.local`, and use a pending `MockClient` response. Tap the real connect button and verify the dedicated cold-start key remains absent while the form and its loading button remain present.

```dart
testWidgets('keeps a user-triggered connection attempt on the form', (
  tester,
) async {
  final pendingHealth = Completer<http.Response>();
  final repository = ConnectionRepository(
    (origin) => ServiceApi(
      origin,
      client: MockClient((request) => pendingHealth.future),
    ),
  );

  await tester.pumpWidget(
    MusicFreeServiceApp(
      connectionRepository: repository,
      preferences: MemoryAppPreferences(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('service-origin-field')),
    'http://manual.local',
  );
  await tester.tap(find.byKey(const Key('connect-button')));
  await tester.pump();

  expect(find.byKey(const Key('cold-start-connecting-route')), findsNothing);
  expect(find.byKey(const Key('connection-route')), findsOneWidget);
  expect(
    tester.widget<AppButton>(find.byKey(const Key('connect-button'))).loading,
    isTrue,
  );
});
```

Use the `AppButton` import added in Step 1. The production change this test catches is treating every loading state as cold-start restoration.

- [x] **Step 4: Run the focused tests and verify RED**

Run:

```bash
flutter test test/features/connection/connection_screen_test.dart
```

Expected: the existing tests pass; the new cold-start view and prefill assertions fail because `ConnectionScreen` currently always renders the form and initializes its controller with an empty string. The manual-loading test may already pass and serves as a preserved behavior check; at least the two new feature tests must fail for the expected missing behavior.

- [x] **Step 5: Add localized connecting-title copy**

Add this key to both ARB files next to `connecting`:

```json
// lib/l10n/app_en.arb
"connectingTitle": "Connecting to TuneFlow Service",

// lib/l10n/app_zh.arb
"connectingTitle": "正在连接音流服务",
```

Regenerate localization sources:

```bash
flutter gen-l10n
```

Expected generated interface:

```dart
String get connectingTitle;
```

- [x] **Step 6: Implement one-time persisted-origin restoration**

Import both `../../storage/app_preferences.dart` for `AppSettings` and `../../storage/app_settings_controller.dart` for `appSettingsProvider`. Add local flags to `_ConnectionScreenState`:

```dart
bool _originEdited = false;
bool _manualConnectionStarted = false;
String? _persistedOrigin;
```

In `initState`, use Riverpod's lifecycle-safe manual listener and restore only an untouched empty controller:

```dart
@override
void initState() {
  super.initState();
  ref.listenManual<AsyncValue<AppSettings>>(
    appSettingsProvider,
    (previous, next) {
      final savedOrigin = next.value?.origin;
      if (savedOrigin == null || !mounted) return;
      if (!_originEdited && origin.text.isEmpty) {
        origin.text = savedOrigin;
      }
      if (_persistedOrigin != savedOrigin) {
        setState(() => _persistedOrigin = savedOrigin);
      }
    },
    fireImmediately: true,
  );
}
```

Before invoking the controller from `connect()`, mark the attempt as manual:

```dart
if (!_manualConnectionStarted) {
  setState(() => _manualConnectionStarted = true);
}
await ref.read(connectionProvider.notifier).connect(origin.text.trim());
```

Add this callback to `ShadInputFormField` so a real edit protects the user's text from late preference delivery:

```dart
onChanged: (_) {
  _originEdited = true;
},
```

Do not clear either flag when a manual attempt fails; that keeps subsequent retries on the form.

- [x] **Step 7: Render the cold-start connecting view**

At the beginning of `build`, derive the branch from real state:

```dart
final coldStartConnecting =
    connection.isLoading &&
    _persistedOrigin != null &&
    !_originEdited &&
    !_manualConnectionStarted;
if (coldStartConnecting) {
  return _ColdStartConnectingView(origin: _persistedOrigin!);
}
```

Implement the private widget with the same safe-area, centered width, padding, image, and dark/light theme behavior as the form. The observable structure must be:

```dart
final class _ColdStartConnectingView extends StatelessWidget {
  const _ColdStartConnectingView({required this.origin});

  final String origin;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('cold-start-connecting-route'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/TuneFlow.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(LucideIcons.audioLines, size: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.connectingTitle,
                    style: ShadTheme.of(context).textTheme.h3,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(origin, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Set the origin style to `ShadTheme.of(context).textTheme.muted`. Do not add buttons, gestures, timers, or navigation calls.

- [x] **Step 8: Run focused tests and verify GREEN**

Run:

```bash
flutter test test/features/connection/connection_screen_test.dart
```

Expected: all connection screen tests pass. The pending futures intentionally remain incomplete and are released when each test disposes its `ProviderScope`; they require no timers or external resources.

- [x] **Step 9: Format the modified Dart files**

Run:

```bash
dart format lib/features/connection/connection_screen.dart test/features/connection/connection_screen_test.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart
```

Expected: formatter exits successfully and changes only formatting in the listed files.

- [x] **Step 10: Lock the late-preference race with a mutation-checked test**

Add `does not overwrite user input when saved settings arrive late` using a test-only delayed `AppPreferences`. Enter `http://manual.local` before completing the stored settings with `http://saved.local`, then assert the real input controller still contains the manual value and the cold-start view stays hidden.

Mutation check: temporarily replace the untouched-input guard with unconditional restoration, run the named test and require it to fail with actual `http://saved.local`; restore the guard and rerun the full connection screen test file to require all tests to pass.

---

### Task 2: Connection lifecycle regression verification

**Files:**
- Test: `test/features/connection/connection_controller_test.dart`
- Test: `test/app/app_shell_test.dart`
- Review: all files modified by Task 1

**Interfaces:**
- Consumes: the unchanged `ConnectionController.build`, `connect`, and `disconnect` persistence lifecycle.
- Produces: verification evidence that the UI-only branching did not change restoration, success navigation, failure routing, or disconnect semantics.

- [x] **Step 1: Run connection controller tests**

Run:

```bash
flutter test test/features/connection/connection_controller_test.dart
```

Expected: all tests pass, including `restores a persisted Service connection` and `connect persists the normalized origin and disconnect preserves UI settings`.

- [x] **Step 2: Run application shell connection tests**

Run:

```bash
flutter test test/app/app_shell_test.dart
```

Expected: all tests pass. If the existing failed-persisted-connection assertion needs to include the newly required prefilled value, strengthen that existing test with the literal `http://offline.local`; do not duplicate the component test.

- [x] **Step 3: Run static analysis over changed production and test files**

Run:

```bash
flutter analyze lib/features/connection/connection_screen.dart test/features/connection/connection_screen_test.dart test/app/app_shell_test.dart
```

Expected: no errors or warnings from the changed surface.

- [x] **Step 4: Review the final diff and worktree scope**

Run:

```bash
git diff -- lib/features/connection/connection_screen.dart lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart test/features/connection/connection_screen_test.dart test/app/app_shell_test.dart docs/superpowers/specs/2026-08-14-cold-start-connecting-screen-design.md docs/superpowers/plans/2026-08-14-cold-start-connecting-screen.md
git status --short
```

Expected: the feature diff contains only the approved cold-start UI, localization, tests, spec, and plan. Existing unrelated modified and untracked files remain untouched. Do not stage or commit without separate user authorization.
