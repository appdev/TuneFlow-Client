# Primary Navigation Root Reset Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every desktop sidebar and mobile bottom-navigation selection open the selected module's root route without rebuilding the root page.

**Architecture:** Keep the existing `StatefulShellRoute.indexedStack` and branch-to-destination mapping. Change the shared navigation callback so every `StatefulNavigationShell.goBranch` call requests the branch's initial route; the indexed shell continues retaining each root page's widget state.

**Tech Stack:** Flutter, Dart, go_router, flutter_test

## Global Constraints

- Desktop and mobile primary navigation must share the same root-reset behavior.
- Root-page state such as search text, scroll position, and loaded data must remain preserved.
- Nested detail routes must not be restored by a later primary-navigation selection.
- Existing application back and forward history behavior must remain unchanged.
- Do not modify unrelated files or existing user changes.

---

### Task 1: Reset primary-navigation branches to their root routes

**Files:**
- Modify: `test/app/app_shell_test.dart`
- Modify: `lib/app/app_shell.dart:78-99`

**Interfaces:**
- Consumes: `StatefulNavigationShell.goBranch(int index, {bool initialLocation = false})` and the existing destination-to-branch index mapping in `AppShell.build`.
- Produces: a shared `navigate(String id)` behavior where every recognized primary destination opens its branch initial route while the shell retains root widget state.

- [x] **Step 1: Add a failing desktop regression for the reported playlist flow**

Extend `local library card uses its read-only production route` after the existing `/playlists/love` assertions:

```dart
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    await tester.tap(find.text('我的歌单').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playlists-screen')), findsOneWidget);
    expect(find.byKey(const Key('playlist-detail-route')), findsNothing);
    expect(
      GoRouterState.of(
        tester.element(find.byKey(const Key('playlists-screen'))),
      ).uri.path,
      '/playlists',
    );
```

This catches the production mutation `initialLocation: false` when switching from search back to the previously nested playlist branch. The assertions observe real routed widgets and the literal expected URI.

- [x] **Step 2: Change mobile nested-branch expectations to the new contract**

In `mobile shell uses compact player and five destinations`, keep the existing navigation through Home downloads and Search settings, but replace the expectations that the More branch restores those nested pages:

```dart
    expect(find.byKey(const Key('more-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('downloads-route')), findsNothing);
```

and:

```dart
    expect(find.byKey(const Key('more-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('settings-route')), findsNothing);
```

Keep the existing `保留搜索状态` assertion unchanged; it proves that returning to a root route does not rebuild the search page.

- [x] **Step 3: Run the focused test and verify RED**

Run:

```sh
flutter test test/app/app_shell_test.dart
```

Expected: FAIL because the desktop playlist branch restores `playlist-detail-route`, and the mobile More branch restores `downloads-route` or `settings-route` instead of `more-mobile-layout`.

- [x] **Step 4: Implement the minimal route fix**

In `AppShell.build`, retain the existing branch lookup and change only the `goBranch` call:

```dart
          navigationShell.goBranch(branchIndex, initialLocation: true);
```

Do not change the fallback path mapping, root widget keys, navigation history, or router branch definitions.

- [x] **Step 5: Format the changed Dart files**

Run:

```sh
dart format lib/app/app_shell.dart test/app/app_shell_test.dart
```

Expected: both files format successfully with no unrelated rewrite.

- [x] **Step 6: Run focused tests and verify GREEN**

Run:

```sh
flutter test test/app/app_shell_test.dart test/app/app_shell_routing_test.dart
```

Expected: PASS. The desktop regression reaches `/playlists`, mobile More reaches its root, and the existing search text remains present across branch changes.

- [x] **Step 7: Run static analysis on the changed files**

Run:

```sh
flutter analyze lib/app/app_shell.dart test/app/app_shell_test.dart
```

Expected: exit code 0 with no diagnostics introduced by this change.

- [x] **Step 8: Review the final diff**

Run:

```sh
git diff --check -- lib/app/app_shell.dart test/app/app_shell_test.dart docs/superpowers/specs/2026-08-16-primary-navigation-root-reset-design.md docs/superpowers/plans/2026-08-16-primary-navigation-root-reset.md
git diff -- lib/app/app_shell.dart test/app/app_shell_test.dart
```

Expected: no whitespace errors; the production diff contains only the `initialLocation` behavior change, and the test diff contains only the reported-flow regression plus updated mobile expectations. Leave all files uncommitted because no commit was authorized.
