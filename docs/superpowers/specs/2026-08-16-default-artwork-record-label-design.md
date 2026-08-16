# Default Artwork Record Label Design

## Outcome

Replace the default-cover music note with a TuneFlow record-label treatment.
The center should read as a real printed vinyl label: straight condensed type,
restrained silver ink, subtle paper/ring texture, and a centered spindle hole.
It must not resemble a generic app icon or a chrome-effect badge.

## Reference findings

The approved direction is informed by real center-label conventions rather
than any single manufacturer identity:

- Blue Note uses bold, direct typographic blocks and strong two-colour print.
- ECM keeps its label name and information on straight baselines with strict
  hierarchy around the spindle.
- Deutsche Grammophon keeps its primary trademark intact while reserving
  circular type for peripheral legal copy.
- Atlantic uses condensed print, strong fields, and clear axis-aware placement.

TuneFlow adopts those shared principles without copying another label's logo,
colour blocking, decorative border, or proprietary lettering.

## Center-label composition

- Keep the existing green semantic accent circle and overall 24% label
  diameter.
- Set `TuneFlow` horizontally above the spindle hole, centered on a straight
  baseline. Do not curve, rotate, skew, or split the brand name.
- Use Barlow Condensed Bold as the wordmark face. Bundle the font locally under
  the SIL Open Font License; rendering must not depend on a network font.
- Render the wordmark with a low-contrast warm-silver gradient. The result
  should resemble metallic printing ink, not polished chrome.
- Add faint concentric printed rings inside the green label. Their contrast
  stays below the wordmark and the existing vinyl grooves.
- Add one short silver rule and three centered registration dots below the
  spindle. They are decorative marks, not invented catalog or playback data.
- Add a centered printed spindle hole matching the approved preview. When a
  player spindle widget is present, it covers the printed hole and must align
  with it rather than cut through the wordmark.

## Rendering boundary

- The TuneFlow label replaces only the default `LucideIcons.music2` fallback.
- Playlist-specific and caller-supplied fallback icons keep their current
  rendering path.
- Build the label from normal Flutter text/layout plus a small decorative
  painter for rings, rule, dots, and printed hole. Do not hand-draw a wordmark
  glyph path.
- Exclude the decorative internal text and marks from semantics. `AppArtwork`'s
  existing image label remains the only accessibility announcement.
- Preserve record geometry, outer grooves, theme palette, seed-independent
  pixels, borderless fallback behaviour, rotation, caching, and sizing.

## Small-size behaviour

- Use the full `TuneFlow` name at every size; do not substitute `TF`.
- At 44 px artwork size the wordmark is allowed to become a recognizable
  horizontal print texture rather than readable body text.
- The label must remain free of seams, clipping, unstable font fallback, and
  one-pixel artifacts at 44 px and 192 px.

## Border contract

- The default artwork surface is borderless in both light and dark themes.
  Do not add a stroke to `_ArtworkFallback`, `AppArtwork`, or an artwork-only
  wrapper around them.
- Remove the `showFallbackBorder` escape hatch and its explicit `false` call
  sites so feature code cannot re-enable an outer fallback border.
- Existing borders on unrelated parent cards, panels, list rows, and player
  spindle widgets remain outside this rule.
- Concentric print rings inside the green center label are artwork content, not
  a component border, and remain part of the approved design.

## Design-system update

Revise `design.md` so missing artwork uses a TuneFlow printed record label
instead of a filled music note. Remove the old prohibition on the TuneFlow
wordmark for this specific default-artwork context; retain the prohibition on
waveforms, generic music notes, and scaled application icons.

## Verification and visual output

- Update structural widget tests to assert the TuneFlow label branch and the
  absence of the previous filled-note painter.
- Assert that fallback decoration has no border in both light and dark themes.
- Verify playlist-specific and caller-supplied icons are unchanged.
- Run `test/design/artwork_test.dart`.
- Run and update `test/design/default_artwork_golden_test.dart` for 44 px and
  192 px artwork in light and dark themes.
- Run focused mobile and desktop player vinyl tests that cover spindle
  alignment and rotation composition.
- Export and return a final PNG rendered from the implemented Flutter widget.
  The already approved pre-implementation preview remains the design target;
  the final PNG is proof of the actual implementation.

## Scope

This change does not alter network artwork, non-default fallback icons,
playback controls, player animation, artwork cache behaviour, or the outer
vinyl composition.
