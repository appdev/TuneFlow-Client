import 'dart:async';

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
import 'settings_controller.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.onBack,
    this.onConnectionSettings,
  });
  final SettingsController controller;
  final VoidCallback? onBack;
  final VoidCallback? onConnectionSettings;

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
        return ColoredBox(
          key: Key(mobile ? 'settings-mobile-layout' : 'settings-wide-layout'),
          color: AppTokens.of(context).background,
          child: SingleChildScrollView(
            key: const Key('settings-route'),
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 38,
              mobile ? 20 : 34,
              mobile ? 16 : 38,
              40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mobile)
                  AppMobilePageHeader(
                    title: '设置',
                    eyebrow: '偏好与连接',
                    onBack: widget.onBack,
                  )
                else ...[
                  const Text('偏好与连接', style: AppTypography.metadata),
                  const SizedBox(height: 3),
                  const Text('设置', style: AppTypography.display),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (mobile) ...[
                  _ConnectionCard(
                    controller: widget.controller,
                    onPressed: widget.onConnectionSettings,
                    compact: true,
                  ),
                  const SizedBox(height: 12),
                  _MobilePreferences(
                    controller: widget.controller,
                    settings: settings,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _ConnectionCard(
                          controller: widget.controller,
                          onPressed: widget.onConnectionSettings,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _DesktopPreferences(
                          controller: widget.controller,
                          settings: settings,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.md),
                _CacheCard(controller: widget.controller),
              ],
            ),
          ),
        );
      },
    ),
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
    return ShadCard(
      padding: const EdgeInsets.all(18),
      radius: BorderRadius.circular(AppRadii.panel),
      title: const Text('本机缓存'),
      description: const Text('只管理当前设备，不会影响 Service 端下载内容。'),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Column(
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
      ),
    );
  }
}

final class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.controller,
    required this.onPressed,
    this.compact = false,
  });

  final SettingsController controller;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final diagnostics = controller.connection;
    final connected = diagnostics?.connected ?? false;
    final horizontalPadding = compact ? 16.0 : 20.0;
    return LayoutBuilder(
      builder: (context, constraints) => ShadButton.outline(
        key: const Key('settings-connection-entry'),
        width: constraints.maxWidth,
        height: 88,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        onPressed: onPressed,
        child: SizedBox(
          width: constraints.maxWidth - horizontalPadding * 2 - 2,
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

final class _MobilePreferences extends StatelessWidget {
  const _MobilePreferences({required this.controller, required this.settings});

  final SettingsController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: const EdgeInsets.all(18),
    radius: BorderRadius.circular(AppRadii.panel),
    child: Column(
      children: [
        _PreferenceSelect<ThemeMode>(
          label: '主题',
          value: _themeLabel(settings.themeMode),
          selected: settings.themeMode,
          options: const [
            ShadOption(value: ThemeMode.system, child: Text('跟随系统')),
            ShadOption(value: ThemeMode.light, child: Text('浅色')),
            ShadOption(value: ThemeMode.dark, child: Text('深色')),
          ],
          onChanged: controller.setThemeMode,
        ),
        const SizedBox(height: 12),
        _PreferenceRow(
          label: '减少透明效果',
          value: settings.reduceTransparency ? '开启' : '关闭',
          onTap: () =>
              controller.setReduceTransparency(!settings.reduceTransparency),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '使用不透明表面替代模糊，界面布局保持不变。',
              style: AppTypography.metadata.copyWith(
                color: AppTokens.of(context).muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _PreferenceSelect<AppLanguage>(
          label: '语言',
          value: _languageLabel(settings.language),
          selected: settings.language,
          options: const [
            ShadOption(value: AppLanguage.system, child: Text('跟随系统')),
            ShadOption(value: AppLanguage.zh, child: Text('简体中文')),
            ShadOption(value: AppLanguage.en, child: Text('English')),
          ],
          onChanged: controller.setLanguage,
        ),
        const SizedBox(height: 12),
        _PreferenceSelect<PlaybackQuality>(
          label: '默认音质',
          value: _qualityLabel(settings.quality),
          selected: settings.quality,
          options: const [
            ShadOption(value: PlaybackQuality.low128k, child: Text('128k')),
            ShadOption(value: PlaybackQuality.high320k, child: Text('320k')),
            ShadOption(value: PlaybackQuality.lossless, child: Text('无损')),
          ],
          onChanged: controller.setQuality,
        ),
        const SizedBox(height: 12),
        _AutoDownloadOnPlaySetting(controller: controller),
        const SizedBox(height: 12),
        _PreferenceRow(
          label: '歌词翻译',
          value: settings.showTranslation ? '开启' : '关闭',
          onTap: () => controller.setShowTranslation(!settings.showTranslation),
        ),
        Offstage(
          child: Column(
            children: [
              const Text('外观'),
              ShadSwitch(
                value: settings.keepAwake,
                onChanged: controller.setKeepAwake,
                label: const Text('保持屏幕常亮'),
              ),
              ShadSwitch(
                value: settings.showLyrics,
                onChanged: controller.setShowLyrics,
                label: const Text('默认显示歌词'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _DesktopPreferences extends StatelessWidget {
  const _DesktopPreferences({required this.controller, required this.settings});

  final SettingsController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: const EdgeInsets.all(18),
    radius: BorderRadius.circular(AppRadii.panel),
    child: Column(
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
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        _AutoDownloadOnPlaySetting(controller: controller),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: AppTokens.of(context).surfaceWarm,
            border: Border.all(color: AppTokens.of(context).border),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: const Text('默认显示歌词与翻译 · 播放时保持唤醒'),
        ),
        Offstage(
          child: Column(
            children: [
              const Text('外观'),
              const Text('语言'),
              const Text('保持屏幕常亮'),
              const Text('默认显示歌词'),
            ],
          ),
        ),
      ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.of(context).border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadSwitch(
            key: const Key('settings-auto-download-on-play'),
            value: value ?? false,
            enabled: enabled,
            onChanged: (next) =>
                unawaited(controller.setAutoDownloadOnPlay(next)),
            label: const Text('边听边存'),
            sublabel: const Text('播放在线音乐时，按 Service 的下载设置自动保存。'),
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

final class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppTokens.of(context).border),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.title)),
            Text(value, style: AppTypography.title),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: ShadSelect<T>(
      initialValue: selected,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      options: options,
      selectedOptionBuilder: (context, _) => Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.title)),
          Text(value, style: AppTypography.title),
        ],
      ),
      onChanged: (next) {
        if (next != null) onChanged(next);
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: AppTypography.title),
      const SizedBox(height: 6),
      ShadSelect<T>(
        initialValue: value,
        options: options,
        selectedOptionBuilder: (context, selected) => Text(labelFor(selected)),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ],
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
