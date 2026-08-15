# Playlist Gallery Artwork Outline Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give gallery playlist artwork a consistent borderless 12 px silhouette without changing artwork elsewhere.

**Architecture:** Add an opt-in border visibility parameter to the shared `AppArtwork` fallback path, preserving the existing default for every current caller. The gallery `PlaylistCard` alone opts out of that border and uses `AppRadii.compactCard` for both artwork and interaction clipping.

**Tech Stack:** Flutter, Dart, `flutter_test`, Material `InkWell`, existing TuneFlow design tokens.

## Global Constraints

- Apply the visual change only to `PlaylistCardVariant.gallery`.
- Gallery artwork radius is exactly `AppRadii.compactCard` (12 px).
- Gallery fallback artwork has no visible border.
- Row playlist cards and non-playlist artwork retain existing behavior.
- Do not change dimensions, grid density, typography, colors, shadows, data, or navigation.
- Do not create a Git commit unless the user separately authorizes it.

---

### Task 1: Borderless Compact Gallery Artwork

**Files:**
- Modify: `lib/design/components/artwork.dart`
- Modify: `lib/design/components/playlist_card.dart`
- Test: `test/design/app_components_test.dart`

**Interfaces:**
- Consumes: `AppRadii.compactCard`, existing `PlaylistCardVariant.gallery`, and the keyed fallback `artwork-fallback-<seed>`.
- Produces: `AppArtwork.showFallbackBorder` (`bool`, default `true`), allowing a caller to suppress only the generated fallback's border.

- [ ] **Step 1: Write the failing gallery styling test**

Extend the existing `playlist without artwork keeps a consistent gallery frame` widget test. After pumping the gallery card, inspect the gallery widgets:

```dart
final artwork = tester.widget<AppArtwork>(find.byType(AppArtwork));
expect(artwork.borderRadius, AppRadii.compactCard);
expect(artwork.showFallbackBorder, isFalse);

final inkWell = tester.widget<InkWell>(find.byType(InkWell));
expect(
  inkWell.borderRadius,
  BorderRadius.circular(AppRadii.compactCard),
);

final fallback = tester.widget<DecoratedBox>(
  find.byKey(const Key('artwork-fallback-love')),
);
final decoration = fallback.decoration as BoxDecoration;
expect(decoration.border, isNull);
```

Retain the existing assertions proving the fallback and `我的收藏` text render.

- [ ] **Step 2: Run the focused test to verify the new contract fails**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name "playlist without artwork keeps a consistent gallery frame"
```

Expected: compilation fails because `AppArtwork.showFallbackBorder` does not exist, or the style assertions fail against the current 16 px radius/border.

- [ ] **Step 3: Add the opt-in fallback border API**

In `AppArtwork`, add the defaulted constructor parameter and field:

```dart
this.showFallbackBorder = true,
```

```dart
final bool showFallbackBorder;
```

Pass it into `_ArtworkFallback`:

```dart
_ArtworkFallback(
  seed: resolved.fallbackSeed,
  icon: icon,
  showBorder: showFallbackBorder,
)
```

Add `required this.showBorder` and `final bool showBorder;` to `_ArtworkFallback`. Make only its border conditional:

```dart
border: showBorder ? Border.all(color: tokens.border) : null,
```

The default `true` preserves every existing caller's appearance.

- [ ] **Step 4: Opt the gallery playlist card into the compact borderless style**

In the gallery branch of `PlaylistCard`, change the `InkWell` and `AppArtwork` arguments:

```dart
borderRadius: BorderRadius.circular(AppRadii.compactCard),
```

```dart
borderRadius: AppRadii.compactCard,
showFallbackBorder: false,
```

Do not alter the row branch.

- [ ] **Step 5: Format the changed Dart files**

Run:

```bash
dart format lib/design/components/artwork.dart lib/design/components/playlist_card.dart test/design/app_components_test.dart
```

Expected: formatter exits successfully and changes only formatting required by the edits.

- [ ] **Step 6: Run focused verification**

Run:

```bash
flutter test test/design/app_components_test.dart --plain-name "playlist without artwork keeps a consistent gallery frame"
```

Expected: PASS.

Then run the complete component test file:

```bash
flutter test test/design/app_components_test.dart
```

Expected: all tests PASS, demonstrating the shared `AppArtwork` default remains compatible with existing component behavior.

- [ ] **Step 7: Review the final diff without committing**

Run:

```bash
git diff --check
git diff -- lib/design/components/artwork.dart lib/design/components/playlist_card.dart test/design/app_components_test.dart
```

Expected: no whitespace errors; the diff contains only the opt-in fallback-border API, gallery radius/border selection, and focused test assertions. Leave all changes uncommitted unless the user authorizes a commit.
