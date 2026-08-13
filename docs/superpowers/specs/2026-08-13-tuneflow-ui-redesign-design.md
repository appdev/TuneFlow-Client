# TuneFlow UI Redesign — Design Specification

Date: 2026-08-13
Status: approved for implementation
Primary system: [`design.md`](../../../design.md)

## Outcome

Redesign the complete Flutter client around a restrained, soft, music-first
visual system. Improve information hierarchy across desktop and mobile without
changing routes, repositories, API contracts, player state, or the structural
contract of shared music-list items.

## Confirmed product decisions

- Audience: Chinese-speaking users of a self-hosted cross-platform music client.
- Primary job: discover, search, organise, and continue playing music.
- Tone: restrained and soft.
- Typography: Noto Serif SC for page-level display; Noto Sans SC for body and
  controls; IBM Plex Mono for time, counters, bitrate, and diagnostics.
- Actual type scale is compact. Choosing the serif direction does not authorise
  oversized Chinese headings.
- Player: immersive full-canvas layout with a blurred background derived from
  the current cover.
- Theme future: prepare a registry for multiple theme families, but do not show
  a theme-family picker in this release.

## Goals

1. Establish a consistent visual hierarchy across all routes.
2. Replace excessive borders and equal-weight surfaces with type, spacing, and
   surface-lightness hierarchy.
3. Keep desktop, narrow, and mobile layouts coherent without shrinking primary
   text or touch targets.
4. Make the player feel immersive while preserving readable lyrics and reliable
   controls across arbitrary cover images.
5. Make later theme-family switching additive rather than a screen rewrite.
6. Preserve existing business behaviour and shared music-list item structure.

## Non-goals

- No route-tree replacement or production-file deletion.
- No API, repository, data-model, audio-service, queue, or persistence redesign.
- No new theme-family picker in this release.
- No dominant-colour extraction dependency or extra image request.
- No change to the field order or responsive behaviour of music-list items.
- No copied visual assets, record-disc construction, or controls from the user
  reference screenshots.

## Current evidence

- Flutter + Riverpod + GoRouter + shadcn_ui.
- Existing semantic light/dark colours, 4-point spacing, and responsive classes.
- Existing ThemeMode persistence already supports system/light/dark.
- Existing shared `CatalogTrackList` is consumed by search and online playlist
  detail; its row contract is the main compatibility boundary.
- Existing visual tests cover desktop and mobile routes at multiple viewports.

## System architecture

### Theme axes

`ThemeMode` remains responsible only for brightness. Add a stable theme-family
identifier and registry:

```text
AppThemeId.mistSea
  └── AppThemeDefinition
      ├── light semantic tokens → light ShadThemeData
      └── dark semantic tokens  → dark ShadThemeData
```

`AppThemeScope` is the single inherited boundary that exposes the active
theme-family ID. `AppTokens.of(context)` resolves the complete semantic token
set through the registry and current brightness. Screens do not import a named
palette and do not branch on a theme ID.

The current settings source remains the single runtime source of truth. This
release may use `AppThemeId.mistSea` as the fixed default without adding an
unused preference or selector. A later feature can add persistence and UI
without changing component contracts.

### Component boundaries

- Theme registry owns palette completeness and Shad scheme construction.
- Shared design components own repeated visual states and semantics.
- Feature screens compose shared components and retain current controllers.
- `CatalogTrackList` owns the shared track-item layout.
- A new player backdrop component owns blurred/fallback imagery and veil logic.
- `AppShell` owns the route-dependent immersive navigation decision.

### Data flow

Normal feature data flow remains:

```text
Repository → Controller state → Screen → shared design component
```

Player imagery uses existing state only:

```text
PlayerState.current.raw['pic']
  └── one shared ImageProvider / Flutter image-cache entry
      ├── sharp AppArtwork
      └── decorative blurred backdrop
           └── shared deterministic seed fallback on missing/error
```

There is no palette-extraction service, separate repository fetch, or persisted
copy of cover imagery. Foreground and background widgets share the same
`ImageProvider`; Flutter's image cache owns network de-duplication.

## Page structures

### Discovery family

Home, playlist square, charts, and user playlists use an Ecosystem Index shape:
one featured focus, then clearly named content rails or lists. Section rhythm
comes from uneven but tokenised spacing, not boxed sections.

### Detail family

Online and local playlist detail pages may redesign their headers and supporting
actions. Their track lists use the locked shared item unchanged.

### Task family

Search, downloads, sources, settings, and connection use Workbench principles:
functional page titles, controls adjacent to their target, local state feedback,
and no decorative dashboard cards.

### Immersive player

Desktop hides the product sidebar and uses a split artwork/lyrics composition.
Mobile hides the bottom navigation and mini player while retaining the existing
cover/lyrics/queue view model. Both retain explicit and system back behaviour.

The blurred cover is scaled beyond the viewport, blurred, slightly desaturated,
and covered by a theme veil. Foreground text never relies on unprocessed cover
contrast. Track changes crossfade the background using opacity only.

## Locked track-item contract

Desktop:

```text
index → artwork → title / artist / quality → favourite → album → duration → more
```

Narrow desktop preserves existing album/duration visibility rules. Mobile:

```text
title / artist / quality → favourite → more
```

Mobile does not gain artwork. Tap/double-tap, action menus, context menus, and
favourite behaviour remain. Visual states must not change row geometry.

## Responsive behaviour

- `<720`: mobile navigation and 16 px page inset; 44 px targets; immersive
  player hides bottom chrome.
- `720–1179`: icon navigation rail; track fields follow current visibility
  rules; no permanent context panel.
- `≥1180`: full navigation sidebar; readable content measure; queue appears only
  when playback context or direct user action requires it.
- Supported visual verification widths: 360, 390, 1024, and 1440 logical pixels.

## Type, spacing, and density

The canonical values live in `design.md`. Critical constraints:

- Home focus: 34 desktop / 28 mobile.
- Ordinary page title: 28 desktop / 24 mobile.
- Track title: 14; metadata: 12; counter/duration: 12 desktop / 11 mobile.
- Body and controls: 15.
- 4-point spacing system.
- Touch targets remain at least 44 even when visual content is compact.

## Interaction and state rules

Interactive components cover default, hover, focus, active, disabled, loading,
error, and success where the state applies. Focus is immediate. Visual actions
use silent success. Failures roll state back and offer retry. Reversible delete
uses Undo; irreversible actions require confirmation.

Motion is restrained: 100–120 ms press, 180 ms state transitions, at most 280 ms
for sheets/page transitions. Reduced motion is opacity-only and no longer than
150 ms. No bounce, parallax, background drift, or animated gradient.

## Error handling

- Skeletons match final geometry.
- Local failures remain local and include a specific retry.
- Empty states have one explanation and at most one primary action.
- Player image failure falls back visually without affecting playback.
- Player playback error preserves queue, metadata, navigation, and retry paths.
- Theme registry fails tests if a registered theme omits a semantic role.

## Accessibility

- Maintain semantics on artwork and icon-only controls.
- Focus ring contrast and keyboard reachability are mandatory.
- Do not encode playing/error/success state only with colour.
- Validate text scaling, screen-reader labels, system back, reduced motion, and
  44 px targets.

## Expected implementation scope

### New production files

- `lib/design/app_theme_definition.dart`
- `lib/design/app_theme_scope.dart`
- `lib/features/player/player_backdrop.dart`
- `tokens.css` (portable export; Flutter does not import it)
- `assets/fonts/NotoSansSC-Variable.ttf`
- `assets/fonts/NotoSerifSC-Variable.ttf`
- `assets/fonts/IBMPlexMono-Medium.ttf`
- `assets/fonts/OFL-NotoSansSC.txt`
- `assets/fonts/OFL-NotoSerifSC.txt`
- `assets/fonts/OFL-IBMPlexMono.txt`

### Existing production files expected to change

- `pubspec.yaml`
- `lib/app/app.dart`
- `lib/app/app_shell.dart`
- `lib/design/design_tokens.dart`
- `lib/design/app_theme.dart`
- `lib/design/app_breakpoints.dart`
- `lib/design/components/app_navigation.dart`
- `lib/design/components/app_button.dart`
- `lib/design/components/app_form.dart`
- `lib/design/components/app_feedback.dart`
- `lib/design/components/app_states.dart`
- `lib/design/components/artwork.dart`
- `lib/design/components/playback_progress.dart`
- `lib/design/components/queue_panel.dart`
- `lib/design/components/playlist_card.dart`
- `lib/design/components/track_tile.dart`
- `lib/design/components/track_actions.dart`
- `lib/features/connection/connection_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/search/search_screen.dart`
- `lib/features/search/search_desktop_results.dart`
- `lib/features/search/search_mobile_results.dart`
- `lib/features/discovery/discovery_screen.dart`
- `lib/features/discovery/online_playlist_detail_screen.dart`
- `lib/features/playlists/playlists_screen.dart`
- `lib/features/playlists/playlist_detail_screen.dart`
- `lib/features/downloads/downloads_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/sources/sources_screen.dart`
- `lib/features/more/more_screen.dart`
- `lib/features/player/player_screen.dart`
- `lib/features/player/lyrics_view.dart`
- `lib/features/player/mini_player.dart`

This is an expected upper bound. The implementation plan must remove files that
do not require a justified change; broad edits are not a goal.

### Test scope

- Existing design, shell, feature, and player widget tests.
- New theme registry completeness and theme-scope tests.
- New player backdrop image/fallback/light/dark/reduced-motion tests.
- AppShell normal and immersive route tests.
- Track-list invariant tests for order, breakpoint visibility, and interaction.
- Existing full and high-fidelity visual galleries at all supported viewports.

### Deletions

None.

## Verification commands

The implementation plan may narrow intermediate checks, but completion requires:

```sh
flutter analyze
flutter test
flutter test test/visual/full_ui_gallery_test.dart
flutter test test/visual/high_fidelity_gallery_test.dart
```

Golden updates are evidence only after the new images are visually inspected;
regeneration alone is not acceptance.

## Acceptance criteria

1. Every route uses the Mist Sea semantic theme without page-local raw colours.
2. Light/dark still follow persisted ThemeMode.
3. The registry can add a second complete theme without editing feature screens.
4. Page titles and body copy follow the confirmed compact type scale.
5. Shared track-item structure and interaction remain unchanged.
6. Player navigation becomes immersive and its background derives from current
   artwork with reliable fallback and readable foreground contrast.
7. Existing business and playback tests remain green.
8. Golden output is coherent at 360, 390, 1024, and 1440 widths.

## Deferred work

- Additional theme-family palettes.
- Theme-family selector UI and persistence field.
- Dominant-colour extraction from covers.
- Any service/API or playback feature change.
