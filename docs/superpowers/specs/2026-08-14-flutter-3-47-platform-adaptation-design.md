# Flutter 3.47 跨平台适配设计

## 目标

让 TuneFlow 在 Flutter 3.47.0 / Dart 3.13.0 下通过静态分析，并在 Android、iOS、macOS、Windows、Linux 的原生构建环境中完成编译。

## 范围

- 修复 Flutter 3.47 暴露的 Dart API、测试调用点和弃用 API。
- 将 Android 构建链升级到 Flutter 3.47 支持且改动较小的组合。
- 接受 Flutter 3.47 对 iOS 工程自动执行的最低系统版本、UIScene 和 Swift Package Manager 迁移。
- 保持现有 macOS 工程行为；仅接受构建所需迁移，不主动删除仍在工作的 CocoaPods 集成。
- 使用现有 `.github/workflows/build-clients.yml` 在五种原生 runner 上验证 release 构建。

不在本次范围内：升级全部 Dart 依赖、重做 UI/golden 基线、修复与编译无关的既有功能测试失败、发布 GitHub Release。

## 推荐方案

### Android

采用兼容性优先的渐进升级：

- Gradle Wrapper 8.14
- Android Gradle Plugin 8.11.1
- Kotlin Gradle Plugin 2.2.20
- Java/Kotlin 编译目标 17

该组合满足 Flutter 3.47 对 Gradle 8.14 和 AGP 8.11.1 的最低要求，也满足 Flutter 自带兼容性检查中的 AGP/KGP 与 KGP/Gradle 组合约束。暂不升级到新项目模板的 Gradle 9.3.1、AGP 9.1.0、KGP 2.4.0，以避免同时引入 AGP 9 new DSL 和插件迁移风险。不得使用 `--android-skip-build-dependency-validation` 掩盖不兼容配置。

### Dart 与 Flutter API

- 为集成测试中的 `ServiceAudioHandler` 提供与生产初始化一致的 `fallbackArtUri`。
- 将需要零参数 builder 的测试改为显式闭包，避免把带命名参数的构造函数 tear-off 传给 `AudioService.init`。
- 将 `ReorderableListView.builder.onReorder` 改为 `onReorderItem`，并移除旧回调所需的 `newIndex` 手工减一逻辑。
- `LockCachingAudioSource` 的实验性警告不通过全局关闭 analyzer 处理；若上游没有稳定替代 API，则保留局部、带理由的抑制，避免静态分析长期带警告。

### iOS 与 macOS

- 接受 Flutter 工具执行的 iOS 15 最低部署版本迁移。
- 接受 UIScene 生命周期迁移以及 Flutter 生成插件的 Swift Package Manager 集成。
- iOS 构建目标为无签名 release 编译；macOS 构建目标为禁用签名的 release 编译。
- CocoaPods 清理是独立迁移，不作为编译适配的前置条件。

### Windows 与 Linux

不在 macOS 上进行无效的交叉编译。复用现有 GitHub Actions：Windows 2022 runner 执行 `flutter build windows --release`，Ubuntu 22.04 runner 安装原生依赖后执行 `flutter build linux --release`。

## 验证标准

本地验证：

1. `flutter analyze` 无 error、warning 或 deprecated diagnostics。
2. 与本次修改直接相关的测试通过，所有测试文件均能被 analyzer 编译检查。
3. `flutter build apk --debug` 成功。
4. `flutter build ios --simulator --debug` 或无签名 release 构建成功。
5. `flutter build macos --debug` 或无签名 release 构建成功。

远端验证：

1. 直接在当前 `main` 分支修复；为使远端构建与本地适配对象一致，提交当前构建所需的源码、资源、依赖清单和平台工程文件。
2. 排除 `build/`、内存转储、测试失败产物、无关文档和其他不参与应用构建的本地文件。
3. 触发 `build-clients.yml`，确认 Android、iOS、macOS、Windows、Linux 五个构建 job 成功。
4. 不触发或执行 GitHub Release 发布步骤；若现有工作流把构建与发布耦合，先调整为安全的仅构建验证入口。

## 风险与回滚

- iOS 自动迁移会改写多个 Xcode 工程文件，提交前必须检查 diff，排除本地绝对路径与生成缓存。
- Android 插件可能对 Kotlin 2.2.20 或 Java 17 暴露新的源码问题；以实际 Gradle 编译输出为准继续做最小修复。
- 工作区已有大量用户修改。提交前必须按构建依赖审查文件清单，保留全部用户改动，禁止清理或重置工作树；只有构建所需文件和本次适配文档可以进入当前分支提交。
- 若远端构建失败，只继续修复与当前适配直接相关的问题；不扩大到既有 UI/golden 回归。
