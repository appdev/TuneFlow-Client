# Mobile Settings and Search Dropdowns Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mobile preference cycling with explicit dropdown selection and render mobile search history as a search-field-anchored overlay that never shifts the content below it.

**Architecture:** Reuse `ShadSelect<T>` for the three mobile preferences and introduce one reusable preference-select row inside `SettingsScreen`. Wrap only the mobile search bar with `ShadPortal`, using the existing `showHistory` state and `searchTapGroup`; keep `SearchHistoryPanel` responsible for the floating surface and actions while leaving repository and controller contracts unchanged.

**Tech Stack:** Flutter 3.47.0, Dart 3.13.0, `shadcn_ui` 0.53.6, Flutter widget tests.

## Global Constraints

- Only mobile interaction changes; desktop settings selects and desktop search-history overlay must remain unchanged.
- Do not change `SettingsController`, `SearchHistoryRepository`, or their persistence contracts.
- Preserve the existing 44 px minimum mobile target size, Chinese tooltip text, semantic theme tokens, and existing option labels.
- Search history must be anchored below the search field, match its width, paint over following content, and never participate in the mobile scroll column's layout.
- Preserve unrelated uncommitted playback-queue edits already present in `lib/features/search/search_screen.dart` and `test/features/search/search_screen_test.dart`; edit only the search-history sections of those files.
- Do not add dependencies, commit, or alter unrelated dirty-worktree files without explicit authorization.

---

## File Map

- `lib/features/settings/settings_screen.dart`: adds the reusable mobile preference select and replaces the three cycling rows.
- `test/features/settings/settings_screen_test.dart`: proves each mobile select exposes all options and writes the directly selected non-next value.
- `lib/features/search/search_screen.dart`: anchors the mobile history panel to the search field with `ShadPortal` and removes the inline history child.
- `lib/features/search/search_history_panel.dart`: renders mobile history with a proper floating surface, border, radius, and shadow.
- `test/features/search/search_screen_test.dart`: proves the overlay position and unchanged filter layout, plus selection/close behavior.
- `test/features/search/search_history_panel_test.dart`: updates the mobile surface contract from inline/transparent to floating/elevated.

### Task 1: Explicit Mobile Preference Selects

**Files:**

- Modify: `lib/features/settings/settings_screen.dart:397-485`
- Test: `test/features/settings/settings_screen_test.dart:44-75`

**Interfaces:**

- Consumes: `SettingsController.setThemeMode(ThemeMode)`, `SettingsController.setLanguage(AppLanguage)`, and `SettingsController.setQuality(PlaybackQuality)`.
- Produces: private widget `_PreferenceSelect<T>` with `label`, `value`, `options`, `labelFor`, and `onChanged` inputs; no public API changes.

- [x] **Step 1: Add a failing widget test for direct selection**

Add a mobile test that chooses values which are not the old cycle's next values:

```dart
testWidgets('mobile preferences use explicit dropdown selections', (
  tester,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var saved = const AppSettings(origin: 'http://service.local');
  final controller = SettingsController(
    settings: saved,
    save: (value) async => saved = value,
    connect: (_) async {},
    disconnect: () async {},
    setPlayerQuality: (_) async {},
  );

  await tester.pumpWidget(harness(SettingsScreen(controller: controller)));
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ShadSelect<ThemeMode>));
  await tester.pumpAndSettle();
  expect(find.text('跟随系统'), findsWidgets);
  expect(find.text('浅色'), findsOneWidget);
  expect(find.text('深色'), findsOneWidget);
  await tester.tap(find.text('浅色'));
  await tester.pumpAndSettle();
  expect(saved.themeMode, ThemeMode.light);

  await tester.tap(find.byType(ShadSelect<AppLanguage>));
  await tester.pumpAndSettle();
  expect(find.text('简体中文'), findsOneWidget);
  expect(find.text('English'), findsOneWidget);
  await tester.tap(find.text('English'));
  await tester.pumpAndSettle();
  expect(saved.language, AppLanguage.en);

  await tester.tap(find.byType(ShadSelect<PlaybackQuality>));
  await tester.pumpAndSettle();
  expect(find.text('128k'), findsOneWidget);
  expect(find.text('320k'), findsOneWidget);
  expect(find.text('无损'), findsOneWidget);
  await tester.tap(find.text('无损'));
  await tester.pumpAndSettle();
  expect(saved.quality, PlaybackQuality.lossless);
});
```

- [x] **Step 2: Run the focused test and confirm the old cycling rows fail it**

Run:

```sh
flutter test test/features/settings/settings_screen_test.dart --plain-name 'mobile preferences use explicit dropdown selections'
```

Expected: FAIL because the mobile tree has no typed `ShadSelect<ThemeMode>`, `ShadSelect<AppLanguage>`, or `ShadSelect<PlaybackQuality>`.

- [x] **Step 3: Replace the three mobile cycling rows with typed selects**

In `_MobilePreferences`, replace only the theme, language, and quality `_PreferenceRow` calls with:

```dart
_PreferenceSelect<ThemeMode>(
  label: '主题',
  value: settings.themeMode,
  options: const [
    ShadOption(value: ThemeMode.system, child: Text('跟随系统')),
    ShadOption(value: ThemeMode.light, child: Text('浅色')),
    ShadOption(value: ThemeMode.dark, child: Text('深色')),
  ],
  labelFor: _themeLabel,
  onChanged: controller.setThemeMode,
),
// Keep the existing transparency row and explanatory copy here.
_PreferenceSelect<AppLanguage>(
  label: '语言',
  value: settings.language,
  options: const [
    ShadOption(value: AppLanguage.system, child: Text('跟随系统')),
    ShadOption(value: AppLanguage.zh, child: Text('简体中文')),
    ShadOption(value: AppLanguage.en, child: Text('English')),
  ],
  labelFor: _languageLabel,
  onChanged: controller.setLanguage,
),
const SizedBox(height: 12),
_PreferenceSelect<PlaybackQuality>(
  label: '默认音质',
  value: settings.quality,
  options: const [
    ShadOption(value: PlaybackQuality.low128k, child: Text('128k')),
    ShadOption(value: PlaybackQuality.high320k, child: Text('320k')),
    ShadOption(value: PlaybackQuality.lossless, child: Text('无损')),
  ],
  labelFor: _qualityLabel,
  onChanged: controller.setQuality,
),
```

Add the private reusable select next to `_PreferenceRow`. The whole 56 px row is the select trigger, rather than a small trailing control:

```dart
final class _PreferenceSelect<T> extends StatelessWidget {
  const _PreferenceSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<Widget> options;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: ShadSelect<T>(
      initialValue: value,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      options: options,
      selectedOptionBuilder: (context, selected) => Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.title)),
          Text(labelFor(selected), style: AppTypography.title),
        ],
      ),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}
```

- [x] **Step 4: Format and run the complete settings suite**

Run:

```sh
dart format lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
flutter test test/features/settings/settings_screen_test.dart
```

Expected: formatting makes no semantic changes; all settings tests PASS, including transparency and cache behavior.

- [x] **Step 5: Review the task diff without committing**

Run:

```sh
git diff --check -- lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
git diff -- lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
```

Expected: no whitespace errors; changes are limited to the three mobile selects, their private helper, and the focused test. Leave them uncommitted because commit authorization was not provided.

### Task 2: Anchored Mobile Search-History Overlay

**Files:**

- Modify: `lib/features/search/search_screen.dart:420-459`
- Modify: `lib/features/search/search_history_panel.dart:24-34`
- Test: `test/features/search/search_screen_test.dart` near `search history uses the active source without storing one`
- Test: `test/features/search/search_history_panel_test.dart:52-78`

**Interfaces:**

- Consumes: `_SearchScreenState.showHistory`, `_selectHistory(String)`, `_removeHistory(String)`, `_clearHistory()`, `searchTapGroup`, and exported `ShadPortal`/`ShadAnchorAuto` from `shadcn_ui`.
- Produces: private `_mobileSearchBarWithHistory(...)` method returning an anchored `ShadPortal`; `SearchHistoryPanel` continues exposing the same constructor and callback signatures.

- [x] **Step 1: Add a failing mobile layout test**

Add a test using the existing mocked `ServiceApi` and `SearchHistoryRepository` setup. Capture the filters before focus, open history, and assert the history is below the field while filters remain fixed:

```dart
testWidgets('mobile search history floats without shifting filters', (
  tester,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({
    SearchHistoryRepository.storageKey: ['晚风', '挪威的森林'],
  });
  final preferences = await SharedPreferences.getInstance();
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
        history: SearchHistoryRepository(
          loadPreferences: () async => preferences,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final filtersBefore = tester.getTopLeft(
    find.byKey(const Key('search-mobile-filters')),
  );
  await tester.tap(find.byKey(const Key('search-field')));
  await tester.pumpAndSettle();

  final fieldRect = tester.getRect(find.byKey(const Key('search-field')));
  final historyRect = tester.getRect(
    find.byKey(const Key('search-history-panel')),
  );
  expect(historyRect.left, fieldRect.left);
  expect(historyRect.top, greaterThanOrEqualTo(fieldRect.bottom));
  expect(historyRect.width, fieldRect.width);
  expect(
    tester.getTopLeft(find.byKey(const Key('search-mobile-filters'))),
    filtersBefore,
  );

  await tester.tap(find.byKey(const Key('search-mobile-masthead')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('search-history-panel')), findsNothing);

  await tester.tap(find.byKey(const Key('search-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('search-history-item-0')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('search-history-panel')), findsNothing);
  expect(
    tester.widget<EditableText>(find.byType(EditableText)).controller.text,
    '晚风',
  );
});
```

- [x] **Step 2: Change the panel test to require a floating mobile surface**

Replace the old `mobile history panel is inline without a desktop shadow` assertion with:

```dart
testWidgets('mobile history panel uses a floating surface', (tester) async {
  await tester.pumpWidget(
    harness(
      SizedBox(
        width: 390,
        child: SearchHistoryPanel(
          items: const ['晚风'],
          mobile: true,
          onSelected: (_) {},
          onRemoved: (_) {},
          onCleared: () {},
        ),
      ),
    ),
  );

  final panel = tester.widget<Container>(
    find.byKey(const Key('search-history-panel')),
  );
  final decoration = panel.decoration! as BoxDecoration;
  expect(decoration.border, isNotNull);
  expect(decoration.boxShadow, isNotEmpty);
});
```

- [x] **Step 3: Run both focused tests and confirm the inline implementation fails**

Run:

```sh
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile search history floats without shifting filters'
flutter test test/features/search/search_history_panel_test.dart --plain-name 'mobile history panel uses a floating surface'
```

Expected: the screen test FAILS because filters move downward; the panel test FAILS because the mobile decoration has no border or shadow.

- [x] **Step 4: Move mobile history into a field-anchored `ShadPortal`**

Add a state method that preserves the existing callbacks and `TapRegion` grouping:

```dart
Widget _mobileSearchBarWithHistory(SearchState state) => LayoutBuilder(
  builder: (context, constraints) => ShadPortal(
    visible: showHistory,
    anchor: const ShadAnchorAuto(offset: Offset(0, 8)),
    portalBuilder: (context) => SizedBox(
      width: constraints.maxWidth,
      child: TapRegion(
        groupId: searchTapGroup,
        child: SearchHistoryPanel(
          items: historyItems,
          mobile: true,
          onSelected: (value) => unawaited(_selectHistory(value)),
          onRemoved: (value) => unawaited(_removeHistory(value)),
          onCleared: () => unawaited(_clearHistory()),
        ),
      ),
    ),
    child: _SearchBar(
      mobile: true,
      state: state,
      controller: query,
      focusNode: searchFocus,
      tapRegionGroupId: searchTapGroup,
      onSearch: _search,
    ),
  ),
);
```

In the mobile branch, render this method instead of the plain `_SearchBar`; keep the desktop `_SearchBar` call unchanged. Delete only the current mobile inline block:

```dart
if (mobile && showHistory) ...[
  const SizedBox(height: 8),
  TapRegion(...SearchHistoryPanel(...)),
],
```

Remove the `if (!(mobile && showHistory))` guard around the result subtree and render the existing mobile/desktop result branch unconditionally. The overlay must not add, remove, or reposition filters or previously loaded results; it only paints above them.

- [x] **Step 5: Give the mobile history panel its floating decoration**

In `SearchHistoryPanel.build`, keep mobile row height/padding differences but use the same floating surface contract for both layouts:

```dart
decoration: BoxDecoration(
  color: tokens.surface,
  border: Border.all(color: tokens.border),
  borderRadius: BorderRadius.circular(AppRadii.compactCard),
  boxShadow: AppShadows.raised,
),
```

Do not change item keys, callbacks, labels, tooltip text, or the 48 px mobile row height.

- [x] **Step 6: Format and run all search-history regression tests**

Run:

```sh
dart format lib/features/search/search_screen.dart lib/features/search/search_history_panel.dart test/features/search/search_screen_test.dart test/features/search/search_history_panel_test.dart
flutter test test/features/search/search_history_panel_test.dart test/features/search/search_screen_test.dart
```

Expected: all tests PASS, including desktop history selection, mobile layout, search playback, provider switching, deletion, and clearing behavior.

- [x] **Step 7: Verify static analysis and the preserved dirty-worktree boundary**

Run:

```sh
flutter analyze lib/features/settings/settings_screen.dart lib/features/search/search_screen.dart lib/features/search/search_history_panel.dart test/features/settings/settings_screen_test.dart test/features/search/search_screen_test.dart test/features/search/search_history_panel_test.dart
git diff --check -- lib/features/settings/settings_screen.dart lib/features/search/search_screen.dart lib/features/search/search_history_panel.dart test/features/settings/settings_screen_test.dart test/features/search/search_screen_test.dart test/features/search/search_history_panel_test.dart
git diff -- lib/features/search/search_screen.dart test/features/search/search_screen_test.dart
```

Expected: analysis reports no issues, diff check reports no whitespace errors, and the pre-existing queue-only playback changes remain intact alongside the new history-overlay hunks. Leave all changes uncommitted unless the user separately authorizes a commit.
