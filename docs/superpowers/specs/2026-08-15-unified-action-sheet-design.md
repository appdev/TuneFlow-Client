# TuneFlow Unified ActionSheet Design

## Status

Implemented design for a simple, reusable mobile ActionSheet, initially applied
to the full-screen player's current-track actions.

## Context

TuneFlow currently routes mobile bottom content through a generic
`showAppSheet(title, child)` API. The player uses that API to open a one-item
track action sheet for “添加到歌单”, while favorite and download actions are
rendered separately in the player controls. The resulting hierarchy is
inconsistent and the generic sheet produces a nested surface with excess empty
space.

The new design follows the iOS Action Sheet interaction model while preserving
TuneFlow's shared Mist Sea / Liquid Glass appearance on both iOS and Android.
It is a choice surface, not a general replacement for every bottom sheet.

## Goals

- Present one to four short choices related to the current context.
- Keep the full-screen player visually calm and avoid a permanent secondary
  action row.
- Make favorite, playlist, and download available from one predictable entry.
- Dismiss the ActionSheet before running an action or opening another sheet.
- Preserve identical geometry and appearance on iOS and Android.
- Reuse existing semantic colors, typography, glass policy, motion, and
  accessibility behavior.

## Non-goals

- Replacing the draggable playback queue.
- Replacing lyrics, playlist pickers, category filters, or other long and
  scrollable content.
- Changing playback, favorite, playlist, or download data flows.
- Introducing platform-specific icon families or different iOS/Android visual
  branches.

## Player experience

The top-right ellipsis remains the single entry labelled “更多操作”. Tapping it
opens the ActionSheet with:

1. Title: the current track title, falling back to the track ID.
2. Message: artist followed by the current quality label, separated by ` · `;
   omit empty segments.
3. “收藏歌曲” or “取消收藏”, derived from current favorite state.
4. “添加到歌单”.
5. “下载当前歌曲”.
6. A separately grouped “取消” action.

The direct favorite and download row is removed from the mobile full-player
control surface. Desktop and mini-player behavior is outside this change.

### Action behavior

- Favorite: dismiss, then call the existing favorite controller operation.
- Add to playlist: dismiss, load playlists, then open the playlist picker.
- Download: dismiss, then enqueue the current track at the player's selected
  quality through the existing current-track actions controller.
- Cancel, barrier tap, and system back: dismiss without side effects.
- Every action is single-line and the sheet does not scroll.
- Failed actions preserve the current track and use existing error messages.
- Successful download keeps the existing silent “已加入下载队列” feedback.

## Component structure

Introduce a reusable `AppActionSheet<T>` presentation with typed choices. The
public API accepts:

- `title`
- optional `message`
- one to four `AppBottomSheetAction<T>` values
- an optional destructive role
- `cancelLabel`, defaulting to “取消”

The presentation returns the selected value. Callers perform asynchronous work
only after the presentation future resolves. This guarantees that the first
sheet is closed before another modal opens.

Use `showCupertinoModalPopup` for the bottom-up route, barrier dismissal, and
ActionSheet-style modal semantics. Build the content from TuneFlow components
rather than raw `CupertinoActionSheet`, because the content must consume
`AppGlassRole.sheet`, `AppGlassPolicy`, Mist Sea tokens, and the existing
reduced-transparency fallback.

## Visual specification

### Layout

- Horizontal viewport inset: 10 px.
- Bottom inset: device safe area plus 10 px.
- Choice-group radius: 15 px.
- Cancel-group radius: 15 px.
- Gap between groups: 8 px.
- Action height: 56 px, exceeding the 44 px minimum target.
- Title and message are centered in a compact context header.
- Options contain text only: no leading icons, chevrons, close button, or drag
  handle.
- The cancel label is semibold; ordinary choices use normal control weight.
- Destructive choices use the semantic danger color.

### Liquid Glass

- The context and option rows form one bounded
  `AppGlassSurface(role: AppGlassRole.sheet)`.
- The cancel action forms a second bounded `glassSheet` surface because it is a
  separate functional group.
- Neither surface is nested inside another glass surface.
- Blur is clipped to each group's rounded bounds.
- Normal mode uses the active theme's `glassSheet` fill, border, blur, and
  shadow.
- Normal mode delegates refraction, edge lighting, and chromatic treatment to
  the exactly pinned `liquid_glass_widgets` renderer through
  `AppGlassSurface`; feature code never imports the package.
- Reduced transparency, increased contrast, unsupported blur, or degraded
  performance uses the existing opaque fallback without changing geometry.
- Light and dark modes use the same structure and spacing.

### Color and type

- Use existing Mist Sea semantic tokens only.
- Default option foreground uses the app's interactive semantic color while
  retaining accessible contrast.
- Title uses the body/control family with medium or semibold weight; this is a
  control surface, not a page heading.
- Message uses metadata typography and muted foreground.
- Do not introduce native iOS blue or page-local raw colors.

## Interaction states

Each action supports:

- default
- hover for pointer-capable devices
- immediate focus-visible treatment
- pressed
- disabled
- loading ownership at the caller after dismissal
- error feedback through the existing message center
- success feedback through existing silent messages

The popup transition uses the Cupertino modal route. Internal state feedback
uses existing duration and curve tokens. Reduced motion uses an opacity-only
transition no longer than 150 ms where the route permits customization.

## Accessibility

- Modal barrier is dismissible and represented in semantics.
- The sheet announces its title before its actions.
- Every action is a semantic button with an enabled state.
- Cancel is explicit even though barrier tap and system back are supported.
- Text scaling must not clip titles or action labels; labels remain short and
  single-line.
- Focus order follows visual order, with Cancel last.
- Color is not the only indicator for disabled or destructive state.

## Verification

- Widget test the typed result for each choice and `null` for cancel, barrier,
  and system-back dismissal.
- Verify the player displays favorite/unfavorite, playlist, and download
  choices with current title and quality.
- Verify the ActionSheet is gone before a playlist picker appears.
- Verify favorite and download operations cannot be triggered twice.
- Verify download uses the currently selected player quality and preserves
  playback on success or failure.
- Verify light, dark, reduced-transparency, high-contrast, and reduced-motion
  behavior.
- Verify 320, 375, 414, and 768 px widths with text scaling and no clipping.
- Add focused visual baselines for the mobile player ActionSheet in light and
  dark modes.

## Scope boundary for future adoption

The shared ActionSheet may later serve other short choice surfaces such as a
small provider selector or compact download-task actions. Adoption requires a
separate call-site review. Long lists, draggable workspaces, reading surfaces,
and grouped filters remain dedicated components.
