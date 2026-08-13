<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4 -->

# Design — TuneFlow 音流

A locked, multi-page design system for the Flutter client. Every page redesign
must read this file first. Extend this system when the product grows; do not
invent page-local themes or raw colours.

## Hallmark record

- Genre: atmospheric, restrained and soft.
- Catalog origin: Bloom family, adapted for a persistent cross-platform app.
- Product theme ID: `mistSea`（雾海）.
- Pre-emit critique: Philosophy 5 · Hierarchy 4 · Execution 4 · Specificity 5 · Restraint 5 · Variety 4.

## Audience and primary job

TuneFlow serves Chinese-speaking users who connect to a self-hosted music
service and care about cross-platform consistency, music discovery, library
management, and uninterrupted playback.

The primary job is to find, organise, and continue playing music with as little
interface friction as possible.

## Design principles

1. Music content is the visual foreground. Interface chrome stays quiet.
2. Hierarchy comes from type scale, whitespace, density, and surface lightness;
   it does not come from drawing a border around everything.
3. One page gets one dominant focus. Secondary information forms calm groups.
4. The app shares one system, while page families retain different structures.
5. Existing data flow, routes, playback behaviour, and track-item information
   architecture are product contracts, not redesign material.

## Page families

- Discovery pages — **Ecosystem Index**: home, playlist square, charts, and user
  playlists. One featured focus followed by clearly named content rails.
- Detail pages — **Catalogue**: online and local playlist details. The header may
  change; the shared track item remains structurally unchanged.
- Task pages — **Workbench**: search, downloads, sources, settings, and service
  connection. Controls stay close to the object they affect.
- Player — **Split Studio / immersive**: clear artwork, lyrics, and controls over
  a full-canvas blurred background derived from the current cover.

## Navigation

- Desktop: a quiet full sidebar at desktop width and an icon rail at narrow
  width. Do not place a permanent queue beside unrelated pages.
- Mobile: five destinations in the existing bottom navigation, with the mini
  player immediately above it. On both iOS and Android, the bottom navigation
  is a floating Liquid Glass tab bar and the mini player is its attached
  accessory. They remain visually distinct surfaces with coordinated geometry.
- Player: hide desktop sidebar, mobile bottom navigation, and mini player. Show
  an explicit back action and retain platform/system back behaviour.

## Mobile material — Liquid Glass

All mobile platforms use the same restrained Liquid Glass visual language.
This is a TuneFlow-owned cross-platform material system inspired by iOS 26,
not a claim that Flutter controls inherit native UIKit rendering.

Liquid Glass is a functional layer for navigation and controls, never a filter
placed indiscriminately over music content. Mobile screens use three layers:

1. **Content layer** — page background, artwork, lyrics, track rows, and primary
   reading content remain optically stable and mostly opaque.
2. **Navigation layer** — top bars, the floating tab bar, and attached mini
   player float above scrolling content using the strongest glass separation.
3. **Control layer** — search, filters, segmented controls, floating actions,
   sheets, menus, and player controls use compact glass where separation is
   needed.

### Material roles

- `glassNav`: persistent navigation and the mini-player accessory.
- `glassControl`: search, filters, transport controls, and compact tool groups.
- `glassSheet`: modal sheets, menus, queue, and temporary expanded surfaces.
- `glassClear`: rare clear treatment over visually rich player backgrounds;
  never use it over dense lists or low-contrast artwork.
- `glassFallback`: opaque, theme-coloured replacement used when transparency is
  reduced, contrast is increased, blur is unavailable, or performance degrades.

Every role is supplied by the active `AppThemeId` light/dark pair. Components
consume semantic glass roles and never hard-code blur, opacity, borders, tints,
or shadows locally. A future theme must provide all glass roles.

### Composition rules

- Glass floats above content; content may scroll underneath it.
- Use one glass surface per functional group. Do not nest glass cards.
- Album cards and track items are content, not glass. Their existing structure
  and row geometry remain unchanged.
- The page background is not blurred. Only bounded functional surfaces blur the
  content behind them.
- Maintain concentric corner geometry between a surface and its internal
  controls. Persistent mobile glass uses the existing radius scale, with the
  tab bar and compact filters allowed to use the pill radius.
- Use a hairline highlight and one restrained shadow. Avoid glow, neon edges,
  iridescence, animated gradients, and decorative refraction.
- Mist Sea supplies the glass tint. Album-cover colour may influence only the
  immersive player background, never global navigation chrome.
- Accent remains limited to selection, playback state, focus, and progress.

### Mobile navigation behaviour

- Keep the existing five destinations and labels.
- The floating tab bar respects the device safe area and stays inset from the
  viewport edges.
- The mini player is an attached accessory immediately above the tab bar. It
  keeps artwork, title, artist, play/pause, and next in their current order.
- During downward content scrolling, the tab bar may minimize and the mini
  player may move into a compact inline relationship. The current track remains
  reachable; the transition cannot change playback state.
- Opening the full player hides both surfaces. Returning restores their prior
  visibility and scroll-related state.

### Mobile component application

- Home: glass top actions, attached mini player, and floating tab bar. Feature
  artwork and recommendation rails remain content surfaces.
- Search: glass search field and filters; result rows remain unchanged content.
- Discovery, charts, playlists, downloads, and library: glass navigation and
  task controls; shared track rows remain opaque and structurally invariant.
- Settings and service connection: grouped content remains calm and readable;
  only navigation, toggles, selectors, menus, and sheets receive glass roles.
- Player: blurred current-cover background, stable artwork and lyrics, plus
  glass top actions, transport island, progress, and secondary controls.

### Cross-platform behaviour

- iOS and Android share the same material appearance and component geometry.
- Platform back gestures, system bars, safe areas, text scaling, haptics, and
  accessibility semantics retain their native behaviour.
- Do not branch visual styling on platform. Branch only where platform behaviour
  or system integration requires it.

### Accessibility and performance

- Body text contrast remains at least 4.5:1 after live compositing; control
  boundaries and large text remain at least 3:1.
- Reduced transparency, increased contrast, unsupported blur, or sustained
  rendering pressure switches glass roles to `glassFallback` without changing
  layout geometry.
- Blur regions must be clipped to their visible bounds. Avoid full-screen blur
  outside the immersive player, where the existing cover-background treatment
  is intentional.
- Reduced motion uses opacity-only transitions up to 150 ms. Standard glass
  movement uses opacity and transform only and follows the existing duration
  tokens.
- Focus, selected, playing, loading, and error states must remain distinguishable
  without relying on transparency or colour alone.

## Theme architecture

Theme style and brightness are separate axes:

- `ThemeMode`: system · light · dark.
- `AppThemeId`: a stable product-theme identifier. This release registers only
  `mistSea`; future themes register another complete light/dark pair.

Every theme must supply the complete semantic palette. Components consume
roles such as `background`, `surface`, `foreground`, `accent`, and `danger`;
they never branch on `mistSea` or use page-local raw colours.

The theme registry is the only place allowed to map a theme ID and brightness
to tokens and `ShadThemeData`. A future theme picker may persist `AppThemeId`
without changing any screen implementation. This release does not expose a
theme-family picker.

## Theme — Mist Sea / light

- `paper`: `oklch(96.5% 0.012 175)`
- `paper-2`: `oklch(93% 0.016 175)`
- `paper-3`: `oklch(89% 0.020 175)`
- `ink`: `oklch(18% 0.018 175)`
- `ink-2`: `oklch(31% 0.018 175)`
- `muted`: `oklch(49% 0.016 175)`
- `rule`: `oklch(84% 0.018 175)`
- `rule-2`: `oklch(70% 0.022 175)`
- `accent`: `oklch(48% 0.085 175)`
- `accent-ink`: `oklch(97% 0.010 175)`
- `focus`: `oklch(57% 0.120 175)`
- `success`: `oklch(52% 0.110 150)`
- `warning`: `oklch(62% 0.120 75)`
- `danger`: `oklch(56% 0.170 25)`

## Theme — Mist Sea / dark

- `paper`: `oklch(14% 0.014 175)`
- `paper-2`: `oklch(18% 0.016 175)`
- `paper-3`: `oklch(23% 0.018 175)`
- `ink`: `oklch(94% 0.010 175)`
- `ink-2`: `oklch(80% 0.012 175)`
- `muted`: `oklch(66% 0.014 175)`
- `rule`: `oklch(30% 0.018 175)`
- `rule-2`: `oklch(43% 0.022 175)`
- `accent`: `oklch(74% 0.085 175)`
- `accent-ink`: `oklch(15% 0.018 175)`
- `focus`: `oklch(80% 0.110 175)`
- `success`: `oklch(74% 0.100 150)`
- `warning`: `oklch(78% 0.110 75)`
- `danger`: `oklch(72% 0.150 25)`

The accent occupies at most 3–5% of a viewport. Album art may carry any colour;
UI chrome may not borrow arbitrary cover colours.

## Typography

- Display: Noto Serif SC, weight 600, upright. Page-level headings only.
- Body and controls: Noto Sans SC, weights 400 / 500 / 600.
- Data: IBM Plex Mono, weight 500. Durations, counters, bitrates, and connection
  diagnostics only.
- Never italicise a heading. Never synthesise a missing weight.

Responsive type tokens:

| Role | Desktop | Mobile | Notes |
| --- | ---: | ---: | --- |
| Home focus | 34 px | 28 px | Two lines maximum |
| Page title | 28 px | 24 px | Ordinary routes |
| Section title | 20 px | 18 px | One line where possible |
| Body / control | 15 px | 15 px | Minimum primary reading size |
| Track title | 14 px | 14 px | Preserves list density |
| Metadata | 12 px | 12 px | Artist, quality, source |
| Counter / duration | 12 px | 11 px | Tabular figures |

## Spacing and shape

- 4-point scale: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64.
- Mobile page inset: 16 px; 360 px layouts may reduce non-content chrome but not
  primary text or touch targets.
- Control radius: 8 px; compact surface: 12 px; card: 16 px; panel: 20 px;
  sheet: 24 px; pill: full radius.
- Use surface lightness before shadow. One restrained shadow level is enough.
- Avoid card-in-card structures and equal card grids where a rail or list works.

## Track-item invariant

The current item layout is locked across search, playlist details, charts, and
downloads.

Desktop order:

`index → artwork → title / artist / quality → favourite → album → duration → more`

Narrow desktop keeps the existing breakpoint-driven hiding of album and
duration. Mobile remains:

`title / artist / quality → favourite → more`

Mobile does not gain artwork. Existing tap/double-tap, context-menu, favourite,
and more-action behaviour remains. The redesign may change typography, spacing,
dividers, hover/focus/pressed/selected/playing/loading colours, but it must not
move fields or change the row geometry between states.

## Immersive player

- Background source: the current track's `raw['pic']` URL. The sharp and blurred
  layers share one `ImageProvider`, request-header configuration, Flutter image
  cache entry, and fallback path.
- Background treatment: cover fit, scale beyond bounds, large-radius blur,
  slight desaturation, then a theme-provided veil.
- Light veil: tinted paper with enough opacity for dark text.
- Dark veil: tinted ink with enough opacity for light text.
- Foreground: one sharp artwork instance, track metadata, lyrics, progress, and
  controls. The blurred image is decorative and excluded from semantics.
- Transition on track change: opacity crossfade only. No zoom, drift, parallax,
  or animated gradient.
- Missing or failed artwork: reuse the deterministic seed artwork for both
  sharp and blurred layers.
- Desktop: artwork and metadata left, lyrics right, controls anchored below.
- Mobile: cover / lyrics / queue remain swipeable views; lyrics are the primary
  reading surface. Navigation chrome remains hidden until exit.

## Interaction and motion

- Touch targets: 44 px minimum.
- Focus rings: immediate and clearly visible; never animated.
- Durations: press 100–120 ms; hover/state 180 ms; sheet/page transition up to
  280 ms. Reduced motion uses opacity only and lasts no more than 150 ms.
- Animate opacity and transform only. The lyric active-line transition may also
  change colour and weight without changing layout.
- Visible actions use silent success. Failures restore state and offer retry.
- Reversible destructive actions offer Undo; irreversible actions require a
  confirmation dialog.

## Loading, empty, and failure states

- Skeleton geometry matches final content to avoid reflow.
- A local failure stays in its surface with a specific message and retry action.
- Empty states explain what is absent and offer at most one primary action.
- Player errors do not erase available queue, metadata, or navigation.

## Accessibility

- Preserve semantic labels on artwork and icon-only controls.
- Meet at least 4.5:1 for body text and 3:1 for large text and control boundaries.
- Colour is never the only indicator for playback, success, warning, or error.
- Keyboard, screen-reader, system back, text scaling, and reduced-motion paths
  are first-class verification targets.

## Exports

The Flutter registry is authoritative for this repository. Portable web tokens
mirror it and must remain generated from the same values.

### CSS token mapping

```css
:root {
  --color-paper: oklch(96.5% 0.012 175);
  --color-paper-2: oklch(93% 0.016 175);
  --color-paper-3: oklch(89% 0.020 175);
  --color-ink: oklch(18% 0.018 175);
  --color-ink-2: oklch(31% 0.018 175);
  --color-muted: oklch(49% 0.016 175);
  --color-rule: oklch(84% 0.018 175);
  --color-rule-2: oklch(70% 0.022 175);
  --color-accent: oklch(48% 0.085 175);
  --color-accent-ink: oklch(97% 0.010 175);
  --color-focus: oklch(57% 0.120 175);
  --font-display: "Noto Serif SC", serif;
  --font-body: "Noto Sans SC", sans-serif;
  --font-outlier: "IBM Plex Mono", monospace;
  --space-xs: 0.25rem; --space-sm: 0.5rem; --space-md: 1rem;
  --space-lg: 1.5rem; --space-xl: 2rem; --space-2xl: 3rem;
  --radius-input: 8px; --radius-card: 16px; --radius-pill: 999px;
  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in: cubic-bezier(0.7, 0, 0.84, 0);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --dur-micro: 120ms; --dur-short: 180ms; --dur-long: 280ms;
}

.dark {
  --color-paper: oklch(14% 0.014 175);
  --color-paper-2: oklch(18% 0.016 175);
  --color-paper-3: oklch(23% 0.018 175);
  --color-ink: oklch(94% 0.010 175);
  --color-ink-2: oklch(80% 0.012 175);
  --color-muted: oklch(66% 0.014 175);
  --color-rule: oklch(30% 0.018 175);
  --color-rule-2: oklch(43% 0.022 175);
  --color-accent: oklch(74% 0.085 175);
  --color-accent-ink: oklch(15% 0.018 175);
  --color-focus: oklch(80% 0.110 175);
}
```

### Tailwind v4 mapping

Use the same colour values under `@theme` with `--color-*`, the same font values
under `--font-*`, and mirror spacing as `--spacing-*`. Do not maintain a second
palette by hand.

### DTCG mapping

Use the role names above under `color`, `font`, `space`, `radius`, and `duration`;
each entry carries `$type` and the exact OKLCH or dimension value. Generate this
from the Flutter theme registry when a token pipeline is introduced.

### shadcn/ui mapping

`paper → background`, `ink → foreground`, `paper-2 → card/popover`,
`accent → primary`, `accent-ink → primary-foreground`, `rule → border/input`,
and `focus → ring`. Use space-separated OKLCH triples.

## Shared and variable rules

Every page shares the theme family, type roles, spacing scale, button voice,
focus treatment, and track-item contract. Page families may vary structure,
content density, and whether artwork is a dominant surface. Only the player may
use current-cover imagery as a full-canvas background.
