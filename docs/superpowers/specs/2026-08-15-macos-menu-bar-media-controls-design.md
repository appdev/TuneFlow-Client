# macOS 菜单栏媒体控制设计

## 目标

为 TuneFlow 的 macOS 客户端增加应用自带的菜单栏媒体控制。完整状态展示 TuneFlow 图标、当前歌曲名、上一首、播放/暂停、下一首和收藏；关闭最后一个窗口后应用继续驻留、播放并响应 macOS 多媒体键。

第一阶段只覆盖 macOS。Windows 系统媒体控制留到后续独立设计，不在本次范围内。

## 插件评估与技术选择

优先评估现有 Flutter 插件：

- `system_tray` 支持 macOS 状态项的图标、标题、提示和上下文菜单，但不支持在一个状态项中放置多个独立可点击的内联按钮。
- `tray_manager` 支持图标、鼠标事件和上下文菜单，但不提供自定义 `NSStatusItem` 视图。
- `mac_menu_bar` 操作的是应用的“文件、编辑、显示”等标准主菜单，不是菜单栏右侧状态项。

这些插件都无法满足截图所示的内联控制和自适应布局，因此使用小型原生 Swift 实现。原生层仅负责展示、窗口生命周期和语义事件转发，播放器业务与收藏业务仍由 Dart 管理。

参考：

- <https://pub.dev/documentation/system_tray/latest/index.html>
- <https://pub.dev/packages/tray_manager>
- <https://pub.dev/packages/mac_menu_bar>
- <https://developer.apple.com/documentation/appkit/nsstatusitem>

## 架构

### Dart 状态协调

新增 `MacOSMenuBarCoordinator`，由 Riverpod 在 macOS 应用根部创建。它依赖现有 `PlayerController` 和 `PlaylistRepository`，负责：

- 监听当前歌曲、播放状态、加载状态、队列位置和时长变化。
- 查询内置 `love` 歌单，判断当前歌曲是否已收藏。
- 将状态转换为不包含业务对象的 `MacOSMenuBarSnapshot`。
- 接收原生层发来的语义命令并调用现有控制器或仓库。
- 在控制器重建、服务断开或应用退出时解除监听。

快照字段包括：

- `trackId`、`source`、`title`、`artist`
- `playing`、`loading`
- `canPlayPause`、`canGoPrevious`、`canGoNext`
- `favorite`、`favoritePending`、`canToggleFavorite`

仅在字段发生变化时向原生层发送新快照，避免进度流造成菜单栏频繁刷新。播放进度不显示在状态项中，也不进入该快照。

### 原生状态项

新增 `MacOSMenuBarController.swift`，通过 `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)` 创建一个状态项。状态项按钮区域承载原生水平布局，包含：

- TuneFlow 模板图标
- 单行歌曲标题
- 上一首按钮
- 播放/暂停按钮
- 下一首按钮
- 收藏按钮

按钮只向 Dart 发送 `previous`、`playPause`、`next`、`toggleFavorite`、`showWindow` 或 `quit` 等语义命令，不直接持有或调用 `just_audio`。

Flutter 与 Swift 使用项目私有的 `MethodChannel`。通道协议使用稳定的小写字符串命令和基础类型 Map；未知字段由接收端忽略，未知命令返回 Flutter 错误，便于后续兼容扩展。

## 菜单栏布局与交互

状态项使用三档布局：

1. 完整模式：主屏幕宽度不小于 1440 点时显示全部控件，歌曲标题最大宽度 160 点，超长文本尾部省略。
2. 紧凑模式：主屏幕宽度小于 1440 点时显示 TuneFlow 图标和播放/暂停按钮。
3. 图标模式：若状态项在布局更新后不可见，则收缩为单个 TuneFlow 图标并重新显示。

macOS 没有公开可靠的菜单栏剩余宽度 API，因此不推测其他应用占用的精确宽度。屏幕档位提供确定性基础降级，`isVisible` 检查提供最终兜底。

- 左键点击 TuneFlow 图标或歌曲标题恢复并聚焦已有主窗口。
- 内联按钮直接执行对应操作。
- 右键打开原生菜单，完整提供当前歌曲、上一首、播放/暂停、下一首、收藏、分隔线、“显示 TuneFlow”和“退出 TuneFlow”。紧凑与图标模式因此不丢失功能。
- 没有当前歌曲时只显示 TuneFlow 图标，媒体和收藏菜单项禁用。
- 加载或缓冲时播放按钮显示忙碌状态并禁用重复点击。
- 队首禁用上一首，队尾禁用下一首。
- 原生按钮提供中文无障碍标签和帮助提示。

菜单栏是原生表面，不能直接使用 Dart 的 `IconData`。实现时添加专用单色模板资源：播放传输图形保持项目既有 Material Rounded 家族，收藏保持既有 Lucide 家族；不引入新的图标库。该跨原生边界例外需同步记录到 `design.md`。

## 多媒体键与系统“正在播放”

继续使用项目已有的 `audio_service` macOS 实现。`ServiceAudioHandler` 已发布 `MediaItem`、`PlaybackState`，并实现 `play`、`pause`、`skipToPrevious`、`skipToNext` 和 `seek`。macOS 的 `MPRemoteCommandCenter` 将系统多媒体键转发给同一个处理器。

本功能不额外安装全局快捷键插件，也不重复监听硬件键，避免一次按键触发两次。菜单栏、应用内播放器、控制中心和硬件多媒体键最终都收敛到现有 `PlayerController`/`ServiceAudioHandler`。

## 收藏行为

收藏按钮固定对应内置 `love`（“我的收藏”）歌单：

- 切换当前歌曲后，通过 `PlaylistRepository.get('love')` 查询歌曲的 `source + id` 是否存在。
- 点击未收藏状态时调用 `addTracks('love', [track])`。
- 点击已收藏状态时调用 `removeTracks('love', [track.id])`。
- 操作期间立即更新图标并进入 `favoritePending`，防止重复点击。
- 请求失败时恢复之前状态；菜单栏继续可用，失败通过现有应用消息中心在主窗口下次可见时呈现。
- 切歌或断开服务会使旧请求结果失效，不能覆盖新歌曲状态。

## 应用生命周期

- `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`。关闭最后一个窗口只关闭或隐藏窗口，不结束 Flutter 引擎和音频处理器。
- Dock 图标点击、状态项图标/标题左键点击和“显示 TuneFlow”都恢复同一个主窗口，并将应用激活到前台；不得创建重复窗口。
- `⌘Q` 与状态项中的“退出 TuneFlow”走同一退出路径。退出前让 Flutter 执行现有资源清理，再终止应用。
- 应用关闭窗口后仍保留 Dock 图标；本次不转换为仅菜单栏应用，也不修改 `LSUIElement`。

## 错误与边界

- 原生通道未就绪、消息解码失败或状态项更新失败不能中断音频播放。记录可诊断日志并等待下一次状态快照重试。
- Dart 控制器不存在或服务未连接时，原生命令返回不可用结果，不抛出未处理异常。
- 快速连续点击通过 Dart 侧命令串行化和 `loading`/`favoritePending` 状态抑制重复操作。
- 原生状态项创建失败时，应用继续以普通窗口音乐客户端运行；多媒体键仍由 `audio_service` 处理。
- 状态项使用模板图像以自动适配浅色、深色和高对比度菜单栏。

## 验证

### Dart 测试

- 快照正确映射空闲、播放、暂停、加载、队首和队尾状态。
- 重复状态不会重复发送，纯播放进度变化不会刷新状态项。
- 原生命令正确路由到 `PlayerController`。
- 收藏查询使用 `source + id`，覆盖添加、移除、失败回滚和切歌竞态。
- 非 macOS 平台不创建协调器，不改变现有启动流程。

### Swift 测试

- 快照切换完整、紧凑和图标模式时控件与宽度正确。
- 每个按钮发送正确语义命令，禁用状态不会发送命令。
- 空队列、加载和收藏等待状态正确呈现。
- “显示 TuneFlow”恢复并聚焦现有窗口。
- 关闭最后一个窗口不会退出，“退出 TuneFlow”走显式退出路径。

### 聚焦回归与运行验证

- 运行 `test/features/player/service_audio_handler_test.dart`、播放器控制器测试和新增菜单栏协调器测试。
- 运行 `macos/RunnerTests` 并执行 macOS debug 构建。
- 在真实 macOS 会话中验证播放/暂停、上一首、下一首硬件媒体键和系统控制中心。
- 验证菜单栏内联按钮、右键菜单、长标题、窄屏降级、关闭窗口后继续播放、Dock 恢复窗口及正常退出。
- 执行项目图标系统要求的播放器和设计组件测试，并确认没有引入被禁止的传输图标调用。

## 非目标

- Windows 的系统媒体传输控制与任务栏集成。
- Linux MPRIS。
- macOS 菜单栏歌词滚动、播放进度条、音量滑块或封面图片。
- 隐藏 Dock 图标或提供“登录时启动”。
- 发布一个通用 Flutter 插件。
