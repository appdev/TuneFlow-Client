# TuneFlow Balanced Theme Colors Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TuneFlow's green-tinted light canvas and green-black dark canvas with the approved Neutral Paper / Soft Charcoal palette while preserving every existing layout, type, geometry, route, and interaction.

**Architecture:** Keep `AppThemeRegistry.mistSea` as the single theme family and change only its semantic `AppTokens` and `AppGlassStyle` color values. All screens continue consuming theme roles; visual gallery coverage is expanded so the same responsive surfaces render in both `ThemeMode.light` and `ThemeMode.dark`, while the cover-derived player background keeps its existing image layers and receives only the new semantic veil.

**Tech Stack:** Flutter/Dart, `shadcn_ui`, `flutter_test`, golden image tests, macOS Flutter runner.

## Global Constraints

- Light mode uses the approved sampled neutrals: `#F6F6F6`, `#FAFAFA`, `#EAEAEA`, `#252525`, `#494949`, `#626262`, and `#DDDDDD`.
- Dark mode uses the approved Soft Charcoal neutrals: `#171817`, `#202120`, `#2B2C2A`, `#ECEDEA`, `#C6C7C3`, `#A0A19D`, `#464743`, and `#30312F`.
- Mist Mint remains the only product accent: light `#14745F` / focus `#008B70`; dark `#69B9A2` / focus `#70D0B5`.
- Preserve layout, spacing, typography, font families, radii, blur sigma, saturation, navigation, routes, playback, queue, downloads, search, connection, and persistence behavior.
- Preserve cover-derived player image layers; change only `playerVeil` to `#CCF6F6F6` in light mode and `#D9171817` in dark mode.
- Components must continue using semantic roles; do not add screen-local brightness branches or raw page colors.
- Required reading text must meet 4.5:1 contrast; focus boundaries must meet 3:1 against their canvas.
- Preserve unrelated worktree changes in `lib/features/connection/connection_screen.dart`, `test/features/connection/connection_screen_test.dart`, `android/build/`, and the connection-branding documents.
- Do not stage, commit, push, publish, or release this work without a separate explicit user authorization.

---

### Task 1: Lock and implement the semantic light/dark palette

**Files:**
- Modify: `test/design/app_theme_test.dart`
- Modify: `lib/design/design_tokens.dart`

**Interfaces:**
- Consumes: `AppTokens.light`, `AppTokens.dark`, and `Color.computeLuminance()`.
- Produces: the approved semantic token values consumed by `buildLightTheme`, `buildDarkTheme`, Glass definitions, and every screen.

- [x] **Step 1: Add exact palette and contrast assertions**

Add this helper above `main()` in `test/design/app_theme_test.dart`:

```dart
double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
```

Add these tests inside `main()`:

```dart
test('Mist Sea exposes the approved Neutral Paper palette', () {
  expect(AppTokens.light.background, const Color(0xFFF6F6F6));
  expect(AppTokens.light.surface, const Color(0xFFFAFAFA));
  expect(AppTokens.light.surfaceWarm, const Color(0xFFEAEAEA));
  expect(AppTokens.light.foreground, const Color(0xFF252525));
  expect(AppTokens.light.foregroundSecondary, const Color(0xFF494949));
  expect(AppTokens.light.muted, const Color(0xFF626262));
  expect(AppTokens.light.border, const Color(0xFFDDDDDD));
  expect(AppTokens.light.borderSoft, const Color(0xFFEAEAEA));
  expect(AppTokens.light.accent, const Color(0xFF14745F));
  expect(AppTokens.light.accentForeground, const Color(0xFFF6F6F6));
  expect(AppTokens.light.focusRing, const Color(0xFF008B70));
  expect(AppTokens.light.success, const Color(0xFF2F7D4A));
  expect(AppTokens.light.warning, const Color(0xFF966000));
  expect(AppTokens.light.danger, const Color(0xFFB93B3B));
  expect(AppTokens.light.overlay, const Color(0x66252525));
  expect(AppTokens.light.playerVeil, const Color(0xCCF6F6F6));
});

test('Mist Sea exposes the approved Soft Charcoal palette', () {
  expect(AppTokens.dark.background, const Color(0xFF171817));
  expect(AppTokens.dark.surface, const Color(0xFF202120));
  expect(AppTokens.dark.surfaceWarm, const Color(0xFF2B2C2A));
  expect(AppTokens.dark.foreground, const Color(0xFFECEDEA));
  expect(AppTokens.dark.foregroundSecondary, const Color(0xFFC6C7C3));
  expect(AppTokens.dark.muted, const Color(0xFFA0A19D));
  expect(AppTokens.dark.border, const Color(0xFF464743));
  expect(AppTokens.dark.borderSoft, const Color(0xFF30312F));
  expect(AppTokens.dark.accent, const Color(0xFF69B9A2));
  expect(AppTokens.dark.accentForeground, const Color(0xFF14201B));
  expect(AppTokens.dark.focusRing, const Color(0xFF70D0B5));
  expect(AppTokens.dark.success, const Color(0xFF75B987));
  expect(AppTokens.dark.warning, const Color(0xFFD7A45A));
  expect(AppTokens.dark.danger, const Color(0xFFE87870));
  expect(AppTokens.dark.overlay, const Color(0xB3121312));
  expect(AppTokens.dark.playerVeil, const Color(0xD9171817));
});

test('theme text and focus roles meet their contrast contracts', () {
  for (final tokens in [AppTokens.light, AppTokens.dark]) {
    expect(_contrastRatio(tokens.foreground, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.foregroundSecondary, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.muted, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.accent, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.accentForeground, tokens.accent), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.focusRing, tokens.background), greaterThanOrEqualTo(3));
    expect(_contrastRatio(tokens.success, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.warning, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.danger, tokens.background), greaterThanOrEqualTo(4.5));
  }
});
```

- [x] **Step 2: Run the focused test and confirm it fails on the old green palette**

Run: `flutter test test/design/app_theme_test.dart`

Expected: the two exact palette tests fail because `AppTokens` still contains `#ECF6F3` and `#040B09` families; existing unrelated tests continue passing.

- [x] **Step 3: Replace the two `AppTokens` constants**

In `lib/design/design_tokens.dart`, replace only `AppTokens.light` and `AppTokens.dark` with:

```dart
static const light = AppTokens(
  background: Color(0xFFF6F6F6),
  surface: Color(0xFFFAFAFA),
  surfaceWarm: Color(0xFFEAEAEA),
  foreground: Color(0xFF252525),
  foregroundSecondary: Color(0xFF494949),
  muted: Color(0xFF626262),
  border: Color(0xFFDDDDDD),
  borderSoft: Color(0xFFEAEAEA),
  accent: Color(0xFF14745F),
  accentForeground: Color(0xFFF6F6F6),
  success: Color(0xFF2F7D4A),
  warning: Color(0xFF966000),
  danger: Color(0xFFB93B3B),
  focusRing: Color(0xFF008B70),
  overlay: Color(0x66252525),
  playerVeil: Color(0xCCF6F6F6),
);

static const dark = AppTokens(
  background: Color(0xFF171817),
  surface: Color(0xFF202120),
  surfaceWarm: Color(0xFF2B2C2A),
  foreground: Color(0xFFECEDEA),
  foregroundSecondary: Color(0xFFC6C7C3),
  muted: Color(0xFFA0A19D),
  border: Color(0xFF464743),
  borderSoft: Color(0xFF30312F),
  accent: Color(0xFF69B9A2),
  accentForeground: Color(0xFF14201B),
  success: Color(0xFF75B987),
  warning: Color(0xFFD7A45A),
  danger: Color(0xFFE87870),
  focusRing: Color(0xFF70D0B5),
  overlay: Color(0xB3121312),
  playerVeil: Color(0xD9171817),
);
```

- [x] **Step 4: Format and verify the semantic palette**

Run: `dart format lib/design/design_tokens.dart test/design/app_theme_test.dart && flutter test test/design/app_theme_test.dart`

Expected: formatting makes no semantic changes and every test in `app_theme_test.dart` passes.

---

### Task 2: Retune Liquid Glass without changing material geometry

**Files:**
- Modify: `test/design/app_glass_surface_test.dart`
- Modify: `lib/design/app_theme_definition.dart`

**Interfaces:**
- Consumes: `AppThemeRegistry.mistSea.light.glass` and `.dark.glass`, keyed by `AppGlassRole`.
- Produces: neutral Glass fills, borders, highlights, fallbacks, and shadows while keeping existing `blurSigma` and `saturation` values unchanged.

- [x] **Step 1: Add exact Glass color tests and geometry guardrails**

Add this test after `every Mist Sea variant defines every glass role`:

```dart
test('Mist Sea glass uses neutral paper and charcoal optics', () {
  final light = AppThemeRegistry.mistSea.light.glass;
  final dark = AppThemeRegistry.mistSea.dark.glass;

  expect(light[AppGlassRole.nav]!.fill, const Color(0xE6FAFAFA));
  expect(light[AppGlassRole.control]!.fill, const Color(0xD9EAEAEA));
  expect(light[AppGlassRole.sheet]!.fill, const Color(0xF2FAFAFA));
  expect(light[AppGlassRole.clear]!.fill, const Color(0xA6FAFAFA));
  expect(light[AppGlassRole.fallback]!.fill, const Color(0xFFFAFAFA));
  expect(light[AppGlassRole.fallback]!.border, const Color(0xFFDDDDDD));

  expect(dark[AppGlassRole.nav]!.fill, const Color(0xE6202120));
  expect(dark[AppGlassRole.control]!.fill, const Color(0xD92B2C2A));
  expect(dark[AppGlassRole.sheet]!.fill, const Color(0xF2202120));
  expect(dark[AppGlassRole.clear]!.fill, const Color(0xA6202120));
  expect(dark[AppGlassRole.fallback]!.fill, const Color(0xFF202120));
  expect(dark[AppGlassRole.fallback]!.border, const Color(0xFF464743));

  expect(light[AppGlassRole.nav]!.blurSigma, 24);
  expect(light[AppGlassRole.control]!.blurSigma, 18);
  expect(light[AppGlassRole.sheet]!.blurSigma, 30);
  expect(light[AppGlassRole.clear]!.blurSigma, 20);
  expect(dark[AppGlassRole.nav]!.blurSigma, 24);
  expect(dark[AppGlassRole.control]!.blurSigma, 18);
  expect(dark[AppGlassRole.sheet]!.blurSigma, 30);
  expect(dark[AppGlassRole.clear]!.blurSigma, 20);
});
```

- [x] **Step 2: Run the focused test and confirm the old green Glass values fail**

Run: `flutter test test/design/app_glass_surface_test.dart`

Expected: `Mist Sea glass uses neutral paper and charcoal optics` fails while the existing policy and geometry tests pass.

- [x] **Step 3: Replace only Glass colors and shadows**

Use these exact optical values in `lib/design/app_theme_definition.dart` while leaving each role's existing `blurSigma` and `saturation` unchanged:

```dart
const _lightGlassShadow = <BoxShadow>[
  BoxShadow(color: Color(0x18252525), blurRadius: 24, offset: Offset(0, 10)),
];
const _darkGlassShadow = <BoxShadow>[
  BoxShadow(color: Color(0x52000000), blurRadius: 28, offset: Offset(0, 12)),
];
```

Apply this color table:

| Variant/role | `fill` | `border` | `highlight` | `fallbackFill` |
| --- | --- | --- | --- | --- |
| light nav | `0xE6FAFAFA` | `0xB3DDDDDD` | `0xBFFFFFFF` | `0xFFFAFAFA` |
| light control | `0xD9EAEAEA` | `0x99DDDDDD` | `0xBFFFFFFF` | `0xFFEAEAEA` |
| light sheet | `0xF2FAFAFA` | `0xCCDDDDDD` | `0xE6FFFFFF` | `0xFFFAFAFA` |
| light clear | `0xA6FAFAFA` | `0xB3FFFFFF` | `0xD9FFFFFF` | `0xFFFAFAFA` |
| light fallback | `0xFFFAFAFA` | `0xFFDDDDDD` | `0x00FFFFFF` | `0xFFFAFAFA` |
| dark nav | `0xE6202120` | `0x99464743` | `0x4DECEDEA` | `0xFF202120` |
| dark control | `0xD92B2C2A` | `0x80464743` | `0x40ECEDEA` | `0xFF2B2C2A` |
| dark sheet | `0xF2202120` | `0xB3464743` | `0x4DECEDEA` | `0xFF202120` |
| dark clear | `0xA6202120` | `0x99464743` | `0x40ECEDEA` | `0xFF2B2C2A` |
| dark fallback | `0xFF202120` | `0xFF464743` | `0x00000000` | `0xFF202120` |

- [x] **Step 4: Format and verify Glass behavior**

Run: `dart format lib/design/app_theme_definition.dart test/design/app_glass_surface_test.dart && flutter test test/design/app_glass_surface_test.dart`

Expected: all Glass palette, blur policy, fallback, animation, and geometry tests pass.

---

### Task 3: Make the design contract match the executable palette

**Files:**
- Modify: `design.md:157-207`
- Modify: `design.md:312-351`

**Interfaces:**
- Consumes: the exact semantic values implemented in Tasks 1 and 2.
- Produces: a human-readable and CSS-exportable source of truth aligned with Flutter tokens.

- [x] **Step 1: Replace the light/dark theme records**

Replace the old green OKLCH role lists with the approved sRGB role tables from `docs/superpowers/specs/2026-08-13-tuneflow-balanced-theme-colors-design.md`, including the Neutral Paper and Soft Charcoal rationales, contrast rules, and Mist Mint usage limit.

- [x] **Step 2: Replace the CSS export block with exact values**

Use these mappings in the light and dark export examples:

```css
--color-paper: #f6f6f6;
--color-paper-2: #fafafa;
--color-paper-3: #eaeaea;
--color-ink: #252525;
--color-ink-2: #494949;
--color-muted: #626262;
--color-rule: #dddddd;
--color-rule-2: #eaeaea;
--color-accent: #14745f;
--color-accent-ink: #f6f6f6;
--color-focus: #008b70;
```

```css
--color-paper: #171817;
--color-paper-2: #202120;
--color-paper-3: #2b2c2a;
--color-ink: #ecedea;
--color-ink-2: #c6c7c3;
--color-muted: #a0a19d;
--color-rule: #464743;
--color-rule-2: #30312f;
--color-accent: #69b9a2;
--color-accent-ink: #14201b;
--color-focus: #70d0b5;
```

- [x] **Step 3: Read back the contract and scan for obsolete palette values**

Run:

```bash
rg -n "ECF6F3|DEECE7|040B09|0A1411|oklch\(48% 0\.085 175\)|oklch\(74% 0\.085 175\)" design.md lib/design test/design
```

Expected: no obsolete palette hits in the modified design/token files; any hit elsewhere must be inspected and changed only if it is a theme definition rather than fixture/content data.

---

### Task 4: Render the full responsive gallery in both theme modes

**Files:**
- Modify: `test/visual/full_ui_gallery_test.dart`
- Modify: `test/visual/high_fidelity_gallery_test.dart`
- Modify: `test/visual/goldens/*.png`
- Modify: `test/visual/full_goldens/*.png`

**Interfaces:**
- Consumes: both gallery harnesses, `_capture`, `_captureSearchHistory`, `_capturePlatformFrame`, existing page fixtures, and both `ThemeMode` values.
- Produces: unchanged dark golden names plus light counterparts for every existing high-fidelity, desktop, mobile, search-history, and platform-frame fixture.

- [x] **Step 1: Parameterize the full-gallery harness and golden names**

Add `required ThemeMode themeMode` to `_shellHarness`, `_capture`, `_captureSearchHistory`, and `_capturePlatformFrame`, and pass it through to `ShadApp.custom`. Add this helper:

```dart
String _goldenPath(String stem, ThemeMode themeMode) =>
    themeMode == ThemeMode.dark
    ? 'full_goldens/$stem.png'
    : 'full_goldens/$stem-light.png';
```

Wrap each existing test matrix in:

```dart
for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
  // Existing viewport/page/platform loops.
}
```

Include `themeMode.name` in test descriptions. Preserve all existing dark filenames by passing the old stem to `_goldenPath`; append `-light` only for light mode.

Wrap the seven high-fidelity scenarios in the same two-mode loop, pass
`themeMode` to `shellHarness`, and use `${themeMode.name}` in their golden
filenames so the pre-existing dark files and light search files remain stable
while their missing counterparts are added.

- [x] **Step 2: Run the full gallery without updating baselines**

Run: `flutter test test/visual/full_ui_gallery_test.dart`

Expected: dark cases fail only because the approved palette changes pixels; light cases additionally report missing `-light.png` baselines. There must be no overflow, exception, missing widget, or fixture failure.

- [x] **Step 3: Generate affected high-fidelity and full-gallery baselines**

Run:

```bash
flutter test --update-goldens test/visual/high_fidelity_gallery_test.dart
flutter test --update-goldens test/visual/full_ui_gallery_test.dart
```

Expected: both commands pass and update color-composited PNGs while preserving their dimensions.

- [x] **Step 4: Review representative rendered images before accepting them**

Inspect at minimum:

- `test/visual/full_goldens/desktop-home-1440x960.png`
- `test/visual/full_goldens/desktop-home-1440x960-light.png`
- `test/visual/full_goldens/desktop-player-1024x768.png`
- `test/visual/full_goldens/desktop-player-1024x768-light.png`
- `test/visual/full_goldens/mobile-search-390x844.png`
- `test/visual/full_goldens/mobile-search-390x844-light.png`
- `test/visual/full_goldens/mobile-player-360x800.png`
- `test/visual/full_goldens/mobile-player-360x800-light.png`

Accept only if dark canvases read as charcoal, light canvases read as neutral paper, artwork remains dominant, player controls remain centered, and no spacing/type/geometry shift is visible.

- [x] **Step 5: Re-run golden suites against the frozen baselines**

Run:

```bash
flutter test test/visual/high_fidelity_gallery_test.dart
flutter test test/visual/full_ui_gallery_test.dart
```

Expected: both suites pass without `--update-goldens`.

---

### Task 5: Verify affected behavior and macOS runtime presentation

**Files:**
- Verify: `lib/design/design_tokens.dart`
- Verify: `lib/design/app_theme_definition.dart`
- Verify: `design.md`
- Verify: `test/design/app_theme_test.dart`
- Verify: `test/design/app_glass_surface_test.dart`
- Verify: `test/visual/high_fidelity_gallery_test.dart`
- Verify: `test/visual/full_ui_gallery_test.dart`

**Interfaces:**
- Consumes: the frozen implementation and generated baselines.
- Produces: analysis, test, build, runtime, diff, and worktree evidence sufficient for completion review.

- [x] **Step 1: Run focused nonvisual regression tests**

Run:

```bash
flutter test test/design/app_theme_test.dart test/design/app_glass_surface_test.dart test/design/mobile_liquid_glass_accessibility_test.dart test/features/player/player_backdrop_test.dart test/features/player/player_screen_test.dart test/features/player/player_controller_test.dart
```

Expected: all theme, Glass, accessibility, player, and queue tests pass.

- [x] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: exit code 0 with no new analysis issues.

- [x] **Step 3: Build the macOS application**

Run: `flutter build macos --debug`

Expected: the debug macOS app builds successfully without changing version or release metadata.

- [x] **Step 4: Inspect the running macOS app at representative widths**

Launch the debug macOS app, use the existing saved Service connection when available, and inspect light and dark themes at approximately 1440 × 960 and 1024 × 768. Confirm the same navigation, player, queue, search, downloads, settings, and cover/lyrics surfaces remain usable; if the Service is unavailable, record that runtime content inspection is blocked and rely on deterministic fixture goldens rather than changing connection behavior.

- [x] **Step 5: Review the final diff and preserve unrelated work**

Run:

```bash
git diff --check
git status --short
git diff -- lib/design/design_tokens.dart lib/design/app_theme_definition.dart test/design/app_theme_test.dart test/design/app_glass_surface_test.dart test/visual/full_ui_gallery_test.dart design.md
```

Expected: no whitespace errors; production changes are limited to semantic/Glass colors; test harness changes only add light/dark coverage; unrelated connection and Android build paths remain untouched and unstaged.

- [x] **Step 6: Leave the completed work uncommitted for user review**

Do not run `git add`, `git commit`, `git push`, release, or publishing commands. Report changed paths, verification evidence, visual inspection results, and any residual runtime limitation.
