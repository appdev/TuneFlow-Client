# TuneFlow Unified Default Track Artwork

Date: 2026-08-14
Status: approved for implementation

## Outcome

Replace the current seed-derived multicolor artwork fallback for tracks with one
calm default-cover structure. Every coverless track uses the same centered
vinyl record and filled single-note symbol in both brightness modes:

- Light mode: a neutral sleeve, dark vinyl record, green center label, and
  filled single music note.
- Dark mode: the same geometry with the approved balanced adaptation: charcoal
  sleeve, near-black vinyl, Mist Mint center label, and dark filled music note.

The TuneFlow gradient logo, waveform, and `TUNEFLOW` wordmark are not used. The
filled note was selected over an outline note because it remains visually
substantial and recognizable in 40–44 px artwork.

## Scope

In scope:

- Missing, empty, or failed track artwork rendered through `AppArtwork`.
- Track artwork in lists, search results, queue, downloads, home, mini player,
  and full player.
- Light/dark fallback selection from the active theme brightness.
- Focused component tests and affected visual baselines.
- Neutral player-backdrop behavior when the current track has no real artwork.

Out of scope:

- Recoloring, filtering, or otherwise changing valid remote or cached artwork.
- Changing artwork URL normalization, caching, repair, or retry behavior.
- Generating per-track colors, initials, artist monograms, or seeded patterns.
- Using the full-color TuneFlow logo in the fallback.
- Changing cover dimensions, radii, layout, navigation, playback, or metadata.
- Redesigning playlist-specific fallback artwork beyond preserving its existing
  content-type contract.

## Visual design

### Light mode — record symbol

The fallback uses the current light semantic palette:

- Sleeve: `surfaceWarm` (`#EAEAEA`).
- Boundary: `border` (`#DDDDDD`).
- Record: `foreground` (`#252525`) with restrained concentric grooves produced
  through opacity, not new raw colors.
- Center label: `accent` (`#14745F`).
- Music symbol: `accentForeground` (`#F6F6F6`).

The record stays centered with enough sleeve visible around it to read as album
art rather than a standalone round icon. The music symbol is optically centered
and remains the only semantic mark.

### Dark mode — balanced record adaptation

The fallback uses the current dark semantic palette:

- Sleeve: `surface` (`#202120`).
- Boundary: `border` (`#464743`).
- Record: a near-black value derived from the dark foreground/background
  semantic palette, with quiet light grooves produced through opacity.
- Center label: `accent` (`#19D39B`).
- Filled music symbol: `accentForeground` (`#101713`).

The record radius, center-label size, note shape, and alignment match the light
version exactly. Only semantic colors and groove contrast change. This is the
approved A “balanced” adaptation; the higher-contrast and quieter alternatives
are not implemented.

### Size behavior

- 40–56 px: preserve the filled note and enough groove contrast to identify the
  record without introducing noise.
- 57 px and above: retain the same structure and restrained groove treatment;
  scale proportionally with the artwork.
- Border radius continues to come from the `AppArtwork` caller.
- No fallback animation, randomization, or per-track color variation is added.

## Component architecture

`AppArtwork` remains the shared boundary for real and fallback images. Its
existing source resolution and cache pipeline stay unchanged:

1. A valid URL continues through `CachedArtworkImage`.
2. A missing URL or a final network/cache decoding failure selects the fallback.
3. The fallback reads `AppTokens.of(context)` and active brightness.
4. The track seed remains available for identity, keys, and diagnostics, but no
   longer affects fallback color or geometry.

The fallback uses one record painter and one theme-aware private widget. Theme
brightness selects semantic colors only; it does not select different geometry
or marks. No screen contains its own fallback drawing or raw fallback colors.

`AppArtwork.icon` remains the content-type hook. Track callers use the default
filled single-note mark in both themes. Playlist callers that already pass
`listMusic` retain that semantic distinction; this feature must not silently
turn a playlist into a track.

## Player backdrop

When real artwork is available, the player keeps its existing enlarged, blurred
cover backdrop and theme veil. When the source has no real URL, the default
record graphic must not be enlarged and blurred behind the player. The
backdrop uses the normal theme canvas/veil instead, while the visible player
artwork still shows the default cover.

This prevents a giant blurred placeholder from competing with lyrics and
controls.

## States and accessibility

- Missing URL and unrecoverable image load/decode failure produce the same
  visual fallback.
- Loading behavior remains unchanged: the fallback continues to appear while
  cached artwork resolves.
- `showFallback: false` continues to render no fallback and is not overridden.
- Existing artwork semantics and labels remain unchanged.
- The fallback is decorative content inside the already-labeled image semantic
  boundary; internal shapes are excluded from semantics.
- The primary symbol must retain at least 3:1 contrast against its immediate
  background in both brightness modes.
- Theme switching updates the fallback without changing track identity,
  playback state, layout geometry, or cache state.

## Verification

Focused tests should prove:

1. Missing artwork renders the light record fallback under the light theme.
2. Missing artwork renders the same record-and-note structure with balanced
   dark colors under the dark theme.
3. Different track seeds produce the same fallback structure and semantic
   colors within one theme.
4. Theme switching changes the fallback design without changing its semantic
   label or dimensions.
5. Network and cached-image failures resolve to the same theme-specific
   fallback.
6. `showFallback: false` remains empty.
7. Playlist `icon` semantics remain distinct where currently requested in both
   themes.
8. The player backdrop does not render or blur placeholder artwork when its
   source URL is absent.

Visual verification should cover at least one 40–44 px list/mini-player use and
one large player use in each brightness mode. Golden changes must be reviewed
for affected screens only; unrelated layout or color movement is not accepted.

## Acceptance criteria

- Every coverless track looks identical to other coverless tracks within the
  same brightness mode.
- Light mode uses the approved record-and-music-symbol design.
- Dark mode uses the approved balanced record-and-filled-note adaptation.
- The full-color TuneFlow logo does not appear in either fallback.
- The waveform and `TUNEFLOW` wordmark do not appear in either fallback.
- Small artwork remains immediately recognizable without illegible detail.
- Valid real artwork and the media-cache pipeline are unchanged.
- The player does not create a blurred full-canvas backdrop from placeholder
  graphics.
- Focused component tests and reviewed visual evidence pass before completion
  is claimed.
