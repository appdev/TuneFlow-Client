# TuneFlow Product README Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the client repository's engineering-heavy README with a restrained, friendly product introduction that helps ordinary music users understand TuneFlow and find current client builds.

**Architecture:** Keep the public landing document intentionally small: one product hero, one desktop experience, three user-facing benefits, one mobile experience, a transparent download section, and a compact Service relationship note. Reuse three existing visual-golden screenshots as stable repository assets, and enforce the public-document contract with one focused Flutter test.

**Tech Stack:** Markdown, Flutter test, PNG assets, GitHub Actions links

## Global Constraints

- Keep the main README product-first; remove architecture diagrams, API routes, local startup commands, provider terminology, and test-command tutorials.
- Do not show or name third-party music-source platforms in README text or screenshots.
- Use only repository-relative image paths and public GitHub URLs.
- Do not invent releases, store availability, usage metrics, reviews, or compatibility promises.
- Describe GitHub Actions artifacts honestly: current builds are development builds, may require GitHub login, and iOS/macOS artifacts are unsigned.
- Preserve copyright and security/privacy boundaries.
- Do not change runtime client behavior or regenerate/delete golden images.
- Do not commit or push without separate authorization.

---

### Task 1: Freeze the public README contract with a failing regression test

**Files:**
- Modify: `test/branding/public_repository_links_test.dart`

- [x] Extend the existing public-document test to read `README.md` and the three curated screenshot files.
- [x] Add a tiny PNG IHDR helper using `dart:typed_data` so the test verifies:
  - desktop screenshot: 1440 × 960
  - mobile player screenshot: 390 × 844
  - mobile library screenshot: 390 × 844
- [x] Assert the README contains:
  - `TuneFlow · 音流`
  - the stable GitHub Actions workflow URL
  - the public client and Service repository URLs
  - all three repository-relative screenshot paths
- [x] Assert the README does not contain local absolute paths, private-LAN literals, Mermaid/API/test-command material, or third-party music-platform names.
- [x] Run the focused test and confirm it fails for the expected missing assets/product structure:

```bash
flutter test test/branding/public_repository_links_test.dart
```

Expected: FAIL because the current README is technical and the curated screenshot paths do not yet exist.

Suggested helper and contract shape:

```dart
import 'dart:typed_data';

({int width, int height}) pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16, Endian.big),
    height: data.getUint32(20, Endian.big),
  );
}
```

### Task 2: Add stable, provider-neutral product screenshots

**Files:**
- Copy: `test/visual/full_goldens/desktop-home-1440x960.png` → `docs/images/readme/tuneflow-desktop-home.png`
- Copy: `test/visual/full_goldens/mobile-player-390x844.png` → `docs/images/readme/tuneflow-mobile-player.png`
- Copy: `test/visual/full_goldens/mobile-library-390x844.png` → `docs/images/readme/tuneflow-mobile-library.png`

- [x] Create `docs/images/readme/`.
- [x] Copy the three approved existing screenshots without resizing or recompressing them.
- [x] Verify the copied files are PNG images with the expected dimensions:

```bash
file docs/images/readme/*.png
sips -g pixelWidth -g pixelHeight docs/images/readme/*.png
```

Expected: one 1440 × 960 desktop image and two 390 × 844 mobile images.

### Task 3: Rewrite README as a restrained product landing page

**Files:**
- Modify: `README.md`

- [x] Replace the engineering-first content with this content hierarchy:

```markdown
<!-- Hallmark · genre: atmospheric · macrostructure: Workbench -->
<!-- Hallmark · pre-emit critique: P4 H5 E4 S5 R5 V4 -->

<p align="center">
  <img src="assets/branding/TuneFlow.png" width="96" alt="TuneFlow 图标">
</p>

<h1 align="center">TuneFlow · 音流</h1>

<p align="center">把喜欢的音乐，安静地留在自己的节奏里。</p>

<p align="center">
  <a href="https://github.com/appdev/TuneFlow-Client/actions/workflows/build-clients.yml">获取最新构建</a>
  ·
  <a href="https://github.com/appdev/TuneFlow">TuneFlow Service</a>
</p>

TuneFlow 是一款面向桌面与移动设备的音乐客户端。它把发现、收藏、歌单与播放放在一个简洁的空间里，让听音乐这件事轻松一点。

![TuneFlow 桌面首页](docs/images/readme/tuneflow-desktop-home.png)

## 为每天的音乐而设计

### 找到想听的
[简短产品文案]

### 把喜欢的留在身边
[简短产品文案]

### 专心听这一首
[简短产品文案]

## 随身，也自在

<p align="center">
  <img src="docs/images/readme/tuneflow-mobile-player.png" width="45%" alt="TuneFlow 移动端播放页">
  <img src="docs/images/readme/tuneflow-mobile-library.png" width="45%" alt="TuneFlow 移动端我的音乐">
</p>

[移动体验文案]

## 获取 TuneFlow

[当前开发构建的透明说明与稳定 workflow 链接]

[Android / iOS / macOS / Windows / Linux 的简洁可用性表格]

## 与 TuneFlow Service 一起使用

[两句以内说明客户端需要连接 TuneFlow Service，并链接公开仓库]

## 版权与使用说明

[保留现有版权与非商业用途边界，不展示工程实现细节]
```

- [x] Keep paragraphs short and user-facing; prefer “发现、收藏、歌单、播放” over implementation terms.
- [x] Make download limitations clear:
  - Android artifact is an APK.
  - Windows and Linux artifacts are packaged builds.
  - iOS and macOS artifacts are unsigned development builds.
  - Actions artifact download may require GitHub login.
- [x] Do not mention unsupported app stores or claim a published GitHub Release.

### Task 4: Verify the frozen result

**Files:**
- Verify: `README.md`
- Verify: `test/branding/public_repository_links_test.dart`
- Verify: `docs/images/readme/*.png`

- [x] Run the focused README contract:

```bash
flutter test test/branding/public_repository_links_test.dart
```

Expected: PASS.

- [x] Run static analysis because a Dart test changed:

```bash
flutter analyze
```

Expected: no new analyzer issues.

- [x] Run whitespace validation:

```bash
git diff --check
```

Expected: no output.

- [x] Run a final public-content scan:

```bash
if rg -n '/Volumes/|/Users/|192\\.168\\.|QQ|网易|酷我|酷狗|咪咕|flowchart|/api/v1|flutter test' README.md; then
  exit 1
fi
```

Expected: no matches.

- [x] Read back the rendered-order Markdown and inspect the three image assets manually. Confirm:
  - the first visible action is “获取最新构建”;
  - screenshots contain no music-platform selector/branding;
  - technical details do not dominate the page;
  - all links are public GitHub links or repository-relative assets.

- [x] Review `git status --short` and report the exact uncommitted file set. Do not commit or push.
