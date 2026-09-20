# 用户主动上传诊断日志

## 行为与数据边界

Android、iOS、macOS、Windows、Linux 在本机记录最近 500 条、最多 512 KiB 的结构化日志，超过上限淘汰旧记录。恢复和导出时只保留最近 7 天的数据。Web 保持可编译，但不显示上传入口。

日志使用固定事件名、字段白名单；HTTP 只保留方法、模板路径、状态、耗时、响应长度。动态路径段替换为 `:id`，不记录查询值、头、请求/响应正文、搜索词、曲目资料、本地文件路径。异常只记录类型、错误代码、Dart package 代码位置，不序列化异常正文或 details。初始化、连接、HTTP/SSE、播放、歌词、电台和缓存失败均有对应记录。不是设备系统日志收集器，也不收集音频或屏幕。

记录不等待磁盘或网络；日志快照合并写入，最多每 2 秒触发一次，生命周期切换时尝试 flush。应用支持目录下 `diagnostics/recent.jsonl` 为当前快照，`recent.pending` 为原子替换临时文件；两者均有大小上限。存储不可用时降级为内存日志，不影响播放。强制结束前最后一批日志可能丢失。

设置 → 帮助与诊断 → 上传日志：先冻结当前日志快照，在后台 isolate 中 gzip 压缩，然后展示条数、大小、收集范围和 Service 主机/端口。确认后只发送该快照。附件为 `diagnostics.jsonl.gz`，首行元数据，其余为 JSONL 日志。压缩包上限 1 MiB。不会上传之后新增的日志。

Sentry SDK 使用独立 `SentryClient`，仅在同意上传后创建。没有 `SentryFlutter.init`、全局自动捕获、原生 crash handler、Session Replay、性能追踪或日志流上传。Flutter/异步错误由本地 handler 记录；保留框架原来的错误处理行为。原生崩溃和其它 isolate 的未处理错误不在这一版收集范围。

上传等待 Sentry HTTP 接收结果，20 秒超时，关闭连接；失败可由用户再次点击重试，无离线发送队列和后台自动重试。同一 reporter 同时只允许一次准备/确认/上传。超时可能发生于远端已接收后，重试可能产生第二份报告。收到事件编号表示平台接收请求，仍需在 Sentry 检查附件配额和可见性。

## 配置

在 Sentry.io 建立 Flutter 项目，取得公开 DSN，通过构建参数注入：

```sh
flutter build apk --release --dart-define=SENTRY_DSN=<your-public-dsn>
flutter build macos --release --dart-define=SENTRY_DSN=<your-public-dsn>
flutter build ios --release --no-codesign --dart-define=SENTRY_DSN=<your-public-dsn>
flutter build windows --release --dart-define=SENTRY_DSN=<your-public-dsn>
flutter build linux --release --dart-define=SENTRY_DSN=<your-public-dsn>
```

DSN 不授予读取项目权限，但会嵌入二进制，因此不能把管理 API Token 当作 DSN。实现只接受 HTTPS 的 sentry.io 子域、无 secret 的 DSN；不支持随意指定上传 URL。SDK 上传禁用重定向。

GitHub Actions 使用 repository variable `SENTRY_DSN` 注入各平台构建。不配置时只记录本地日志，上传按钮禁用；App 不要求最终用户输入 DSN。仓库不包含真实 DSN、账户 token 或日志文件。

诊断包消耗 Sentry **附件配额**和对应的事件配额，不是 Logs 的 5 GB 配额。试用前在控制台确认免费计划、附件存储、保留周期和项目成员权限；不要开启付费 PAYG 来验证此功能。

## 验证与运维

- 单元测试：字段脱敏/白名单、容量与存储失败、跨启动恢复、gzip 内容、无配置、同意/取消、并发抑制、超时与失败。
- Widget：移动/桌面确认弹窗，取消不发送、成功报告编号、失败重试。
- SDK 边界：以 MockClient 读取真实 SDK 编码的 envelope 和 gzip 附件，验证无额外请求及 200/429/500/网络失败处理。
- 原生构建需覆盖插件注册；Web 构建检查条件导入边界。Windows/Linux/iOS 需对应 CI/主机验证。
- 最后用测试 Sentry 项目和虚构操作数据验证：启动未点击时没有发往 Sentry 的请求；取消不发送；确认后只有一份诊断附件；平台能下载解压并按事件编号查询。真实 DSN 未提供时不能宣称这项已完成。

回退：移除构建参数即可禁用上传；本地日志仍受上述容量限制。整个功能不修改 Service API、数据格式或服务器配置。
