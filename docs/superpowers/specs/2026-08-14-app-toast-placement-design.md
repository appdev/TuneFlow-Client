# TuneFlow App Toast Placement

Date: 2026-08-14
Status: approved design

## Outcome

Move every transient message produced by `showAppMessage` from the lower-right
corner to a horizontally centered position in the upper-middle of the entire
TuneFlow application viewport. The behavior applies consistently to desktop
and mobile layouts.

## Scope

In scope:

- Success, informational, and destructive messages produced through the shared
  `showAppMessage` helper.
- Desktop and mobile application sizes.
- Global placement relative to the application viewport, independent of the
  triggering page, control, player, or navigation region.
- Focused widget tests for message content and viewport-relative placement.

Out of scope:

- Page-local notices, dialogs, sheets, tooltips, and other non-Sonner feedback.
- Changes to message copy, duration, queue behavior, destructive semantics, or
  background interaction.
- A redesign of the toast surface, typography, colors, or animation.
- Adding a new toast dependency.

## Design

Keep the existing `shadcn_ui` `ShadSonner` implementation. Configure its
placement once at the application feedback host so all existing and future
`showAppMessage` callers inherit the same behavior without page-level changes.

The toast stack is aligned horizontally to the center of the full application
viewport. Its vertical anchor uses an alignment near `Alignment(0, -0.45)`,
which places the leading toast at approximately 28% of the usable viewport
height: visibly above center while remaining clear of the window edge, mobile
status area, and typical top navigation.

Placement is based on the root application viewport. It must not be calculated
from the triggering widget, current content pane, desktop player bar, or mobile
bottom navigation. Existing Sonner responsive width constraints and safe
padding remain active.

## Behavior and data flow

1. A feature calls `showAppMessage` with its existing title, optional
   description, and destructive flag.
2. The helper builds the existing primary or destructive `ShadToast`.
3. The root `ShadSonner` displays the toast stack at the shared upper-middle
   alignment.
4. Sonner continues to manage timing, stacking, dismissal, animation, and
   pointer behavior.

No business feature gains positioning knowledge, and no call-site API changes
are required.

## Third-party assessment

`toastification` supports arbitrary alignment and cross-platform overlays, but
would duplicate the existing Sonner host and require theme and test migration.
`fluttertoast` offers Android-like gravity, but its native and context-based
paths differ across platforms and provide less consistent desktop styling.
Because the installed Sonner already exposes global alignment and stacking,
adding either dependency would increase integration cost without improving the
requested behavior.

## Verification

Focused widget tests should prove:

1. A title-only confirmation remains visible with unchanged copy.
2. A title and description remain visible with unchanged copy.
3. A toast is horizontally centered relative to the root viewport.
4. Its center is above the viewport midpoint and near the approved
   upper-middle anchor at both a representative desktop size and a
   representative mobile size.
5. Existing destructive message construction remains supported.

Tests should use a tolerance for rendered coordinates so font metrics and
minor package layout changes do not create brittle pixel-exact assertions.

## Acceptance criteria

- Every `showAppMessage` toast uses the same application-relative
  upper-middle placement on desktop and mobile.
- The toast is horizontally centered and does not appear in the lower-right
  corner.
- Existing message content, visual semantics, duration, stacking, dismissal,
  and background interaction remain unchanged.
- No third-party toast package is added.
- Focused widget tests pass without overwriting unrelated worktree changes.
