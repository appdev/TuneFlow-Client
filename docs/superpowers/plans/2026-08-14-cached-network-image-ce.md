# Cached Network Image CE Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every Flutter UI network-image path with `cached_network_image_ce` so a real image for the same cached URL survives rebuilds and desktop/mobile breakpoint changes without flashing the placeholder, while placeholders remain the loading/error behavior for uncached URLs.

**Architecture:** `AppArtwork` remains the business-facing artwork component and delegates its network branch to one shared CE `DefaultCacheManager`. A new application-level image-cache service owns that manager, its dedicated file/metadata directories, usage accounting, clearing, and disposal; the existing `MediaCache` becomes audio-only. Settings receives both services and reports/clears them independently.

**Tech Stack:** Flutter/Dart 3.9+, `cached_network_image_ce` 4.10.0, Riverpod 3, `path_provider`, `http`, `flutter_test`.

## Global Constraints

- Add `cached_network_image_ce: ^4.10.0` as a direct dependency; do not add `extended_image` or retain a second UI network-image downloader.
- All Flutter UI network images under `lib/` must flow through `CachedNetworkImage` or `CachedNetworkImageProvider`; `Image.network`, `NetworkImage`, and `CachedArtworkImage` are forbidden.
- The same normalized URL uses the same `imageUrl` and `cacheKey`, preserves `artworkRequestHeaders`, sets `disablePlaceholderOnCacheHit: true`, and uses zero fade durations.
- A changed URL must never reuse the previous URL's image (`useOldImageOnUrlChange: false`).
- `showFallback: false` must remain empty during loading and after failure.
- The CE cache uses a dedicated application-cache directory for image files, a dedicated application-support directory for Hive metadata, `LruCleanupStrategy`, a 30-day `stalePeriod`, 1000 objects, a 10-second connection timeout, and a 30-second request timeout.
- Existing 1/2/5/10/20 GB choices constrain audio only; image cache has no user-selectable byte limit.
- “清理缓存” clears audio disk cache, CE image disk/metadata cache, and Flutter's in-memory image cache, but does not modify Service downloads, notification artwork, favorites, or audio behavior.
- Delete only the legacy `<support>/media-cache/images` directory during media-cache initialization; preserve sibling `.mp3` and `.flac` files.
- Preserve all unrelated dirty-worktree changes. Do not stage, commit, regenerate unrelated goldens, or reformat unrelated files without explicit authorization.

---

## File Map

- Create `lib/storage/app_image_cache.dart`: image-cache service interface and CE implementation.
- Create `lib/storage/app_image_cache_scope.dart`: context injection for the shared image-cache service used by plain Flutter widgets.
- Create `test/storage/app_image_cache_test.dart`: CE directory, usage, clear, timeout/configuration, and failure-accounting tests.
- Create `test/support/fake_app_image_cache.dart`: small deterministic fake for settings and app wiring tests.
- Create `test/design/network_image_contract_test.dart`: static guard against alternate UI network-image paths.
- Modify `pubspec.yaml` and `pubspec.lock`: direct CE dependency; remove direct `crypto` only after the final source scan proves the app no longer imports it.
- Modify `lib/main.dart`: create independent audio/image caches and inject both.
- Modify `lib/app/app.dart`, `lib/app/app_providers.dart`, and `lib/app/runtime_providers.dart`: inject the image-cache service into widgets and settings, and dispose it with the app.
- Modify `lib/design/components/artwork.dart`: replace the custom lease/download widget with CE.
- Modify `lib/features/search/search_track_artwork.dart`: reuse `AppArtwork` rather than its own downloader.
- Modify `lib/storage/media_cache.dart`: remove all image responsibilities and migrate away the legacy image directory.
- Modify `lib/features/settings/settings_controller.dart` and `lib/features/settings/settings_screen.dart`: independent audio/image usage and combined clear.
- Modify focused tests under `test/design`, `test/features/player`, `test/features/search`, `test/features/settings`, `test/storage`, and `test/app`.
- Delete `lib/storage/media_cache_scope.dart` and `test/app/media_cache_scope_test.dart` after no consumer remains.

---

### Task 1: Add the CE image-cache service and application wiring

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/storage/app_image_cache.dart`
- Create: `lib/storage/app_image_cache_scope.dart`
- Create: `test/storage/app_image_cache_test.dart`
- Create: `test/support/fake_app_image_cache.dart`
- Modify: `lib/app/app_providers.dart`
- Modify: `lib/app/app.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `abstract interface class AppImageCache` with `BaseCacheManager get manager`, `ValueListenable<int> get usageBytes`, `Future<void> refreshUsage()`, `Future<void> clear()`, and `Future<void> dispose()`.
- Produces: `CeAppImageCache({required Directory cacheBaseDirectory, required Directory metadataBaseDirectory, http.Client Function()? httpClientFactory, Future<void> Function()? clearMemoryImageCache})`.
- Produces: `AppImageCacheScope.of(BuildContext)` and `AppImageCacheScope.maybeOf(BuildContext)`.
- Produces: nullable Riverpod `appImageCacheProvider` and `MusicFreeServiceApp(imageCache: ...)` injection.

- [ ] **Step 1: Add the dependency and resolve the lockfile**

Add beneath `http` in `pubspec.yaml`:

```yaml
  cached_network_image_ce: ^4.10.0
```

Run:

```bash
flutter pub get
```

Expected: exit 0; `pubspec.lock` resolves `cached_network_image_ce` 4.10.x and its CE platform packages.

- [ ] **Step 2: Write failing service tests**

Create `test/storage/app_image_cache_test.dart` with real temporary directories and a `MockClient`. Cover these exact behaviors:

```dart
test('stores CE files only below the dedicated cache base and reports bytes', () async {
  final service = CeAppImageCache(
    cacheBaseDirectory: cacheBase,
    metadataBaseDirectory: metadataBase,
    httpClientFactory: () => MockClient((request) async {
      expect(request.headers['user-agent'], 'TuneFlow Test');
      return http.Response.bytes(pngBytes, 200, headers: {'content-type': 'image/png'});
    }),
  );

  await service.manager.getSingleFile(
    'https://example.test/cover.png',
    headers: const {'User-Agent': 'TuneFlow Test'},
  );
  await service.refreshUsage();

  expect(service.usageBytes.value, greaterThan(0));
  expect(await cacheBase.list(recursive: true).where((e) => e is File).isEmpty, isFalse);
  expect(await outsideSentinel.exists(), isTrue);
  await service.dispose();
});

test('clear removes CE disk data, clears Flutter memory, and refreshes usage', () async {
  var memoryClears = 0;
  final service = CeAppImageCache(
    cacheBaseDirectory: cacheBase,
    metadataBaseDirectory: metadataBase,
    httpClientFactory: () => MockClient((_) async =>
      http.Response.bytes(pngBytes, 200, headers: {'content-type': 'image/png'})),
    clearMemoryImageCache: () async => memoryClears++,
  );
  await service.manager.getSingleFile('https://example.test/cover.png');
  await service.refreshUsage();
  expect(service.usageBytes.value, greaterThan(0));

  await service.clear();

  expect(memoryClears, 1);
  expect(service.usageBytes.value, 0);
  expect(await outsideSentinel.exists(), isTrue);
  await service.dispose();
});

test('a failed usage scan preserves the last confirmed byte count', () async {
  await service.manager.getSingleFile('https://example.test/cover.png');
  await service.refreshUsage();
  final confirmed = service.usageBytes.value;
  await cacheBase.delete(recursive: true);
  await File(cacheBase.path).writeAsString('not a directory');
  await expectLater(service.refreshUsage(), throwsA(isA<FileSystemException>()));
  expect(service.usageBytes.value, confirmed);
});
```

Also assert the constructed `DefaultCacheManager` exposes `stalePeriod == Duration(days: 30)`, `maxNrOfCacheObjects == 1000`, and `connectionParameters` of 10/30 seconds. Use `File('assets/branding/TuneFlow.png').readAsBytes()` as valid `pngBytes`; do not invent encoded bytes.

- [ ] **Step 3: Run the service test and verify RED**

Run:

```bash
flutter test test/storage/app_image_cache_test.dart
```

Expected: FAIL because `app_image_cache.dart` and `CeAppImageCache` do not exist.

- [ ] **Step 4: Implement the service and scope**

Create `lib/storage/app_image_cache.dart` with this public shape and behavior:

```dart
abstract interface class AppImageCache {
  BaseCacheManager get manager;
  ValueListenable<int> get usageBytes;
  Future<void> refreshUsage();
  Future<void> clear();
  Future<void> dispose();
}

final class CeAppImageCache implements AppImageCache {
  CeAppImageCache({
    required this.cacheBaseDirectory,
    required Directory metadataBaseDirectory,
    http.Client Function()? httpClientFactory,
    Future<void> Function()? clearMemoryImageCache,
  }) : _usageBytes = ValueNotifier(0),
       _clearMemoryImageCache = clearMemoryImageCache ?? _clearFlutterImageMemoryCache,
       _manager = DefaultCacheManager(
         stalePeriod: const Duration(days: 30),
         maxNrOfCacheObjects: 1000,
         connectionParameters: const ConnectionParameters(
           connectionTimeout: Duration(seconds: 10),
           requestTimeout: Duration(seconds: 30),
         ),
         httpClientFactory: httpClientFactory,
         cacheDirectoryProvider: () async => cacheBaseDirectory,
         metadataDirectoryProvider: () async => metadataBaseDirectory,
         cleanupStrategy: const LruCleanupStrategy(),
       );

  final Directory cacheBaseDirectory;
  final DefaultCacheManager _manager;
  final ValueNotifier<int> _usageBytes;
  final Future<void> Function() _clearMemoryImageCache;
  bool _disposed = false;

  @override
  BaseCacheManager get manager => _manager;

  @override
  ValueListenable<int> get usageBytes => _usageBytes;
}
```

Implement `refreshUsage()` by recursively listing only `cacheBaseDirectory` with `followLinks: false`, summing `FileStat.size`, and assigning `_usageBytes.value` only after the complete scan succeeds. Implement `clear()` so it attempts `_manager.emptyCache()` and `_clearMemoryImageCache()`, refreshes usage in `finally`, and rethrows the first failure with its original stack; one failed layer must not skip the other. `_clearFlutterImageMemoryCache` must call both `PaintingBinding.instance.imageCache.clear()` and `clearLiveImages()`. Make `dispose()` idempotent, await `_manager.dispose()`, then dispose the notifier.

Create `lib/storage/app_image_cache_scope.dart` as an `InheritedWidget` identical in lookup semantics to the old media scope, but carrying `AppImageCache`.

- [ ] **Step 5: Add deterministic test support**

Create `test/support/fake_app_image_cache.dart`:

```dart
final class FakeAppImageCache implements AppImageCache {
  FakeAppImageCache({required this.manager, int usageBytes = 0})
      : _usage = ValueNotifier(usageBytes);

  @override
  final BaseCacheManager manager;
  final ValueNotifier<int> _usage;
  int clearCalls = 0;
  int refreshCalls = 0;
  int disposeCalls = 0;

  @override ValueListenable<int> get usageBytes => _usage;
  @override Future<void> refreshUsage() async => refreshCalls++;
  @override Future<void> clear() async { clearCalls++; _usage.value = 0; }
  @override Future<void> dispose() async { disposeCalls++; _usage.dispose(); }
}
```

Use a real test `DefaultCacheManager` when a valid `BaseCacheManager` is required; do not implement the package's broad manager interface by hand.

- [ ] **Step 6: Wire the service into providers, app context, main, and disposal**

Add to `app_providers.dart`:

```dart
final appImageCacheProvider = Provider<AppImageCache?>((ref) => null);
```

Add `AppImageCache? imageCache` to `MusicFreeServiceApp`, override the provider when non-null, and wrap the built `ShadApp` in `AppImageCacheScope` when available. Convert the outer app widget to `StatefulWidget`; in `dispose`, call `unawaited(widget.imageCache?.dispose())` once. Do not make the scope depend on `MediaCache`.

In `main.dart`, initialize image caching independently from audio caching:

```dart
final appCache = await getApplicationCacheDirectory();
AppImageCache? imageCache;
CeAppImageCache? candidate;
try {
  candidate = CeAppImageCache(
    cacheBaseDirectory: Directory(
      '${appCache.path}${Platform.pathSeparator}image-cache',
    ),
    metadataBaseDirectory: Directory(
      '${support.path}${Platform.pathSeparator}image-cache-metadata',
    ),
  );
  await candidate.refreshUsage();
  imageCache = candidate;
} on Object catch (error) {
  debugPrint('Local image cache unavailable: $error');
  await candidate?.dispose();
}
```

Pass `imageCache` to `MusicFreeServiceApp`. Preserve the existing independent `MediaCache` try/catch and audio-service injection.

- [ ] **Step 7: Run Task 1 tests and analysis**

Run:

```bash
dart format lib/storage/app_image_cache.dart lib/storage/app_image_cache_scope.dart lib/app/app.dart lib/app/app_providers.dart lib/main.dart test/storage/app_image_cache_test.dart test/support/fake_app_image_cache.dart
flutter test test/storage/app_image_cache_test.dart test/app/app_shell_test.dart
flutter analyze lib/storage/app_image_cache.dart lib/storage/app_image_cache_scope.dart lib/app/app.dart lib/app/app_providers.dart lib/main.dart
```

Expected: all commands exit 0. Do not commit unless the user separately authorizes a commit.

---

### Task 2: Replace all Flutter UI network artwork with the shared CE path

**Files:**
- Modify: `lib/design/components/artwork.dart`
- Modify: `lib/features/search/search_track_artwork.dart`
- Modify: `test/design/artwork_test.dart`
- Modify: `test/features/search/search_track_artwork_test.dart`
- Modify: `test/features/player/player_screen_test.dart`
- Create: `test/design/network_image_contract_test.dart`

**Interfaces:**
- Consumes: `AppImageCacheScope.maybeOf(context)?.manager` from Task 1.
- Produces: `AppArtwork` as the only business-level URL artwork entry; no public `CachedArtworkImage` remains.
- Produces: optional `AppArtwork.fallback` so specialized callers such as search preserve their current deterministic placeholder while sharing the CE loader.

- [ ] **Step 1: Write failing AppArtwork CE contract tests**

Replace the old `FileImage`/`FakeMediaCache` assertion in `test/design/artwork_test.dart` with an `AppImageCacheScope` harness and inspect the `CachedNetworkImage` child:

```dart
final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
expect(image.imageUrl, 'https://p3.music.126.net/cover.jpg');
expect(image.cacheKey, 'https://p3.music.126.net/cover.jpg');
expect(image.httpHeaders, artworkRequestHeaders);
expect(image.cacheManager, same(imageCache.manager));
expect(image.disablePlaceholderOnCacheHit, isTrue);
expect(image.useOldImageOnUrlChange, isFalse);
expect(image.fadeInDuration, Duration.zero);
expect(image.fadeOutDuration, Duration.zero);
expect(image.fit, BoxFit.cover);
expect(image.filterQuality, FilterQuality.medium);
```

Add tests using a pending `MockClient` and an HTTP 500 response to assert `artwork-fallback-<seed>` appears for uncached loading/error when `showFallback: true`, and never appears when `showFallback: false`.

- [ ] **Step 2: Write failing breakpoint and URL-identity regression tests**

In `test/features/player/player_screen_test.dart`, add a harness that wraps `PlayerScreen` in `AppImageCacheScope` with a real temporary CE manager backed by `MockClient`. Cache valid PNG bytes for the current track URL before pumping the player. Then:

```dart
tester.view.physicalSize = const Size(1200, 800);
await tester.pumpWidget(harness(scopedPlayer));
await tester.pump();
expect(find.byKey(const Key('artwork-fallback-wy-cached')), findsNothing);

tester.view.physicalSize = const Size(390, 844);
await tester.pump();
expect(find.byKey(const Key('player-mobile-layout')), findsOneWidget);
expect(find.byKey(const Key('artwork-fallback-wy-cached')), findsNothing);

tester.view.physicalSize = const Size(1200, 800);
await tester.pump();
expect(find.byKey(const Key('player-desktop-stage')), findsOneWidget);
expect(find.byKey(const Key('artwork-fallback-wy-cached')), findsNothing);
```

Use the same `Track.fromJson` pattern already present in the file and set its raw picture field to the cached URL. Assert the mock HTTP request count does not increase during either resize.

Add a second test that changes the controller to a track with a different URL whose request is held by a `Completer`. Immediately after the state update, assert the first URL's `CachedNetworkImage` is absent and the new track's fallback is present; complete the second request and then assert the fallback disappears. This is the proof for `useOldImageOnUrlChange: false`.

- [ ] **Step 3: Write the failing static contract test**

Create `test/design/network_image_contract_test.dart`:

```dart
test('Flutter UI has one network-image loading path', () async {
  final violations = <String>[];
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = await entity.readAsString();
    for (final forbidden in const [
      'Image.network(',
      'NetworkImage(',
      'CachedArtworkImage',
    ]) {
      if (source.contains(forbidden)) violations.add('${entity.path}: $forbidden');
    }
  }
  expect(violations, isEmpty, reason: violations.join('\n'));
});
```

This intentionally excludes `MediaItem.artUri`, which is notification metadata rather than a Flutter UI image widget.

- [ ] **Step 4: Run focused tests and verify RED**

Run:

```bash
flutter test test/design/artwork_test.dart test/features/player/player_screen_test.dart test/design/network_image_contract_test.dart
```

Expected: FAIL because the custom widget and `NetworkImage` path still exist and `AppArtwork` does not build CE.

- [ ] **Step 5: Replace the custom widget with CE**

In `lib/design/components/artwork.dart`, remove `dart:async`, `media_cache.dart`, `media_cache_scope.dart`, `CachedArtworkImage`, and all lease/repair state. Import CE and the new scope. Add `final Widget? fallback` to `AppArtwork`; resolve it with `showFallback ? (this.fallback ?? _ArtworkFallback(...)) : const SizedBox.shrink()`. The network branch must be exactly equivalent to:

```dart
CachedNetworkImage(
  key: ValueKey(resolved.url),
  imageUrl: resolved.url!,
  cacheKey: resolved.url!,
  httpHeaders: artworkRequestHeaders,
  cacheManager: AppImageCacheScope.maybeOf(context)?.manager,
  fit: BoxFit.cover,
  filterQuality: FilterQuality.medium,
  disablePlaceholderOnCacheHit: true,
  useOldImageOnUrlChange: false,
  fadeInDuration: Duration.zero,
  fadeOutDuration: Duration.zero,
  placeholderFadeInDuration: Duration.zero,
  placeholder: (_, _) => fallback,
  errorBuilder: (_, _, _) => fallback,
)
```

Keep URL normalization, semantics, dimensions, clipping, icon choice, and `_ArtworkFallback` unchanged. The `ValueKey` must contain the normalized URL so a URL change cannot retain prior widget state.

- [ ] **Step 6: Route search artwork through AppArtwork**

Replace `_ArtworkImage`'s `CachedArtworkImage` branch with:

```dart
AppArtwork(
  key: Key('search-artwork-${track.source}-${track.id}'),
  imageUrl: uri.toString(),
  seed: '${track.source}:${track.id}',
  semanticLabel: '${track.name} 封面',
  size: size,
  width: size,
  height: size,
  borderRadius: 0,
  fallback: fallback,
)
```

Retain the existing letter fallback both while `FutureBuilder` has no URI and while the resolved URL is loading or failed by passing it as `AppArtwork.fallback`. Update `test/features/search/search_track_artwork_test.dart` to inspect `CachedNetworkImage` and assert headers/cache identity instead of casting an `Image` to `NetworkImage`.

- [ ] **Step 7: Run Task 2 verification**

Run:

```bash
dart format lib/design/components/artwork.dart lib/features/search/search_track_artwork.dart test/design/artwork_test.dart test/features/search/search_track_artwork_test.dart test/features/player/player_screen_test.dart test/design/network_image_contract_test.dart
flutter test test/design/artwork_test.dart test/features/search/search_track_artwork_test.dart test/features/player/player_screen_test.dart test/design/network_image_contract_test.dart
rg -n "Image\.network\(|NetworkImage\(|CachedArtworkImage" lib
```

Expected: all tests pass; `rg` exits 1 with no matches. Do not weaken the static test with allowlists for UI files.

---

### Task 3: Make MediaCache audio-only and remove the legacy image cache

**Files:**
- Modify: `lib/storage/media_cache.dart`
- Modify: `test/storage/media_cache_test.dart`
- Modify: `test/support/fake_media_cache.dart`
- Delete: `lib/storage/media_cache_scope.dart`
- Delete: `test/app/media_cache_scope_test.dart`
- Modify: `pubspec.yaml` and `pubspec.lock` if `crypto` becomes unused

**Interfaces:**
- Produces: `MediaCacheUsage({required int audioBytes, required int limitBytes})` with `totalBytes == audioBytes`.
- Produces: audio-only `MediaCache`; `acquireAudio`, lease protection, `invalidate`, reconciliation, limit, clear, and disposal retain their current behavior.

- [ ] **Step 1: Replace image tests with failing audio-only migration tests**

Remove image download, image concurrency, image corruption, force-refresh, and cross-kind LRU tests from `test/storage/media_cache_test.dart`. Add:

```dart
test('initialization removes only the legacy image directory', () async {
  await root.create(recursive: true);
  final audio = File('${root.path}/wy-song-128k.mp3');
  await audio.writeAsBytes(List.filled(7, 1));
  final legacyImages = Directory('${root.path}/images');
  await legacyImages.create();
  await File('${legacyImages.path}/cover.image').writeAsBytes([1, 2, 3]);
  final unrelated = File('${root.path}/keep.txt');
  await unrelated.writeAsString('keep');

  final cache = FileMediaCache(root: root);
  await cache.initialize(limitBytes: 100);

  expect(await legacyImages.exists(), isFalse);
  expect(await audio.exists(), isTrue);
  expect(await unrelated.exists(), isTrue);
  expect(cache.usage.value.audioBytes, 7);
  expect(cache.usage.value.totalBytes, 7);
  await cache.dispose();
});

test('audio limit ignores files outside the audio cache contract', () async {
  await root.create(recursive: true);
  final audio = File('${root.path}/wy-small-128k.mp3');
  await audio.writeAsBytes(List.filled(8, 1));
  final unrelated = File('${root.path}/keep.txt');
  await unrelated.writeAsBytes(List.filled(100, 2));

  final cache = FileMediaCache(root: root);
  await cache.initialize(limitBytes: 10);

  expect(await audio.exists(), isTrue);
  expect(await unrelated.exists(), isTrue);
  expect(cache.usage.value.audioBytes, 8);
  expect(cache.usage.value.totalBytes, 8);
  await cache.dispose();
});
```

- [ ] **Step 2: Run media-cache tests and verify RED**

Run:

```bash
flutter test test/storage/media_cache_test.dart
```

Expected: FAIL because usage still requires `imageBytes` and initialization recreates the images directory.

- [ ] **Step 3: Remove image responsibilities from MediaCache**

In `lib/storage/media_cache.dart`:

- Remove `dart:convert`, `crypto`, `MediaCacheKind.image`, `_images`, `_imageDownloads`, `acquireImage`, `_downloadImage`, `_imageKey`, image classification, and image totals.
- Change `MediaCacheUsage` to:

```dart
const MediaCacheUsage({required this.audioBytes, required this.limitBytes});
final int audioBytes;
final int limitBytes;
int get totalBytes => audioBytes;
```

- Make `_entries()` recognize only direct children of `root` ending in `.mp3` or `.flac`.
- At the start of `initialize`, call a private migration that deletes `Directory('${root.path}${Platform.pathSeparator}images')` recursively if it exists; do not recreate it and do not delete any sibling.
- Keep `.part`/`.mime` cleanup, protected leases, deferred deletion, audio LRU, limit updates, and HTTP client ownership unchanged.

Update `FakeMediaCache` to remove `imageFile`, `imageRequests`, and `acquireImage`; default usage becomes `MediaCacheUsage(audioBytes: 0, limitBytes: defaultMediaCacheLimitBytes)`.

- [ ] **Step 4: Delete the obsolete media scope and remove crypto if safe**

Delete `lib/storage/media_cache_scope.dart` and its test. Run:

```bash
rg -n "media_cache_scope|MediaCacheScope|package:crypto" lib test
```

Expected: no scope matches. If and only if `package:crypto` has no remaining `lib/` import, remove direct `crypto: ^3.0.7` from `pubspec.yaml` and run `flutter pub get`; CE may continue to resolve crypto transitively.

- [ ] **Step 5: Run Task 3 verification**

Run:

```bash
dart format lib/storage/media_cache.dart test/storage/media_cache_test.dart test/support/fake_media_cache.dart
flutter test test/storage/media_cache_test.dart test/features/player/service_audio_handler_test.dart test/features/player/player_controller_test.dart
flutter analyze lib/storage/media_cache.dart lib/features/player/service_audio_handler.dart
```

Expected: exit 0; audio caching and playback consumers remain green.

---

### Task 4: Separate settings usage and clear both cache systems

**Files:**
- Modify: `lib/app/runtime_providers.dart`
- Modify: `lib/features/settings/settings_controller.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `test/features/settings/settings_controller_test.dart`
- Modify: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `MediaCache.usage` for audio and `AppImageCache.usageBytes` for images.
- Produces: `SettingsController.imageCacheBytes` and combined `clearLocalCache()` behavior.

- [ ] **Step 1: Write failing controller tests for independent usage and clearing**

Update cache fixtures to the audio-only `MediaCacheUsage`. Add a fake image cache and assert:

```dart
test('reports audio and image usage independently', () {
  final manager = DefaultCacheManager(
    cacheDirectoryProvider: () async => imageCacheBase,
    metadataDirectoryProvider: () async => imageMetadataBase,
  );
  addTearDown(manager.dispose);
  final media = FakeMediaCache(
    usage: const MediaCacheUsage(audioBytes: 12, limitBytes: 100),
  );
  final images = FakeAppImageCache(manager: manager, usageBytes: 5);
  final controller = buildController(mediaCache: media, imageCache: images);

  expect(controller.cacheUsage.audioBytes, 12);
  expect(controller.cacheUsage.limitBytes, 100);
  expect(controller.imageCacheBytes, 5);
});

test('clear attempts audio and image caches and publishes their actual usage', () async {
  final manager = DefaultCacheManager(
    cacheDirectoryProvider: () async => imageCacheBase,
    metadataDirectoryProvider: () async => imageMetadataBase,
  );
  addTearDown(manager.dispose);
  final media = FakeMediaCache(
    usage: const MediaCacheUsage(audioBytes: 12, limitBytes: 100),
  );
  final images = FakeAppImageCache(manager: manager, usageBytes: 5);
  final controller = buildController(mediaCache: media, imageCache: images);

  await controller.clearLocalCache();

  expect(media.clearCalls, 1);
  expect(images.clearCalls, 1);
  expect(controller.cacheUsage.audioBytes, 0);
  expect(controller.imageCacheBytes, 0);
});
```

Add one failure test where audio clear throws and verify image clear is still called, `cacheError` contains the failure, and confirmed nonzero image usage is not overwritten with zero unless its own clear succeeded.

- [ ] **Step 2: Write failing settings copy tests**

Update `test/features/settings/settings_screen_test.dart` to expect these exact strings:

```dart
expect(find.textContaining('音频 2 MB / 5 GB'), findsOneWidget);
expect(find.textContaining('图片 512 KB'), findsOneWidget);
expect(find.textContaining('由图片缓存自动管理'), findsOneWidget);
expect(find.text('音频缓存上限'), findsOneWidget);
```

Retain the clear confirmation assertion that both audio playback cache and cover cache are local-only and do not affect Service downloads.

- [ ] **Step 3: Run settings tests and verify RED**

Run:

```bash
flutter test test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart
```

Expected: FAIL because the controller has no image service/usage and the UI still presents a combined limit.

- [ ] **Step 4: Implement independent settings state**

Add `AppImageCache? imageCache` to `SettingsController`. Initialize and listen as follows:

```dart
cacheUsage = mediaCache?.usage.value ?? MediaCacheUsage(
  audioBytes: 0,
  limitBytes: settings.cacheLimitBytes,
);
imageCacheBytes = imageCache?.usageBytes.value ?? 0;
mediaCache?.usage.addListener(_cacheUsageChanged);
imageCache?.usageBytes.addListener(_imageCacheUsageChanged);
```

Remove `clearImageMemoryCache`; that responsibility now belongs to `AppImageCache.clear()`. Implement `clearLocalCache()` so it attempts both non-null services even if the first fails, preserves the first error/stack, and throws `StateError('Local caches are unavailable')` only when both are null. Remove both listeners in `dispose()`.

Pass `ref.read(appImageCacheProvider)` from `runtime_providers.dart`.

- [ ] **Step 5: Update cache-card copy and layout**

Change the combined “used / limit” display into two explicit lines:

```dart
Text(
  '音频 ${_formatBytes(usage.audioBytes)} / ${_formatBytes(usage.limitBytes)}',
  style: AppTypography.title,
),
Text(
  '图片 ${_formatBytes(controller.imageCacheBytes)} · 由图片缓存自动管理',
  style: AppTypography.metadata.copyWith(color: AppTokens.of(context).muted),
),
```

Rename the selector label to `音频缓存上限`. Keep option values, clear dialog, busy state, and errors unchanged.

- [ ] **Step 6: Run Task 4 verification**

Run:

```bash
dart format lib/app/runtime_providers.dart lib/features/settings/settings_controller.dart lib/features/settings/settings_screen.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart
flutter test test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart test/app/app_shell_test.dart
flutter analyze lib/app/runtime_providers.dart lib/features/settings/settings_controller.dart lib/features/settings/settings_screen.dart
```

Expected: exit 0; settings show separate usage and the capacity control is explicitly audio-only.

---

### Task 5: Freeze the migration with focused and broad verification

**Files:**
- Verify only; modify production files only if a failing check identifies an in-scope defect.
- Update existing goldens only if the cache-card copy causes an intentional pixel diff and only for settings golden files.

**Interfaces:**
- Consumes: completed Tasks 1–4.
- Produces: evidence that all UI network images use CE and that existing audio/UI behavior remains intact.

- [ ] **Step 1: Run static source and dependency audits**

Run:

```bash
rg -n "Image\.network\(|NetworkImage\(|CachedArtworkImage|acquireImage\(|MediaCacheScope" lib
rg -n "cached_network_image_ce|extended_image" pubspec.yaml pubspec.lock
flutter pub deps | rg "cached_network_image_ce|extended_image|flutter_cache_manager"
```

Expected: first command has no matches; `cached_network_image_ce` is direct and resolved; `extended_image` is not added as a direct dependency. A transitive package in the existing `shadcn_ui` tree is acceptable only when no application source imports it.

- [ ] **Step 2: Run all focused regression tests together**

Run:

```bash
flutter test \
  test/storage/app_image_cache_test.dart \
  test/storage/media_cache_test.dart \
  test/design/artwork_test.dart \
  test/design/network_image_contract_test.dart \
  test/features/search/search_track_artwork_test.dart \
  test/features/player/player_screen_test.dart \
  test/features/player/player_backdrop_test.dart \
  test/features/player/mobile_vinyl_record_test.dart \
  test/features/player/mini_player_test.dart \
  test/features/settings/settings_controller_test.dart \
  test/features/settings/settings_screen_test.dart
```

If `test/features/player/mini_player_test.dart` does not exist, use the actual file returned by `rg --files test/features/player | rg 'mini.*test'`; do not create a duplicate test file solely to satisfy this command.

Expected: exit 0 and no uncaught image HTTP/decoding errors.

- [ ] **Step 3: Run analyzer and complete test suite**

Run:

```bash
flutter analyze
flutter test
```

Expected: both exit 0. If pre-existing unrelated failures occur, preserve their complete command/output and run the narrowest affected suite to distinguish them from this change; do not alter unrelated user work.

- [ ] **Step 4: Verify intentional visual scope**

Run the existing visual tests that cover player, search, downloads, playlists, home, and settings. Start with:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart test/visual/full_ui_gallery_test.dart
```

Expected: player/search/download/home/playlist images are unchanged when fixtures use fallbacks. Only settings snapshots may change due to the approved copy. If settings goldens fail, regenerate only the settings golden cases using the repository's existing golden update command discovered from the test file, then review the resulting image diff before retaining it.

- [ ] **Step 5: Review the final diff and working-tree boundaries**

Run:

```bash
git diff -- pubspec.yaml pubspec.lock lib/main.dart lib/app/app.dart lib/app/app_providers.dart lib/app/runtime_providers.dart lib/design/components/artwork.dart lib/features/search/search_track_artwork.dart lib/storage/media_cache.dart lib/storage/app_image_cache.dart lib/storage/app_image_cache_scope.dart lib/features/settings/settings_controller.dart lib/features/settings/settings_screen.dart test/storage/app_image_cache_test.dart test/storage/media_cache_test.dart test/design/artwork_test.dart test/design/network_image_contract_test.dart test/features/search/search_track_artwork_test.dart test/features/player/player_screen_test.dart test/features/settings/settings_controller_test.dart test/features/settings/settings_screen_test.dart test/support/fake_media_cache.dart test/support/fake_app_image_cache.dart
git status --short
```

Confirm the diff contains only the approved CE migration, audio-only media cache, legacy image-directory removal, settings separation, and tests. Leave all changes uncommitted unless the user explicitly authorizes staging/commit.
