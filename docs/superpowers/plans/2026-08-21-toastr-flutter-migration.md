# `toastr_flutter` Toast Migration Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Shad Sonner-backed `showAppMessage(...)` implementation with `toastr_flutter ^2.5.1` while preserving all existing business call sites and six-platform support.

**Architecture:** Keep `showAppMessage(BuildContext, {required String title, String? message, bool destructive = false})` as the application boundary and map every message to the icon-free `Toastr.blank` type. Compose the plugin's `TransitionBuilder` into the existing `MaterialApp.router.builder`, then remove only the obsolete Sonner theme configuration.

**Tech Stack:** Flutter 3.47, Dart 3.13, `toastr_flutter ^2.5.1`, `shadcn_ui`, `go_router`, `flutter_test`.

## Global Constraints

- Support Android, iOS, Windows, macOS, Linux, and Web through `toastr_flutter`'s Flutter Overlay implementation.
- Keep every existing `showAppMessage(...)` business call site source-compatible.
- Use `Toastr.blank` for every message so no Toast icon or icon placeholder is rendered; retain `destructive` for source compatibility.
- Render one centered visible text: prefer `message` when present, otherwise `title`; keep the configured title for semantics only.
- Use `ToastrPosition.topCenter`, a 3-second duration, no progress bar, and no close button.
- Preserve light/dark theme behavior by deriving `ToastrTheme` from `Theme.of(context).brightness`.
- Do not remove `shadcn_ui`, modify business copy, add notification permissions, or add loading/promise/action Toast features.
- Preserve all pre-existing dirty-worktree changes; patch only Toast-specific lines in overlapping files.
- Do not commit unless the user separately authorizes a commit.

---

### Task 1: Replace the project Toast adapter with `toastr_flutter`

**Files:**
- Modify: `pubspec.yaml:36-58`
- Modify: `pubspec.lock`
- Modify: `test/design/app_components_test.dart:1-25,468-550`
- Modify: `lib/design/components/app_feedback.dart:1-68`

**Interfaces:**
- Consumes: `Toastr.blank(String message, {String? title, ToastrOptions? options}) -> String`.
- Produces: `String showAppMessage(BuildContext context, {required String title, String? message, bool destructive = false})`.

- [x] **Step 1: Add the selected dependency and resolve it**

Add the dependency next to the other UI packages without reordering unrelated dependencies:

```yaml
dependencies:
  shadcn_ui: ^0.53.6
  toastr_flutter: ^2.5.1
  liquid_glass_widgets: 0.29.6
```

Run:

```sh
flutter pub get
```

Expected: dependency resolution succeeds, `pubspec.lock` contains `toastr_flutter` version `2.5.1`, and no unrelated dependency is intentionally upgraded.

- [x] **Step 2: Rewrite the focused widget tests to describe the new adapter behavior**

Import the plugin's public API:

```dart
import 'package:toastr_flutter/toastr.dart';
```

Wrap the existing Shad test app's builder so it matches production integration:

```dart
builder: (context, child) => Toastr.builder(
  context,
  ShadAppBuilder(child: child!),
),
```

Replace the Sonner-coupled assertions with public `ToastrWidget.config` assertions. The icon-free test must assert:

```dart
final toast = tester.widget<ToastrWidget>(find.byType(ToastrWidget));
expect(toast.config.type, ToastrType.blank);
expect(toast.config.title, '已保存');
expect(toast.config.message, '设置已更新');
expect(toast.config.position, ToastrPosition.topCenter);
expect(toast.config.duration, const Duration(seconds: 3));
expect(toast.config.showProgressBar, isFalse);
expect(toast.config.showCloseButton, isFalse);
expect(
  find.descendant(
    of: find.byType(ToastrWidget),
    matching: find.byType(CustomPaint),
  ),
  findsNothing,
);
```

The title-only test must assert that the title becomes the sole message:

```dart
final toast = tester.widget<ToastrWidget>(find.byType(ToastrWidget));
expect(toast.config.type, ToastrType.blank);
expect(toast.config.title, isNull);
expect(toast.config.message, '已加入下载队列');
```

Add a destructive and dark-theme case:

```dart
showAppMessage(
  context,
  title: '操作失败',
  message: '请稍后重试',
  destructive: true,
);

final toast = tester.widget<ToastrWidget>(find.byType(ToastrWidget));
expect(toast.config.type, ToastrType.blank);
expect(toast.config.theme, ToastrTheme.dark);
```

Keep the two viewport sizes `Size(1200, 800)` and `Size(390, 844)`, replace the `ShadToast` finder with `find.byType(ToastrWidget)`, and assert horizontal centering plus placement in the upper half of the viewport. Clear the plugin's static Toast state after each affected test:

```dart
addTearDown(Toastr.clearAll);
```

- [x] **Step 3: Run the focused tests and verify they fail against the Sonner implementation**

Run:

```sh
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage'
```

Expected: FAIL because `showAppMessage` still builds `ShadToast`, so no `ToastrWidget` is found.

- [x] **Step 4: Implement the minimal `toastr_flutter` adapter**

Replace the Toast-specific import and function body while leaving `AppNotice` unchanged:

```dart
import 'package:toastr_flutter/toastr.dart';

String showAppMessage(
  BuildContext context, {
  required String title,
  String? message,
  bool destructive = false,
}) {
  final hasMessage = message?.isNotEmpty ?? false;
  final options = ToastrOptions(
    duration: const Duration(seconds: 3),
    position: ToastrPosition.topCenter,
    showProgressBar: false,
    showCloseButton: false,
    theme: Theme.of(context).brightness == Brightness.dark
        ? ToastrTheme.dark
        : ToastrTheme.light,
  );
  final toastMessage = hasMessage ? message! : title;
  final toastTitle = hasMessage ? title : null;

  return Toastr.blank(toastMessage, title: toastTitle, options: options);
}
```

Do not change the public parameter semantics while implementing this mapping.

- [x] **Step 5: Run the adapter tests and verify they pass**

Run:

```sh
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage'
```

Expected: all `showAppMessage` tests PASS with `ToastrWidget.config` reporting the designed type, content, theme, duration, and position.

### Task 2: Integrate the Toast overlay at the application root and remove Sonner configuration

**Files:**
- Modify: `lib/app/app.dart:1-210`
- Modify: `lib/design/app_theme.dart:1-40`
- Test: `test/app/app_shell_test.dart:1-120`

**Interfaces:**
- Consumes: `Toastr.builder(BuildContext context, Widget? child) -> Widget` and the `showAppMessage(...) -> String` adapter from Task 1.
- Produces: a `MaterialApp.router.builder` composition that supplies Toastr's explicit Overlay without changing the existing theme, glass-policy, Shad, or application-message host ordering.

- [x] **Step 1: Add an application-root integration test**

Import the adapter and plugin API in `test/app/app_shell_test.dart`, then add a test that pumps the real application, calls the adapter from the connection route context, and inspects the resulting configuration:

```dart
testWidgets('application root hosts toastr feedback', (tester) async {
  addTearDown(Toastr.clearAll);
  await tester.pumpWidget(
    MusicFreeServiceApp(
      preferences: MemoryAppPreferences(const AppSettings()),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byKey(const Key('connection-route')));
  showAppMessage(context, title: '集成成功', message: '根 Overlay 可用');
  await tester.pump(const Duration(milliseconds: 350));

  final toast = tester.widget<ToastrWidget>(find.byType(ToastrWidget));
  expect(toast.config.title, '集成成功');
  expect(toast.config.message, '根 Overlay 可用');
});
```

- [x] **Step 2: Run the integration test before root-builder wiring**

Run:

```sh
flutter test test/app/app_shell_test.dart --plain-name 'application root hosts toastr feedback'
```

Expected: the test either FAILS because automatic Overlay discovery is unreliable in the router hierarchy, or passes through the package's zero-setup fallback. Record the result; a pass does not remove the explicit-builder requirement from the approved design.

- [x] **Step 3: Compose `Toastr.builder` into `MaterialApp.router.builder`**

Add the plugin import in `lib/app/app.dart` and wrap the current builder result without changing its internal order:

```dart
import 'package:toastr_flutter/toastr.dart';

builder: (context, child) => Toastr.builder(
  context,
  AppThemeScope(
    definition: themeDefinition,
    child: AppGlassPolicyHost(
      reduceTransparency: settings?.reduceTransparency ?? false,
      child: ShadAppBuilder(child: _AppMessageHost(child: child!)),
    ),
  ),
),
```

- [x] **Step 4: Remove obsolete Sonner theme configuration**

Delete only these Toast-specific declarations from `lib/design/app_theme.dart`:

```dart
const appToastAlignment = Alignment(0, -0.45);
```

and:

```dart
sonnerTheme: const ShadSonnerTheme(alignment: appToastAlignment),
```

Keep the Shad import and every other theme field because the design system still uses them.

- [x] **Step 5: Run focused integration and component verification**

Run:

```sh
flutter test test/app/app_shell_test.dart --plain-name 'application root hosts toastr feedback'
flutter test test/design/app_components_test.dart
```

Expected: both commands PASS. The full component file must remain green because `AppNotice`, buttons, alerts, and sheets continue to use `shadcn_ui`.

- [x] **Step 6: Run static analysis on every changed Dart surface**

Run:

```sh
flutter analyze lib/design/components/app_feedback.dart lib/design/app_theme.dart lib/app/app.dart test/design/app_components_test.dart test/app/app_shell_test.dart
```

Expected: `No issues found!`

- [x] **Step 7: Verify obsolete Toast symbols are absent**

Run:

```sh
rg -n "ShadToast|ShadSonner|appToastAlignment|sonnerTheme" lib test --glob '*.dart'
```

Expected: no matches. If unrelated test fixtures intentionally document old behavior, inspect rather than deleting them blindly; application code must have no matches.

- [x] **Step 8: Review the final diff without touching unrelated worktree changes**

Run:

```sh
git diff -- pubspec.yaml pubspec.lock lib/design/components/app_feedback.dart lib/design/app_theme.dart lib/app/app.dart test/design/app_components_test.dart test/app/app_shell_test.dart docs/superpowers/specs/2026-08-21-toastr-flutter-migration-design.md docs/superpowers/plans/2026-08-21-toastr-flutter-migration.md
```

Expected: only the dependency addition, Toast adapter replacement, root builder composition, Sonner cleanup, focused tests, and approved documentation are attributable to this task. Do not discard or rewrite pre-existing changes found in these files.
