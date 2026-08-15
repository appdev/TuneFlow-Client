# Flutter 客户端“边听边存”设置设计

## 目标

在 Flutter 客户端设置页提供“边听边存”开关，使用户可以读取并修改 TuneFlow Service 的 `player.autoDownloadOnPlay` 设置。该设置由 Service 统一持久化，Web 与所有 Flutter 客户端共享同一状态。

## 范围

- Flutter 客户端增加 Service 设置读取与更新能力。
- 桌面和移动设置布局都显示“边听边存”开关。
- 覆盖加载、提交、失败恢复和未连接状态。
- 增加仓库、控制器和组件层的针对性测试。

本次不修改 Service 端行为，不把该设置写入客户端 `SharedPreferences`，不部署客户端，也不调整其他下载设置。

## 数据所有权

`player.autoDownloadOnPlay` 的唯一事实来源是当前连接的 TuneFlow Service：

- 读取：`GET /api/v1/settings`
- 更新：`PATCH /api/v1/settings`
- 请求体：`{"player.autoDownloadOnPlay": <boolean>}`

客户端不缓存持久化副本。重新连接、连接到另一台 Service 或重新进入由新控制器承载的设置页面时，以当前 Service 返回值为准。

## 架构

### Service 设置仓库

新增轻量 `ServiceSettingsRepository`，封装 `ServiceApi`：

- 读取完整设置响应并严格提取布尔型 `player.autoDownloadOnPlay`。
- PATCH 单个设置键，并从响应中确认最终布尔值。
- 缺失键、错误类型、网络失败或 Service 错误均向上抛出，不猜测默认值。

仓库保持独立，避免在 Widget 或通用本机偏好模型中散落 Service API 细节。

### 设置控制器

扩展 `SettingsController`，注入可选的 Service 设置读取与更新函数。控制器维护以下瞬时状态：

- 当前 Service 返回的开关值；加载完成前为空。
- 是否正在加载或提交。
- 最近一次 Service 设置错误。

页面初始化时加载一次。用户切换时：

1. 在提交期间禁用重复操作。
2. 将目标值 PATCH 到 Service。
3. 仅使用 Service 确认返回的值更新界面。
4. 失败时保持原值，并向界面暴露错误。

本机 `AppSettings` 和 `SharedAppPreferences` 不新增字段。

### Provider 接线

`settingsControllerProvider` 从当前 `connectionProvider` 获取已连接的 `ServiceApi`，创建 `ServiceSettingsRepository` 并注入控制器。未连接时不提供 Service 设置操作，界面显示不可用状态。

连接切换会重建或刷新相关依赖，使开关状态来自新的 Service，而不是沿用上一台 Service 的值。

## 用户界面

在设置页的播放偏好区域增加一项：

- 标题：`边听边存`
- 说明：`播放在线音乐时，按 Service 的下载设置自动保存。`
- 控件：现有设计系统的 `ShadSwitch`
- 稳定测试键：`settings-auto-download-on-play`

桌面布局直接显示带说明的开关行；移动布局在现有偏好卡片中显示同一开关与说明。加载或提交期间禁用开关。未连接或读取失败时同样禁用，并在设置区域显示简洁错误提示；错误不得伪装成“关闭”。

## 错误处理

- GET 失败：值保持未知，开关禁用，展示读取失败信息。
- PATCH 失败：保留提交前值，开关恢复可操作，展示更新失败信息。
- Service 返回缺失键或非布尔值：视为无效响应，行为与读取/更新失败相同。
- 快速重复点击：提交期间忽略后续切换，避免请求乱序。
- 控制器被释放后完成的异步请求不得触发无效通知。

## 测试与验收

### 仓库测试

- GET 正确解析 `player.autoDownloadOnPlay`。
- PATCH 发送唯一目标键并解析确认值。
- 缺失键和非布尔值被拒绝。
- Service API 错误向控制器传播。

### 控制器测试

- 初始加载成功后显示 Service 值。
- 成功切换后采用 Service 确认值。
- 更新失败时保留原值并记录错误。
- 加载和提交期间忙碌状态正确，重复提交被抑制。
- 未注入 Service 设置能力时保持不可用。

### Widget 测试

- 桌面和移动布局均显示标题、说明及稳定测试键。
- 点击开关调用控制器并反映成功结果。
- 加载、提交、未连接和错误状态正确禁用或提示。

### 验证命令

运行相关设置仓库、控制器和设置页面测试，以及 Flutter 静态分析。若相关文件已有用户未提交修改，最终 diff 必须确认只增加本功能所需内容且未覆盖其他工作。

## 风险与约束

- 当前 Flutter 工作树已有大量未提交修改，实施必须采用小范围补丁并保留现有内容。
- 这是 Service 全局设置；一台客户端修改后会影响连接同一 Service 的其他客户端。
- 本次仅保证进入设置页或连接依赖重建时读取最新值，不新增实时跨客户端设置事件协议。
