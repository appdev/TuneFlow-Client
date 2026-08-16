# Download Event Invalidation Boundaries Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure download progress events refresh only download UI while local music refreshes only from library events.

**Architecture:** Keep `EventCoordinator` as the single event-to-resource invalidation boundary. Separate `downloads.*` and `library.*` handling instead of inferring library changes from download snapshots; the Service already publishes `library.updated` after completed media is materialized.

**Tech Stack:** Dart, Flutter, `flutter_test`

## Global Constraints

- Preserve all unrelated dirty-worktree changes.
- Do not modify the Service, routes, controllers, or UI widgets.
- `downloads.*` must invalidate downloads only.
- `library.*` must invalidate local music only.
- `track.resources.updated` behavior must remain unchanged.
- Do not commit unless the user separately authorizes a commit.

---

### Task 1: Separate download and library invalidation

**Files:**
- Modify: `test/events/event_coordinator_test.dart`
- Modify: `lib/events/event_coordinator.dart:27-31`

**Interfaces:**
- Consumes: `EventCoordinator.accept(DomainEvent event) -> bool`
- Produces: independent calls to `invalidateDownloads()` for `downloads.*` and `invalidateLibrary()` for `library.*`

- [x] **Step 1: Write the failing regression test**

Replace the existing download/library coupling test with an explicit event-boundary test:

```dart
test('download and library events invalidate only their own resources', () {
  var downloads = 0;
  var library = 0;
  final coordinator = EventCoordinator(
    invalidateSources: () {},
    invalidatePlaylists: () {},
    invalidateDownloads: () => downloads++,
    invalidateLibrary: () => library++,
    invalidatePlaylistDetail: (_) {},
  );

  coordinator.accept(
    const DomainEvent(type: 'downloads.updated', data: null, sequence: 1),
  );

  expect(downloads, 1);
  expect(library, 0);

  coordinator.accept(
    const DomainEvent(type: 'library.updated', data: null, sequence: 2),
  );
  coordinator.accept(
    const DomainEvent(type: 'downloads.updated', data: null, sequence: 1),
  );

  expect(downloads, 1);
  expect(library, 1);
});
```

- [x] **Step 2: Run the regression test and verify RED**

Run:

```sh
flutter test test/events/event_coordinator_test.dart
```

Expected: FAIL at `expect(library, 0)` because the current `downloads.*` branch also calls `invalidateLibrary()`.

- [x] **Step 3: Implement the minimal event-boundary change**

Change the coordinator branch to:

```dart
if (event.type.startsWith('downloads.')) invalidateDownloads();
if (event.type.startsWith('library.')) invalidateLibrary();
```

Do not change sequence handling, playlist invalidation, or targeted track-resource updates.

- [x] **Step 4: Run the focused test and verify GREEN**

Run:

```sh
flutter test test/events/event_coordinator_test.dart
```

Expected: all tests in the file PASS with no errors.

- [x] **Step 5: Review the final diff**

Run:

```sh
git diff --check -- lib/events/event_coordinator.dart test/events/event_coordinator_test.dart
git diff -- lib/events/event_coordinator.dart test/events/event_coordinator_test.dart
```

Expected: only the download/library invalidation assertion and the single production branch change are added on top of the user's existing resource-update work.
