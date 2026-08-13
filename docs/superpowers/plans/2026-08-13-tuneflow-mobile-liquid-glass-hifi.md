# TuneFlow Mobile Liquid Glass High-Fidelity Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the existing Hallmark high-fidelity package so every mobile artboard uses one restrained, cross-platform Liquid Glass visual language while desktop artboards and locked mobile track-item geometry remain unchanged.

**Architecture:** Extend the existing Mist Sea token file with semantic glass roles, then apply those roles through shared mobile classes in the single static prototype. Navigation, task controls, and player controls receive bounded glass surfaces; artwork, lyrics, cards, and track rows remain stable content. Browser assertions and rendered screenshots prove responsive geometry, fallback behaviour, and desktop isolation.

**Tech Stack:** Static HTML5, CSS custom properties and `color-mix()`, `backdrop-filter` with opaque fallbacks, vanilla JavaScript, Hallmark v1.1.0, local HTTP preview, browser screenshot/evaluation tooling.

## Global Constraints

- Modify only the Hallmark prototype package and its documentation; do not modify Flutter production source.
- Apply the same Liquid Glass appearance to iOS and Android.
- Preserve mobile destinations exactly: 首页, 搜索, 我的音乐, 下载, 更多.
- Preserve mobile track-item order exactly: `title / artist / quality → favourite → more`; do not add artwork or alter row geometry.
- Keep desktop artboards visually and structurally unchanged.
- Use Mist Sea semantic tokens; do not introduce component-local raw colours or font declarations.
- Keep album cards, artwork, lyrics, track rows, and primary reading content out of glass surfaces.
- Minimum touch target is 44 px; primary mobile text is not reduced.
- Support light, dark, reduced-transparency, increased-contrast, unsupported-blur, and reduced-motion outcomes without geometry changes.
- Verify 320, 375, 390, 414, and 768 px viewport widths with no horizontal overflow or wrapped bottom-navigation labels.

---

## File Map

- Modify `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css`: own all light/dark glass tokens and fallback values.
- Modify `.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html`: own shared glass primitives, mobile component styling, bounded markup hooks, accessibility fallbacks, and artboard behaviour.
- Modify `.codex/ui-design/tuneflow-hallmark-hifi-20260813/README.md`: record the new material scope and exact verification evidence.
- Replace `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-home.png`: rendered mobile home evidence.
- Replace `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-search.png`: rendered mobile search evidence.
- Replace `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-player.png`: rendered mobile player evidence.

### Task 1: Add Semantic Glass Tokens

**Files:**
- Modify: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css`

**Interfaces:**
- Consumes: existing Mist Sea `--color-paper*`, `--color-rule*`, `--color-shadow`, radii, duration, and easing tokens.
- Produces: `--glass-nav-*`, `--glass-control-*`, `--glass-sheet-*`, `--glass-clear-*`, and `--glass-fallback-*` custom properties consumed by Task 2 and Task 3.

The design-role mapping is fixed: `glassNav` → `--glass-nav-*`,
`glassControl` → `--glass-control-*`, `glassSheet` → `--glass-sheet-*`,
`glassClear` → `--glass-clear-*`, and `glassFallback` →
`--glass-fallback-*`.

- [ ] **Step 1: Record the pre-change invariant**

Run:

```bash
rg -n -- '--glass-(nav|control|sheet|clear|fallback)' .codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css
```

Expected: no matches, proving the roles do not yet exist.

- [ ] **Step 2: Add complete light-theme glass roles to `:root`**

Add named values derived only from existing Mist Sea colours:

```css
--glass-nav-fill:color-mix(in oklch,var(--color-paper-2) 72%,transparent);
--glass-nav-border:color-mix(in oklch,var(--color-ink) 10%,transparent);
--glass-nav-highlight:color-mix(in oklch,var(--color-accent-ink) 66%,transparent);
--glass-nav-blur:24px;
--glass-nav-saturation:1.22;
--glass-control-fill:color-mix(in oklch,var(--color-paper-2) 64%,transparent);
--glass-control-border:color-mix(in oklch,var(--color-ink) 9%,transparent);
--glass-control-highlight:color-mix(in oklch,var(--color-accent-ink) 54%,transparent);
--glass-control-blur:18px;
--glass-control-saturation:1.16;
--glass-sheet-fill:color-mix(in oklch,var(--color-paper-2) 82%,transparent);
--glass-sheet-border:color-mix(in oklch,var(--color-ink) 12%,transparent);
--glass-sheet-highlight:color-mix(in oklch,var(--color-accent-ink) 62%,transparent);
--glass-sheet-blur:28px;
--glass-sheet-saturation:1.18;
--glass-clear-fill:color-mix(in oklch,var(--color-paper) 28%,transparent);
--glass-clear-border:color-mix(in oklch,var(--color-accent-ink) 30%,transparent);
--glass-clear-highlight:color-mix(in oklch,var(--color-accent-ink) 40%,transparent);
--glass-clear-blur:20px;
--glass-clear-saturation:1.24;
--glass-fallback-fill:var(--color-paper-2);
--glass-fallback-border:var(--color-rule-2);
--glass-shadow:0 12px 34px color-mix(in oklch,var(--color-shadow) 72%,transparent);
```

Keep the values inside the token block; no component selector may contain an OKLCH, hex, RGB, or font-family literal.

- [ ] **Step 3: Override every role inside `.dark`**

Use the dark Mist Sea surfaces as the source:

```css
.dark {
  --glass-nav-fill:color-mix(in oklch,var(--color-paper-2) 70%,transparent);
  --glass-nav-border:color-mix(in oklch,var(--color-ink) 16%,transparent);
  --glass-nav-highlight:color-mix(in oklch,var(--color-ink) 20%,transparent);
  --glass-control-fill:color-mix(in oklch,var(--color-paper-2) 58%,transparent);
  --glass-control-border:color-mix(in oklch,var(--color-ink) 14%,transparent);
  --glass-control-highlight:color-mix(in oklch,var(--color-ink) 16%,transparent);
  --glass-sheet-fill:color-mix(in oklch,var(--color-paper-2) 78%,transparent);
  --glass-sheet-border:color-mix(in oklch,var(--color-ink) 18%,transparent);
  --glass-sheet-highlight:color-mix(in oklch,var(--color-ink) 20%,transparent);
  --glass-clear-fill:color-mix(in oklch,var(--color-paper) 24%,transparent);
  --glass-clear-border:color-mix(in oklch,var(--color-ink) 22%,transparent);
  --glass-clear-highlight:color-mix(in oklch,var(--color-ink) 18%,transparent);
  --glass-fallback-fill:var(--color-paper-2);
  --glass-fallback-border:var(--color-rule-2);
}
```

- [ ] **Step 4: Verify role completeness and token purity**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path('.codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css').read_text()
roles = ('nav', 'control', 'sheet', 'clear', 'fallback')
missing = [role for role in roles if f'--glass-{role}-' not in text]
assert not missing, missing
for prop in ('fill', 'border'):
    for role in roles:
        assert f'--glass-{role}-{prop}' in text
print('glass roles complete')
PY
```

Expected: `glass roles complete`.

### Task 2: Build Shared Mobile Glass Navigation and Task Controls

**Files:**
- Modify: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html`

**Interfaces:**
- Consumes: all semantic glass tokens from Task 1 and existing mobile structure.
- Produces: `.glass-nav`, `.glass-control`, `.glass-sheet`, `.glass-clear`, `.mobile-dock`, `.mobile-mini`, and `.mobile-nav` visuals shared by mobile home and search.

- [ ] **Step 1: Add bounded glass primitives**

Add shared classes near the existing mobile styles:

```css
.glass-nav,.glass-control,.glass-sheet,.glass-clear{position:relative;isolation:isolate;border:var(--rule-thin) solid transparent;box-shadow:var(--glass-shadow);overflow:hidden}
.glass-nav{background:var(--glass-nav-fill);border-color:var(--glass-nav-border);backdrop-filter:blur(var(--glass-nav-blur)) saturate(var(--glass-nav-saturation))}
.glass-control{background:var(--glass-control-fill);border-color:var(--glass-control-border);backdrop-filter:blur(var(--glass-control-blur)) saturate(var(--glass-control-saturation))}
.glass-sheet{background:var(--glass-sheet-fill);border-color:var(--glass-sheet-border);backdrop-filter:blur(var(--glass-sheet-blur)) saturate(var(--glass-sheet-saturation))}
.glass-clear{background:var(--glass-clear-fill);border-color:var(--glass-clear-border);backdrop-filter:blur(var(--glass-clear-blur)) saturate(var(--glass-clear-saturation))}
.glass-nav::before,.glass-control::before,.glass-sheet::before,.glass-clear::before{content:"";position:absolute;z-index:-1;inset:0;border-radius:inherit;pointer-events:none}
.glass-nav::before{box-shadow:inset 0 1px var(--glass-nav-highlight)}
.glass-control::before{box-shadow:inset 0 1px var(--glass-control-highlight)}
.glass-sheet::before{box-shadow:inset 0 1px var(--glass-sheet-highlight)}
.glass-clear::before{box-shadow:inset 0 1px var(--glass-clear-highlight)}
```

Do not apply these classes to `.mobile-focus`, `.album-card`, `.mobile-track`, `.cover`, or lyric elements.

- [ ] **Step 2: Replace the full-width footer plane with one attached dock**

Wrap each mobile home/search mini player and nav in exactly one `.mobile-dock`:

```html
<div class="mobile-dock">
  <div class="mobile-mini glass-nav">…existing mini-player children in the same order…</div>
  <nav class="mobile-nav glass-nav">…the same five buttons and labels…</nav>
</div>
```

Style it as two coordinated but separate surfaces:

```css
.mobile-dock{position:absolute;z-index:6;left:var(--space-3);right:var(--space-3);bottom:max(var(--space-2),env(safe-area-inset-bottom));display:grid;gap:var(--space-2);pointer-events:none}
.mobile-dock>*{pointer-events:auto}
.mobile-mini{position:relative;left:auto;right:auto;bottom:auto;height:60px;border-radius:var(--radius-panel)}
.mobile-nav{position:relative;left:auto;right:auto;bottom:auto;height:64px;padding:var(--space-1);border-radius:var(--radius-pill)}
.mobile-nav button.active{background:color-mix(in oklch,var(--color-accent) 12%,transparent);color:var(--color-accent);font-weight:600}
```

Adjust `.mobile-shell` and `.mobile-scroll` bottom padding so the last visible content cannot be obscured by the 132 px dock plus the safe area.

- [ ] **Step 3: Apply glass to navigation actions and search controls**

Add `glass-control` only to bounded functional controls:

```html
<button class="icon-btn glass-control" aria-label="设置">…</button>
<label class="search-box mobile-search-box glass-control">…</label>
<div class="mobile-filters glass-control">…existing four filter buttons…</div>
```

Remove the old opaque backgrounds and redundant borders from those mobile selectors. Keep the ordinary page title, result count, and result rows outside the glass.

- [ ] **Step 4: Preserve mobile information contracts**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import re
text = Path('.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html').read_text()
for screen in ('mobile-home', 'mobile-search'):
    end = 'id="mobile-search"' if screen == 'mobile-home' else 'id="mobile-player"'
    block = text.split(f'id="{screen}"', 1)[1].split(end, 1)[0]
    labels = re.findall(r'<nav class="mobile-nav glass-nav">(.*?)</nav>', block, re.S)
    assert len(labels) == 1
    assert re.findall(r'</svg>([^<]+)</button>', labels[0]) == ['首页','搜索','我的音乐','下载','更多']
search = text.split('id="mobile-search"', 1)[1].split('id="mobile-player"', 1)[0]
rows = re.findall(r'<div class="mobile-track[^>]*">(.*?)</div>\s*</div>', search, re.S)
assert 'cover ' not in search.split('<div class="mobile-track',1)[1]
assert search.count('class="mobile-track') == 5
print('navigation and track-item contracts preserved')
PY
```

Expected: `navigation and track-item contracts preserved`.

- [ ] **Step 5: Verify desktop isolation**

Run:

```bash
git diff -- .codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html | rg '^[+-].*(desktop|sidebar|mini-player|track-row)'
```

Expected: no desktop selector or desktop markup changes; `.mobile-*` changes are allowed.

### Task 3: Convert the Mobile Player Controls to Bounded Glass Islands

**Files:**
- Modify: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html`

**Interfaces:**
- Consumes: `.glass-nav`, `.glass-control`, and `.glass-clear` from Task 2; existing cover-derived background and mobile player structure.
- Produces: glass top actions, progress island, transport island, and utility island in `#mobile-player`, while leaving artwork and lyrics stable.

- [ ] **Step 1: Add semantic hooks without restructuring content**

Update only mobile-player control markup:

```html
<div class="player-bar mobile-player-bar">
  <button class="icon-btn glass-clear" aria-label="返回">…</button>
  <span class="player-mode glass-control">正在播放</span>
  <button class="icon-btn glass-clear" aria-label="更多">…</button>
</div>
…
<div class="mobile-player-controls">
  <div class="player-progress glass-control">…</div>
  <div class="transport-buttons glass-control">…</div>
  <div class="mobile-player-utils glass-clear">…</div>
</div>
```

Do not wrap `.mobile-player-art`, `.mobile-player-title`, `.mobile-lyrics`, or `.swipe-dots` in glass.

- [ ] **Step 2: Create quiet player glass islands**

Add mobile-only rules:

```css
.mobile-player-bar .player-mode{min-height:36px;display:flex;align-items:center;padding:0 var(--space-3);border-radius:var(--radius-pill)}
.mobile-player-controls .player-progress{min-height:44px;padding:0 var(--space-3);border-radius:var(--radius-pill)}
.mobile-player-controls .transport-buttons{min-height:68px;padding:var(--space-2);border-radius:var(--radius-pill)}
.mobile-player-utils{min-height:48px;padding:0 var(--space-2);border-radius:var(--radius-pill)}
```

Retain one accent play button. Do not tint the other transport buttons and do not add glow.

- [ ] **Step 3: Verify player separation and interaction labels**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path('.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html').read_text()
player = text.split('id="mobile-player"', 1)[1].split('<footer class="board-foot"', 1)[0]
for marker in ('mobile-player-bar', 'player-progress glass-control', 'transport-buttons glass-control', 'mobile-player-utils glass-clear'):
    assert marker in player, marker
for content in ('mobile-player-art', 'mobile-player-title', 'mobile-lyrics'):
    fragment = player.split(content, 1)[0][-80:]
    assert 'glass-' not in fragment, (content, fragment)
assert 'aria-label="返回"' in player
assert 'aria-label="更多"' in player
print('player glass is bounded to controls')
PY
```

Expected: `player glass is bounded to controls`.

### Task 4: Add Accessibility, Contrast, and Performance Fallbacks

**Files:**
- Modify: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html`

**Interfaces:**
- Consumes: all glass primitives and fallback tokens.
- Produces: identical-geometry opaque rendering for reduced transparency, high contrast, and unsupported blur; reduced-motion behaviour; a prototype inspection switch through `data-transparency`.

- [ ] **Step 1: Add opaque fallbacks without changing layout**

Append:

```css
@supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))){
  .glass-nav,.glass-control,.glass-sheet,.glass-clear{background:var(--glass-fallback-fill);border-color:var(--glass-fallback-border)}
}
[data-transparency="reduce"] .glass-nav,
[data-transparency="reduce"] .glass-control,
[data-transparency="reduce"] .glass-sheet,
[data-transparency="reduce"] .glass-clear{background:var(--glass-fallback-fill);border-color:var(--glass-fallback-border);backdrop-filter:none}
@media (prefers-contrast:more){
  .glass-nav,.glass-control,.glass-sheet,.glass-clear{background:var(--glass-fallback-fill);border-color:var(--color-ink-2);backdrop-filter:none}
}
@media (prefers-reduced-motion:reduce){
  .mobile-dock,.glass-nav,.glass-control,.glass-sheet,.glass-clear{transition-duration:0s!important;animation:none!important}
}
```

Do not add a visible settings control solely for prototype QA; the `data-transparency` attribute is the inspection hook.

- [ ] **Step 2: Add WebKit parity and clipped blur bounds**

For every `backdrop-filter` declaration, add the matching `-webkit-backdrop-filter`. Confirm every glass selector has `overflow:hidden` and a bounded radius inherited from the component.

- [ ] **Step 3: Verify fallback geometry in the browser**

With the local HTTP preview open, evaluate before and after setting the hook:

```javascript
const dock = document.querySelector('#mobile-home .mobile-dock');
const before = dock.getBoundingClientRect().toJSON();
document.querySelector('#mobile-home .mobile-shell').dataset.transparency = 'reduce';
const after = dock.getBoundingClientRect().toJSON();
({sameGeometry: before.x === after.x && before.y === after.y && before.width === after.width && before.height === after.height,
  background: getComputedStyle(document.querySelector('#mobile-home .mobile-nav')).backgroundColor});
```

Expected: `sameGeometry: true` and an opaque fallback background.

### Task 5: Verify Responsive Rendering and Interaction

**Files:**
- Modify if a failure is found: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html`
- Modify if a token failure is found: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css`

**Interfaces:**
- Consumes: completed high-fidelity prototype.
- Produces: browser evidence for all mobile artboards and target widths.

- [ ] **Step 1: Start or reuse the local preview**

Run:

```bash
python3 -m http.server 53841 --bind 127.0.0.1 --directory .codex/ui-design/tuneflow-hallmark-hifi-20260813
```

Expected: `Serving HTTP on 127.0.0.1 port 53841` or reuse the existing server at `http://127.0.0.1:53841/`.

- [ ] **Step 2: Check every target width and mobile artboard**

For each viewport width `320`, `375`, `390`, `414`, and `768`, activate `mobile-home`, `mobile-search`, and `mobile-player`, then evaluate:

```javascript
({
  overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
  wrappedLabels: [...document.querySelectorAll('.canvas.is-active .mobile-nav button')]
    .some(el => el.scrollHeight > el.clientHeight),
  minTouch: Math.min(...[...document.querySelectorAll('.canvas.is-active button')]
    .filter(el => getComputedStyle(el).display !== 'none')
    .map(el => Math.min(el.getBoundingClientRect().width, el.getBoundingClientRect().height))),
  dockVisible: !document.querySelector('.canvas.is-active .mobile-dock') ||
    document.querySelector('.canvas.is-active .mobile-dock').getBoundingClientRect().bottom <=
    document.querySelector('.canvas.is-active').getBoundingClientRect().bottom
})
```

Expected: `overflow: false`, `wrappedLabels: false`, `minTouch >= 44`, and `dockVisible: true` where the dock exists.

- [ ] **Step 3: Check interactions**

Click the mobile home/search active tab, favourite controls, and play/pause. Expected: active destination remains legible without colour alone, favourite state toggles, and play icon toggles without layout shift. Confirm `#mobile-player` has no `.mobile-dock`.

- [ ] **Step 4: Run Hallmark structural checks**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
html = Path('.codex/ui-design/tuneflow-hallmark-hifi-20260813/index.html').read_text()
css = Path('.codex/ui-design/tuneflow-hallmark-hifi-20260813/tokens.css').read_text()
assert 'html,body{min-height:100%;overflow-x:clip}' in html
assert 'font-style:normal' in html
assert 'fake browser' not in html.lower()
assert html.count('class="mobile-dock"') == 2
assert html.count('class="mobile-nav glass-nav"') == 2
assert 'mobile-track' in html and 'mobile-track cover' not in html
assert all(name in css for name in ('--glass-nav-fill','--glass-control-fill','--glass-sheet-fill','--glass-clear-fill','--glass-fallback-fill'))
print('Hallmark mobile glass checks passed')
PY
git diff --check -- .codex/ui-design/tuneflow-hallmark-hifi-20260813
```

Expected: `Hallmark mobile glass checks passed` and no `git diff --check` output.

### Task 6: Refresh Rendered Evidence and Documentation

**Files:**
- Modify: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/README.md`
- Replace: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-home.png`
- Replace: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-search.png`
- Replace: `.codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-player.png`

**Interfaces:**
- Consumes: final browser-verified artboards from Task 5.
- Produces: reviewable PNG evidence and an accurate package handoff.

- [ ] **Step 1: Capture final 390 × 844 artboards**

At viewport `390 × 844`, activate each artboard and capture the canvas only:

```text
mobile-home   → tuneflow-hallmark-mobile-home.png
mobile-search → tuneflow-hallmark-mobile-search.png
mobile-player → tuneflow-hallmark-mobile-player.png
```

The screenshot must include the full canvas, with no browser chrome or review switcher.

- [ ] **Step 2: Visually inspect all three screenshots**

Confirm:

- Home: top action, attached mini player, and floating tab bar share one material family; recommendation cards remain stable content.
- Search: search and filters are glass; every result row stays structurally unchanged and readable behind the dock.
- Player: artwork and lyrics remain clear; top, progress, transport, and utility controls are bounded glass islands with one accent play control.
- No glass nesting, glow, neon edges, decorative refraction, clipped labels, overlap, or accidental desktop changes.

- [ ] **Step 3: Update README with exact outcomes**

Replace the mobile description and verification bullets with:

```markdown
- Mobile home, search, and player use shared Mist Sea Liquid Glass roles on iOS and Android.
- Glass is bounded to navigation and controls; artwork, cards, lyrics, and track items remain content surfaces.
- Bottom navigation and mini player are attached but separate floating surfaces.
- Opaque fallback preserves geometry for reduced transparency, increased contrast, and unsupported blur.
- Browser widths checked: 320, 375, 390, 414, and 768 px.
```

Keep the existing statement that Flutter source was not modified.

- [ ] **Step 4: Run the final frozen-tree verification**

Run:

```bash
git diff --check -- design.md \
  docs/superpowers/specs/2026-08-13-tuneflow-mobile-liquid-glass-design.md \
  docs/superpowers/plans/2026-08-13-tuneflow-mobile-liquid-glass-hifi.md \
  .codex/ui-design/tuneflow-hallmark-hifi-20260813
test -s .codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-home.png
test -s .codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-search.png
test -s .codex/ui-design/tuneflow-hallmark-hifi-20260813/tuneflow-hallmark-mobile-player.png
```

Expected: all commands exit `0` with no whitespace errors.

## Completion Evidence

- Token completeness output.
- Navigation and track-item invariant output.
- Player control-boundary output.
- Browser width matrix for 320/375/390/414/768 px.
- Fallback geometry assertion.
- Hallmark structural-check output.
- Three visually inspected mobile screenshots.
- Final `git diff --check` and non-empty evidence-file checks.
