# Desktop Mottled Translucent Vinyl and Ambilight Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将桌面播放器唱片改造成由封面取色驱动、带云雾与径向沉积斑驳的半透明彩胶，中心封面保持完全不透明，并通过固定 Ambilight 与只覆盖树脂外圈的固定光斑形成相对流动感，同时保持移动端、布局和播放行为不变。

**Architecture:** `DesktopOrbitVinyl` 使用三个独立栅格边界：唱片后方的固定 Ambilight、包含半透明程序化树脂与完全不透明封面的旋转节点，以及位于最上方并以偶奇环形路径排除封面的固定光斑节点。持续播放只更新唱片 `RotationTransition` 的变换矩阵；树脂纹理从固定光斑下经过产生折射错觉，不逐帧重新生成纹理或柔光。

**Tech Stack:** Flutter/Dart、`CustomPainter`、Canvas gradients/paths、`ImageFiltered`、Flutter widget tests、现有 desktop player golden tests。

## Global Constraints

- 只修改桌面端彩胶材质及其测试、桌面视觉基线和 `design.md` 对应规则；不修改 `MobileVinylRecord`、共享移动唱片、取色器、播放领域状态、歌词、控制栏或响应式安全区。
- 保持当前工作树中的唱片直径和位置参数，包括 `rightOverflow = recordDiameter * (wide ? .42 : .45)`、`top = -recordDiameter * .40`，除非视觉验证证明 Ambilight 被错误裁切；任何几何微调不得侵入歌词或底部控制区。
- 保持中心封面约占唱片直径的 60%、18 秒旋转周期、暂停续转角度和现有唯一封面语义。
- 树脂透明度只能在 `PressedVinylPainter` 的离屏合成层内生效；中心 `AppArtwork` 必须在该 painter 之后独立绘制并保持 `alpha = 1`，不得置于 `Opacity`、透明 `ColorFilter` 或树脂离屏层中。
- 不绘制唱片外缘 stroke、完整圆周高光、实体阴影轮廓、中心封面色带或独立发光环。
- 不绘制同心沟槽或任何可读作常规黑胶线圈的圆形轨道；多层颜料必须先离屏合成，再通过约 `.76–.80` 的统一最终透明度与播放器背景混合。
- 删除孤立随机颗粒和沉积末端圆点。颜料纹理必须在接近外缘前经独立径向遮罩连续衰减，外缘只保留干净 PVC 基底与抗锯齿圆形裁切。
- 程序化纹理由歌曲 `source:id` 稳定种子和现有 `ArtworkPalette` 驱动；不增加纹理图片、Fragment Shader、第三方依赖、第二套封面解码或取色流程。
- Ambilight 与固定环形光斑都不得进入 `player-desktop-orbit-turn`，不响应唱片角度、播放进度或音频频谱；`blurEnabled == false` 时不得保留实时模糊。
- 固定光斑使用外圆减去 `innerFraction = .60` 内圆的偶奇路径，只覆盖树脂外圈；禁止让高光或混合模式覆盖中心封面。
- 浅色模式必须使用比暗色模式更高的饱和度和峰值 alpha、较低的派生明度；两种模式保持相同几何，避免浅色背景洗掉晕染或暗色背景产生刺眼霓虹。
- 保留并绕开工作区中现有搜索、专辑详情、Android dump、失败产物及其他无关改动，不格式化或改写无关文件。
- 设计依据：`docs/superpowers/specs/2026-08-21-desktop-translucent-diffractive-vinyl-design.md`。

---

### Task 1: 锁定固定光源、树脂透明度与不透明封面的组件契约

**Files:**
- Modify: `test/features/player/desktop_orbit_vinyl_test.dart`

- [ ] 更新桌面彩胶结构测试，使用稳定 key 验证：
  - `player-desktop-vinyl-ambilight` 恰好存在一个且不是 `player-desktop-orbit-turn` 的后代；
  - `player-desktop-vinyl-optical-glaze` 恰好存在一个且不是旋转节点的后代；其 painter 类型为 `VinylOpticalGlazePainter`，`innerFraction == .60`；
  - `player-desktop-vinyl-material`、`player-desktop-vinyl-artwork` 和 `player-desktop-vinyl-spindle` 均位于旋转节点下；
  - 旧的 `player-desktop-vinyl-diffraction`、`player-desktop-vinyl-refraction`、独立 inner-ring 节点和 edge-border/fade 节点不再存在；
  - 400 px 唱片中的中心封面仍为 `240 × 240`，且其直接几何容器不额外增加边框宽度。
- [ ] 将 blur policy 测试改为验证 Ambilight：默认路径存在 `player-desktop-vinyl-ambilight-blur`；`reduceTransparency: true` 时只存在 `player-desktop-vinyl-ambilight-fallback`，两条路径中心与尺寸一致。
- [ ] 更新材质 painter 测试，验证 painter 接收歌曲稳定种子、主色、辅助色和 `materialOpacity = .78`；断言透明度严格位于 0 与 1 之间，相同输入不触发 `shouldRepaint`，种子、颜色或透明度变化时触发重绘。
- [ ] 验证 `player-desktop-vinyl-artwork` 不存在 `Opacity` 或 `ColorFiltered` 祖先，并保持 `240 × 240`；这项结构证据与 painter 独立节点共同证明封面不继承树脂透明度。
- [ ] 更新重绘隔离测试，同时跟踪 Ambilight、固定光斑和程序化彩胶 painter；连续推进旋转帧和父级播放进度更新时三者 paint 次数均为 0。
- [ ] 运行聚焦测试并确认失败只来自尚未实现的新结构与 key：

```sh
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

### Task 2: 保持固定、无环形边界的 Ambilight

**Files:**
- Modify: `lib/features/player/desktop_orbit_vinyl.dart`
- Verify: `test/features/player/desktop_orbit_vinyl_test.dart`

- [ ] 保留 `_DesktopOrbitVinylState` 对 `blurEnabled`、旋转控制器和缓存视觉节点的现有生命周期；把 `_diffraction`/`_buildDiffraction` 及相关 key、painter 语义改为 Ambilight。
- [ ] Ambilight 外层范围保持在唱片直径的 `1.20–1.35` 倍。新增固定 painter，分别从 `vinylAccent`、`backgroundBase`、`backgroundCompanion` 派生可见但受限的颜色，在三个至四个不同方向绘制重叠的偏心柔光区域；禁止完整 `SweepGradient` 圆环、外缘 stroke 和可辨认的第二层圆盘。
- [ ] 标准路径通过 `ImageFiltered` 做有限模糊，并由 `player-desktop-vinyl-ambilight-blur` 标识；关闭 blur 时使用预混合低透明径向渐变，由 `player-desktop-vinyl-ambilight-fallback` 标识，保持相同中心、尺寸和色区方向。
- [ ] 将 Ambilight 包裹在独立 `RepaintBoundary`、`ExcludeSemantics` 和 `IgnorePointer` 中；`shouldRepaint` 只比较配色与降级模式。
- [ ] 保持 Ambilight 位于唱片旋转节点之外且不增加第二个 `RotationTransition`；暂停、恢复和减少动态效果前后方向固定，唱片旋转时不重绘 Ambilight painter。
- [ ] 将主题 `Brightness` 纳入缓存视觉输入和 `VinylAmbilightPainter.shouldRepaint`。浅色模式提高峰值 alpha、饱和度并压低派生明度；暗色模式保持克制。组件测试分别验证两种模式的 painter 配置和固定方向。
- [ ] 运行聚焦测试，确认固定/旋转层级、策略分支和重绘隔离通过：

```sh
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

### Task 3: 用稳定程序化纹理替换纯色、折射环和规则线条

**Files:**
- Modify: `lib/features/player/desktop_orbit_vinyl.dart`
- Modify: `test/features/player/desktop_orbit_vinyl_test.dart`
- Modify: `design.md`

- [ ] 用一个有稳定公开测试类型的程序化材质 painter 取代当前 `SweepGradient` 基底、封面折射环和 `TexturedVinylPainter`。Painter 接收 `seed`、`vinylAccent`、`backgroundCompanion` 及必要的派生高光/暗部颜色，并在圆形裁切内一次性绘制完整透明 PVC 材质。
- [ ] 使用确定性伪随机序列生成有固定上限的宽尺度云雾／大理石路径：控制点、弯曲方向、面积、深浅和透明度由歌曲种子决定；不同路径使用主色深浅变体与辅助色混合，避免均匀扇区、重复模板和逐帧随机数。
- [ ] 将径向沉积改为受控流动带：删除 `_paintMarbling` 中的随机 dot 循环和 `_paintRadialDeposits` 的末端圆点；限制路径终点和宽色块范围，避免在圆形裁切处产生截断暗点。
- [ ] 把云雾与流动带放入独立 pattern layer，并用从半径约 `.90` 开始、`.97` 前结束的径向 `dstIn` 遮罩平滑衰减；基础 PVC 圆盘不使用该遮罩，从而保持连续、干净的外缘而不形成额外边框。
- [ ] 完全删除 `_paintGrooves` 及所有同心圆／圆弧轨道绘制，不以降低透明度的方式保留线圈。将当前圆弧反光替换为少量宽幅、非同心的低频树脂明暗变化；旋转材质不承担主要镜面高光，主要高光由 Task 4 的固定环形光斑提供。
- [ ] 将 PVC 基底、云雾和颜料沉积绘制在同一个离屏层中，内部颜色允许保持饱满，恢复离屏层时通过 painter 的稳定 `materialOpacity`（目标 `.76–.80`）统一合成。测试断言该值严格位于 0 与 1 之间，并纳入 `shouldRepaint` 比较。
- [ ] 移除旋转节点外层的完整 edge fade/outline 结构、封面折射图像层及中心封面外的渐变色带/box shadow 容器。中心封面改为精确 `artworkDiameter` 的圆形 `AppArtwork`，不增加描边；保留轴孔和唯一封面语义。
- [ ] 确保 painter 的 `shouldRepaint` 比较稳定种子和所有绘制输入；程序化路径只在歌曲或配色变化时重建，并继续位于旋转 `RepaintBoundary` 内。
- [ ] 更新 `design.md` 的 “Immersive player” 桌面规则：受控半透明斑驳彩胶、完全不透明且无边框的中心封面、无同心沟槽、固定 Ambilight、只覆盖树脂的固定光斑及 blur policy 降级；明确移动端不继承该材质。
- [ ] 格式化并运行组件测试：

```sh
dart format lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

### Task 4: 增加只覆盖树脂的固定环形光斑

**Files:**
- Modify: `lib/features/player/desktop_orbit_vinyl.dart`
- Modify: `test/features/player/desktop_orbit_vinyl_test.dart`

**Interfaces:**
- Consumes: `ArtworkPalette.vinylAccent`、`ArtworkPalette.backgroundCompanion`、`AppGlassPolicy.blurEnabled` 和中心封面比例 `.60`。
- Produces: `VinylOpticalGlazePainter({required Color accentColor, required Color companionColor, double innerFraction = .60, required bool softened})`，以及稳定节点 key `player-desktop-vinyl-optical-glaze`、`player-desktop-vinyl-optical-glaze-paint`。

- [ ] 在结构测试中先要求固定光斑位于旋转唱片之后、但不是 `player-desktop-orbit-turn` 的后代；读取 painter 并断言 `innerFraction == .60`、颜色来自 palette，且相同输入的 `shouldRepaint` 为 false。
- [ ] 在 `_DesktopOrbitVinylState` 缓存 `_opticalGlaze`，由 `_rebuildVisuals()` 与 Ambilight、turntable 一起重建；Stack 顺序固定为 Ambilight、turntable、optical glaze：

```dart
return Stack(
  alignment: Alignment.center,
  clipBehavior: Clip.none,
  children: [
    Positioned.fill(child: _buildAmbilightHost(diameter)),
    Positioned.fill(child: _turntable),
    Positioned.fill(child: _opticalGlaze),
  ],
);
```

- [ ] 新增公开可测试 painter，并在 `paint` 开头使用偶奇路径裁剪树脂圆环；内圆直径必须精确等于唱片直径的 `.60`，不能依赖封面像素或图片 alpha：

```dart
final class VinylOpticalGlazePainter extends CustomPainter {
  const VinylOpticalGlazePainter({
    required this.accentColor,
    required this.companionColor,
    this.innerFraction = .60,
    required this.softened,
  });

  final Color accentColor;
  final Color companionColor;
  final double innerFraction;
  final bool softened;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final inner = Rect.fromCenter(
      center: outer.center,
      width: size.shortestSide * innerFraction,
      height: size.shortestSide * innerFraction,
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(outer)
      ..addOval(inner);
    canvas.save();
    canvas.clipPath(ring, doAntiAlias: true);
    final band = Rect.fromCenter(
      center: Offset(size.width * .34, size.height * .28),
      width: size.width * .78,
      height: size.height * .18,
    );
    canvas.save();
    canvas.translate(band.center.dx, band.center.dy);
    canvas.rotate(-.72);
    canvas.translate(-band.center.dx, -band.center.dy);
    canvas.drawOval(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: .20),
            accentColor.withValues(alpha: .12),
            Colors.transparent,
          ],
          stops: const [0, .38, .58, 1],
        ).createShader(band)
        ..blendMode = BlendMode.screen
        ..maskFilter = softened
            ? const MaskFilter.blur(BlurStyle.normal, 7)
            : null,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VinylOpticalGlazePainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.companionColor != companionColor ||
      oldDelegate.innerFraction != innerFraction ||
      oldDelegate.softened != softened;
}
```

- [ ] 光斑不得绘制完整圆周、外缘 stroke 或均匀白色蒙版。标准路径可使用有限 `MaskFilter.blur`；`softened == false` 时改用多级渐变 stops 形成柔边，不保留 blur。光斑峰值 alpha 保持克制，并只使用提亮后的 palette 颜色与白色高光。
- [ ] 用 `RepaintBoundary`、`ExcludeSemantics` 和 `IgnorePointer` 包裹光斑 painter。推进 8 帧旋转及父级状态更新时，光斑 painter 的 paint 次数必须保持 0；减少动态效果前后节点和裁切范围保持不变。
- [ ] 格式化并运行聚焦测试：

```sh
dart format lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart
```

### Task 5: 验证桌面集成、视觉基线和移动端不回归

**Files:**
- Verify: `test/features/player/player_screen_test.dart`
- Verify: `test/features/player/mobile_vinyl_record_test.dart`
- Update: `test/visual/full_goldens/desktop-player-1024x768.png`
- Update: `test/visual/full_goldens/desktop-player-1024x768-light.png`
- Update: `test/visual/full_goldens/desktop-player-1440x960.png`
- Update: `test/visual/full_goldens/desktop-player-1440x960-light.png`

- [ ] 运行桌面播放器测试，确认 1024×768 和 1440×960 下唱片裁切、歌词安全区、控制栏和旋转状态保持有效：

```sh
flutter test test/features/player/player_screen_test.dart
```

- [ ] 只更新四个 desktop player golden：

```sh
flutter test test/visual/full_ui_gallery_test.dart --update-goldens --plain-name 'desktop player dark 1024x768'
flutter test test/visual/full_ui_gallery_test.dart --update-goldens --plain-name 'desktop player light 1024x768'
flutter test test/visual/full_ui_gallery_test.dart --update-goldens --plain-name 'desktop player dark 1440x960'
flutter test test/visual/full_ui_gallery_test.dart --update-goldens --plain-name 'desktop player light 1440x960'
```

- [ ] 打开四张更新后的基线逐张检查：浅色模式 Ambilight 清晰可辨但不形成硬边，暗色模式不过亮；中心封面无框、清晰且与原图亮度一致；背景能透过彩胶但唱片仍保留饱满颜色；云雾大理石和受控流动色带清楚可见；固定环形光斑只落在树脂外圈且不形成完整光环；不存在同心沟槽或线圈感；唱片外缘干净、无随机污点、描边或第二层圆盘；Ambilight 与光斑不污染歌词和控制栏。
- [ ] 不带 `--update-goldens` 重跑同四个测试，证明程序化纹理由稳定种子生成，视觉基线可重复。
- [ ] 运行移动唱片测试和最终聚焦回归：

```sh
flutter test test/features/player/mobile_vinyl_record_test.dart
flutter test test/features/player/desktop_orbit_vinyl_test.dart test/features/player/player_screen_test.dart test/features/player/mobile_vinyl_record_test.dart
```

- [ ] 检查最终 diff、格式和工作树范围，确保没有覆盖用户的无关改动，也没有纳入 Android dump 或失败产物：

```sh
dart format --output=none --set-exit-if-changed lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart
git diff --check -- lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart test/features/player/player_screen_test.dart design.md
git diff -- lib/features/player/desktop_orbit_vinyl.dart test/features/player/desktop_orbit_vinyl_test.dart test/features/player/player_screen_test.dart design.md docs/superpowers/specs/2026-08-21-desktop-translucent-diffractive-vinyl-design.md docs/superpowers/plans/2026-08-21-desktop-translucent-diffractive-vinyl.md
git status --short
```

## Rollback

- 所有生产改动限定在现有桌面彩胶组件和 `design.md`，可通过逐文件反向应用本次 diff 回退，不删除资产或迁移数据。
- Golden 更新只覆盖四张 desktop player 基线；若视觉验收不通过，保留实现和测试证据，恢复这四张基线到执行前内容后继续调整，不触碰其他页面基线。
- 不提交、推送、发布或部署；这些外部动作不在本计划授权范围内。
