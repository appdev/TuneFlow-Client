# Mobile Secondary Navigation Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the five-destination mobile navigation on secondary routes while retaining the mini player and providing reliable page-level back navigation.

**Architecture:** Keep every route in the existing `StatefulShellRoute` so branch state survives. Classify mobile primary routes with an exact-path allowlist in `AppShell`, let `AppMobileDock` render navigation and mini-player independently, and pass a shared pop-or-fallback callback from `app_router.dart` into secondary screens. Extend the shared mobile header with a standard back control and use the same control above custom detail heroes.

**Tech Stack:** Flutter, Dart, go_router, Riverpod, shadcn_ui/Lucide icons, flutter_test.

## Global Constraints

- Mobile primary paths are exactly `/`, `/search`, `/discover`, `/playlists`, and `/more`; every other Shell path defaults to secondary.
- Secondary mobile pages hide the five-destination navigation, retain the mini player only when a current track exists, and reserve no empty bottom space otherwise.
- A secondary back action pops the current route when possible, then falls back to its owning mobile primary route; unknown fallback is `/`.
- Android system back and iOS back gestures continue to use the existing Navigator stack.
- Desktop sidebar, desktop mini player, full-screen player, playback state, and `StatefulNavigationShell` state retention remain unchanged.
- Ordinary back glyphs use `LucideIcons`, have a minimum 44 px target, and expose the Chinese semantic label and Tooltip `返回`.
- Do not add dependencies or refactor unrelated page structure.
- The worktree already contains unrelated and overlapping uncommitted edits. Before every patch, inspect the current diff for the target file and preserve those edits. Do not commit unless the user separately authorizes it.

---

## File Structure

- `lib/app/app_shell.dart`: owns the pure mobile-primary route policy and passes the resulting visibility into the Dock.
- `lib/design/components/app_mobile_dock.dart`: composes the mini player and five-destination navigation independently.
- `lib/design/components/app_mobile_chrome.dart`: owns the reusable accessible mobile back control and optional header leading slot.
- `lib/app/app_router.dart`: owns pop-or-fallback route callbacks and supplies them to secondary screens.
- `lib/features/{downloads,settings,sources,more,discovery}/...`: displays shared header back actions on secondary workbench/discovery pages.
- `lib/features/{discovery,playlists,library}/...`: displays the shared back action above custom catalogue/detail heroes.
- `test/app/app_shell_routing_test.dart`: verifies the route allowlist as a pure policy.
- `test/app/app_shell_test.dart`: verifies runtime Dock visibility, mini-player continuity, source-pop behavior, and deep-link fallback.
- `test/design/app_mobile_chrome_test.dart`: verifies the shared back control's callback, semantics, Tooltip, and target size.
- Existing focused feature tests: verify each changed screen still renders in mobile and desktop layouts.
- `design.md`: records that the five mobile destinations are persistent only on primary pages.

---

### Task 1: Separate Mobile Primary Navigation from the Mini Player

**Files:**
- Modify: `lib/app/app_shell.dart:42-143`
- Modify: `lib/design/components/app_mobile_dock.dart:8-56`
- Modify: `test/app/app_shell_routing_test.dart:5-36`
- Modify: `test/app/app_shell_test.dart:620-775`

**Interfaces:**
- Produces: `bool showsMobilePrimaryNavigation(String location)`.
- Produces: `AppMobileDock(..., bool showNavigation = true)`; the default preserves isolated existing callers.
- Consumes: `GoRouterState.uri.path`, already supplied to `AppShell.location`.

- [ ] **Step 1: Inspect overlapping user changes before editing**

Run:

```sh
git diff -- lib/app/app_shell.dart lib/design/components/app_mobile_dock.dart test/app/app_shell_routing_test.dart test/app/app_shell_test.dart
```

Record the existing hunks mentally and patch around them; do not restore or rewrite unrelated changes.

- [ ] **Step 2: Add failing pure route-policy tests**

Add to `test/app/app_shell_routing_test.dart`:

```dart
test('mobile primary navigation appears only on exact primary paths', () {
  for (final location in const [
    '/',
    '/search',
    '/discover',
    '/playlists',
    '/more',
  ]) {
    expect(showsMobilePrimaryNavigation(location), isTrue, reason: location);
  }

  for (final location in const [
    '/search/playlist/kw/list-1',
    '/search/album/kw/album-1',
    '/discover/playlist/kw/list-1',
    '/playlists/love',
    '/library',
    '/more/downloads',
    '/more/settings',
    '/more/sources',
    '/more/about',
    '/square',
    '/charts',
    '/downloads',
    '/settings',
    '/sources',
    '/future-secondary',
  ]) {
    expect(showsMobilePrimaryNavigation(location), isFalse, reason: location);
  }
});
```

- [ ] **Step 3: Run the policy test and verify the intended failure**

Run:

```sh
flutter test test/app/app_shell_routing_test.dart
```

Expected: compilation fails because `showsMobilePrimaryNavigation` does not exist.

- [ ] **Step 4: Implement the exact-path policy and pass it to the Dock**

Add the pure policy near `navigationSelectionForLocation` in `lib/app/app_shell.dart`:

```dart
const _mobilePrimaryLocations = <String>{
  '/',
  '/search',
  '/discover',
  '/playlists',
  '/more',
};

bool showsMobilePrimaryNavigation(String location) =>
    _mobilePrimaryLocations.contains(location);
```

In the mobile branch, keep the Dock mounted for player updates but pass the policy result:

```dart
AppMobileDock(
  player: player,
  destinations: _mobileDestinations,
  selectedId: mobileSelectedId,
  onSelected: navigate,
  onOpenPlayer: openPlayer,
  showNavigation: showsMobilePrimaryNavigation(location),
)
```

Do not reuse `navigationSelectionForLocation`; ownership selection and primary/secondary hierarchy are different policies.

- [ ] **Step 5: Add failing runtime assertions for a secondary route**

In the existing mobile Shell test, immediately after opening `more-about`, replace the old tab-based escape expectation with:

```dart
expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);
expect(find.byKey(const Key('mobile-mini-player')), findsNothing);
expect(
  tester.getSize(find.byType(AppMobileDock)).height,
  0,
);
```

After a current track has been installed, navigate to `/more/about` again and assert:

```dart
expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);
expect(find.byKey(const Key('mobile-mini-player')), findsOneWidget);
```

Where this broad Shell test currently escapes `/more/about` or `/more/settings` by tapping a now-hidden primary destination, navigate to the required setup root explicitly:

```dart
tester.element(find.byKey(const Key('main-shell'))).go('/more');
await tester.pumpAndSettle();
```

Task 3 adds dedicated user-facing back-button assertions; this direct navigation is only test setup for the broader state-retention scenario.

Expected before implementation: the bottom navigation is still present and the empty secondary Dock still reserves space.

- [ ] **Step 6: Implement independent Dock composition**

Add the optional property:

```dart
final bool showNavigation;
```

with constructor default:

```dart
this.showNavigation = true,
```

Move `ListenableBuilder` outside the safe-area surface so the zero-content case can return immediately, then compose only existing children:

```dart
final hasTrack = player.state.current != null;
if (!hasTrack && !showNavigation) return const SizedBox.shrink();

return BackdropGroup(
  child: SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Column(
      key: const Key('mobile-player-dock'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTrack)
          MiniPlayer(
            controller: player,
            onOpen: onOpenPlayer,
            variant: MiniPlayerVariant.mobile,
          ),
        if (hasTrack && showNavigation)
          const SizedBox(height: AppSpacing.xs),
        if (showNavigation)
          AppMobileNavigation(
            destinations: destinations,
            selectedId: selectedId,
            onSelected: onSelected,
          ),
      ],
    ),
  ),
);
```

The zero-content test intentionally measures the outer `AppMobileDock` widget because the inner `mobile-player-dock` Column does not exist in this state. Do not wrap `SizedBox.shrink()` in a 12 px `SafeArea` merely to preserve a key.

- [ ] **Step 7: Run focused policy and Shell tests**

Run:

```sh
flutter test test/app/app_shell_routing_test.dart test/app/app_shell_test.dart
```

Expected: route-policy and Dock-visibility assertions pass. No test attempts to tap a hidden destination; user-facing back behavior is added and verified in Tasks 2–4.

---

### Task 2: Add the Shared Accessible Mobile Back Control

**Files:**
- Modify: `lib/design/components/app_mobile_chrome.dart:8-46`
- Create: `test/design/app_mobile_chrome_test.dart`

**Interfaces:**
- Produces: `AppMobileBackButton({Key? key, required VoidCallback onPressed})`.
- Produces: `AppMobilePageHeader(..., VoidCallback? onBack)`; when null, existing primary-page headers remain unchanged.
- Consumes: `LucideIcons.chevronLeft` from `shadcn_ui` and existing `AppGlassSurface`/token styling.

- [ ] **Step 1: Write failing control tests**

Create `test/design/app_mobile_chrome_test.dart` with these imports and wrapper, then add the tests below:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_mobile_chrome.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget testApp(Widget child) => ShadApp(
  theme: buildLightTheme(),
  home: Scaffold(body: Center(child: child)),
);
```

```dart
testWidgets('mobile back control is accessible and invokes its callback', (
  tester,
) async {
  var presses = 0;
  await tester.pumpWidget(
    testApp(
      AppMobilePageHeader(
        title: '设置',
        onBack: () => presses++,
      ),
    ),
  );

  final back = find.byKey(const Key('mobile-page-back'));
  expect(back, findsOneWidget);
  expect(find.bySemanticsLabel('返回'), findsOneWidget);
  expect(tester.getSize(back).width, greaterThanOrEqualTo(44));
  expect(tester.getSize(back).height, greaterThanOrEqualTo(44));

  await tester.longPress(back);
  await tester.pumpAndSettle();
  expect(find.text('返回'), findsOneWidget);

  await tester.tap(back);
  expect(presses, 1);
});

testWidgets('primary mobile header omits back control by default', (
  tester,
) async {
  await tester.pumpWidget(testApp(const AppMobilePageHeader(title: '发现')));
  expect(find.byKey(const Key('mobile-page-back')), findsNothing);
});
```

- [ ] **Step 2: Run the test and verify the intended failure**

Run:

```sh
flutter test test/design/app_mobile_chrome_test.dart
```

Expected: compilation fails because `onBack` and `AppMobileBackButton` do not exist.

- [ ] **Step 3: Implement the shared control and optional header leading**

Add:

```dart
final class AppMobileBackButton extends StatelessWidget {
  const AppMobileBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '返回',
    excludeSemantics: true,
    child: Tooltip(
      message: '返回',
      child: IconButton(
        key: const Key('mobile-page-back'),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: onPressed,
        icon: const Icon(LucideIcons.chevronLeft, size: 20),
      ),
    ),
  );
}
```

Add `VoidCallback? onBack` to `AppMobilePageHeader`. In its outer Row, render the button before the title column with an `AppSpacing.xs` gap. Keep title typography, eyebrow, and action grouping unchanged. The standalone control must also be usable by detail screens with custom heroes.

- [ ] **Step 4: Run the focused component test**

Run:

```sh
flutter test test/design/app_mobile_chrome_test.dart
```

Expected: both tests pass, including semantics, Tooltip, callback, and 44 px target.

---

### Task 3: Wire Workbench and Discovery Secondary Back Navigation

**Files:**
- Modify: `lib/app/app_router.dart:104-129, 411-548`
- Modify: `lib/features/downloads/downloads_screen.dart:26-29, 169-200`
- Modify: `lib/features/settings/settings_screen.dart:18-21, 95-105`
- Modify: `lib/features/sources/sources_screen.dart:14-17, 66-77`
- Modify: `lib/features/more/about_screen.dart:15-30, 48-56`
- Modify: `lib/features/discovery/discovery_screen.dart:30-49, 212-235`
- Modify: `test/app/app_shell_test.dart:703-745`
- Modify: `test/features/downloads/downloads_screen_test.dart`
- Modify: `test/features/settings/settings_screen_test.dart`
- Modify: `test/features/sources/sources_screen_test.dart`
- Modify: `test/features/more/about_screen_test.dart`
- Modify: `test/features/discovery/discovery_screen_test.dart`

**Interfaces:**
- Produces in `app_router.dart`: `VoidCallback secondaryBack(BuildContext context, String fallbackLocation)` local to `buildAppRouter`.
- Consumes: `AppMobilePageHeader.onBack` from Task 2.
- Screen constructor additions are optional `VoidCallback? onBack` to preserve isolated callers; the production router always supplies it for these secondary routes.

- [ ] **Step 1: Inspect all target diffs before patching**

Run:

```sh
git diff -- lib/app/app_router.dart lib/features/downloads/downloads_screen.dart lib/features/settings/settings_screen.dart lib/features/sources/sources_screen.dart lib/features/more/about_screen.dart lib/features/discovery/discovery_screen.dart test/app/app_shell_test.dart test/features/downloads/downloads_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sources/sources_screen_test.dart test/features/more/about_screen_test.dart test/features/discovery/discovery_screen_test.dart
```

Preserve the existing settings/about/search-related work already present in the tree.

- [ ] **Step 2: Add failing screen-level back-header assertions**

For each focused screen test, render the mobile screen with `onBack: () => backCalls++` and assert:

```dart
expect(find.byKey(const Key('mobile-page-back')), findsOneWidget);
await tester.tap(find.byKey(const Key('mobile-page-back')));
expect(backCalls, 1);
```

Cover `DownloadsScreen`, `SettingsScreen`, `SourcesScreen`, `AboutScreen`, and non-embedded mobile `DiscoveryScreen`. Also assert an embedded discovery screen omits the page header/back control, because its parent `/discover` owns primary navigation.

- [ ] **Step 3: Run the feature tests and verify they fail**

Run:

```sh
flutter test test/features/downloads/downloads_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sources/sources_screen_test.dart test/features/more/about_screen_test.dart test/features/discovery/discovery_screen_test.dart
```

Expected: constructor or finder failures because the back callbacks are not wired.

- [ ] **Step 4: Add optional screen callbacks and pass them to shared headers**

Add these exact optional fields and constructor arguments:

```dart
// DownloadsScreen
const DownloadsScreen({super.key, required this.controller, this.onBack});
final VoidCallback? onBack;

// SettingsScreen
const SettingsScreen({
  super.key,
  required this.controller,
  this.onBack,
});
final VoidCallback? onBack;

// SourcesScreen
const SourcesScreen({super.key, required this.controller, this.onBack});
final VoidCallback? onBack;

// AboutScreen
const AboutScreen({
  super.key,
  required this.loadPackageInfo,
  required this.openExternalUri,
  this.onBack,
});
final VoidCallback? onBack;

// DiscoveryScreen
const DiscoveryScreen({
  super.key,
  required this.repository,
  required this.kind,
  required this.onSearch,
  this.onOpenPlaylist,
  this.playTracks,
  this.playlists,
  this.embedded = false,
  this.onBack,
});
final VoidCallback? onBack;
```

Then pass the callback only to mobile headers:

```dart
AppMobilePageHeader(
  title: '设置',
  eyebrow: '偏好与连接',
  onBack: widget.onBack,
)
```

Pass `widget.onBack` from downloads, settings, and sources; pass `onBack` from stateless `AboutScreen`; pass `widget.embedded ? null : widget.onBack` from `DiscoveryScreen` into `_PageHeader`, extend `_PageHeader` with `VoidCallback? onBack`, and pass that value to its `AppMobilePageHeader`. Do not add a back control to primary `/discover`'s embedded child content.

- [ ] **Step 5: Add the router pop-or-fallback callback and wire workbench routes**

Inside `buildAppRouter`, add:

```dart
VoidCallback secondaryBack(
  BuildContext context,
  String fallbackLocation,
) => () {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackLocation);
  }
};
```

Update factories to accept context and pass fallbacks:

```dart
Widget downloadsRoute(BuildContext context) => DownloadsScreen(
  key: ValueKey('downloads-${readDownloadVersion()}'),
  controller: DownloadsController(DownloadRepository(requireConnected().api)),
  onBack: secondaryBack(context, '/more'),
);
```

Use `/more` for downloads, settings, sources, and about, including their desktop-root aliases when rendered on mobile. Use `/discover` for `/square` and `/charts`. The callback is present in desktop instances but has no visual effect because only mobile headers render it.

- [ ] **Step 6: Replace secondary-tab escape assertions with back behavior**

In `test/app/app_shell_test.dart`, after opening `/more/about`, assert the tab bar is absent, tap `mobile-page-back`, and expect `more-mobile-layout`. Add a direct deep-link case:

```dart
final shell = tester.element(find.byKey(const Key('main-shell')));
shell.go('/settings');
await tester.pumpAndSettle();
expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);
await tester.tap(find.byKey(const Key('mobile-page-back')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('more-mobile-layout')), findsOneWidget);
expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
```

This verifies both normal pop and no-stack fallback without depending on internal Router state.

- [ ] **Step 7: Run workbench/discovery and Shell tests**

Run:

```sh
flutter test test/features/downloads/downloads_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sources/sources_screen_test.dart test/features/more/about_screen_test.dart test/features/discovery/discovery_screen_test.dart test/app/app_shell_test.dart
```

Expected: all tests pass; primary `/more` and `/discover` retain the five-destination navigation while their secondary screens do not.

---

### Task 4: Wire Catalogue, Playlist, Album, and Library Back Navigation

**Files:**
- Modify: `lib/app/app_router.dart:69-119, 249-417, 465-493`
- Modify: `lib/features/discovery/album_detail_screen.dart:25-38, 330-352`
- Modify: `lib/features/discovery/online_playlist_detail_screen.dart:25-36, 329-369`
- Modify: `lib/features/playlists/playlist_detail_screen.dart:19-30, 129-176`
- Modify: `lib/features/library/local_library_screen.dart:21-32, 137-184`
- Modify: `test/features/discovery/album_detail_screen_test.dart`
- Modify: `test/features/discovery/online_playlist_detail_screen_test.dart`
- Modify: `test/features/playlists/playlist_detail_screen_test.dart`
- Modify: `test/features/library/local_library_screen_test.dart`
- Modify: `test/app/app_shell_test.dart:834-935`

**Interfaces:**
- Consumes: `secondaryBack(BuildContext, String)` from Task 3.
- Consumes: standalone `AppMobileBackButton` from Task 2.
- Screen constructor additions are optional `VoidCallback? onBack`; the production router supplies them for every detail/library route.

- [ ] **Step 1: Inspect overlapping detail/router diffs**

Run:

```sh
git diff -- lib/app/app_router.dart lib/features/discovery/album_detail_screen.dart lib/features/discovery/online_playlist_detail_screen.dart lib/features/playlists/playlist_detail_screen.dart lib/features/library/local_library_screen.dart test/features/discovery/album_detail_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/library/local_library_screen_test.dart test/app/app_shell_test.dart
```

- [ ] **Step 2: Add failing mobile detail back-control tests**

In the first mobile-size screen construction in each focused feature test, declare `var backCalls = 0;`, add the following named argument to `AlbumDetailScreen`, `OnlinePlaylistDetailScreen`, `PlaylistDetailScreen`, and `LocalLibraryScreen`, then assert the control is present:

```dart
onBack: () => backCalls++,

expect(find.byKey(const Key('mobile-page-back')), findsOneWidget);
await tester.tap(find.byKey(const Key('mobile-page-back')));
expect(backCalls, 1);
```

In each file's wide-layout construction, also supply `onBack: () => backCalls++` and assert `find.byKey(const Key('mobile-page-back'))` finds nothing. This covers album detail, online playlist detail, Service playlist detail, and local library without changing their repository/controller fixtures.

- [ ] **Step 3: Run focused detail tests and verify failure**

Run:

```sh
flutter test test/features/discovery/album_detail_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/library/local_library_screen_test.dart
```

Expected: constructor or finder failures because detail screens do not expose back callbacks.

- [ ] **Step 4: Add optional callbacks and place the shared control above custom heroes**

Add `final VoidCallback? onBack` to each widget using the optional constructor pattern from Task 3. In each mobile-only content column, place:

```dart
if (widget.onBack case final onBack?) ...[
  Align(
    alignment: Alignment.centerLeft,
    child: AppMobileBackButton(onPressed: onBack),
  ),
  const SizedBox(height: AppSpacing.xs),
],
```

Then render the existing metadata/playlist/library hero unchanged. Import `app_mobile_chrome.dart` in these screens. Do not show this control in desktop/narrow layouts classified above mobile.

- [ ] **Step 5: Pass route-specific callbacks from every detail builder**

Change `onlinePlaylistRoute` to accept the route context and fallback:

```dart
Widget onlinePlaylistRoute(
  BuildContext context,
  GoRouterState state, {
  required String fallbackLocation,
}) {
  final connected = requireConnected();
  final source = state.pathParameters['source']!;
  final playlistId = state.pathParameters['playlistId']!;
  return OnlinePlaylistDetailScreen(
    key: ValueKey('online-playlist-$source-$playlistId'),
    controller: OnlinePlaylistDetailController(
      catalog: SearchRepository(connected.api),
      playlists: PlaylistRepository(connected.api),
      source: source,
      playlistId: playlistId,
      initialPlaylist: state.extra is CatalogCollection
          ? state.extra! as CatalogCollection
          : null,
    ),
    player: requirePlayer(),
    downloads: DownloadRepository(connected.api),
    onBack: secondaryBack(context, fallbackLocation),
  );
}
```

Wire these fallbacks:

- search online playlist and album: `/search`;
- discover online playlist, square online playlist, `/square`, and `/charts`: `/discover`;
- Service playlist detail and local library: `/playlists`;
- unknown future secondary routes remain covered by the Shell hide policy and should use `/` when they adopt `secondaryBack`.

- [ ] **Step 6: Extend the player-return integration test**

In the existing mobile detail/player preservation test, assert before opening the full player:

```dart
expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);
expect(find.byKey(const Key('mobile-mini-player')), findsOneWidget);
expect(find.byKey(const Key('mobile-page-back')), findsOneWidget);
```

After closing the player, repeat those assertions and retain `detailRequests == 1`. Because this fixture entered `/square/kw/list-1`, tap the first back control and verify `playlist-square-layout` appears while the tab bar remains hidden. Tap that page's back control and verify `discovery-hub-route` appears with `mobile-bottom-navigation` restored:

```dart
await tester.tap(find.byKey(const Key('mobile-page-back')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('playlist-square-layout')), findsOneWidget);
expect(find.byKey(const Key('mobile-bottom-navigation')), findsNothing);

await tester.tap(find.byKey(const Key('mobile-page-back')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('discovery-hub-route')), findsOneWidget);
expect(find.byKey(const Key('mobile-bottom-navigation')), findsOneWidget);
```

- [ ] **Step 7: Run catalogue/detail and Shell tests**

Run:

```sh
flutter test test/features/discovery/album_detail_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/library/local_library_screen_test.dart test/app/app_shell_test.dart
```

Expected: mobile details have a working back action, wide layouts are unchanged, and the mini player survives full-player round trips without reloading detail data.

---

### Task 5: Update the Design Contract and Run Frozen Verification

**Files:**
- Modify: `design.md:46-55, 108-119`
- Verify all files changed in Tasks 1–4.

**Interfaces:**
- Consumes: final route policy, Dock composition, and secondary back behavior.
- Produces: documented navigation contract and final verification evidence.

- [ ] **Step 1: Update the source-of-truth navigation rules**

Change the mobile navigation paragraph in `design.md` to explicitly state:

```markdown
- Mobile primary pages: five destinations in the bottom navigation, with the mini
  player immediately above it. Secondary pages hide the five-destination
  navigation, retain the mini player when a current track exists, and provide an
  explicit top back action plus platform/system back behaviour.
```

In “Mobile navigation behaviour,” add that only `/`, `/search`, `/discover`, `/playlists`, and `/more` are primary mobile destinations and unlisted Shell routes default to secondary. Preserve the existing Liquid Glass visual rules.

- [ ] **Step 2: Format only the touched Dart files**

Run `dart format` with the explicit changed file list from `git diff --name-only -- '*.dart'`. Exclude unrelated dirty Dart files by comparing the list to Tasks 1–4 before running the formatter.

Expected: formatter changes only task-owned hunks/files.

- [ ] **Step 3: Run the focused functional suites**

Run:

```sh
flutter test test/app/app_shell_routing_test.dart test/app/app_shell_test.dart test/design/app_mobile_chrome_test.dart
flutter test test/features/downloads/downloads_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sources/sources_screen_test.dart test/features/more/about_screen_test.dart test/features/discovery/discovery_screen_test.dart
flutter test test/features/discovery/album_detail_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/library/local_library_screen_test.dart
```

Expected: every command exits 0.

- [ ] **Step 4: Run icon-system verification required by project rules**

Run:

```sh
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: both tests pass; the first `rg` returns no matches; the second returns matches only in `lib/design/components/app_playback_button.dart`.

- [ ] **Step 5: Run targeted analysis and diff checks**

Run:

```sh
flutter analyze lib/app/app_shell.dart lib/app/app_router.dart lib/design/components/app_mobile_dock.dart lib/design/components/app_mobile_chrome.dart lib/features/downloads/downloads_screen.dart lib/features/settings/settings_screen.dart lib/features/sources/sources_screen.dart lib/features/more/about_screen.dart lib/features/discovery/discovery_screen.dart lib/features/discovery/album_detail_screen.dart lib/features/discovery/online_playlist_detail_screen.dart lib/features/playlists/playlist_detail_screen.dart lib/features/library/local_library_screen.dart
git diff --check
```

Expected: analyzer and diff check exit 0.

- [ ] **Step 6: Review the final frozen diff against the specification**

Run:

```sh
git diff -- design.md lib/app/app_shell.dart lib/app/app_router.dart lib/design/components/app_mobile_dock.dart lib/design/components/app_mobile_chrome.dart lib/features/downloads/downloads_screen.dart lib/features/settings/settings_screen.dart lib/features/sources/sources_screen.dart lib/features/more/about_screen.dart lib/features/discovery/discovery_screen.dart lib/features/discovery/album_detail_screen.dart lib/features/discovery/online_playlist_detail_screen.dart lib/features/playlists/playlist_detail_screen.dart lib/features/library/local_library_screen.dart test/app/app_shell_routing_test.dart test/app/app_shell_test.dart test/design/app_mobile_chrome_test.dart test/features/downloads/downloads_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sources/sources_screen_test.dart test/features/more/about_screen_test.dart test/features/discovery/discovery_screen_test.dart test/features/discovery/album_detail_screen_test.dart test/features/discovery/online_playlist_detail_screen_test.dart test/features/playlists/playlist_detail_screen_test.dart test/features/library/local_library_screen_test.dart
```

Confirm: only five exact primary paths show the tab bar; secondary empty Dock is zero-height; secondary playback stays reachable; every known secondary family has explicit back; desktop and full player logic are unchanged; unrelated dirty changes remain intact. Do not commit without explicit user authorization.
