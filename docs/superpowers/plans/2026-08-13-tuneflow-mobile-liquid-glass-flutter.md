# TuneFlow Mobile Liquid Glass Flutter Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved restrained, soft TuneFlow visual system in Flutter, using Liquid Glass-inspired navigation and control layers across every mobile screen on iOS and Android while preserving content geometry, routes, playback behaviour, and the locked mobile track-item structure.

**Architecture:** Register the Mist Sea theme as a complete semantic theme family, expose it through an inherited scope, and make every glass effect consume one of five central roles. A single mobile dock owns the mini player and five-destination tab bar. Mobile pages reuse shared chrome and sheet primitives; the full player adds a cover-derived backdrop from the same cached image provider as the sharp artwork. Accessibility and performance policy can disable blur without changing layout. Desktop keeps its existing layout and receives no glass treatment, although shared Mist Sea palette and typography corrections apply consistently.

**Tech Stack:** Flutter 3.35.2, Dart 3.9.0, `shadcn_ui` 0.53.6, Riverpod 3.3.2, GoRouter 17.2.3, Flutter `BackdropGroup`/`BackdropFilter.grouped`, widget and golden tests.

## Global Constraints

- Do not change API clients, repositories, data models, audio-service semantics,
  queue behaviour, navigation destinations, or route paths.
- Keep the mobile track-item contract exactly
  `title / artist / quality -> favourite -> more`; do not add artwork or duration.
- Keep the five mobile destinations and order exactly:
  `首页`, `搜索`, `我的音乐`, `下载`, `更多`.
- Apply glass only to navigation, compact controls, temporary sheets, and rare
  player control islands. Track rows, artwork, lyrics, cards, and primary reading
  surfaces remain stable content surfaces.
- Do not place raw glass colours, alpha values, blur sigma, saturation, borders,
  highlights, or shadows in page files. Every value comes from a semantic role.
- Do not nest glass surfaces or share a backdrop key between overlapping filters.
- Keep light/dark, high-contrast, reduced-motion, and opaque-fallback behaviour
  deterministic and testable.
- Register only `AppThemeId.mistSea` in this release. Do not add a theme picker or
  persist a theme-family choice yet.
- Use the same mobile appearance on iOS and Android. Branch only for native
  system behaviour such as safe areas, back gestures, system bars, and haptics.
- Keep desktop layout and interaction unchanged. Shared palette/type corrections
  may change its rendering, but desktop must never instantiate mobile glass.
- Do not update golden files until the rendered screens have been manually
  inspected at both target mobile widths.
- Do not upgrade existing Dart or Flutter packages as part of this work.

## Locked Visual Metrics

| Item | Metric |
| --- | --- |
| Minimum touch target | 44 x 44 logical pixels |
| Mobile horizontal page inset | 16 px |
| Floating dock outer inset | 12 px |
| Mini-player height | 60 px |
| Gap between mini player and tab bar | 8 px |
| Tab-bar content height | 64 px plus bottom safe area |
| Glass control radius | 16 px |
| Glass navigation radius | 22 px |
| Glass sheet radius | 28 px top / 24 px floating |
| Normal transition | 220-280 ms |
| Reduced-motion transition | at most 150 ms, opacity only |

## Baseline Evidence

- `flutter analyze` is clean before implementation.
- The focused baseline command below passes all 24 tests:

  ```bash
  flutter test \
    test/design/app_theme_test.dart \
    test/app/app_shell_test.dart \
    test/features/player/player_screen_test.dart \
    test/features/search/search_screen_test.dart
  ```

- Dependency resolution reports 40 packages with newer releases outside current
  constraints. This is recorded evidence, not permission to upgrade them.
- Existing Open Design SSIM comparisons describe the previous design. Preserve
  `test/visual/full-fidelity-report.md` as historical evidence; it is not the
  acceptance oracle for Liquid Glass.

---

## Task 1: Establish the Theme Registry and Production Typography

**Files:**

- Create: `lib/design/app_theme_definition.dart`
- Create: `lib/design/app_theme_scope.dart`
- Modify: `lib/design/design_tokens.dart`
- Modify: `lib/design/app_theme.dart`
- Modify: `lib/app/app.dart`
- Modify: `pubspec.yaml`
- Add: `assets/fonts/NotoSerifSC-VariableFont_wght.ttf`
- Add: `assets/fonts/OFL-NotoSerifSC.txt`
- Add: `assets/fonts/IBMPlexMono-Medium.ttf`
- Add: `assets/fonts/OFL-IBMPlexMono.txt`
- Test: `test/design/app_theme_test.dart`
- Test: `test/app/app_shell_test.dart`

- [ ] Extend the theme tests first so they fail unless every registered theme has
  a light and dark definition, the three font families resolve, and Mist Sea is
  the only registered theme family.
- [ ] Add the registry contract without UI selection state:

  ```dart
  enum AppThemeId { mistSea }

  final class AppThemeDefinition {
    const AppThemeDefinition({
      required this.id,
      required this.light,
      required this.dark,
    });

    final AppThemeId id;
    final AppThemeVariant light;
    final AppThemeVariant dark;
  }

  abstract final class AppThemeRegistry {
    static const current = AppThemeId.mistSea;
    static AppThemeDefinition definition(AppThemeId id) => switch (id) {
      AppThemeId.mistSea => mistSea,
    };
  }
  ```

- [ ] Add `AppThemeScope` as an `InheritedWidget` exposing the current
  `AppThemeDefinition` and variant. `MusicFreeServiceApp` supplies fixed
  `AppThemeId.mistSea`; existing `ThemeMode` persistence continues to choose
  light/dark.
- [ ] Refactor `AppTokens` into semantic colour and type roles consumed by both
  `ShadThemeData` and app components. Preserve compatibility getters temporarily
  only where they make migration reviewable; remove no public role without a
  repository-wide consumer check.
- [ ] Use Noto Serif SC only for page-level display roles, Noto Sans CJK SC for
  body/control roles, and IBM Plex Mono Medium for time, count, bitrate, and
  diagnostic roles. Keep Chinese page titles compact; do not reproduce the
  oversized headings from early mockups.
- [ ] Download fonts only from their official repositories and retain their OFL
  license files. Source Noto Serif SC's variable font and `OFL.txt` from
  `https://github.com/google/fonts/tree/main/ofl/notoserifsc`; source IBM Plex
  Mono Medium and its license from
  `https://github.com/IBM/plex/tree/master/packages/plex-mono/fonts/complete/ttf`
  and `https://github.com/IBM/plex/blob/master/LICENSE.txt`. Register exact
  family names and weights in `pubspec.yaml`.
- [ ] Keep the existing `ShadApp.custom` composition and supply its light/dark
  themes from the selected definition rather than duplicating a second theme
  system.
- [ ] Run:

  ```bash
  flutter test test/design/app_theme_test.dart test/app/app_shell_test.dart
  flutter analyze
  ```

## Task 2: Build the Glass Role System, Primitive, and Fallback Policy

**Files:**

- Create: `lib/design/app_glass_policy.dart`
- Create: `lib/design/components/app_glass_surface.dart`
- Modify: `lib/design/app_theme_definition.dart`
- Modify: `lib/design/design_tokens.dart`
- Modify: `lib/storage/app_preferences.dart`
- Modify: `lib/storage/app_settings_controller.dart`
- Modify: `test/support/memory_app_preferences.dart`
- Test: `test/design/app_glass_surface_test.dart`
- Test: `test/storage/app_preferences_test.dart`

- [ ] Write failing tests for role completeness, light/dark role differences,
  high-contrast fallback, explicit reduced-transparency fallback, disabled blur,
  and geometry equality between blurred and opaque modes.
- [ ] Define the complete semantic API:

  ```dart
  enum AppGlassRole { nav, control, sheet, clear, fallback }

  final class AppGlassStyle {
    const AppGlassStyle({
      required this.fill,
      required this.border,
      required this.highlight,
      required this.fallbackFill,
      required this.blurSigma,
      required this.saturation,
      required this.shadows,
    });
    // Immutable fields use Color, double, and List<BoxShadow>.
  }

  final class AppGlassPolicy {
    const AppGlassPolicy({
      required this.blurEnabled,
      required this.reduceMotion,
    });
    final bool blurEnabled;
    final bool reduceMotion;
  }
  ```

- [ ] Add `reduceTransparency` to `AppSettings`, storage serialization, defaults,
  controller update methods, and memory test doubles. This is an accessibility
  preference, not a theme-family preference.
- [ ] Derive policy from `MediaQuery.highContrast`,
  `MediaQuery.disableAnimations`, `MediaQuery.accessibleNavigation`, the stored
  `reduceTransparency` setting, and an injectable session performance flag.
- [ ] Implement `AppGlassPerformanceController` with a rolling 60-frame window.
  Mark the current session degraded when at least 20% of measured frames exceed
  24 ms. Do not automatically restore blur during that session; this prevents
  visible oscillation. Keep frame timing subscription lifecycle-owned and
  removable in tests.
- [ ] Implement `AppGlassSurface` as:
  `ClipRRect -> BackdropFilter.grouped -> DecoratedBox -> child`. Use
  `BackdropFilter.enabled` so opaque fallback retains identical constraints,
  padding, radius, and semantics. Use `BackdropGroup` only at bounded parents
  where children do not overlap.
- [ ] Treat `fallback` as a style supplied by each theme, not a page-selectable
  decorative role. `AppGlassSurface(role: fallback)` is valid for tests and
  diagnostics; automatic policy uses the requested role's `fallbackFill`.
- [ ] Run:

  ```bash
  flutter test test/design/app_glass_surface_test.dart test/storage/app_preferences_test.dart
  flutter analyze
  ```

## Task 3: Replace the Mobile Bottom Stack with One Floating Dock

**Files:**

- Create: `lib/design/components/app_mobile_dock.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/design/components/app_navigation.dart`
- Modify: `lib/features/player/mini_player.dart`
- Test: `test/app/app_shell_test.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] Add failing shell tests for exact destination labels/order, a 44 px minimum
  target per item, selected lens semantics, bottom safe-area handling, mini-player
  controls, and complete dock absence on `/player`.
- [ ] Change only the mobile shell to a body that extends behind a single
  `AppMobileDock`. The dock owns horizontal inset, safe area, `BackdropGroup`,
  and vertical composition. Do not stack two unrelated opaque bars.
- [ ] Implement the tab bar as `glassNav`, 64 px content height, with a restrained
  selected lens using background plus accent colour so selection is not
  colour-only. Keep the existing icons and route destinations.
- [ ] Refactor the mobile mini player to `glassNav` with this fixed order:
  artwork, title/artist, play/pause, next. It is 60 px high, exposes one combined
  semantic label for track identity, and retains independent semantic buttons.
- [ ] Omit the mini-player row entirely when the queue is empty; remove its 8 px
  accessory gap at the same time. Keep the tab bar visible on ordinary routes.
- [ ] Hide the complete dock, including tab bar and mini player, while the
  full-screen player route is active. Preserve desktop mini-player behaviour.
- [ ] Run:

  ```bash
  flutter test test/app/app_shell_test.dart test/features/player/player_screen_test.dart
  flutter analyze
  ```

## Task 4: Create Shared Mobile Chrome, Fields, Segments, and Sheets

**Files:**

- Create: `lib/design/components/app_mobile_chrome.dart`
- Modify: `lib/design/components/app_form.dart`
- Modify: `lib/design/components/app_feedback.dart`
- Modify: `lib/features/search/track_action_sheet.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/design/app_mobile_chrome_test.dart`
- Test: `test/features/settings/settings_screen_test.dart`

- [ ] Write component tests for `AppMobilePageHeader`, glass search field,
  segmented control, chip/control group, mobile sheet, desktop opaque sheet, and
  accessibility labels.
- [ ] Add shared mobile components that consume only `glassNav`, `glassControl`,
  or `glassSheet`. Give each an explicit opaque desktop path; do not infer mobile
  from operating-system platform.
- [ ] Extend the existing field API with an intentional glass presentation used
  for search and compact filters. Keep validation, focus, keyboard, and controller
  behaviour unchanged.
- [ ] Route mobile action sheets, queue sheets, and menus through `glassSheet`.
  Keep body content opaque enough for readability and preserve dismissal/back
  behaviour.
- [ ] Add a `减少透明效果` accessibility toggle to Settings, backed by
  `AppSettings.reduceTransparency`. Its helper text states that it replaces blur
  with an opaque surface without changing layout.
- [ ] Run:

  ```bash
  flutter test test/design/app_mobile_chrome_test.dart test/features/settings/settings_screen_test.dart
  flutter analyze
  ```

## Task 5: Migrate Home, Search, and Utility Screens

**Files:**

- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/search/search_screen.dart`
- Modify: `lib/features/search/search_mobile_results.dart`
- Modify: `lib/features/search/search_history_panel.dart`
- Modify: `lib/features/downloads/downloads_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/features/sources/sources_screen.dart`
- Modify: `lib/features/connection/connection_screen.dart`
- Modify: `lib/features/more/more_screen.dart`
- Test: corresponding files under `test/features/`

- [ ] Add or update widget tests before each screen migration so page semantics,
  actions, route transitions, and list-item structure are pinned independently
  of visual styling.
- [ ] Use shared page headers and compact serif display roles. Keep normal Chinese
  titles within the locked compact scale and preserve text scaling.
- [ ] Convert search fields, provider selectors, filters, connection status, and
  compact action clusters to `glassControl`. Keep result rows, history content,
  download rows, settings groups, and source rows on stable content surfaces.
- [ ] Preserve every existing empty, loading, error, connected, and disconnected
  state. Glass styling must not absorb state indicators or weaken contrast.
- [ ] Verify keyboard insets on search/connection forms and ensure the floating
  dock never covers the last result row.
- [ ] Run focused tests for all modified feature directories, then:

  ```bash
  flutter test test/features/home test/features/search test/features/downloads \
    test/features/settings test/features/sources test/features/connection
  flutter analyze
  ```

## Task 6: Migrate Discovery, Charts, Playlists, and Library Without Row Changes

**Files:**

- Modify: `lib/features/discovery/discovery_screen.dart`
- Modify: `lib/features/discovery/playlist_discovery_view.dart`
- Modify: `lib/features/discovery/online_playlist_detail_screen.dart`
- Modify: `lib/features/playlists/playlists_screen.dart`
- Modify: `lib/features/playlists/playlist_detail_screen.dart`
- Modify: `lib/features/catalog/catalog_track_list.dart`
- Test: `test/features/discovery/`
- Test: `test/features/playlists/`
- Test: `test/features/catalog/catalog_track_list_test.dart`

- [ ] Strengthen tests around chart presence, discovery tabs, playlist navigation,
  favourite/more action order, and the absence of mobile row artwork/duration.
- [ ] Apply glass to headers, tabs, filters, and floating actions only. Do not wrap
  playlist cards, cover grids, chart entries, metadata blocks, or track rows in
  glass.
- [ ] Preserve the current music-list layout the user explicitly kept. Visual
  refresh may change type, spacing tokens, focus, selection, and pressed states;
  it must not change field order or responsive disclosure.
- [ ] Ensure the chart/ranking entry remains discoverable in the approved
  navigation/content location at both target widths.
- [ ] Run:

  ```bash
  flutter test test/features/discovery test/features/playlists \
    test/features/catalog/catalog_track_list_test.dart
  flutter analyze
  ```

## Task 7: Implement the Cover-Derived Full Player

**Files:**

- Modify: `lib/design/components/artwork.dart`
- Create: `lib/features/player/player_backdrop.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/player/lyrics_view.dart`
- Test: `test/design/artwork_test.dart`
- Test: `test/features/player/player_backdrop_test.dart`
- Test: `test/features/player/player_screen_test.dart`

- [ ] Write failing tests for one shared image provider, deterministic fallback,
  decorative-background semantics exclusion, opacity-only track transition,
  reduced-motion timing, and full-player dock absence.
- [ ] Introduce an immutable artwork source that owns one provider instance:

  ```dart
  final class AppArtworkSource {
    AppArtworkSource.network(String url, {required this.fallbackSeed})
        : provider = NetworkImage(url, headers: artworkRequestHeaders);

    final ImageProvider<Object> provider;
    final String fallbackSeed;
  }
  ```

  Pass the same `AppArtworkSource` to sharp artwork and backdrop; do not trigger
  colour extraction, a second HTTP request, or a second provider construction.
- [ ] Build `PlayerBackdrop` with a full-canvas `Stack`: cover image using
  `BoxFit.cover`, `ImageFiltered` blur and scale to hide edges, Mist Sea light/dark
  veil, and a deterministic gradient fallback derived from the existing seed.
  Wrap decoration in `ExcludeSemantics` and `IgnorePointer`.
- [ ] Crossfade only opacity when the track changes: 280 ms normally and no more
  than 150 ms when reduced motion is enabled. Do not animate blur radius, colour
  extraction, gradients, or layout.
- [ ] Recompose the mobile player above the backdrop while preserving its
  existing cover/lyrics/queue `PageView`, queue actions, playback state, seek
  behaviour, and keep-awake lifecycle.
- [ ] Use `glassClear` only for bounded transport/control islands and `glassSheet`
  for queue surfaces. Keep artwork, lyrics, metadata, and progress reading areas
  stable and contrast-safe over every fallback.
- [ ] Run:

  ```bash
  flutter test test/design/artwork_test.dart \
    test/features/player/player_backdrop_test.dart \
    test/features/player/player_screen_test.dart
  flutter analyze
  ```

## Task 8: Prove Accessibility, Fallback, and Cross-Platform Behaviour

**Files:**

- Create: `test/design/mobile_liquid_glass_accessibility_test.dart`
- Modify: `integration_test/mobile_acceptance_test.dart`
- Modify: platform system-bar configuration files only if runtime evidence shows
  a mismatch; do not branch component visuals by platform.

- [ ] Test light/dark, `highContrast`, `disableAnimations`,
  `accessibleNavigation`, stored reduced transparency, session performance
  degradation, text scales 1.0/1.3/2.0, and bottom safe areas.
- [ ] Assert every interactive target is at least 44 x 44 and selection/state is
  never communicated only by colour or blur.
- [ ] Assert opaque fallback has the same geometry, semantics, route behaviour,
  and scroll clearance as normal glass.
- [ ] Extend mobile acceptance coverage for tab navigation, mini-player next,
  full-player entry/exit, queue, back navigation, keyboard dismissal, settings
  persistence, and reconnect lifecycle.
- [ ] Run the same acceptance route on at least one recent iOS simulator and one
  Android emulator. Record OS/device and screenshots; platform parity means the
  same component layout, not identical system chrome.
- [ ] Run:

  ```bash
  flutter test test/design/mobile_liquid_glass_accessibility_test.dart
  flutter test integration_test/mobile_acceptance_test.dart
  flutter analyze
  ```

## Task 9: Render, Review, and Freeze the New Visual Baseline

**Files:**

- Modify: `test/visual/full_ui_gallery_test.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Add/update after approval: `test/visual/full_goldens/mobile-*.png`
- Add: targeted reduced-transparency goldens under `test/visual/full_goldens/`
- Preserve: `test/visual/design_baselines/`
- Preserve: `test/visual/full-fidelity-report.md`

- [ ] Render all 11 mobile pages at 390 x 844 and 360 x 800 in both light and
  dark mode: home, search, playlist square, charts, library, playlist detail,
  player, downloads, settings, sources, and more.
- [ ] Add opaque-fallback goldens for home, search, and player at 390 x 844. Their
  geometry must match the corresponding blur-enabled capture.
- [ ] Run existing desktop gallery tests at 1024 x 768 and 1440 x 960 to catch
  accidental mobile-glass leakage or desktop layout regression.
- [ ] Manually inspect each capture for hierarchy, Chinese type scale, safe-area
  clearance, scroll reachability, dock state, glass restraint, artwork loading,
  player readability, dark contrast, and 44 px targets before accepting it.
- [ ] Update only the new Flutter goldens after visual approval. Do not overwrite
  the historical Open Design baselines or manufacture a passing SSIM report.
- [ ] Run the final frozen-tree verification:

  ```bash
  dart format --output=none --set-exit-if-changed lib test integration_test
  flutter analyze
  flutter test
  flutter test test/visual/full_ui_gallery_test.dart
  flutter test test/visual/high_fidelity_gallery_test.dart
  ```

- [ ] Record the exact Flutter/Dart version, simulator/emulator targets, commands,
  test counts, and any remaining device-only blur/performance risk in the final
  handoff. Do not claim completion from prototype screenshots alone.

## Completion Criteria

- Every mobile route uses the shared Mist Sea typography and semantic component
  system; glass is limited to the approved functional layers.
- iOS and Android render the same five-destination floating dock and mobile page
  composition, with native platform behaviour preserved.
- The full player uses the current cover as a cached blurred background with a
  deterministic fallback and no extra network request.
- Reduced transparency, high contrast, reduced motion, and session performance
  fallback preserve geometry and functionality.
- The shared music-list item contract, routes, repositories, and playback
  behaviour remain unchanged and are covered by tests.
- Focused tests, complete Flutter tests, visual galleries, and manual mobile
  inspection pass on the frozen tree.
