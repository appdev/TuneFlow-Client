# TuneFlow 客户端构建工作流设计

## 目标

为 TuneFlow（音流）客户端建立 GitHub Actions 构建流水线，并上传五个平台的可下载构建产物。

## 构建矩阵

- Android：使用 GitHub Secrets 恢复 JKS，只构建已签名 Release APK。
- iOS：执行 `flutter build ios --release --no-codesign`，上传未签名 Runner.app 压缩包。
- macOS：执行 `flutter build macos --release`，禁用代码签名，上传未签名 TuneFlow.app 压缩包。
- Windows：执行 `flutter build windows --release`，上传 Release 目录压缩包。
- Linux：安装 GTK/CMake 依赖后执行 `flutter build linux --release`，上传 bundle 压缩包。

工作流支持 `workflow_dispatch`、`push` 到 `main` 和 Pull Request。构建产物只上传为 Actions Artifact，不自动创建 Release。

## Android 签名边界

JKS 内容、store password、key alias 和 key password 均存入 GitHub Actions Secrets。仓库只保存 Secret 名称和 Gradle 读取逻辑，不保存明文。工作流在 Runner 临时目录恢复 JKS，并生成被 Git 忽略的 `android/key.properties`；构建完成后 Runner 销毁。

## 验证

仓库契约测试检查五端命令、Android 仅 APK、iOS/macOS 无签名、Artifact 上传和 Release 签名配置。发布后手动触发工作流，确认五个 Job 与 Artifact 状态。
