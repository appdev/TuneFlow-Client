# Local Media Cache Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-device 5 GB default cache shared by playback audio and artwork, with fixed capacity choices, persistent images, cross-type LRU eviction, and a local-only clear action.

**Architecture:** A single injected `MediaCache` owns local audio and image files under the existing `media-cache` application-support directory. It exposes leases for active-file protection, a usage notifier for settings UI, and serialized maintenance for exact byte accounting and cross-type LRU eviction; artwork and `ServiceAudioHandler` both use this service.

**Tech Stack:** Flutter/Dart, Riverpod, `just_audio`, `audio_service`, `http`, `path_provider`, `shared_preferences`, `crypto`, `flutter_test`.

## Global Constraints

- The capacity applies only to cache files on the current client device; it never calls or changes Service download APIs, jobs, or files.
- Audio and image cache share one limit with fixed choices of 1 GB, 2 GB, 5 GB, 10 GB, and 20 GB; the default is 5 GB.
- Evict complete, unprotected files from oldest last-use time to newest, across both media kinds.
- Never delete a file while it is playing, downloading, reading, writing, or decoding; finish pending cleanup after its lease is released.
- Preserve the existing flat audio layout under `media-cache`; store images under `media-cache/images` and include both in one recursive scan.
- Keep network playback and deterministic image fallbacks working when local caching fails.
- Preserve all unrelated dirty-worktree changes. In particular, regenerate only cache-affected settings goldens from the current tree and do not rewrite other visual baselines.
- Commit steps below require explicit user authorization. If authorization is absent, skip the commit without blocking implementation or verification.

---

## File Structure

- Create `lib/storage/media_cache.dart`: cache contracts, leases, usage snapshot, file-backed implementation, serialized maintenance, image download, LRU, and local clear.
- Create `lib/storage/media_cache_scope.dart`: inherited access used by shared artwork widgets without coupling design code to Riverpod.
- Create `test/storage/media_cache_test.dart`: file-backed cache tests with temporary directories and mock HTTP.
- Create `test/support/fake_media_cache.dart`: deterministic `MediaCache` for controller/widget tests.
- Modify `lib/storage/app_preferences.dart`: fixed cache sizes and persisted per-device capacity.
- Modify `lib/app/app_providers.dart`, `lib/app/app.dart`, and `lib/main.dart`: inject one production cache instance into audio, UI, and settings.
- Modify `lib/features/player/service_audio_handler.dart`: acquire and release audio leases, notify the cache when streaming completes, and preserve fallback behavior.
- Modify `lib/design/components/artwork.dart`: persistent cached-image loader plus existing network-only fallback when no cache scope is installed.
- Modify `lib/features/search/search_track_artwork.dart`: route search covers through the shared cached-image loader while retaining the initial-letter fallback.
- Modify `lib/features/settings/settings_controller.dart` and `lib/features/settings/settings_screen.dart`: usage state, fixed capacity selector, confirmation, clear operation, and local-only copy.
- Modify focused tests under `test/storage`, `test/features/player`, `test/design`, `test/features/search`, and `test/features/settings`.
- Modify only cache-affected settings golden files after focused widget tests pass.

### Task 1: Persist the fixed local cache capacity

**Files:**
- Modify: `lib/storage/app_preferences.dart:1-150`
- Modify: `test/storage/app_preferences_test.dart:1-90`
- Modify: `test/support/memory_app_preferences.dart:1-20`

**Interfaces:**
- Produces: `const int bytesPerGiB`, `const int defaultMediaCacheLimitBytes`, `const List<int> mediaCacheLimitOptionsBytes`.
- Produces: `AppSettings.cacheLimitBytes` and `AppSettings.copyWith(cacheLimitBytes: ...)`.
- Persists: shared-preference key `media_cache_limit_bytes`.

- [ ] **Step 1: Write failing preference tests**

Add assertions that an empty preference store returns `5 * bytesPerGiB`, that each allowed value round-trips, and that a stored unsupported or non-positive value falls back to 5 GB:

```dart
expect(settings.cacheLimitBytes, 5 * bytesPerGiB);
for (final bytes in mediaCacheLimitOptionsBytes) {
  await preferences.write(AppSettings(cacheLimitBytes: bytes));
  expect((await preferences.read()).cacheLimitBytes, bytes);
}
```

- [ ] **Step 2: Run the focused test and verify the new assertions fail**

Run: `flutter test test/storage/app_preferences_test.dart`

Expected: FAIL because `cacheLimitBytes` and cache-size constants do not exist.

- [ ] **Step 3: Add the fixed capacity model and persistence**

Define binary GB values once and validate values while reading:

```dart
const bytesPerGiB = 1024 * 1024 * 1024;
const defaultMediaCacheLimitBytes = 5 * bytesPerGiB;
const mediaCacheLimitOptionsBytes = <int>[
  1 * bytesPerGiB,
  2 * bytesPerGiB,
  5 * bytesPerGiB,
  10 * bytesPerGiB,
  20 * bytesPerGiB,
];

int _cacheLimitOrDefault(int? value) =>
    mediaCacheLimitOptionsBytes.contains(value)
    ? value!
    : defaultMediaCacheLimitBytes;
```

Add the field to the constructor, equality, hash code, and `copyWith`. Read and write `media_cache_limit_bytes` through `SharedPreferencesAsync`. Update the memory preference fake only where its equality expectations require the new field.

- [ ] **Step 4: Run preference tests**

Run: `flutter test test/storage/app_preferences_test.dart test/features/connection/connection_controller_test.dart`

Expected: PASS, including the existing rule that disconnect preserves every non-origin preference.

- [ ] **Step 5: Commit this task if explicitly authorized**

```bash
git add lib/storage/app_preferences.dart test/storage/app_preferences_test.dart test/support/memory_app_preferences.dart
git commit -m "feat: persist local media cache limit"
```

### Task 2: Build the unified file-backed cache

**Files:**
- Create: `lib/storage/media_cache.dart`
- Create: `test/storage/media_cache_test.dart`
- Modify: `pubspec.yaml:30-50`
- Modify: `pubspec.lock`

**Interfaces:**
- Consumes: `defaultMediaCacheLimitBytes` and the allowed limits from Task 1.
- Produces: `enum MediaCacheKind { audio, image }`.
- Produces: immutable `MediaCacheUsage({audioBytes, imageBytes, limitBytes})` with `totalBytes`.
- Produces: `MediaCacheLease.file` and idempotent `Future<void> release()`.
- Produces: `MediaCache.usage`, `initialize`, `acquireAudio`, `acquireImage`, `invalidate`, `reconcile`, `setLimit`, `clearLocal`, and `dispose`.
- Produces: `FileMediaCache` with a testable `Directory root`, injected `http.Client`, and injected clock.

- [ ] **Step 1: Write failing lifecycle and accounting tests**

Use `Directory.systemTemp.createTemp`, `MockClient`, and a mutable clock. Cover these exact cases:

```dart
final cache = FileMediaCache(
  root: temp,
  client: MockClient((request) async => http.Response(imageBytes, 200)),
  now: () => now,
);
await cache.initialize(limitBytes: 20);

final audio = await cache.acquireAudio(
  source: 'wy',
  trackId: 'one',
  quality: '128k',
);
await audio.file.writeAsBytes(List.filled(12, 1));
await audio.release();

final image = await cache.acquireImage(
  Uri.parse('https://example.test/cover.jpg'),
  headers: artworkRequestHeaders,
);
expect(cache.usage.value.audioBytes, 12);
expect(cache.usage.value.imageBytes, imageBytes.length);
await image.release();
```

Add separate tests for URL request deduplication, stable SHA-256 image keys, old flat audio discovery, `.part` cleanup, exact cross-type LRU order, touch-on-hit, protected-file deferral, limit reduction, a single oversized file, deletion failure continuation, and `clearLocal` leaving an active lease until release.

- [ ] **Step 2: Run the cache test and verify it fails**

Run: `flutter test test/storage/media_cache_test.dart`

Expected: FAIL because `media_cache.dart` does not exist.

- [ ] **Step 3: Add the explicit `crypto` dependency and cache contracts**

Add `crypto: ^3.0.7` to direct dependencies, run `flutter pub get`, and define:

```dart
abstract interface class MediaCache {
  ValueListenable<MediaCacheUsage> get usage;
  Future<void> initialize({required int limitBytes});
  Future<MediaCacheLease> acquireAudio({
    required String source,
    required String trackId,
    required String quality,
  });
  Future<MediaCacheLease> acquireImage(
    Uri uri, {
    Map<String, String> headers = const {},
    bool forceRefresh = false,
  });
  Future<void> invalidate(File file);
  Future<void> reconcile();
  Future<void> setLimit(int bytes);
  Future<void> clearLocal();
  Future<void> dispose();
}
```

Reject unsupported limits in `setLimit` with `ArgumentError`. Make `MediaCacheLease.release` idempotent so widget disposal and image-error recovery cannot double-release.

- [ ] **Step 4: Implement atomic image storage and in-flight request sharing**

Create `root/images`, normalize the cache key input as URL plus sorted header entries, hash with SHA-256, and write `<digest>.part` before renaming to `<digest>.image`. Keep a `Map<String, Future<File>>` so concurrent callers share one request but receive independent leases.

Accept only HTTP 2xx responses. On download, directory, or write failure, delete the temporary file if present and rethrow without damaging another complete entry.

- [ ] **Step 5: Implement serialized scanning, usage, LRU, and protected paths**

Serialize `initialize`, `reconcile`, `setLimit`, `clearLocal`, lease release, and invalidation through one future chain. Scan the flat root for `.mp3`/`.flac` audio and `images/*.image` for pictures; exclude `.part`, the images directory itself, and unrelated application-support files.

Use `FileStat.modified` as last-use time and call `setLastModified(now())` on a successful cache hit. Sort unprotected candidates by modified time then path for deterministic ties. Delete until `audioBytes + imageBytes <= limitBytes`, publish actual byte counts after every operation, and remember pending trim/clear work when protected files prevent completion.

- [ ] **Step 6: Run cache tests and static analysis for the new file**

Run: `dart format lib/storage/media_cache.dart test/storage/media_cache_test.dart && flutter test test/storage/media_cache_test.dart && flutter analyze lib/storage/media_cache.dart test/storage/media_cache_test.dart`

Expected: all tests PASS and analysis reports no issues.

- [ ] **Step 7: Commit this task if explicitly authorized**

```bash
git add pubspec.yaml pubspec.lock lib/storage/media_cache.dart test/storage/media_cache_test.dart
git commit -m "feat: add unified local media cache"
```

### Task 3: Inject one cache instance through app startup

**Files:**
- Create: `lib/storage/media_cache_scope.dart`
- Create: `test/support/fake_media_cache.dart`
- Modify: `lib/app/app_providers.dart:1-20`
- Modify: `lib/app/app.dart:45-125`
- Modify: `lib/main.dart:1-35`
- Test: `test/app/media_cache_scope_test.dart`

**Interfaces:**
- Consumes: `MediaCache` from Task 2 and `AppSettings.cacheLimitBytes` from Task 1.
- Produces: `mediaCacheProvider` with a disabled/no-persistence default for isolated widget tests and a production override in `MusicFreeServiceApp`.
- Produces: `MediaCacheScope.of(context)` and `MediaCacheScope.maybeOf(context)`.
- Produces: `FakeMediaCache` with controllable usage and call recording.

- [ ] **Step 1: Write failing scope and app injection tests**

Test that descendants receive the exact cache passed to `MediaCacheScope`, `maybeOf` returns null outside a scope, and `MusicFreeServiceApp(mediaCache: fake)` exposes that same instance through the scope/provider. The fake must record `initialize`, `setLimit`, `clearLocal`, image requests, and audio requests without touching disk.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `flutter test test/app/media_cache_scope_test.dart`

Expected: FAIL because the scope and provider do not exist.

- [ ] **Step 3: Add the scope, provider, fake, and lifecycle ownership**

Wrap `_AppView` content in `MediaCacheScope(cache: ref.watch(mediaCacheProvider), child: ...)`. `MusicFreeServiceApp` accepts an optional `MediaCache`; production passes one explicitly, while tests that do not care about persistence use a no-op implementation rather than writing to the host application-support directory.

In `main`, create `SharedAppPreferences`, read the local settings once, create `FileMediaCache` rooted at `<applicationSupport>/media-cache`, initialize it with `settings.cacheLimitBytes`, pass the same object into `ServiceAudioHandler` and `MusicFreeServiceApp`, and dispose it through the app lifecycle owner. Do not create separate audio and image cache instances.

- [ ] **Step 4: Run app injection and existing startup tests**

Run: `flutter test test/app/media_cache_scope_test.dart test/app/app_shell_test.dart`

Expected: PASS without real network or host cache writes.

- [ ] **Step 5: Commit this task if explicitly authorized**

```bash
git add lib/storage/media_cache_scope.dart test/support/fake_media_cache.dart lib/app/app_providers.dart lib/app/app.dart lib/main.dart test/app/media_cache_scope_test.dart
git commit -m "feat: inject local media cache"
```

### Task 4: Put playback audio under leases and the shared quota

**Files:**
- Modify: `lib/features/player/service_audio_handler.dart:45-220`
- Modify: `test/features/player/service_audio_handler_test.dart:1-30`
- Modify: `test/features/player/player_controller_test.dart:450-490` only if the `AudioPort` contract changes

**Interfaces:**
- Consumes: `MediaCache.acquireAudio`, `MediaCacheLease`, `reconcile`, and `invalidate`.
- Preserves: `AudioPort.playCachedTrack(Track, String)` and `AudioPort.playTrack(Track, Uri, String)` so `PlayerController` behavior stays stable.
- Owns: one current audio lease and one download-progress subscription.

- [ ] **Step 1: Write failing audio integration tests**

Using `FakeMediaCache`, verify:

- `playCachedTrack` requests the source/id/quality key and reads the lease file.
- starting another track releases the previous lease only after the new source is accepted.
- stream download completion calls `reconcile`.
- decode failure calls `invalidate`, releases the lease, and still allows `PlayerController` to resolve a fresh stream.
- `stopPlayback` and `stop` release the current lease and progress subscription.

- [ ] **Step 2: Run focused player tests and verify the new tests fail**

Run: `flutter test test/features/player/service_audio_handler_test.dart test/features/player/player_controller_test.dart`

Expected: FAIL because `ServiceAudioHandler` still builds and deletes cache paths directly.

- [ ] **Step 3: Replace direct path creation with cache leases**

Inject `MediaCache` into `ServiceAudioHandler`. Remove `_cacheFile`; use `acquireAudio(source: track.source, trackId: track.id, quality: quality)`. For a cached file, set the file path while its lease is held. For a network stream, pass the leased target to `LockCachingAudioSource` and listen for download progress `1.0` to call `reconcile`.

On invalid cached audio, invalidate it and rethrow so the existing `PlayerController` fallback resolves a fresh Service stream. Cache bookkeeping failures must not turn a playable network URI into a playback failure: fall back to a non-caching audio source when acquiring the target fails.

- [ ] **Step 4: Verify audio behavior**

Run: `dart format lib/features/player/service_audio_handler.dart test/features/player/service_audio_handler_test.dart && flutter test test/features/player/service_audio_handler_test.dart test/features/player/player_controller_test.dart`

Expected: PASS, including offline cached playback and stale-cache fallback.

- [ ] **Step 5: Commit this task if explicitly authorized**

```bash
git add lib/features/player/service_audio_handler.dart test/features/player/service_audio_handler_test.dart test/features/player/player_controller_test.dart
git commit -m "feat: enforce shared quota for playback cache"
```

### Task 5: Persist every artwork surface

**Files:**
- Modify: `lib/design/components/artwork.dart:1-150`
- Modify: `lib/features/search/search_track_artwork.dart:1-145`
- Modify: `test/design/artwork_test.dart:1-45`
- Modify: `test/design/app_components_test.dart:310-370`
- Modify: `test/features/search/search_track_artwork_test.dart:1-80`

**Interfaces:**
- Consumes: `MediaCacheScope.maybeOf`, `MediaCache.acquireImage`, `MediaCacheLease`, and `invalidate`.
- Produces: `CachedArtworkImage`, accepting URL, headers, size/fit, fallback widget, and semantic/key data.
- Changes: `AppArtworkSource` stores normalized URL plus `fallbackSeed`, rather than a process-only `NetworkImage` instance.

- [ ] **Step 1: Write failing persistent artwork tests**

Cover these behaviors with `FakeMediaCache` and a temporary-file-backed lease:

- a cache scope makes `AppArtwork` request the normalized URL with `artworkRequestHeaders` and render a `FileImage`.
- recreating the widget with a fresh cache service instance hits the same disk file without HTTP.
- two sharp/blurred consumers deduplicate through `MediaCache`.
- an image decode error invalidates once, forces one refresh, then uses the existing fallback.
- without `MediaCacheScope`, component-only tests retain the current `NetworkImage` behavior.
- `SearchTrackArtwork` keeps its initial-letter fallback but uses the shared cached loader when a URL exists.

- [ ] **Step 2: Run focused artwork tests and verify they fail**

Run: `flutter test test/design/artwork_test.dart test/design/app_components_test.dart test/features/search/search_track_artwork_test.dart`

Expected: FAIL because artwork still bypasses the disk cache.

- [ ] **Step 3: Add the reusable cached artwork state machine**

`CachedArtworkImage` acquires a lease in `initState`/`didChangeDependencies`, reacquires when URL or cache identity changes, releases on replacement/dispose, and ignores stale async completions by checking a generation token. While waiting it renders the supplied fallback. On decode error it schedules one `invalidate` plus `forceRefresh: true`; a second failure renders fallback without looping.

When no scope exists, construct the existing `NetworkImage(normalizedUrl, headers: artworkRequestHeaders)` so isolated widget/golden harnesses remain deterministic unless they explicitly install a cache.

- [ ] **Step 4: Route shared and search artwork through the new loader**

Make `AppArtwork` delegate the image body to `CachedArtworkImage`. Replace only `_ArtworkImage`'s `Image.network` branch in search; retain picture resolution, request-once behavior, keys, border radius, and initial-letter fallback.

- [ ] **Step 5: Run artwork and major consumer tests**

Run: `dart format lib/design/components/artwork.dart lib/features/search/search_track_artwork.dart test/design/artwork_test.dart test/features/search/search_track_artwork_test.dart && flutter test test/design/artwork_test.dart test/design/app_components_test.dart test/features/search/search_track_artwork_test.dart test/features/player/player_screen_test.dart test/features/home/home_screen_test.dart test/features/downloads/downloads_screen_test.dart`

Expected: PASS; runtime-scoped artwork uses disk files, while no-scope tests preserve existing behavior.

- [ ] **Step 6: Commit this task if explicitly authorized**

```bash
git add lib/design/components/artwork.dart lib/features/search/search_track_artwork.dart test/design/artwork_test.dart test/design/app_components_test.dart test/features/search/search_track_artwork_test.dart
git commit -m "feat: persist artwork across app restarts"
```

### Task 6: Add local cache controls to Settings

**Files:**
- Modify: `lib/features/settings/settings_controller.dart:1-100`
- Modify: `lib/features/settings/settings_screen.dart:1-430`
- Modify: `lib/app/runtime_providers.dart:10-35`
- Modify: `test/features/settings/settings_controller_test.dart:1-90`
- Modify: `test/features/settings/settings_screen_test.dart:1-80`

**Interfaces:**
- Consumes: `MediaCache.usage`, `setLimit`, `clearLocal`, and `AppSettings.cacheLimitBytes`.
- Produces: `SettingsController.cacheUsage`, `cacheBusy`, `cacheError`, `setCacheLimit(int)`, and `clearLocalCache()`.
- Uses: `showAppDestructiveDialog` for the clear confirmation.

- [ ] **Step 1: Write failing controller tests**

Using `FakeMediaCache`, verify that `setCacheLimit` rejects values outside the fixed list, persists first, invokes `setLimit`, rolls the preference back if the cache operation fails, and publishes the actual usage snapshot. Verify `clearLocalCache` calls only `MediaCache.clearLocal` plus an injected memory-image clear callback; it must not receive a `DownloadRepository` or `ServiceApi` dependency.

- [ ] **Step 2: Write failing desktop and mobile widget tests**

Assert the visible copy and keys:

```dart
expect(find.text('本机缓存'), findsOneWidget);
expect(find.textContaining('不会影响 Service 端下载内容'), findsOneWidget);
expect(find.byKey(const Key('settings-cache-limit')), findsOneWidget);
expect(find.byKey(const Key('settings-clear-local-cache')), findsOneWidget);
```

Test selection of 10 GB, cancellation of the destructive confirmation, confirmed clear, disabled actions while busy, audio/image breakdown formatting, and a user-facing error when deletion fails.

- [ ] **Step 3: Run focused settings tests and verify they fail**

Run: `flutter test test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart`

Expected: FAIL because settings has no cache state or controls.

- [ ] **Step 4: Extend the controller and provider wiring**

Subscribe to `cache.usage` in `SettingsController`, remove the listener in `dispose`, and expose immutable state. `setCacheLimit` must keep persisted settings and active cache limit consistent; if applying the limit fails after save, restore the previous setting and limit before exposing the error. `clearLocalCache` clears disk cache, then calls:

```dart
PaintingBinding.instance.imageCache
  ..clear()
  ..clearLiveImages();
```

Inject the callback in tests. In `settingsControllerProvider`, pass `ref.read(mediaCacheProvider)` and register `ref.onDispose(controller.dispose)`.

- [ ] **Step 5: Add the responsive “本机缓存” card**

Use the existing `_PreferenceRow`/`_LabeledSelect` patterns and `showAppDestructiveDialog`. Show total usage, audio, image, selected limit, busy state, and exact isolation copy. The clear confirmation says it removes only audio playback cache and cover cache on this device and does not affect Service downloads.

Format bytes with B/KB/MB/GB and one decimal place for values below 10 GB. Do not add any `DownloadRepository`, download action, or Service request to this screen/controller.

- [ ] **Step 6: Run and format focused settings tests**

Run: `dart format lib/features/settings/settings_controller.dart lib/features/settings/settings_screen.dart lib/app/runtime_providers.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart && flutter test test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart`

Expected: PASS at desktop and 390 × 844 mobile dimensions.

- [ ] **Step 7: Commit this task if explicitly authorized**

```bash
git add lib/features/settings/settings_controller.dart lib/features/settings/settings_screen.dart lib/app/runtime_providers.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart
git commit -m "feat: add local cache settings"
```

### Task 7: Integrate, update affected visuals, and freeze verification evidence

**Files:**
- Modify only if output changed: `test/visual/full_goldens/desktop-settings-1024x768.png`
- Modify only if output changed: `test/visual/full_goldens/desktop-settings-1440x960.png`
- Modify only if output changed: `test/visual/full_goldens/mobile-settings-360x800.png`
- Modify only if output changed: `test/visual/full_goldens/mobile-settings-390x844.png`
- Modify matching `*-light.png` settings goldens only if those variants are present in the current test matrix.
- Do not modify non-settings goldens.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: final evidence that local audio and image caching, settings, and existing playback/search behavior work together.

- [ ] **Step 1: Inspect the final diff and current dirty overlap before visual writes**

Run: `git status --short && git diff --check && git diff -- lib/storage lib/features/player/service_audio_handler.dart lib/design/components/artwork.dart lib/features/search/search_track_artwork.dart lib/features/settings lib/app lib/main.dart pubspec.yaml`

Confirm there are no Service download API changes, no unrelated source edits, no debug logging, and no accidental overwrite of pre-existing theme/layout work. Record the current hashes of settings golden files before regenerating them.

- [ ] **Step 2: Run the complete focused cache regression set**

Run:

```bash
flutter test \
  test/storage/app_preferences_test.dart \
  test/storage/media_cache_test.dart \
  test/features/player/service_audio_handler_test.dart \
  test/features/player/player_controller_test.dart \
  test/design/artwork_test.dart \
  test/design/app_components_test.dart \
  test/features/search/search_track_artwork_test.dart \
  test/features/settings/settings_controller_test.dart \
  test/features/settings/settings_screen_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run broader consumer and static checks**

Run:

```bash
flutter analyze
flutter test \
  test/features/home/home_screen_test.dart \
  test/features/downloads/downloads_screen_test.dart \
  test/features/search/search_screen_test.dart \
  test/features/player/player_screen_test.dart \
  test/app/app_shell_test.dart
```

Expected: analysis and tests PASS. If a failure predates this change, preserve its output and distinguish it from cache regressions rather than editing unrelated code.

- [ ] **Step 4: Regenerate only settings visual baselines from the current tree**

Run the repository's existing full-gallery test with the golden update flag and a name filter that selects settings captures only. Verify `git status --short test/visual` lists only settings golden changes attributable to the new cache card; restore nothing and do not rewrite other user-owned golden changes.

Then run the same settings captures without `--update-goldens` and expect PASS. If the current gallery cannot filter individual settings captures, do not run a broad overwrite; report the affected settings baselines for manual reconciliation.

- [ ] **Step 5: Perform a native runtime smoke check**

On one available native target, load a cover online, quit the app process, disable or block the image source, reopen, and confirm the cover comes from disk. Confirm Settings shows the same device's usage, changing to 1 GB triggers trim, and clearing cache changes only local usage while the Service downloads list remains unchanged.

If runtime networking or a Service instance is unavailable, record that limitation and rely on the fresh-instance disk-cache test rather than weakening the requirement.

- [ ] **Step 6: Final diff and verification freeze**

Run: `git diff --check && git status --short`

Review every changed path against this plan. Report exact passing commands, any skipped visual/runtime check, pre-existing dirty files left untouched, and residual platform risk.

- [ ] **Step 7: Commit final visual baselines if explicitly authorized**

```bash
git add test/visual/full_goldens/*settings*.png
git commit -m "test: update local cache settings goldens"
```
