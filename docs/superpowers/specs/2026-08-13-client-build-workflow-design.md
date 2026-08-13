# TuneFlow 客户端构建与发布工作流设计

## 目标

为 TuneFlow（音流）客户端建立只能手动触发的 GitHub Actions 流水线。五个平台全部构建成功后，流水线自动创建正式 GitHub Release，并附加全部构建产物。

## 构建矩阵

- Android：使用 GitHub Secrets 恢复 JKS，只构建已签名 Release APK。
- iOS：执行 `flutter build ios --release --no-codesign`，上传未签名 Runner.app 压缩包。
- macOS：执行 `flutter build macos --release`，禁用代码签名，上传未签名 TuneFlow.app 压缩包。
- Windows：执行 `flutter build windows --release`，上传 Release 目录压缩包。
- Linux：安装 GTK/CMake 依赖后执行 `flutter build linux --release`，上传 bundle 压缩包。

工作流只支持 `workflow_dispatch`，不响应 `push` 或 Pull Request。各平台构建产物先上传为 Actions Artifact；独立的发布 Job 等待五个平台全部成功后再统一创建 GitHub Release，避免出现只包含部分平台产物的版本。

## 版本与发布规则

- 从 `pubspec.yaml` 的 `version` 字段读取完整版本，例如 `1.0.0+1`。
- Git 标签和 Release 名称使用带 `v` 前缀的完整版本，例如 `v1.0.0+1`。
- Release 为正式版本，不是 draft 或 prerelease。
- 发布 Job 下载五个平台的 Actions Artifact，并将 APK、ZIP 和 TAR.GZ 文件作为 Release assets 上传。
- 仅发布 Job 授予 `contents: write` 权限，用于创建标签、Release 和上传附件；构建 Job 保持 `contents: read`。
- 如果同名标签或 Release 已存在，发布失败并保留现有版本，不覆盖标签、说明或附件。
- 任一平台构建失败或取消时，发布 Job 不运行。

## Android 签名边界

JKS 内容、store password、key alias 和 key password 均存入 GitHub Actions Secrets。仓库只保存 Secret 名称和 Gradle 读取逻辑，不保存明文。工作流在 Runner 临时目录恢复 JKS，并生成被 Git 忽略的 `android/key.properties`；构建完成后 Runner 销毁。

## 验证

仓库契约测试检查仅允许手动触发、五端命令、Android 仅 APK、iOS/macOS 无签名、五个 Artifact 上传、发布 Job 的依赖关系、版本解析、写权限和五个平台附件。上线后手动触发工作流，确认五个构建 Job 全部成功，随后创建与 `pubspec.yaml` 版本一致且包含五个平台附件的正式 Release。
