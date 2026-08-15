# Connection Screen Branding Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the connection screen's generic music icon with TuneFlow branding, remove the explanatory copy, and show the platform-specific Service address as a placeholder while leaving the field empty.

**Architecture:** Keep the change inside the existing `ConnectionScreen`. Reuse `assets/branding/TuneFlow.png` and the existing `defaultServiceOrigin(TargetPlatform)` helper; move the helper's result from the text controller's initial value to `ShadInputFormField.placeholder`.

**Tech Stack:** Flutter, Dart, `flutter_test`, `shadcn_ui`

## Global Constraints

- Android placeholder: `http://10.0.2.2:3124`.
- Other-platform placeholder: `http://127.0.0.1:3124`.
- Keep user input, validation, connection submission, and error presentation behavior unchanged.
- Add no assets or dependencies.
- Do not commit unless the user separately authorizes a commit.

---

### Task 1: Update the connection screen presentation and initial input state

**Files:**
- Modify: `test/features/connection/connection_screen_test.dart:14-86`
- Modify: `lib/features/connection/connection_screen.dart:19-84`

**Interfaces:**
- Consumes: `String defaultServiceOrigin(TargetPlatform platform)` and bundled asset `assets/branding/TuneFlow.png`.
- Produces: `ConnectionScreen` with key `connection-brand-logo`, an empty `TextEditingController`, and a platform-specific placeholder widget.

- [x] **Step 1: Replace the macOS initial-value expectation with failing presentation assertions**

Update the first widget test and add an Android widget test:

```dart
testWidgets('shows TuneFlow branding and a macOS Service placeholder', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await tester.pumpWidget(
      MusicFreeServiceApp(preferences: MemoryAppPreferences()),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<ShadInputFormField>(
      find.byKey(const Key('service-origin-field')),
    );
    expect(
      find.image(const AssetImage('assets/branding/TuneFlow.png')),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.music2), findsNothing);
    expect(
      find.text(
        '输入运行 Service 的电脑地址。Android 模拟器访问本机请使用 10.0.2.2。',
      ),
      findsNothing,
    );
    expect(field.controller?.text, isEmpty);
    expect(find.text('http://127.0.0.1:3124'), findsOneWidget);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});

testWidgets('shows the Android emulator Service address as a placeholder', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await tester.pumpWidget(
      MusicFreeServiceApp(preferences: MemoryAppPreferences()),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<ShadInputFormField>(
      find.byKey(const Key('service-origin-field')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.text('http://10.0.2.2:3124'), findsOneWidget);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/features/connection/connection_screen_test.dart
```

Expected: FAIL because the generic `LucideIcons.music2` is still rendered, the description is still visible, and the controller still contains the default address.

- [x] **Step 3: Implement the minimal connection-screen change**

Initialize the controller without text:

```dart
final origin = TextEditingController();
```

Replace the generic icon with the existing branded asset while preserving a compact header footprint:

```dart
Image.asset(
  'assets/branding/TuneFlow.png',
  key: const Key('connection-brand-logo'),
  width: 64,
  height: 64,
  filterQuality: FilterQuality.high,
  errorBuilder: (context, error, stackTrace) => const Icon(
    LucideIcons.audioLines,
    size: 64,
  ),
),
```

Delete the description `Text(strings.connectDescription)` and its preceding eight-pixel spacer. Add the placeholder to the existing input field:

```dart
placeholder: Text(defaultServiceOrigin(defaultTargetPlatform)),
```

- [x] **Step 4: Format and verify GREEN**

Run:

```bash
dart format lib/features/connection/connection_screen.dart test/features/connection/connection_screen_test.dart
flutter test test/features/connection/connection_screen_test.dart
```

Expected: formatting succeeds and all connection-screen tests PASS, including the existing unsupported-API test that proves manually entered text remains visible.

- [x] **Step 5: Run targeted static analysis**

Run:

```bash
flutter analyze lib/features/connection/connection_screen.dart test/features/connection/connection_screen_test.dart
```

Expected: `No issues found!`

- [x] **Step 6: Review the final diff**

Run:

```bash
git diff --check
git diff -- lib/features/connection/connection_screen.dart test/features/connection/connection_screen_test.dart docs/superpowers/specs/2026-08-13-connection-screen-branding-design.md docs/superpowers/plans/2026-08-13-connection-screen-branding.md
```

Expected: no whitespace errors; the diff contains only the approved screen, tests, design spec, and implementation plan.
