# Search Field Alignment and Clear Action Design

## Context

The search field uses a 52 px glass container on mobile, while `ShadInput`
keeps its default 8 px vertical padding and intrinsic content height. The outer
surface grows to 52 px, but the internal row remains top-positioned, so the
search glyph, placeholder, and entered text appear vertically high.

The shared `AppTextField` already exposes leading and trailing slots, but it
does not expose the input padding needed to make a fixed-height field's internal
row fill and center predictably.

## Goals

- Vertically center the mobile search glyph, placeholder, entered text, and
  trailing action inside the existing 52 px field.
- Provide a one-tap clear action on every platform when the query is non-empty.
- Clear the visible query and search results while retaining input focus and the
  software keyboard.
- Preserve the current search-history behavior and desktop shortcut hint.

## Non-goals

- Redesigning search filters, results, history contents, or search submission.
- Changing the mobile field height or restructuring the desktop search layout.
- Adding another icon library or changing unrelated text fields.

## Approved Approach

Extend `AppTextField` with an optional padding parameter that is forwarded to
`ShadInput`. The search screen will use that shared capability to define a
fixed, vertically centered internal layout rather than overlaying controls or
replacing the shared field with a raw Flutter text field.

For the 52 px mobile field, the leading search-glyph region and the trailing
clear-action region will use a 44 px height with 4 px vertical field padding.
This fills the field exactly and lets the input row's existing centered cross
axis alignment center the glyph and text.

The desktop field's content is currently 38 px high. `ShadInput` consumes 1 px
at each edge for decoration, so containing the required 44 x 44 px clear target
requires a 46 px outer field. It will use 44 px leading and trailing regions
with no vertical field padding. This is the only desktop geometry change.

## Clear-action Behavior

- The clear action is available on mobile and desktop only when the current
  query is non-empty.
- It uses the ordinary Lucide icon family and exposes the Chinese semantic
  label and tooltip `清除搜索`.
- Its interactive target is at least 44 x 44 px.
- On desktop, the clear action replaces the `⌘ K` hint while text is present;
  the hint returns after clearing.
- Activating it clears the `TextEditingController`, resets the search state to
  an empty query/results state, and requests focus for the existing search
  `FocusNode` so the user can type immediately.
- On mobile, clearing may reveal the existing search-history portal when saved
  history exists. This is existing behavior and should not shift filters or
  result layout.

## State and Data Flow

The existing query controller listener already rebuilds the search screen when
text changes. The trailing widget can therefore be derived from
`controller.text.isNotEmpty` without introducing duplicate state.

The clear callback is owned by `_SearchScreenState`, where both the text input
and feature `SearchController` are available. `_SearchBar` receives the callback
and renders the platform-independent clear action. The callback clears the text,
resets the feature search state with an empty query, then restores focus. On
Android it also reissues `TextInput.show` after the tap frame so a late platform
hide cannot close the keyboard while Flutter still reports the field focused.

## Accessibility and Visual Rules

- Use `LucideIcons.x` (or the closest existing Lucide clear glyph).
- Keep a minimum 44 px tap/click target.
- Provide both tooltip and semantic meaning in Chinese.
- Do not add a bespoke icon, Material icon, or Cupertino glyph.
- Preserve the current glass surface, radius, and colors. Preserve the 52 px
  mobile height; use a 46 px desktop outer height so its decorated 44 px inner
  area meets the target-size rule.

## Verification

Add focused widget coverage for:

1. Mobile search content is centered within the 52 px field.
2. The desktop field is 46 px high, contains a 44 px action, and its search
   content remains centered.
3. The clear action is absent for an empty query.
4. The clear action appears after entering text on mobile and desktop.
5. Activating it clears the editable text and search result state.
6. Focus remains on the search input after clearing.
7. Desktop `⌘ K` is present only while the query is empty.
8. Existing mobile search-history positioning remains unchanged.

Run the focused search and shared-component widget suites, static analysis for
changed files, and Android-emulator visual acceptance at a mobile viewport.
