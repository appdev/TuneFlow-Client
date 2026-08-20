# Mobile Search Source Selection Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mobile search source selection capability-aware, atomic with category changes, and rendered through a reusable project-level selection sheet.

**Architecture:** Add a typed `showSelection` variant to `AppBottomSheet`, then make `SearchScreen` derive valid source choices from the active `SearchView`. Extend `SearchController.search` with an optional requested view so a source/category transition produces one target request instead of an unrelated track request followed by a collection request.

**Tech Stack:** Flutter 3.47, Dart 3.13, shadcn_ui, Flutter widget tests, Android 35 emulator.

## Global Constraints

- Songs expose every track-capable provider plus `SearchController.aggregateSource`.
- Playlists expose only playlist-capable providers and never aggregate source.
- Albums expose only album-capable providers; the verified Service currently yields 网易音乐 and message `当前仅网易音乐支持专辑搜索`.
- Source/category transitions issue only the target-category request and never silently fall back to songs.
- Selection UI keeps typed values, selected semantics, stable keys, scrolling, 44 px targets, the existing mobile action-sheet presentation with a separate cancel card, and desktop dialog presentation.
- Do not change Service code or unrelated dirty-worktree changes.

---

### Task 1: Shared Typed Selection Sheet

**Files:**
- Modify: `lib/design/components/app_bottom_sheet.dart`
- Test: `test/design/app_bottom_sheet_test.dart`

**Interfaces:**
- Produces `AppBottomSheetSelection<T>` with `value`, `label`, optional `key`, and `enabled`.
- Produces `AppBottomSheet.showSelection<T>(BuildContext context, {required String title, String? message, required List<AppBottomSheetSelection<T>> options, required T selectedValue}) -> Future<T?>`.

- [ ] **Step 1: Write failing typed-selection tests**

Open `showSelection<String>` with six options, assert selected semantics, scroll to the last item, tap it, and expect the typed result. At desktop size assert the same API uses `app-adaptive-dialog`.

```dart
result = await AppBottomSheet.showSelection<String>(
  context,
  title: '音乐来源',
  message: '选择当前分类支持的来源',
  selectedValue: 'kw',
  options: const [
    AppBottomSheetSelection(value: 'kw', label: '酷我音乐'),
    AppBottomSheetSelection(value: 'kg', label: '酷狗音乐'),
    AppBottomSheetSelection(value: 'tx', label: 'QQ音乐'),
    AppBottomSheetSelection(value: 'wy', label: '网易音乐'),
    AppBottomSheetSelection(value: 'mg', label: '咪咕音乐'),
    AppBottomSheetSelection(value: 'all', label: '全部来源'),
  ],
);
```

- [ ] **Step 2: Run the focused test and verify RED**

```sh
flutter test test/design/app_bottom_sheet_test.dart --plain-name 'showSelection returns a typed value from a scrollable mobile sheet'
```

Expected: compilation fails because the new option type and method do not exist.

- [ ] **Step 3: Implement the minimal shared API**

Use `showContent<T>` for adaptive chrome. The body is a bounded `ListView` with at least 44 px rows, `Semantics(button: true, selected: ...)`, stable option keys, disabled callbacks, and a Lucide check. Reject an empty option list with `ArgumentError`.

- [ ] **Step 4: Run shared component tests and verify GREEN**

```sh
flutter test test/design/app_bottom_sheet_test.dart
```

Expected: PASS without overflow diagnostics.

### Task 2: Atomic Source and Category Search

**Files:**
- Modify: `lib/features/search/search_controller.dart`
- Test: `test/features/search/search_controller_test.dart`

**Interfaces:**
- Modifies `SearchController.search({required String source, required String query, SearchView? view})`.
- A supported explicit `view` becomes the initial state and sole loading target.

- [ ] **Step 1: Write a failing controller test**

Start with aggregate track results, clear recorded requests, then call:

```dart
await controller.search(
  source: 'wy',
  query: 'jay',
  view: SearchView.albums,
);
```

Assert `state.source == 'wy'`, `state.view == SearchView.albums`, and the only POST is `/api/v1/catalog/albums/search`.

- [ ] **Step 2: Run the focused test and verify RED**

```sh
flutter test test/features/search/search_controller_test.dart --plain-name 'search changes source and collection view atomically'
```

Expected: compilation fails because `search` has no `view` parameter.

- [ ] **Step 3: Implement the optional target view**

Resolve `requestedView = view ?? state.view`; compute `effectiveView` against the normalized source; use it for the new `SearchState`, section-loading decisions, and `_loadActive`. Preserve all existing callers and aggregate track behavior.

- [ ] **Step 4: Run controller tests and verify GREEN**

```sh
flutter test test/features/search/search_controller_test.dart
```

Expected: PASS, including cache, pagination, aggregate, and stale-generation tests.

### Task 3: Capability-Aware Mobile Source Selection

**Files:**
- Modify: `lib/features/search/search_screen.dart`
- Test: `test/features/search/search_screen_test.dart`

**Interfaces:**
- Consumes `AppBottomSheet.showSelection<String>` and `SearchController.search(..., view: targetView)`.
- Produces private helpers for active kind, valid providers, aggregate availability, and the album limitation message.

- [ ] **Step 1: Write a failing source-option test**

Using live-like capabilities, verify the song sheet contains five providers plus `全部来源`; the playlist sheet contains five providers without aggregate; and the album sheet contains only `网易音乐` plus `当前仅网易音乐支持专辑搜索`.

- [ ] **Step 2: Run the option test and verify RED**

```sh
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile source sheet shows only sources supported by the active category'
```

Expected: FAIL because the hand-written sheet always exposes every provider plus aggregate and has no limitation message.

- [ ] **Step 3: Write a failing request-routing test**

After aggregate song results load, clear the recorded paths, tap `search-mobile-filter-playlists`, settle, and assert the only POST is `/api/v1/catalog/playlists/search` for the selected fallback provider.

- [ ] **Step 4: Run the routing test and verify RED**

```sh
flutter test test/features/search/search_screen_test.dart --plain-name 'mobile category fallback requests only the target collection'
```

Expected: FAIL because `_selectMobileView` first requests `/api/v1/catalog/tracks/search`.

- [ ] **Step 5: Replace hand-written options and make transitions atomic**

Filter providers by the active kind, append aggregate only for tracks, and call the shared selection API. `_selectMobileView` chooses a capability-valid fallback and calls `search(source: source, query: query.text, view: view)` once; an already-compatible source may keep `selectView(view)` to reuse cache. Source changes call `search` with `view: state.view` so the category remains selected.

- [ ] **Step 6: Run search screen tests and verify GREEN**

```sh
flutter test test/features/search/search_screen_test.dart
```

Expected: PASS without overflow or pending-timer failures.

### Task 4: Focused Regression and Android Evidence

**Files:**
- Verify only; do not update goldens unless approved behavior intentionally changes their pixels.

**Interfaces:**
- Consumes final Tasks 1–3 and produces automated plus device evidence.

- [ ] **Step 1: Format and inspect the scoped diff**

```sh
dart format lib/design/components/app_bottom_sheet.dart lib/features/search/search_controller.dart lib/features/search/search_screen.dart test/design/app_bottom_sheet_test.dart test/features/search/search_controller_test.dart test/features/search/search_screen_test.dart
git diff --check
git diff -- lib/design/components/app_bottom_sheet.dart lib/features/search/search_controller.dart lib/features/search/search_screen.dart test/design/app_bottom_sheet_test.dart test/features/search/search_controller_test.dart test/features/search/search_screen_test.dart
```

Expected: formatting succeeds, whitespace check is silent, and no unrelated changes appear.

- [ ] **Step 2: Run the focused regression suite**

```sh
flutter test test/design/app_bottom_sheet_test.dart test/features/search/search_controller_test.dart test/features/search/search_screen_test.dart test/features/search/search_history_panel_test.dart
```

Expected: PASS.

- [ ] **Step 3: Verify on Android 35 Pixel 8**

Connect to `http://192.168.0.172:3124/`, search `jay`, and verify songs switch between aggregate and single sources; playlists stay selected while switching kw/kg/tx/wy/mg; albums show only 网易音乐 and the limitation message in the shared selection sheet; category fallback issues no unrelated track request; and `adb logcat` contains no Flutter exception.

- [ ] **Step 4: Final review**

Confirm existing dirty changes remain intact, no generated failure images or Service files changed, and report any residual risk.
