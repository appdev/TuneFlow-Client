# TuneFlow Mobile Liquid Glass Design

Date: 2026-08-13
Status: approved for Flutter implementation

## Outcome

Apply one restrained iOS 26 Liquid Glass-inspired visual language to every
TuneFlow mobile screen on both iOS and Android. Preserve the current information
architecture, routes, playback behaviour, mobile navigation destinations, and
the locked track-item structure.

This work changes the visual and interaction layer only. It does not make
Flutter controls native UIKit controls and must not describe the result as
native Liquid Glass rendering.

## Product intent

- Audience: Chinese-speaking cross-platform music listeners connected to a
  self-hosted service.
- Primary job: discover, manage, and continue playing music with minimal
  interface friction.
- Tone: restrained, soft, and immersive.
- Theme: existing Mist Sea light and dark palettes.

## Chosen approach

Use layered Liquid Glass rather than applying transparency to every surface.
The distinction is functional:

1. Content is stable and readable.
2. Navigation floats above content.
3. Controls use glass only when grouping or separation is necessary.

Rejected alternatives:

- Full glassification makes lists noisy, weakens hierarchy, and increases render
  cost.
- Navigation-only glass does not create a coherent mobile visual language across
  search, settings, sheets, and the player.

## Scope

The design applies to mobile home, search, discovery, charts, playlist details,
library, downloads, settings, service connection, sheets, menus, queue, and the
full-screen player. Desktop remains unchanged.

Both iOS and Android use the same appearance. Platform-specific branching is
limited to system behaviour such as safe areas, back gestures, system bars,
haptics, and accessibility integration.

## Material architecture

Components consume semantic roles supplied by every light/dark theme pair:

| Role | Purpose | Typical surfaces |
| --- | --- | --- |
| `glassNav` | Persistent navigation | Top bar, tab bar, mini player |
| `glassControl` | Compact interaction groups | Search, filters, transport controls |
| `glassSheet` | Temporary elevated surfaces | Menus, queue, modal sheets |
| `glassClear` | Rare rich-background treatment | Selected player controls only |
| `glassFallback` | Accessible/performance fallback | Opaque replacement for any glass role |

Each role owns its tint, opacity, blur strength, highlight, boundary, shadow,
and fallback surface. Page components cannot introduce local glass values.
Future `AppThemeId` registrations must supply all five roles.

## Composition

- Content scrolls behind bounded glass surfaces.
- Track rows, artwork, lyrics, and primary reading areas remain content surfaces.
- Do not nest glass surfaces or place glass around every card.
- Use concentric radii and one restrained shadow level.
- Use Mist Sea for chrome tint. Cover colour affects only the full player
  background.
- Accent is limited to selection, playback, focus, and progress.
- No glow, neon edges, animated gradients, decorative refraction, or iridescent
  overlays.

## Component behaviour

### Top region

Ordinary page titles remain in the content layer. Back, settings, overflow, and
other persistent top actions may sit in a compact glass navigation surface.
Scrolling may change its separation but cannot shrink primary text.

### Search and task controls

Search fields, filters, segmented controls, selectors, and compact task actions
use `glassControl`. Search result rows retain the existing mobile item layout:

`title / artist / quality → favourite → more`

### Tab bar and mini player

- Keep five destinations: 首页, 搜索, 我的音乐, 下载, 更多.
- Render the tab bar as a safe-area-aware floating glass surface inset from the
  viewport edges.
- Attach the mini player immediately above it as a separate, coordinated
  `glassNav` surface.
- Preserve mini-player content order: artwork, title/artist, play/pause, next.
- Downward scrolling may minimize the tab bar and move the mini player into a
  compact inline relationship.
- The compact transition cannot alter playback state or hide access to the
  current track.
- The full player hides both surfaces and restores them on exit.

### Lists and content cards

Album cards, recommendation rails, settings groups, and shared track items do
not become glass by default. Hierarchy continues to come from typography,
spacing, surface lightness, and dividers.

### Sheets and menus

Queue, context menus, selectors, and modal sheets use `glassSheet`. They need a
clear boundary, stable text contrast, and an opaque fallback. Destructive actions
retain confirmation or Undo behaviour defined by the main design system.

### Full-screen player

Keep the current-cover blurred background and theme veil. Artwork and lyrics
remain optically stable. Use glass for the top actions, transport island,
progress, and secondary utilities. `glassClear` is allowed only where the player
background remains rich enough to support it; otherwise use `glassControl`.

## Interaction and motion

- Minimum touch target: 44 px.
- Press feedback: 100–120 ms.
- State transition: 180 ms.
- Sheet or coordinated tab-bar transition: up to 280 ms.
- Animate opacity and transform only.
- Reduced motion uses opacity only and completes within 150 ms.
- Focus rings are immediate and never animated.

## Accessibility and fallbacks

- Validate final composited contrast, not token contrast in isolation.
- Body text requires 4.5:1; large text and control boundaries require 3:1.
- Selected, playing, loading, focus, and error states cannot rely on tint or
  transparency alone.
- Reduced transparency and increased contrast use `glassFallback` while keeping
  identical geometry.
- Unsupported blur or sustained rendering pressure also uses `glassFallback`.
- Text scaling and screen readers must not lose labels or reorder controls.

## Performance constraints

- Clip blur to visible rounded bounds.
- Do not use full-screen backdrop blur on ordinary pages.
- Avoid nested or overlapping blur regions where one shared surface is enough.
- The full-screen player may retain its existing decorative blurred cover layer.
- Verify scroll smoothness on representative low- and mid-range Android devices,
  not only iOS simulators.

## High-fidelity acceptance criteria

- Mobile home, search, and player artboards visibly share one material system.
- The bottom tab bar and mini player read as attached but separate surfaces.
- Search controls use glass while result item geometry remains unchanged.
- Player controls remain legible over at least one warm and one dark cover.
- Screens remain usable at 320, 375, 390, 414, and 768 px widths without
  horizontal overflow or two-line navigation labels.
- Light, dark, reduced-transparency, and increased-contrast states have defined
  rendering outcomes.

## Out of scope

- Desktop Liquid Glass conversion.
- Navigation, route, playback, or data-flow changes.
- Track-item restructuring.
- New mobile destinations.
- A theme picker UI.
- Native UIKit implementation or platform-exclusive visual branches.
