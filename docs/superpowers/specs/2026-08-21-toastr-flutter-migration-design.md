# `toastr_flutter` Toast 迁移设计

## 背景

项目当前通过 `shadcn_ui` 的 `ShadToast` 和 `ShadSonner` 显示瞬时反馈。
Toast 调用已经集中在 `showAppMessage(...)`，但底层组件属于通用 UI 组件库，
而不是专门的 Toast 插件。项目决定改用全平台专用插件 `toastr_flutter`。

`toastr_flutter` 使用 Flutter Overlay 在 Android、iOS、Windows、macOS、Linux
和 Web 上提供一致实现，不承诺调用各操作系统的原生 Toast API。

## 目标

- 使用 `toastr_flutter ^2.5.1` 替换 `ShadToast`/`ShadSonner`。
- 保持现有 `showAppMessage(context, title, message, destructive)` 调用接口，避免修改
  功能页面中的调用方。
- 所有瞬时消息使用无图标 Toast，避免状态图标造成视觉干扰。
- 在现有 `MaterialApp.router` 与 `go_router` 结构中可靠显示 Toast。
- 保持全平台支持、明暗主题适配和自动消失行为。

## 非目标

- 不移除 `shadcn_ui`；项目的其他设计组件仍然依赖它。
- 不把 Toast 改造成系统通知，也不请求通知权限。
- 不引入加载 Toast、Promise API、操作按钮或业务级 Toast 队列管理。
- 不改动现有业务页面的提示文案或触发条件。

## 组件与集成

在 `pubspec.yaml` 增加 `toastr_flutter ^2.5.1`，并更新锁文件。

应用根部继续使用现有 `MaterialApp.router.builder`。该 builder 在保留
`AppThemeScope`、`AppGlassPolicyHost`、`ShadAppBuilder` 和 `_AppMessageHost` 顺序的
基础上，与 `Toastr.builder` 组合，使插件在嵌套导航和 `go_router` 下获得稳定的
Overlay。不会新增全局 navigator key 或单独的初始化服务。

`showAppMessage(...)` 仍是业务代码唯一需要调用的入口。`BuildContext` 继续保留，
用于读取当前明暗主题，也保持源代码兼容；插件本身不依赖调用方传递 context。

## 消息映射与展示

- 所有消息使用 `Toastr.blank`，确保插件不创建图标或图标占位。
- 保留 `destructive` 参数以维持现有调用点兼容；它不改变无图标 Toast 的外观。
- `message` 非空时，视觉上仅显示完整的 `message`；`title` 只保留在插件配置中供语义信息使用。
- `message` 为空时，将 `title` 作为唯一可见文本。
- 明亮主题使用插件明亮主题，暗色主题使用插件暗色主题。
- 每个 Toast 只渲染一个居中文本；短文案保持单行，较长错误信息可自然换行而不截断。
- 位置固定为 `topCenter`，展示时长为 3 秒。
- 不显示进度条和关闭按钮；保留插件默认的点击/滑动关闭能力。

`showAppMessage` 返回插件生成的 `String` Toast ID；现有调用方均不依赖返回值，因而
该收窄不会要求修改调用点，并为将来按 ID 关闭 Toast 保留能力。

## 清理范围

- 从 `app_feedback.dart` 移除 `ShadToast` 和 `ShadSonner` 使用。
- 从 `app_theme.dart` 移除 `appToastAlignment` 和 `sonnerTheme` 配置。
- 不触碰 `AppNotice`、`ShadAlert` 或其他 Shad 组件。
- 不对现有功能页面做批量重写。

## 错误与边界行为

Toast 是非关键反馈，插件显示失败不得改变业务操作结果。迁移不新增异常捕获或重试；
业务逻辑仍先完成自身操作，再请求显示反馈。重复消息和并发消息沿用插件的默认堆叠
行为，不添加跨页面状态。

## 验证

更新 `test/design/app_components_test.dart` 中与 Sonner 类型耦合的测试，验证：

- 普通消息能显示标题和正文。
- 仅标题消息不会产生额外占位文本。
- 普通和 destructive 调用均使用无图标的 `blank` 类型。
- Toast 在桌面和移动视口均位于顶部居中区域。

测试 harness 使用与生产应用相同的 `Toastr.builder` 集成方式，避免只验证插件的
偶然全局查找行为。随后运行：

```sh
flutter test test/design/app_components_test.dart
flutter analyze lib/design/components/app_feedback.dart lib/design/app_theme.dart lib/app/app.dart
```

若依赖更新影响更广，再运行完整 `flutter test`。最终用 `rg` 确认应用代码中不再存在
`ShadToast`、`ShadSonner`、`appToastAlignment` 或 `sonnerTheme` 引用。

## 工作区保护

当前工作区在 `pubspec.yaml`、`pubspec.lock`、`app_theme.dart`、`app.dart` 和组件测试等
相关文件中已有用户改动。实施时仅做针对 Toast 的最小补丁，不覆盖、格式化或回退
无关改动；验证结果将明确区分本次迁移与既有工作区状态。
