# Cached Network Image CE 统一图片缓存设计

## 目标

使用 `cached_network_image_ce` 接管客户端所有 Flutter UI 网络图片加载。相同 URL 已经存在真实图片时，Widget 重建、路由切换和桌面/移动断点切换不得先显示占位图；只有从未取得真实图片或最终加载失败时才显示占位图。

## 已确认的产品边界

- 相同 URL、内存或磁盘缓存可用：直接显示真实图片，跳过占位图和淡入淡出。
- 相同 URL 首次加载：尚无真实图片时允许显示现有确定性占位图。
- URL 改变：不得继续显示上一 URL 的图片；新 URL 未完成时显示占位图。
- 图片加载或解码最终失败：显示现有占位图，不让错误影响页面主体。
- 图片缓存由 `cached_network_image_ce` 独立管理。
- 现有 1/2/5/10/20 GB 容量选择只约束音频缓存，不再宣称图片与音频共享精确字节配额。
- 设置页分别展示音频缓存和图片缓存占用；“清理本机缓存”同时清理两者以及 Flutter 内存图片缓存。
- 音频播放缓存、Service 下载任务和下载文件行为不变。

## 依赖与缓存管理

将 `cached_network_image_ce` 作为直接依赖加入 `pubspec.yaml`。不使用间接依赖身份，也不同时保留 `extended_image` 或自研 UI 图片下载器作为另一条网络加载路径。

应用创建一个共享的 `DefaultCacheManager` 实例并注入图片组件：

- 文件目录使用应用缓存目录，Hive 元数据使用应用支持目录。
- 使用 `LruCleanupStrategy`。
- `stalePeriod` 为 30 天。
- `maxNrOfCacheObjects` 为 1000。
- 设置合理的连接与请求超时，网络失败由组件错误状态处理。
- 所有封面继续携带现有 `artworkRequestHeaders`。

图片缓存没有用户可调的精确字节上限。设置页通过扫描该管理器专属文件目录展示实际图片文件占用；扫描和清理不得遍历或删除其他应用文件。

## 统一 UI 入口

保留 `AppArtwork` 作为业务层统一封面组件，但将其网络分支改为 `CachedNetworkImage`：

- `disablePlaceholderOnCacheHit: true`。
- 缓存命中时使用零淡入、零淡出，不引入视觉闪烁。
- 使用规范化 URL 作为 `imageUrl` 和稳定 `cacheKey`；请求头不改变同 URL 的 Flutter 图片缓存身份。
- `placeholder` 返回现有 `_ArtworkFallback`。
- `errorBuilder` 返回同一个 fallback。
- `showFallback: false` 时 loading 和 error 都保持空白，不意外新增默认图。
- 保留现有尺寸、裁剪、圆角、语义标签和 `FilterQuality` 行为。

`SearchTrackArtwork` 继续负责异步解析图片 URL，但解析完成后的网络图片必须复用同一缓存组件，不保留专用下载实现。

播放器背景、桌面封面、移动黑胶、Mini Player、队列、首页、发现、歌单、下载和搜索等页面都通过 `AppArtwork` 或统一的 CE 包装组件加载。`lib/` 中不得残留 `Image.network`、`NetworkImage` 或自研 `CachedArtworkImage`。

音频通知的 `MediaItem.artUri` 由系统/`audio_service` 消费，不是 Flutter UI 图片组件，不改成 `CachedNetworkImage`。

## 移除旧图片缓存路径

从 `MediaCache` 移除 UI 图片下载、图片租约、图片修复和图片 LRU 职责，只保留音频缓存：

- 删除 `acquireImage` 及相关并发下载表。
- `MediaCacheUsage.limitBytes` 只与音频字节比较。
- 保留兼容读取旧的 `media_cache_limit_bytes` 偏好键，但设置页文案改为“音频缓存上限”。
- 升级后首次初始化删除旧 `media-cache/images` 目录中的自研图片缓存；这些文件没有 URL 元数据，无法可靠迁移到 CE。
- 删除旧图片只影响可重新下载的本机缓存，不影响音频缓存、Service 下载或用户收藏数据。

## 设置页与生命周期

新增一个应用级图片缓存服务，拥有共享 `DefaultCacheManager`，并暴露：

- 当前图片缓存字节数。
- 刷新占用统计。
- 清空 CE 磁盘缓存及 Hive 元数据。
- 清空 Flutter `PaintingBinding.instance.imageCache`。
- 应用退出时释放缓存管理器。

设置页显示：

- 音频缓存占用和可选容量上限。
- 图片缓存实际占用，并说明由图片框架自动管理。
- 清理操作完成后重新读取两类实际占用。

任何图片统计或清理失败都应保留真实可读取的数值并显示可理解错误，不得把失败误报为零。

## 测试与验收

测试先失败再实现，至少覆盖：

1. `AppArtwork` 使用 `CachedNetworkImage`、稳定 cache key、请求头和共享 cache manager。
2. loading 与 error 状态遵守 `showFallback`。
3. 同 URL 从桌面播放器切到移动播放器时，磁盘缓存命中不渲染占位图。
4. 同 URL 从移动切回桌面同样不闪占位图。
5. URL 改变时不显示上一首图片。
6. 搜索异步解析 URL 后使用统一 CE 入口。
7. 静态契约测试扫描 `lib/`，禁止重新引入 `Image.network`、`NetworkImage` 和 `CachedArtworkImage`。
8. 音频缓存容量设置不再包含图片字节。
9. 设置页分别展示音频、图片占用，清理同时调用两类缓存并清除 Flutter 内存图片缓存。
10. 旧自研图片目录只在迁移时删除，音频文件保持不变。
11. 相关播放器、搜索、下载、歌单和视觉测试继续通过。

## 非目标

- 不修改 Service API 或图片 URL 的来源。
- 不缓存歌词、搜索响应或播放队列。
- 不把系统通知图片交给 Flutter Widget 管理。
- 不为 CE 图片缓存实现新的精确字节配额或重新实现其内部 Hive 索引。
- 不在本次工作中迁移无法反查 URL 的旧图片缓存文件。
