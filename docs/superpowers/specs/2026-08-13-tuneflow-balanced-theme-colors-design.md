<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 -->

# TuneFlow Balanced Theme Colors

Date: 2026-08-13
Status: approved for implementation

## Outcome

Retune the existing Mist Sea theme for comfortable long sessions without
changing TuneFlow's layout, typography, component geometry, navigation,
interaction, or information hierarchy.

The dark variant uses the selected **Soft Charcoal** canvas with **Mist Mint**
highlights. The light variant derives its neutral canvas and text colors from
the user-provided reference screenshot. Both variants retain one mint brand hue
and adjust only its lightness and chroma for contrast.

## Scope

In scope:

- Mist Sea light and dark semantic color tokens.
- Light and dark Liquid Glass fills, borders, highlights, fallbacks, and
  shadows.
- Player veil and overlay colors.
- Theme/token tests and affected visual golden baselines.
- The color sections of the root `design.md`.

Out of scope:

- Layout, spacing, type scale, fonts, radii, component ownership, or routes.
- Track-item structure and behavior.
- Playback, queue, download, search, connection, or persistence behavior.
- Adding a second user-selectable theme family.
- Borrowing the reference application's layout, assets, content, or typography.

No production file or component is deleted.

## Evidence and provenance

The light palette was sampled from the user-attached screenshot
`codex-clipboard-4eda7907-0d22-402a-b7ef-19305d0bdf3d.png` at its original
2636 × 1574 resolution.

Repeated neutral pixels and direct surface samples yielded:

- Main canvas: `#F6F6F6`.
- Elevated canvas/player: `#FAFAFA`.
- Compact control fill: `#E7E7E7`.
- Secondary surface: `#EAEAEA`.
- Divider/boundary: `#DDDDDD`.
- Primary text: `#252525`.
- Secondary text: `#494949`.
- Muted readable text: `#626262`.
- Very weak reference text: `#ACACAC`.
- Reference accent: `#01F269`.

Only the neutral background and text DNA is adopted. The sampled neon green is
not adopted because the user selected Mist Mint as TuneFlow's highlight color.
The very weak `#ACACAC` value may be used only for disabled or nonessential
decoration; it must not carry ordinary metadata or helper text.

## Design principles

1. Large dark areas are charcoal, not green-black or pure black.
2. Surface hierarchy is expressed by increasing lightness: canvas, surface,
   then raised surface.
3. Large light areas use the sampled neutral gray-white canvas rather than the
   current green-tinted paper.
4. Mist Mint occupies at most about 3% of a viewport and is reserved for active,
   playing, progress, focus, and selected states.
5. Album art remains the most chromatic content. Global chrome never borrows
   arbitrary cover colors.
6. Text contrast takes precedence over pixel matching when a sampled weak gray
   would fail accessibility.

## Semantic palette

Flutter token definitions use the following opaque sRGB values. Components
continue to consume semantic roles and must not add page-local raw colors.

### Mist Sea light — Neutral Paper

| Role | Value | Purpose |
| --- | --- | --- |
| `background` | `#F6F6F6` | Main page canvas, sampled directly |
| `surface` | `#FAFAFA` | Player, popover, and elevated reading surface |
| `surfaceWarm` | `#EAEAEA` | Selected/secondary surface and grouped controls |
| `foreground` | `#252525` | Primary text |
| `foregroundSecondary` | `#494949` | Body and secondary text |
| `muted` | `#626262` | Metadata and helper text; sampled and readable |
| `border` | `#DDDDDD` | Visible boundaries and dividers |
| `borderSoft` | `#EAEAEA` | Quiet separation not relied on as the only cue |
| `accent` | `#14745F` | Light-mode Mist Mint; text/fill contrast 5.26:1 |
| `accentForeground` | `#F6F6F6` | Text/icons on accent; contrast 5.26:1 |
| `focusRing` | `#008B70` | Strong keyboard/accessibility focus |
| `success` | `#2F7D4A` | Completed and connected states |
| `warning` | `#966000` | Recoverable attention states |
| `danger` | `#B93B3B` | Destructive and failed states |
| `overlay` | `#66252525` | Modal scrim based on sampled primary ink |
| `playerVeil` | `#CCF6F6F6` | Cover-derived player background veil |

The three status colors retain at least 4.68:1 contrast against the neutral
canvas. Danger, warning, and success must never be the only state signal.

### Mist Sea dark — Soft Charcoal

| Role | Value | Purpose |
| --- | --- | --- |
| `background` | `#171817` | Warm-neutral charcoal canvas |
| `surface` | `#202120` | Navigation and ordinary panels |
| `surfaceWarm` | `#2B2C2A` | Raised, selected, and temporary surfaces |
| `foreground` | `#ECEDEA` | Soft off-white primary text |
| `foregroundSecondary` | `#C6C7C3` | Body and secondary text |
| `muted` | `#A0A19D` | Metadata and helper text |
| `border` | `#464743` | Functional component boundaries |
| `borderSoft` | `#30312F` | Quiet dividers and surface separation |
| `accent` | `#69B9A2` | Selected Mist Mint highlight |
| `accentForeground` | `#14201B` | Text/icons on accent; contrast 7.24:1 |
| `focusRing` | `#70D0B5` | Strong focus without neon glow |
| `success` | `#75B987` | Completed and connected states |
| `warning` | `#D7A45A` | Recoverable attention states |
| `danger` | `#E87870` | Destructive and failed states |
| `overlay` | `#B3121312` | Modal scrim with charcoal phase |
| `playerVeil` | `#D9171817` | Charcoal veil over cover-derived backdrop |

Primary, secondary, muted, and accent contrast against the dark canvas are
15.15:1, 10.48:1, 6.85:1, and 7.68:1 respectively.

## Liquid Glass mapping

Glass remains a bounded functional material. Its structure and blur values do
not change; only color and optical weight change.

Light roles:

- Navigation and sheets bias toward `#FAFAFA` with enough opacity to keep text
  stable over artwork.
- Compact controls bias toward `#EAEAEA`.
- Borders use translucent white highlights plus the sampled `#DDDDDD` neutral
  boundary.
- Fallback surfaces are opaque semantic light surfaces.

Dark roles:

- Navigation and sheets derive from `#202120`, not the old green-black.
- Compact controls and clear player controls derive from `#2B2C2A`.
- Borders/highlights are neutral gray, never green edge glow.
- Shadows remain black modifiers but become softer because the charcoal canvas
  already supplies separation.
- Fallback surfaces are opaque semantic charcoal surfaces.

Reduced transparency and increased contrast retain the same layout geometry.

## Player treatment

The immersive player keeps the current cover-derived sharp and blurred image
layers. Light mode uses the sampled neutral paper veil; dark mode uses the new
charcoal veil. The artwork itself is not recolored. Playback controls remain
centered and Mist Mint marks progress, play state, focus, and the current queue
item.

## Interaction states

- Default: semantic canvas/surface with primary or secondary text.
- Hover: move one surface level lighter; do not increase accent footprint.
- Focus: use the dedicated focus ring at a minimum 3:1 boundary contrast.
- Active/pressed: retain geometry and use the raised surface plus a subtle
  luminance change.
- Selected/playing: Mist Mint plus an icon, indicator, weight, or shape cue.
- Disabled: weak reference gray is allowed only with disabled semantics and no
  required reading content.
- Error/success/loading: retain icon or progress cues; color alone is
  insufficient.

## Architecture and files

Expected production/design changes:

- `design.md` — replace the Mist Sea light/dark color records and document the
  neutral-paper/soft-charcoal rationale.
- `lib/design/design_tokens.dart` — update both `AppTokens` variants.
- `lib/design/app_theme_definition.dart` — retune light and dark Glass roles.

Expected verification changes:

- `test/design/app_theme_test.dart` and focused Glass/theme tests — assert the
  new semantic mappings and brightness separation.
- Affected files under `test/visual/goldens/` and
  `test/visual/full_goldens/` — update only after reviewing generated diffs.

No screen should branch on brightness or `AppThemeId` to apply local colors.
`AppThemeRegistry` remains the sole theme-family mapping layer.

## Verification

1. Run `flutter analyze`.
2. Run focused theme, Glass, player, and accessibility tests.
3. Render all existing high-fidelity and full-gallery visual tests in light and
   dark modes.
4. Review golden diffs for desktop 1440 × 960 and 1024 × 768, plus mobile
   390 × 844 and 360 × 800.
5. Confirm no layout, typography, or geometry pixels move except where color
   compositing changes anti-aliasing.
6. Verify body/helper contrast and focus visibility in both modes.
7. Build and inspect the macOS app at multiple window widths for final runtime
   evidence.

## Acceptance criteria

- Dark pages read as soft charcoal rather than green-black.
- Light pages match the reference's neutral `#F6F6F6` canvas and sampled text
  hierarchy without copying its layout.
- Mist Mint remains the only product accent and occupies roughly 3% or less of
  ordinary views.
- Album covers remain visually dominant in both modes.
- All text needed for reading meets at least 4.5:1 contrast; focus and functional
  boundaries meet at least 3:1 where they are the only boundary cue.
- All existing interaction and responsive behavior remains unchanged.
- Static analysis, focused tests, visual galleries, and macOS runtime inspection
  pass before completion is claimed.
