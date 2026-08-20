# Search Field Alignment and Clear Action Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Center search-field content on mobile and provide an accessible one-tap clear action on mobile and desktop.

**Architecture:** Extend the existing `AppTextField` wrapper with optional input padding, then keep search-specific geometry and clearing behavior inside `SearchScreen`. Derive clear-button visibility from the existing `TextEditingController`, reset results through the existing feature `SearchController.search` empty-query path, and retain the current focus node.

**Tech Stack:** Flutter, Dart, `shadcn_ui` (`ShadInput` and Lucide icons), Flutter widget tests, Android SDK/emulator.

## Global Constraints

- Preserve all unrelated dirty-worktree changes; edit only the named sections and never restore whole files.
- Do not add dependencies or another icon library.
- Use an ordinary Lucide clear glyph and keep every icon-only clear control at least 44 x 44 px.
- Expose the Chinese tooltip and semantic label `清除搜索`.
- Keep the mobile search field at 52 px; use a 46 px desktop outer height so the decorated inner area can contain a 44 px clear target.
- Show the clear action on every platform only while the query is non-empty.
- Clearing must reset text and results, retain focus/keyboard, and preserve existing mobile search-history behavior.
- On desktop, show `⌘ K` only while the query is empty.
- Do not commit: the user has not authorized commits, and the working tree already contains unrelated changes.

---

### Task 1: Forward custom input padding through `AppTextField`

**Files:**
- Modify: `lib/design/components/app_form.dart:9-57`
- Test: `test/design/app_components_test.dart:341-358`

**Interfaces:**
- Consumes: `ShadInput.padding` of type `EdgeInsetsGeometry?`.
- Produces: `AppTextField.padding` of type `EdgeInsetsGeometry?`, forwarded unchanged to `ShadInput`.

- [ ] **Step 1: Add a failing wrapper-contract test**

Add this widget test after `AppTextField forwards edited values` in `test/design/app_components_test.dart`:

```dart
testWidgets('AppTextField forwards custom input padding', (tester) async {
  const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 4);
  await tester.pumpWidget(
    ShadApp(
      theme: buildLightTheme(),
      home: const Scaffold(
        body: AppTextField(
          placeholder: '搜索音乐',
          padding: padding,
        ),
      ),
    ),
  );

  expect(tester.widget<ShadInput>(find.byType(ShadInput)).padding, padding);
});
```

- [ ] **Step 2: Run the focused test and verify the API is missing**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name 'AppTextField forwards custom input padding'
```

Expected: compilation fails because `AppTextField` has no named parameter `padding`.

- [ ] **Step 3: Implement the minimal shared wrapper change**

In `lib/design/components/app_form.dart`, add the constructor argument and field:

```dart
this.padding,
```

```dart
final EdgeInsetsGeometry? padding;
```

Forward it in `ShadInput`:

```dart
padding: padding,
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name 'AppTextField forwards custom input padding'
```

Expected: PASS.

- [ ] **Step 5: Review the narrow diff**

Run:

```bash
git diff -- lib/design/components/app_form.dart test/design/app_components_test.dart
```

Expected: only the optional padding contract and its focused test are new; existing user changes remain intact.

---

### Task 2: Center mobile search content and add the cross-platform clear action

**Files:**
- Modify: `lib/features/search/search_screen.dart:120-130, 157-185, 596-649`
- Test: `test/features/search/search_screen_test.dart:76-106, 947-1090`

**Interfaces:**
- Consumes: `AppTextField.padding`, `TextEditingController.clear()`, `FocusNode.requestFocus()`, and `SearchController.search({required String source, required String query, SearchView? view})`.
- Produces: `_clearSearch() -> Future<void>`, `_SearchBar.onClear -> Future<void> Function()`, `Key('search-field-leading')`, and `Key('search-clear')`.

- [ ] **Step 1: Add a failing mobile alignment and clear-behavior test**

Add a focused test near the existing mobile search tests. Use the existing `harness`, `ServiceApi`, repositories, and `testPlayer` helpers. The mock search response must return one track for a non-empty query so result reset is observable:

```dart
testWidgets('mobile search centers content and clears query with focus retained', (
  tester,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': {
            'list': [
              {
                'id': 'wind',
                'name': '晚风',
                'singer': '伍佰',
                'source': 'kw',
              },
            ],
            'total': 1,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
  final controller = feature.SearchController(SearchRepository(api));

  await tester.pumpWidget(
    harness(
      SearchScreen(
        controller: controller,
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        player: testPlayer(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final field = find.byKey(const Key('search-field'));
  final leading = find.byKey(const Key('search-field-leading'));
  expect(tester.getSize(field).height, 52);
  expect(tester.getCenter(leading).dy, closeTo(tester.getCenter(field).dy, .01));
  expect(
    tester.getCenter(find.text('搜索音乐')).dy,
    closeTo(tester.getCenter(field).dy, .01),
  );
  expect(find.byKey(const Key('search-clear')), findsNothing);

  await tester.enterText(field, '伍佰');
  expect(
    tester.getCenter(find.byType(EditableText)).dy,
    closeTo(tester.getCenter(field).dy, .01),
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  expect(controller.state.query, '伍佰');
  expect(find.byKey(const Key('search-results-heading')), findsOneWidget);

  final clear = find.byKey(const Key('search-clear'));
  expect(clear, findsOneWidget);
  expect(find.byTooltip('清除搜索'), findsOneWidget);
  expect(find.bySemanticsLabel('清除搜索'), findsOneWidget);
  expect(tester.getSize(clear), const Size.square(44));
  await tester.tap(clear);
  await tester.pumpAndSettle();

  expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
  expect(controller.state.query, '');
  expect(find.byKey(const Key('search-results-heading')), findsNothing);
  expect(find.byKey(const Key('search-clear')), findsNothing);
  expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
});
```

- [ ] **Step 2: Add a failing desktop visibility, sizing, and shortcut test**

Add a focused desktop test near `desktop search leaves navigation controls to window chrome`:

```dart
testWidgets('desktop search swaps shortcut hint for an accessible clear action', (
  tester,
) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': {'list': <Object?>[], 'total': 0},
        }),
        200,
      ),
    ),
  );

  await tester.pumpWidget(
    harness(
      SearchScreen(
        controller: feature.SearchController(SearchRepository(api)),
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        player: testPlayer(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final field = find.byKey(const Key('search-field'));
  expect(tester.getSize(field).height, 46);
  expect(find.text('⌘ K'), findsOneWidget);
  expect(find.byKey(const Key('search-clear')), findsNothing);

  await tester.enterText(field, 'Jay');
  await tester.pump();
  final clear = find.byKey(const Key('search-clear'));
  expect(clear, findsOneWidget);
  expect(tester.getSize(clear), const Size.square(44));
  expect(find.text('⌘ K'), findsNothing);

  await tester.tap(clear);
  await tester.pumpAndSettle();
  expect(find.text('⌘ K'), findsOneWidget);
  expect(find.byKey(const Key('search-clear')), findsNothing);
  expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
});
```

- [ ] **Step 3: Run both new tests and verify behavioral failures**

Run:

```bash
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile search centers content and clears query with focus retained'
flutter test test/features/search/search_screen_test.dart --plain-name 'desktop search swaps shortcut hint for an accessible clear action'
```

Expected: FAIL because the alignment key and clear action do not exist and desktop height is still 42 px.

- [ ] **Step 4: Add the state-owner clear callback**

In `_SearchScreenState`, add:

```dart
Future<void> _clearSearch() async {
  query.clear();
  await _controller.search(
    source: selectedSource,
    query: '',
    view: _controller.state.view,
  );
  if (!mounted) return;
  searchFocus.requestFocus();
  unawaited(
    Future<void>.delayed(Duration.zero, () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !searchFocus.hasFocus) return;
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
        );
      });
    }),
  );
}
```

The deferred `TextInput.show` is required because Android may deliver a
button-tap keyboard hide after the focus node has already remained focused.
The mobile widget test must simulate that late hide after tapping clear and
assert that the next settled frame makes `tester.testTextInput.isVisible`
true again.

Pass `onClear: _clearSearch` to both mobile and desktop `_SearchBar` construction sites.

- [ ] **Step 5: Implement the centered geometry and conditional clear action**

Add `required this.onClear` and this field to `_SearchBar`:

```dart
final Future<void> Function() onClear;
```

Change the outer height and the constrained minimum height to the same platform-specific value:

```dart
final fieldHeight = mobile ? 52.0 : 46.0;
```

Use `fieldHeight` for `SizedBox.height` and `BoxConstraints.minHeight`. Configure `AppTextField` with:

```dart
padding: EdgeInsets.symmetric(horizontal: 4, vertical: mobile ? 3 : 0),
leading: const SizedBox(
  key: Key('search-field-leading'),
  width: 44,
  height: 44,
  child: Center(child: Icon(LucideIcons.search, size: 18)),
),
trailing: controller.text.isNotEmpty
    ? IconButton(
        key: const Key('search-clear'),
        tooltip: '清除搜索',
        onPressed: () => unawaited(onClear()),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          maximumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(LucideIcons.x, size: 18),
      )
    : mobile
        ? null
        : const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Text('⌘ K', style: AppTypography.metadata),
          ),
```

Retain the existing controller, focus node, tap-region group, placeholder,
surface selection, and submit callback unchanged.

- [ ] **Step 6: Run the two new tests and correct only observed implementation defects**

Run:

```bash
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile search centers content and clears query with focus retained'
flutter test test/features/search/search_screen_test.dart --plain-name 'desktop search swaps shortcut hint for an accessible clear action'
```

Expected: both PASS; no overflow or pending-timer exception is reported.

- [ ] **Step 7: Re-run the existing history-positioning regression test**

Run:

```bash
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile search history floats without shifting filters'
```

Expected: PASS, confirming that clearing/focus integration did not alter the portal layout.

- [ ] **Step 8: Review the search diff against current user changes**

Run:

```bash
git diff -- lib/features/search/search_screen.dart test/features/search/search_screen_test.dart
```

Expected: the new clear callback, `_SearchBar` interface/geometry, and focused tests are additive; pre-existing source-selection, history-portal, and playback edits remain untouched.

---

### Task 3: Run integration checks and emulator acceptance

**Files:**
- Verify: `lib/design/components/app_form.dart`
- Verify: `lib/features/search/search_screen.dart`
- Verify: `test/design/app_components_test.dart`
- Verify: `test/features/search/search_screen_test.dart`
- Create temporarily: `/tmp/tuneflow-search-clear.png` (emulator screenshot only; do not add to the repository)

**Interfaces:**
- Consumes: the final code and tests from Tasks 1 and 2.
- Produces: test, analyzer, icon-policy, Android build/install, and visual-runtime evidence.

- [ ] **Step 1: Format only the changed Dart files**

Run:

```bash
dart format lib/design/components/app_form.dart lib/features/search/search_screen.dart test/design/app_components_test.dart test/features/search/search_screen_test.dart
```

Expected: formatter completes successfully without touching unrelated files.

- [ ] **Step 2: Run the focused component and feature suites**

Run:

```bash
flutter test test/design/app_components_test.dart
flutter test test/features/search/search_screen_test.dart
flutter test test/features/player/player_screen_test.dart
```

Expected: all three suites PASS.

- [ ] **Step 3: Run targeted static analysis**

Run:

```bash
flutter analyze lib/design/components/app_form.dart lib/features/search/search_screen.dart test/design/app_components_test.dart test/features/search/search_screen_test.dart
```

Expected: no issues found.

- [ ] **Step 4: Verify icon-system policy**

Run:

```bash
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: the first command has no matches; the second has matches only in `lib/design/components/app_playback_button.dart`. The new clear action appears as `LucideIcons.x` and introduces no raw Material icon.

- [ ] **Step 5: Build and install the debug APK on the connected API 35 emulator**

Run:

```bash
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am force-stop com.musicfree.serviceclient
adb -s emulator-5554 shell monkey -p com.musicfree.serviceclient -c android.intent.category.LAUNCHER 1
```

Expected: build succeeds, install reports `Success`, and TuneFlow launches on `sdk gphone64 arm64` / Android 15 API 35 without clearing app data.

- [ ] **Step 6: Perform mobile visual and interaction acceptance**

On the emulator, open the primary Search tab. Verify the search glyph and placeholder are vertically centered. Enter `伍佰`, verify a 44 px clear action appears at the right, activate it, and verify the text/results clear while the keyboard remains open. If saved search history exists, verify it appears as the existing floating panel without moving the filters.

Capture the accepted state:

```bash
adb -s emulator-5554 exec-out screencap -p > /tmp/tuneflow-search-clear.png
```

Inspect `/tmp/tuneflow-search-clear.png` using the local image viewer. Expected: no vertical bias, clipping, overlap, or layout overflow in the 52 px field.

- [ ] **Step 7: Record final repository evidence without committing**

Run:

```bash
git status --short
git diff --check -- lib/design/components/app_form.dart lib/features/search/search_screen.dart test/design/app_components_test.dart test/features/search/search_screen_test.dart docs/superpowers/specs/2026-08-20-search-field-alignment-and-clear-design.md docs/superpowers/plans/2026-08-20-search-field-alignment-and-clear.md
```

Expected: `git diff --check` has no output. Report the exact changed files, successful commands, emulator evidence, and any residual risk; leave all changes uncommitted.
