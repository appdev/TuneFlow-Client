# Search Playback Immediate Response Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a search-result tap publish the selected track immediately while artwork loads asynchronously and falls back to the existing placeholder.

**Architecture:** Keep ownership in `SearchScreen`: start `PlayerController.play(track)` first so its synchronous state notification updates the mini player, then launch a separate artwork enrichment future. Reuse `SearchController.loadPicture` for cached, validated artwork lookup and `PlayerController.updateTrackArtwork` for source/id-safe queue updates.

**Tech Stack:** Flutter, Dart, `flutter_test`, `ChangeNotifier`, existing TuneFlow player and artwork components.

## Global Constraints

- Preserve the search result behavior that queues only the selected track.
- Use the existing `AppArtwork` placeholder; do not add artwork UI or assets.
- Artwork failure must not interrupt, roll back, or delay playback.
- A stale artwork response must not overwrite a later track selection.
- Do not change album, online-playlist, audio-resolution, or player queue behavior.
- Preserve unrelated dirty-worktree changes and do not commit without explicit authorization.

---

### Task 1: Decouple search playback from artwork loading

**Files:**
- Modify: `test/features/search/search_screen_test.dart:853-946`
- Modify: `lib/features/search/search_screen.dart:193-206`

**Interfaces:**
- Consumes: `PlayerController.play(Track) -> Future<void>`, `SearchController.loadPicture(Track) -> Future<Uri?>`, and `PlayerController.updateTrackArtwork(Track, Uri) -> bool`.
- Produces: `_play(Track) -> Future<void>` that publishes playback before waiting for artwork, plus a private `_loadPlaybackArtwork(Track) -> Future<void>` enrichment operation.

- [x] **Step 1: Strengthen the pending-artwork widget test**

Rename the existing test to `search playback responds before artwork finishes` and, immediately after tapping and pumping once, assert that the selected track is already current, is the only queued track, and has no artwork yet. Complete the pending picture response, settle, then assert that the artwork URL was applied:

```dart
await tester.tap(find.byKey(const Key('search-track-kw-one')));
await tester.pump();

expect(player.state.current?.id, 'one');
expect(player.state.queue.map((track) => track.id), ['one']);
expect(player.state.currentIndex, 0);
expect(player.state.current?.raw['pic'], isNull);

pictureResponse.complete(
  http.Response(
    jsonEncode({
      'data': {
        'url':
            '/api/v1/playback/resources/'
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
            'picture',
      },
    }),
    200,
  ),
);
await tester.pumpAndSettle();

expect(
  player.state.current?.raw['pic'],
  'http://service.local/api/v1/playback/resources/'
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
  'picture',
);
```

Keep the existing second-search step before completing the picture response and retain the final single-track queue assertions so the test also protects against result-list replacement and stale UI data.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```sh
flutter test test/features/search/search_screen_test.dart --plain-name 'search playback responds before artwork finishes'
```

Expected: FAIL before the picture response is completed because `player.state.current` is still null (or still the previous track), proving that artwork currently blocks playback publication.

- [x] **Step 3: Implement immediate playback with background artwork enrichment**

Replace the blocking artwork-before-play sequence with playback-first ordering:

```dart
Future<void> _play(Track track) async {
  final playback = widget.player.play(track);
  final embedded = track.raw['pic'];
  if (embedded is! String || embedded.isEmpty) {
    unawaited(_loadPlaybackArtwork(track));
  }
  await playback;
}

Future<void> _loadPlaybackArtwork(Track track) async {
  final picture = await _controller.loadPicture(track);
  if (picture != null) {
    widget.player.updateTrackArtwork(track, picture);
  }
}
```

This ordering relies on `PlayerController.playTracks` synchronously setting state and notifying listeners before its first `await`. `loadPicture` already converts request failures to `null`, and `updateTrackArtwork` only changes queue entries matching the original source and ID.

- [x] **Step 4: Run the focused test and verify GREEN**

Run:

```sh
flutter test test/features/search/search_screen_test.dart --plain-name 'search playback responds before artwork finishes'
```

Expected: PASS.

- [x] **Step 5: Run the search regression suite**

Run:

```sh
flutter test test/features/search/search_screen_test.dart
```

Expected: all tests pass, including embedded-artwork playback and single-track queue behavior.

- [x] **Step 6: Verify the final diff**

Run:

```sh
dart format --output=none --set-exit-if-changed lib/features/search/search_screen.dart test/features/search/search_screen_test.dart
git diff --check -- lib/features/search/search_screen.dart test/features/search/search_screen_test.dart
git diff -- lib/features/search/search_screen.dart test/features/search/search_screen_test.dart
```

Expected: formatting and whitespace checks pass; the diff contains only the pending-artwork regression assertions and playback/artwork ordering change. Leave changes uncommitted unless the user separately authorizes a commit.
