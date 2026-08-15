# Playlist Gallery Artwork Outline Design

## Goal

Make gallery playlist covers feel cleaner and visually consistent. Real artwork
and generated fallback artwork should share the same silhouette instead of the
fallback appearing as a separately bordered card.

## Scope

- Apply the change only to the gallery variant of `PlaylistCard`.
- Use a 12 px corner radius for gallery artwork.
- Remove the visible border from gallery fallback artwork.
- Match the gallery interaction clipping to the 12 px artwork radius.
- Leave row playlist cards and artwork used by search, player, downloads, and
  other screens unchanged.

## Component Design

`AppArtwork` will expose a narrowly scoped way for callers to suppress the
fallback border while preserving its current default behavior. Gallery
`PlaylistCard` will opt into the borderless fallback and pass
`AppRadii.compactCard` as its artwork radius. Its ink response will use the same
radius so pressed and hover states do not protrude beyond the intended shape.

Network artwork and fallback artwork keep the same square sizing and cropping.
Typography, spacing, grid sizing, record illustration, colors, and playlist
metadata do not change.

## Verification

- Add or update a widget test proving gallery artwork uses the compact radius
  and disables its fallback border.
- Keep coverage that a playlist without artwork still renders its fallback.
- Run the focused design component tests and formatting checks for changed Dart
  files.

## Non-goals

- No global artwork redesign.
- No changes to card dimensions, grid density, colors, or shadows.
- No changes to playlist data or navigation behavior.
