# Recent Listening Deduplication Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the home screen's “最近常听” list shows each `source + id` track only once while preserving playback-history order.

**Architecture:** Keep `PlaybackHistoryRepository` unchanged so it retains complete event history. Deduplicate tracks at the `HomeController` boundary when history entries become `HomeState.continueListening`, using a private helper that preserves the first occurrence.

**Tech Stack:** Dart, Flutter, `flutter_test`, `http/testing.dart`

## Global Constraints

- Use `Track.source` and `Track.id` together as track identity.
- Preserve the first occurrence and the existing history order.
- Do not merge same-name tracks whose `source` or `id` differs.
- Do not change UI components, server APIs, or `PlaybackHistoryRepository` behavior.
- Preserve all unrelated dirty-worktree changes and do not commit without explicit authorization.

---

### Task 1: Deduplicate recent listening tracks

**Files:**
- Modify: `test/features/home/home_controller_test.dart`
- Modify: `lib/features/home/home_controller.dart`

**Interfaces:**
- Consumes: `List<PlaybackHistoryEntry>` from `PlaybackHistoryRepository.readPlaybackHistory()` and each entry's `Track`.
- Produces: `_uniqueTracks(Iterable<Track> tracks) -> List<Track>`, used only when assigning `HomeState.continueListening`.

- [x] **Step 1: Add a failing controller test**

Add a test whose history response contains `kw:repeat`, `kw:other`, another `kw:repeat` with changed metadata, and `qq:repeat`. After `refresh()`, assert the identities and retained metadata:

```dart
test('dashboard keeps only the latest occurrence of each source track', () async {
  final api = ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/playback/history') {
        return data([
          {
            'track': {
              'id': 'repeat',
              'name': 'Newest metadata',
              'singer': 'Artist',
              'source': 'kw',
            },
            'startedAt': 400,
          },
          {
            'track': {
              'id': 'other',
              'name': 'Other',
              'singer': 'Artist',
              'source': 'kw',
            },
            'startedAt': 300,
          },
          {
            'track': {
              'id': 'repeat',
              'name': 'Older metadata',
              'singer': 'Artist',
              'source': 'kw',
            },
            'startedAt': 200,
          },
          {
            'track': {
              'id': 'repeat',
              'name': 'Different source',
              'singer': 'Artist',
              'source': 'qq',
            },
            'startedAt': 100,
          },
        ]);
      }
      return data(<Object?>[]);
    }),
  );
  final controller = HomeController(
    playlists: PlaylistRepository(api),
    downloads: DownloadRepository(api),
    library: LibraryRepository(api),
    history: PlaybackHistoryRepository(api, platform: 'other'),
  );

  await controller.refresh();

  expect(
    controller.state.continueListening
        .map((track) => '${track.source}:${track.id}'),
    ['kw:repeat', 'kw:other', 'qq:repeat'],
  );
  expect(controller.state.continueListening.first.title, 'Newest metadata');
});
```

- [x] **Step 2: Run the new test and verify RED**

Run:

```bash
flutter test test/features/home/home_controller_test.dart --plain-name 'dashboard keeps only the latest occurrence of each source track'
```

Expected: the identity assertion fails because `kw:repeat` appears twice.

- [x] **Step 3: Add the minimal order-preserving helper**

Add this private helper to `lib/features/home/home_controller.dart`:

```dart
List<Track> _uniqueTracks(Iterable<Track> tracks) {
  final seen = <String>{};
  return List.unmodifiable(
    tracks.where((track) => seen.add('${track.source}:${track.id}')),
  );
}
```

Use it only when new history exists:

```dart
continueListening:
    nextHistory == null
        ? state.continueListening
        : _uniqueTracks(nextHistory!.map((item) => item.track)),
```

- [x] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
flutter test test/features/home/home_controller_test.dart --plain-name 'dashboard keeps only the latest occurrence of each source track'
```

Expected: PASS.

- [x] **Step 5: Run the complete home controller test file**

Run:

```bash
flutter test test/features/home/home_controller_test.dart
```

Expected: all tests pass without new warnings or errors.

- [x] **Step 6: Review the scoped diff**

Run:

```bash
git diff --check -- lib/features/home/home_controller.dart test/features/home/home_controller_test.dart
git diff -- lib/features/home/home_controller.dart test/features/home/home_controller_test.dart
```

Expected: only the test-first deduplication change is present, with no whitespace errors or unrelated edits.
