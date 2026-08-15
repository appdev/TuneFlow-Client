# TuneFlow App Toast Placement Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Place every `showAppMessage` toast at the horizontal center and upper-middle of the full TuneFlow application viewport on desktop and mobile.

**Architecture:** Keep `showAppMessage` and every feature call site unchanged. Define one shared alignment constant in the app theme and apply it through `ShadSonnerTheme`, which the root `ShadAppBuilder`'s existing `ShadSonner` reads for all transient messages.

**Tech Stack:** Flutter, Dart, `shadcn_ui` 0.53.6, `flutter_test`

## Global Constraints

- Apply the placement to every message produced by `showAppMessage`, including destructive messages.
- Use the entire application viewport as the positioning boundary on desktop and mobile.
- Use `Alignment(0, -0.45)` as the approved upper-middle anchor.
- Preserve message copy, visual semantics, duration, stacking, dismissal, animation, and background interaction.
- Do not add a third-party toast dependency.
- Preserve unrelated dirty-worktree changes and do not commit without explicit user authorization.

---

## File structure

- Modify `lib/design/app_theme.dart`: own the shared toast alignment constant and pass it to both light and dark `ShadThemeData` through `ShadSonnerTheme`.
- Modify `test/design/app_components_test.dart`: verify theme configuration and rendered placement at representative desktop and mobile viewport sizes while preserving the existing content assertions.

### Task 1: Configure and verify application-wide toast placement

**Files:**

- Modify: `lib/design/app_theme.dart`
- Test: `test/design/app_components_test.dart`

**Interfaces:**

- Consumes: the existing `ShadAppBuilder`-owned `ShadSonner`, `buildLightTheme()`, `buildDarkTheme()`, and `showAppMessage(BuildContext, {required String title, String? message, bool destructive = false})`.
- Produces: `const Alignment appToastAlignment = Alignment(0, -0.45)` and light/dark themes whose `sonnerTheme.alignment` resolves to that value.

- [x] **Step 1: Add a failing rendered-position test**

Add a widget test beside the existing `showAppMessage` tests. It renders both representative viewport sizes, gives each queued toast a unique title, and checks the root-relative position with a tolerance instead of pixel-exact vertical coordinates:

```dart
testWidgets('showAppMessage is upper-middle on desktop and mobile', (
  tester,
) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  for (final size in const [Size(1200, 800), Size(390, 844)]) {
    tester.view.physicalSize = size;
    final toastTitle = '定位提示-${size.width}';
    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Builder(
          builder: (context) => AppButton(
            onPressed: () => showAppMessage(context, title: toastTitle),
            child: const Text('触发定位'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发定位'));
    await tester.pump();

    final toast = find.ancestor(
      of: find.text(toastTitle),
      matching: find.byType(ShadToast),
    );
    final toastCenter = tester.getCenter(toast);
    expect(toastCenter.dx, closeTo(size.width / 2, 1));
    expect(toastCenter.dy, greaterThan(size.height * .25));
    expect(toastCenter.dy, lessThan(size.height * .40));
  }
});
```

- [x] **Step 2: Run the focused test and verify the new contract fails**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage is upper-middle on desktop and mobile'
```

Observed before implementation: the desktop toast center was `990` instead of the expected viewport center `600`, proving the test detects Sonner's lower-right default.

- [x] **Step 3: Add the shared alignment to the application theme**

In `lib/design/app_theme.dart`, define the approved application-level value after the imports:

```dart
const appToastAlignment = Alignment(0, -0.45);
```

Then pass it from `_themeFor` into the existing `ShadThemeData` constructor:

```dart
return ShadThemeData(
  brightness: variant.brightness,
  colorScheme: _schemeFor(variant),
  textTheme: ShadTextTheme(family: AppTypography.bodyFontFamily),
  radius: const BorderRadius.all(Radius.circular(AppRadii.control)),
  breakpoints: ShadBreakpoints(sm: 720, md: 900, lg: 1180),
  sonnerTheme: const ShadSonnerTheme(alignment: appToastAlignment),
  outlineButtonTheme: restingActionTheme,
  ghostButtonTheme: restingActionTheme,
  linkButtonTheme: restingActionTheme,
);
```

Do not wrap individual pages in new overlay widgets and do not change `showAppMessage` or its callers.

- [x] **Step 4: Run focused tests and formatting**

Run:

```bash
dart format lib/design/app_theme.dart test/design/app_components_test.dart
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage is upper-middle on desktop and mobile'
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage displays transient Sonner feedback'
flutter test test/design/app_components_test.dart --plain-name 'showAppMessage can display a title-only confirmation'
```

Expected: formatting succeeds and all three focused tests pass.

- [x] **Step 5: Run the affected test file and static analysis**

Run:

```bash
flutter test test/design/app_components_test.dart
flutter analyze lib/design/app_theme.dart test/design/app_components_test.dart
```

Expected: both commands exit successfully. If unrelated pre-existing failures appear, preserve their exact output and distinguish them from failures caused by these two modified files.

- [x] **Step 6: Review the final diff without committing**

Run:

```bash
git diff --check -- lib/design/app_theme.dart test/design/app_components_test.dart
git diff -- lib/design/app_theme.dart test/design/app_components_test.dart
git status --short -- lib/design/app_theme.dart test/design/app_components_test.dart docs/superpowers/specs/2026-08-14-app-toast-placement-design.md docs/superpowers/plans/2026-08-14-app-toast-placement.md
```

Expected: the code diff is limited to the global Sonner alignment and its focused tests; the approved design and plan remain uncommitted documentation files unless the user separately authorizes a commit.
