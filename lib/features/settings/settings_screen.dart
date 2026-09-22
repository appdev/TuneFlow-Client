import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import '../../storage/app_preferences.dart';
import '../connection/connection_repository.dart';
import '../radio/radio_controller.dart';
import 'settings_controller.dart';
import 'diagnostics_card.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.onBack,
    this.onConnectionSettings,
    this.onServiceSettings,
    this.radio,
  });
  final SettingsController controller;
  final VoidCallback? onBack;
  final VoidCallback? onConnectionSettings;
  final VoidCallback? onServiceSettings;
  final RadioController? radio;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshServiceSettings());
    unawaited(widget.controller.refreshCacheUsage());
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    unawaited(widget.controller.refreshServiceSettings());
    unawaited(widget.controller.refreshCacheUsage());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final mobile =
            classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
        final settings = widget.controller.state;
        final twoColumns = constraints.maxWidth >= 1000;
        final playback = _PlaybackSettings(
          controller: widget.controller,
          settings: settings,
          radio: widget.radio,
        );
        final lyrics = _LocalPlaybackAndLyricsSettings(
          controller: widget.controller,
          settings: settings,
        );
        final general = _GeneralSettings(
          controller: widget.controller,
          settings: settings,
        );
        final service = _SettingsSection(
          title: 'Service 与连接',
          description: '管理服务连接与服务端功能',
          children: [
            _ConnectionCard(
              controller: widget.controller,
              onPressed: widget.onConnectionSettings,
            ),
            _ServiceSettingsEntry(onPressed: widget.onServiceSettings),
            _AutoDownloadOnPlaySetting(controller: widget.controller),
          ],
        );
        final cache = _CacheCard(controller: widget.controller);
        final diagnostics = DiagnosticsCard(
          reporter: widget.controller.diagnostics,
          serviceOrigin:
              widget.controller.connection?.origin ?? settings.origin,
        );
        return ColoredBox(
          key: Key(mobile ? 'settings-mobile-layout' : 'settings-wide-layout'),
          color: AppTokens.of(context).background,
          child: SingleChildScrollView(
            key: const Key('settings-route'),
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 32,
              mobile ? 20 : 32,
              mobile ? 16 : 32,
              40,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (mobile)
                      AppMobilePageHeader(title: '设置', onBack: widget.onBack)
                    else
                      const Text('设置', style: AppTypography.display),
                    const SizedBox(height: 8),
                    Text(
                      '播放、歌词与连接偏好',
                      style: AppTypography.body.copyWith(
                        color: AppTokens.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (twoColumns)
                      Row(
                        key: const Key('settings-two-columns'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                playback,
                                const SizedBox(height: 24),
                                service,
                                const SizedBox(height: 24),
                                cache,
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              children: [
                                lyrics,
                                const SizedBox(height: 24),
                                general,
                                if (!kIsWeb) ...[
                                  const SizedBox(height: 24),
                                  diagnostics,
                                ],
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      playback,
                      const SizedBox(height: 24),
                      lyrics,
                      const SizedBox(height: 24),
                      general,
                      const SizedBox(height: 24),
                      service,
                      const SizedBox(height: 24),
                      cache,
                      if (!kIsWeb) ...[const SizedBox(height: 24), diagnostics],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class _ServiceSettingsEntry extends StatelessWidget {
  const _ServiceSettingsEntry({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 280.0;
      return ShadButton.ghost(
        key: const Key('settings-service-functions-entry'),
        foregroundColor: AppTokens.of(context).foreground,
        width: width,
        height: 80 * MediaQuery.textScalerOf(context).scale(1),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: SizedBox(
          width: width - 2,
          child: const Row(
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Service 功能设置', style: AppTypography.title),
                    SizedBox(height: 4),
                    Text('下载、元数据与每日推荐', style: AppTypography.metadata),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      );
    },
  );
}

final class _CacheCard extends StatelessWidget {
  const _CacheCard({required this.controller});

  final SettingsController controller;

  Future<void> _setLimit(BuildContext context, int bytes) async {
    try {
      await controller.setCacheLimit(bytes);
    } on Object catch (error) {
      if (context.mounted) {
        showAppMessage(
          context,
          title: '调整失败',
          message: appErrorMessage(error, fallback: '无法调整缓存上限，请稍后重试。'),
          destructive: true,
        );
      }
    }
  }

  Future<void> _clear(BuildContext context) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '清理本机缓存？',
      message: '仅清理此设备上的音频播放缓存和封面缓存，不会影响 Service 端下载内容。',
      cancelLabel: '取消',
      confirmLabel: '清理缓存',
    );
    if (!accepted || !context.mounted) return;
    try {
      await controller.clearLocalCache();
      if (context.mounted) {
        showAppMessage(context, title: '清理完成', message: '本机缓存已清理');
      }
    } on Object catch (error) {
      if (context.mounted) {
        showAppMessage(
          context,
          title: '清理失败',
          message: appErrorMessage(error, fallback: '无法清理本机缓存，请稍后重试。'),
          destructive: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = controller.cacheUsage;
    if (kIsWeb) {
      return const _SettingsSection(
        title: '浏览器存储',
        description: 'Web 端不使用原生音频文件缓存。',
        children: [
          Text('页面资源缓存由浏览器管理，可通过浏览器的站点设置清理。歌曲下载保存在 Service，不会保存到此设备。'),
        ],
      );
    }
    final limitSelect = IgnorePointer(
      ignoring: controller.cacheBusy,
      child: KeyedSubtree(
        key: const Key('settings-cache-limit'),
        child: _LabeledSelect<int>(
          label: '音频缓存上限',
          value: controller.state.cacheLimitBytes,
          options: [
            for (final bytes in mediaCacheLimitOptionsBytes)
              ShadOption(value: bytes, child: Text(_cacheLimitLabel(bytes))),
          ],
          labelFor: _cacheLimitLabel,
          onChanged: (bytes) => unawaited(_setLimit(context, bytes)),
        ),
      ),
    );
    final clearButton = AppButton(
      key: const Key('settings-clear-local-cache'),
      loading: controller.cacheBusy,
      variant: ShadButtonVariant.outline,
      onPressed: () => unawaited(_clear(context)),
      child: const Text('清理缓存'),
    );
    return _SettingsSection(
      title: '本机缓存',
      description: '只管理当前设备，不会影响 Service 端下载内容。',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '音频 ${_formatBytes(usage.audioBytes)} / '
              '${_formatBytes(usage.limitBytes)}',
              style: AppTypography.title,
            ),
            const SizedBox(height: 6),
            Text(
              controller.imageCacheAvailable
                  ? '图片 ${_formatBytes(controller.imageCacheBytes)} · '
                        '由图片缓存自动管理'
                  : '图片缓存不可用',
              style: AppTypography.metadata.copyWith(
                color: AppTokens.of(context).muted,
              ),
            ),
            if (controller.cacheError case final error?) ...[
              const SizedBox(height: AppSpacing.sm),
              AppNotice.error(
                title: '缓存操作失败',
                message: appErrorMessage(error, fallback: '缓存信息暂时无法读取，请稍后重试。'),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 520
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        limitSelect,
                        const SizedBox(height: 12),
                        clearButton,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: limitSelect),
                        const SizedBox(width: 12),
                        clearButton,
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller, required this.onPressed});

  final SettingsController controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final diagnostics = controller.connection;
    final connected = diagnostics?.connected ?? false;
    return LayoutBuilder(
      builder: (context, constraints) => ShadButton.ghost(
        key: const Key('settings-connection-entry'),
        foregroundColor: AppTokens.of(context).foreground,
        width: constraints.maxWidth,
        height: 88 * MediaQuery.textScalerOf(context).scale(1),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: SizedBox(
          width: constraints.maxWidth - 2,
          child: Row(
            children: [
              const Icon(LucideIcons.server, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service 连接',
                      key: Key('settings-connection-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title,
                    ),
                    const SizedBox(height: 6),
                    AppStatusBadge(
                      label: _connectionLabel(diagnostics),
                      tone: connected ? StatusTone.success : StatusTone.danger,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String _connectionLabel(ConnectionDiagnostics? diagnostics) {
  if (diagnostics == null || !diagnostics.connected) return '暂不可达';
  return switch (diagnostics.endpointRole) {
    EndpointRole.lan => '内网连接',
    EndpointRole.external => '外网连接',
    EndpointRole.bootstrap => '备用地址连接',
  };
}

/// A single quiet surface per group; rows use space instead of nested cards.
final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.section),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: AppTypography.metadata.copyWith(color: tokens.muted),
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: tokens.borderSoft),
            children[i],
          ],
        ],
      ),
    );
  }
}

final class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.controller, required this.settings});

  final SettingsController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => _SettingsSection(
    title: '通用',
    description: '此设备的界面偏好',
    children: [
      _LabeledSelect<ThemeMode>(
        label: '主题',
        value: settings.themeMode,
        options: const [
          ShadOption(value: ThemeMode.system, child: Text('跟随系统')),
          ShadOption(value: ThemeMode.light, child: Text('浅色')),
          ShadOption(value: ThemeMode.dark, child: Text('深色')),
        ],
        labelFor: _themeLabel,
        onChanged: controller.setThemeMode,
      ),
      _LabeledSelect<AppLanguage>(
        label: '语言',
        value: settings.language,
        options: const [
          ShadOption(value: AppLanguage.system, child: Text('跟随系统')),
          ShadOption(value: AppLanguage.zh, child: Text('简体中文')),
          ShadOption(value: AppLanguage.en, child: Text('English')),
        ],
        labelFor: _languageLabel,
        onChanged: controller.setLanguage,
      ),
      _SwitchPreference(
        key: const Key('settings-reduce-transparency'),
        value: settings.reduceTransparency,
        onChanged: controller.setReduceTransparency,
        label: '减少透明效果',
        description: '使用不透明表面替代模糊，界面布局保持不变。',
      ),
    ],
  );
}

final class _PlaybackSettings extends StatelessWidget {
  const _PlaybackSettings({
    required this.controller,
    required this.settings,
    this.radio,
  });

  final SettingsController controller;
  final AppSettings settings;
  final RadioController? radio;

  @override
  Widget build(BuildContext context) => _SettingsSection(
    title: '播放',
    description: '音质、进度与连续播放',
    children: [
      _LabeledSelect<PlaybackQuality>(
        label: '默认音质',
        value: settings.quality,
        options: const [
          ShadOption(value: PlaybackQuality.low128k, child: Text('128k')),
          ShadOption(value: PlaybackQuality.high320k, child: Text('320k')),
          ShadOption(value: PlaybackQuality.lossless, child: Text('无损')),
        ],
        labelFor: _qualityLabel,
        onChanged: controller.setQuality,
      ),

      _SwitchPreference(
        key: const Key('settings-keep-awake'),
        value: settings.keepAwake,
        onChanged: controller.setKeepAwake,
        label: '保持屏幕常亮',
      ),
      _SwitchPreference(
        key: const Key('settings-remember-progress'),
        value: settings.rememberPlaybackProgress,
        onChanged: controller.setRememberPlaybackProgress,
        label: '记忆播放进度',
        description: '仅保存在此设备，接近歌曲结尾时自动清除。',
      ),
      _SwitchPreference(
        key: const Key('settings-auto-skip-errors'),
        value: settings.autoSkipPlaybackErrors,
        onChanged: controller.setAutoSkipPlaybackErrors,
        label: '播放错误时自动跳过',
        description: '仅尝试队列中尚未失败的下一首歌曲。',
      ),
      if (radio != null) _AutoRadioContinuationSetting(controller: radio!),
    ],
  );
}

final class _LocalPlaybackAndLyricsSettings extends StatelessWidget {
  const _LocalPlaybackAndLyricsSettings({
    required this.controller,
    required this.settings,
  });

  final SettingsController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => _SettingsSection(
    title: '歌词',
    description: '显示内容与阅读方式',
    children: [
      _SwitchPreference(
        key: const Key('settings-show-lyrics'),
        value: settings.showLyrics,
        onChanged: controller.setShowLyrics,
        label: '默认显示歌词',
      ),
      _SwitchPreference(
        key: const Key('settings-show-translation'),
        value: settings.showTranslation,
        onChanged: controller.setShowTranslation,
        label: '默认显示翻译',
      ),
      _SwitchPreference(
        key: const Key('settings-show-romanization'),
        value: settings.showRomanization,
        onChanged: controller.setShowRomanization,
        label: '默认显示罗马音',
      ),
      _PreferenceSelect<LyricFontSize>(
        label: '歌词字号',
        value: _lyricFontSizeLabel(settings.lyricFontSize),
        selected: settings.lyricFontSize,
        options: const [
          ShadOption(value: LyricFontSize.small, child: Text('小')),
          ShadOption(value: LyricFontSize.standard, child: Text('标准')),
          ShadOption(value: LyricFontSize.large, child: Text('大')),
        ],
        onChanged: controller.setLyricFontSize,
      ),
      _PreferenceSelect<LyricAlignment>(
        label: '歌词对齐',
        value: _lyricAlignmentLabel(settings.lyricAlignment),
        selected: settings.lyricAlignment,
        options: const [
          ShadOption(value: LyricAlignment.adaptive, child: Text('跟随布局')),
          ShadOption(value: LyricAlignment.left, child: Text('居左')),
          ShadOption(value: LyricAlignment.center, child: Text('居中')),
          ShadOption(value: LyricAlignment.right, child: Text('居右')),
        ],
        onChanged: controller.setLyricAlignment,
      ),
      _PreferenceSelect<LyricAuxiliaryOrder>(
        label: '辅助歌词顺序',
        value: _lyricAuxiliaryOrderLabel(settings.lyricAuxiliaryOrder),
        selected: settings.lyricAuxiliaryOrder,
        options: const [
          ShadOption(
            value: LyricAuxiliaryOrder.translationFirst,
            child: Text('翻译优先'),
          ),
          ShadOption(
            value: LyricAuxiliaryOrder.romanizationFirst,
            child: Text('罗马音优先'),
          ),
          ShadOption(
            value: LyricAuxiliaryOrder.romanizationAbove,
            child: Text('罗马音在原文上方'),
          ),
        ],
        onChanged: controller.setLyricAuxiliaryOrder,
      ),
      _SwitchPreference(
        key: const Key('settings-traditional-lyrics'),
        value: settings.useTraditionalLyrics,
        onChanged: controller.setUseTraditionalLyrics,
        label: '歌词转换为繁体中文',
      ),
      _SwitchPreference(
        key: const Key('settings-emphasize-active-lyric'),
        value: settings.emphasizeActiveLyric,
        onChanged: controller.setEmphasizeActiveLyric,
        label: '放大当前歌词',
      ),
      _SwitchPreference(
        key: const Key('settings-animated-background'),
        value: settings.animatedBackground,
        onChanged: controller.setAnimatedBackground,
        label: '流动渐变背景',
        description: '播放时根据封面颜色缓慢流动，暂停或减少动画时停止。',
      ),
    ],
  );
}

final class _AutoRadioContinuationSetting extends StatelessWidget {
  const _AutoRadioContinuationSetting({required this.controller});

  final RadioController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _SwitchPreference(
      key: const Key('settings-auto-radio-continuation'),
      value: controller.state.autoContinuation,
      onChanged: (value) => unawaited(controller.setAutoContinuation(value)),
      label: '随心听自动续播',
      description: '播放队列接近末尾时自动补充推荐歌曲。',
    ),
  );
}

final class _SwitchPreference extends StatelessWidget {
  const _SwitchPreference({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) => _ToggleRow(
    value: value,
    onChanged: onChanged,
    label: label,
    description: description,
  );
}

/// The entire row is a pointer target; the native switch retains keyboard focus.
final class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.enabled = true,
    this.switchKey,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;
  final bool enabled;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.body),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: AppTypography.metadata.copyWith(
                          color: AppTokens.of(context).muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 48,
                height: 44,
                child: Center(
                  child: ShadSwitch(
                    key: switchKey,
                    value: value,
                    enabled: enabled,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _AutoDownloadOnPlaySetting extends StatelessWidget {
  const _AutoDownloadOnPlaySetting({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.autoDownloadOnPlay;
    final available = controller.serviceSettingsAvailable;
    final error = controller.serviceSettingsError;
    final enabled =
        available && !controller.serviceSettingsBusy && value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ToggleRow(
            switchKey: const Key('settings-auto-download-on-play'),
            value: value ?? false,
            enabled: enabled,
            onChanged: (next) =>
                unawaited(controller.setAutoDownloadOnPlay(next)),
            label: '边听边存',
            description: '播放在线音乐时，按 Service 的下载设置自动保存。',
          ),
          if (!available) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '连接 Service 后可设置',
              style: AppTypography.metadata.copyWith(
                color: AppTokens.of(context).muted,
              ),
            ),
          ],
          if (controller.serviceSettingsBusy && value == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '正在读取 Service 设置…',
              style: AppTypography.metadata.copyWith(
                color: AppTokens.of(context).muted,
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppNotice.error(
              title: value == null ? 'Service 设置读取失败' : 'Service 设置更新失败',
              message: appErrorMessage(
                error,
                fallback: value == null
                    ? 'Service 设置暂时无法读取，请稍后重试。'
                    : 'Service 设置暂时无法更新，请稍后重试。',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _PreferenceSelect<T> extends StatelessWidget {
  const _PreferenceSelect({
    required this.label,
    required this.value,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final T selected;
  final List<Widget> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final control = Semantics(
          label: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: ShadSelect<T>(
              initialValue: selected,
              minWidth: stacked ? constraints.maxWidth : 140,
              options: options,
              selectedOptionBuilder: (context, _) => Text(value),
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
            ),
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: AppTypography.body),
              const SizedBox(height: 8),
              control,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.body)),
            const SizedBox(width: 12),
            control,
          ],
        );
      },
    ),
  );
}

final class _LabeledSelect<T> extends StatelessWidget {
  const _LabeledSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<Widget> options;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => _PreferenceSelect<T>(
    label: label,
    value: labelFor(value),
    selected: value,
    options: options,
    onChanged: onChanged,
  );
}

String _themeLabel(ThemeMode value) => switch (value) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

String _languageLabel(AppLanguage value) => switch (value) {
  AppLanguage.system => '跟随系统',
  AppLanguage.zh => '简体中文',
  AppLanguage.en => 'English',
};

String _qualityLabel(PlaybackQuality value) => switch (value) {
  PlaybackQuality.lossless => '无损',
  _ => value.apiValue,
};

String _lyricFontSizeLabel(LyricFontSize value) => switch (value) {
  LyricFontSize.small => '小',
  LyricFontSize.standard => '标准',
  LyricFontSize.large => '大',
};

String _lyricAlignmentLabel(LyricAlignment value) => switch (value) {
  LyricAlignment.adaptive => '跟随布局',
  LyricAlignment.left => '居左',
  LyricAlignment.center => '居中',
  LyricAlignment.right => '居右',
};

String _lyricAuxiliaryOrderLabel(LyricAuxiliaryOrder value) => switch (value) {
  LyricAuxiliaryOrder.translationFirst => '翻译优先',
  LyricAuxiliaryOrder.romanizationFirst => '罗马音优先',
  LyricAuxiliaryOrder.romanizationAbove => '罗马音在原文上方',
};

String _cacheLimitLabel(int bytes) => '${bytes ~/ bytesPerGiB} GB';

String _formatBytes(int bytes) {
  if (bytes >= bytesPerGiB) {
    final value = bytes / bytesPerGiB;
    return value >= 10 || value == value.roundToDouble()
        ? '${value.toStringAsFixed(0)} GB'
        : '${value.toStringAsFixed(1)} GB';
  }
  const mib = 1024 * 1024;
  if (bytes >= mib) {
    final value = bytes / mib;
    return value == value.roundToDouble()
        ? '${value.toStringAsFixed(0)} MB'
        : '${value.toStringAsFixed(1)} MB';
  }
  const kib = 1024;
  if (bytes >= kib) return '${(bytes / kib).toStringAsFixed(0)} KB';
  return '$bytes B';
}
