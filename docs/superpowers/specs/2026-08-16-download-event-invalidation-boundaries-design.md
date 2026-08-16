# 下载事件刷新边界设计

## 问题

Service 会在下载数据写入过程中频繁发布 `downloads.updated`。Flutter 客户端当前把所有 `downloads.*` 事件同时映射为下载管理和本地音乐失效，导致本地音乐路由在下载期间反复重建并持续显示加载状态。

## 目标行为

- `downloads.*` 事件只使下载管理数据失效。
- `library.*` 事件只使本地音乐数据失效。
- `track.resources.updated` 继续只定向更新当前播放曲目的歌词或封面。
- 不通过防抖或延迟刷新掩盖跨资源刷新；事件类型本身就是刷新边界。

下载完成后，Service 会在媒体文件及其资源进入本地音乐库后发布 `library.updated`，因此客户端不需要从 `downloads.updated` 推断本地音乐是否已经变化。

## 实现

在 `EventCoordinator.accept` 中移除 `downloads.*` 分支对 `invalidateLibrary` 的调用，保留 `invalidateDownloads`。`library.*` 分支仍负责调用 `invalidateLibrary`。不修改路由、controller 或 Service。

## 验证

更新事件协调器测试，明确断言：

1. `downloads.updated` 只触发一次下载失效，不触发本地音乐失效。
2. 后续 `library.updated` 只触发本地音乐失效。
3. 旧序列事件仍会被拒绝，现有资源定向更新行为保持不变。

运行 `flutter test test/events/event_coordinator_test.dart` 作为聚焦验证。
