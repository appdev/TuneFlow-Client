# Mobile Resin Vinyl Design

## Goal

Replace the mobile player's existing full-cover vinyl appearance with the
completed desktop translucent resin vinyl appearance while preserving the
mobile layout and rotation behavior.

## Scope

- Keep the mobile artwork page centered and retain its current responsive
  record diameter of 148–264 px.
- Reuse the desktop resin material, QQ-derived continuous texture, groove
  highlight, circular masks, optical lighting, and artwork-derived colors.
- Change the center artwork to the desktop proportion of approximately 60% of
  the record diameter. The artwork remains sharp, borderless, and opaque.
- Preserve the current mobile rotation state machine: rotate only while the
  artwork page is visible, playback is active, and processing is ready; pause
  at the current angle and resume from that angle. Reduced-motion policy still
  disables rotation.
- Keep mobile metadata, controls, page navigation, backdrop, and record sizing
  unchanged.

## Architecture

The resin vinyl implementation becomes a shared visual component rather than
being copied into the mobile widget. The existing desktop entry point keeps its
current API and keys. The shared implementation accepts the small set of keys
that differ between desktop and mobile so mobile tests and accessibility
semantics remain platform-specific.

`MobileVinylRecord` remains the mobile-facing wrapper. It receives the current
`ArtworkPalette` and delegates rendering and rotation to the shared resin
component using the existing mobile root, turn, artwork, and spindle keys. This
removes the legacy full-cover surface and procedural mobile groove painter.

The player screen selects the artwork palette for both layout classes and
passes the palette through `_MobilePlayer` and `_MobileNowPlaying` to
`MobileVinylRecord`. Desktop palette behavior remains unchanged.

## Data Flow

1. `PlayerScreen` resolves the current artwork source.
2. `ArtworkPaletteController` extracts or retrieves the current palette on
   mobile as it already does on desktop.
3. The palette is passed through the mobile player hierarchy.
4. `MobileVinylRecord` supplies the palette, artwork source, semantic label,
   and existing `rotating` boolean to the shared resin vinyl.
5. The shared component renders the same material stack on both platforms.

Missing or failed artwork continues through the existing `AppArtwork`
fallback and seeded palette behavior. No new network or persistence behavior is
introduced.

## Motion and Accessibility

- Rotation period remains 18 seconds.
- Pause/resume angle continuity remains unchanged.
- `MediaQuery.disableAnimations` and the glass policy continue to disable
  rotation.
- `accessibleNavigation` alone does not disable rotation.
- Existing mobile semantic label and structural keys remain available.

## Performance

The shared component retains its `RepaintBoundary` isolation. The resin
texture assets are already bundled and decoded through Flutter's image cache.
The mobile instance is smaller than the desktop instance, and no duplicate
material implementation or additional animation controller is introduced.

## Verification

- Focused mobile vinyl widget tests verify the 60% center artwork, resin asset
  layers, circular masks, semantic label, and original rotation behavior.
- Player screen tests verify that the extracted palette reaches the mobile
  vinyl without changing desktop behavior.
- Static analysis covers all changed production and test files.
- Launch the application on the existing Pixel 8 Android emulator and inspect
  blue, dark, and warm artwork in the real mobile player. Confirm centered
  sizing, opaque artwork, resin texture, palette response, page switching, and
  pause/resume rotation.

## Documentation

Update the immersive-player section of `design.md` so mobile explicitly reuses
the shared translucent resin material while retaining its own centered layout
and motion conditions.

## Non-goals

- No change to mobile record size, metadata layout, controls, backdrop, or
  swipe navigation.
- No change to playback state semantics or rotation timing.
- No second copy of the desktop painter or asset stack.
- No mobile-specific redesign of the approved resin effect.
