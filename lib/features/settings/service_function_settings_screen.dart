import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_states.dart';
import '../../design/design_tokens.dart';
import 'service_function_settings_controller.dart';
import 'service_settings_repository.dart';

final class ServiceFunctionSettingsScreen extends StatefulWidget {
  const ServiceFunctionSettingsScreen({
    super.key,
    required this.controller,
    this.onBack,
    this.updates,
  });

  final ServiceFunctionSettingsController controller;
  final VoidCallback? onBack;
  final Listenable? updates;

  @override
  State<ServiceFunctionSettingsScreen> createState() =>
      _ServiceFunctionSettingsScreenState();
}

final class _ServiceFunctionSettingsScreenState
    extends State<ServiceFunctionSettingsScreen> {
  late final TextEditingController timeZone = TextEditingController();
  late final TextEditingController musicBrainzBaseUrl = TextEditingController();
  late final TextEditingController aiBaseUrl = TextEditingController();
  late final TextEditingController aiModel = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncTextFields);
    widget.updates?.addListener(_handleExternalSettingsUpdate);
    unawaited(widget.controller.load());
  }

  void _handleExternalSettingsUpdate() {
    widget.controller.externalSettingsChanged();
  }

  @override
  void didUpdateWidget(covariant ServiceFunctionSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncTextFields);
      oldWidget.controller.dispose();
      widget.controller.addListener(_syncTextFields);
      unawaited(widget.controller.load());
    }
    if (!identical(oldWidget.updates, widget.updates)) {
      oldWidget.updates?.removeListener(_handleExternalSettingsUpdate);
      widget.updates?.addListener(_handleExternalSettingsUpdate);
    }
  }

  void _syncTextFields() {
    final draft = widget.controller.state.draft;
    if (draft == null) return;
    if (timeZone.text != draft.recommendationTimeZone) {
      timeZone.text = draft.recommendationTimeZone;
    }
    if (musicBrainzBaseUrl.text != draft.musicBrainzBaseUrl) {
      musicBrainzBaseUrl.text = draft.musicBrainzBaseUrl;
    }
    if (aiBaseUrl.text != draft.recommendationAiBaseUrl) {
      aiBaseUrl.text = draft.recommendationAiBaseUrl;
    }
    if (aiModel.text != draft.recommendationAiModel) {
      aiModel.text = draft.recommendationAiModel;
    }
  }

  Future<void> _save() async {
    final draft = widget.controller.state.draft;
    if (draft == null) return;
    final normalizedTimeZone = timeZone.text.trim();
    if (normalizedTimeZone.isEmpty) {
      showAppMessage(
        context,
        title: '设置未保存',
        message: '推荐时区不能为空。',
        destructive: true,
      );
      return;
    }
    widget.controller.update(
      draft.copyWith(
        recommendationTimeZone: normalizedTimeZone,
        musicBrainzBaseUrl: musicBrainzBaseUrl.text.trim(),
        recommendationAiBaseUrl: aiBaseUrl.text.trim(),
        recommendationAiModel: aiModel.text.trim(),
      ),
    );
    final saved = await widget.controller.save();
    if (mounted && saved) showAppMessage(context, title: 'Service 设置已保存');
  }

  Future<void> _testMusicBrainz() async {
    final result = await widget.controller.testMusicBrainzConnection(
      musicBrainzBaseUrl.text.trim(),
    );
    if (!mounted || result == null) return;
    showAppMessage(
      context,
      title: result.ok ? 'MusicBrainz 连接正常' : 'MusicBrainz 连接失败',
      message: result.ok
          ? result.normalizedBaseUrl
          : _musicBrainzError(result.errorCode),
      destructive: !result.ok,
    );
  }

  void _setMusicBrainzBaseUrl(String value) {
    final draft = widget.controller.state.draft;
    if (draft == null) return;
    musicBrainzBaseUrl.text = value;
    widget.controller.update(draft.copyWith(musicBrainzBaseUrl: value));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncTextFields);
    widget.updates?.removeListener(_handleExternalSettingsUpdate);
    widget.controller.dispose();
    timeZone.dispose();
    musicBrainzBaseUrl.dispose();
    aiBaseUrl.dispose();
    aiModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final draft = state.draft;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      if (state.loading && draft == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (draft == null) {
        return AppRetryState(
          message: state.error == null
              ? 'Service 功能设置不可用'
              : appErrorMessage(state.error!, fallback: '无法读取 Service 设置。'),
          retryLabel: '重试',
          onRetry: widget.controller.load,
        );
      }
      return ColoredBox(
        key: Key(
          mobile
              ? 'service-function-settings-mobile'
              : 'service-function-settings-wide',
        ),
        color: AppTokens.of(context).background,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            mobile ? 20 : 34,
            mobile ? 16 : 38,
            48,
          ),
          children: [
            if (mobile)
              AppMobilePageHeader(
                title: 'Service 功能设置',
                eyebrow: '下载与每日推荐',
                onBack: widget.onBack,
              )
            else
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('下载与每日推荐', style: AppTypography.metadata),
                  SizedBox(height: 4),
                  Text('Service 功能设置', style: AppTypography.display),
                ],
              ),
            if (state.error case final error?) ...[
              const SizedBox(height: 14),
              AppNotice.error(
                title: '设置操作失败',
                message: appErrorMessage(error, fallback: 'Service 设置未更新。'),
              ),
            ],
            if (state.externalUpdatePending) ...[
              const SizedBox(height: 14),
              AppNotice(
                title: 'Service 设置已在其他位置更新',
                message: '当前草稿尚未覆盖。重新加载后可查看最新设置。',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  key: const Key('service-settings-reload-external'),
                  variant: ShadButtonVariant.outline,
                  onPressed: widget.controller.reloadExternalSettings,
                  leading: const Icon(LucideIcons.refreshCw, size: 18),
                  child: const Text('重新加载'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SettingsCard(
              title: '播放与下载',
              description: '这些选项由 Service 执行，对连接到同一 Service 的客户端生效。',
              children: [
                _SwitchRow(
                  label: '启用下载功能',
                  value: draft.downloadEnabled,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(downloadEnabled: value),
                  ),
                ),
                _SwitchRow(
                  label: '边听边存',
                  value: draft.autoDownloadOnPlay,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(autoDownloadOnPlay: value),
                  ),
                ),
                _SwitchRow(
                  label: '同名文件直接跳过',
                  value: draft.skipExisting,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(skipExisting: value),
                  ),
                ),
                _SwitchRow(
                  label: '当前音源失败时尝试其他音源',
                  value: draft.useOtherSource,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(useOtherSource: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              title: '文件组织',
              description: '下载目录由 Service 宿主机管理；这里配置目录内的组织方式。',
              children: [
                _SwitchRow(
                  label: '按歌单名称分目录',
                  value: draft.groupByPlaylist,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(groupByPlaylist: value),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('文件名格式', style: AppTypography.metadata),
                const SizedBox(height: 6),
                KeyedSubtree(
                  key: const Key('service-download-file-name'),
                  child: ShadSelect<String>(
                    key: ValueKey(draft.fileName),
                    initialValue: draft.fileName,
                    options: const [
                      ShadOption(value: '歌名 - 歌手', child: Text('歌名 - 歌手')),
                      ShadOption(value: '歌手 - 歌名', child: Text('歌手 - 歌名')),
                      ShadOption(value: '歌名', child: Text('歌名')),
                    ],
                    selectedOptionBuilder: (context, value) => Text(value),
                    onChanged: (value) {
                      if (value != null) {
                        widget.controller.update(
                          draft.copyWith(fileName: value),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('最大并发下载数')),
                    SizedBox(
                      width: 120,
                      child: ShadSelect<int>(
                        key: const Key('service-download-concurrency'),
                        initialValue: draft.maxConcurrent,
                        options: [
                          for (var value = 1; value <= 6; value++)
                            ShadOption(value: value, child: Text('$value')),
                        ],
                        selectedOptionBuilder: (context, value) =>
                            Text('$value 个'),
                        onChanged: (value) {
                          if (value != null) {
                            widget.controller.update(
                              draft.copyWith(maxConcurrent: value),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              title: '歌词与元数据',
              description: '分别控制旁挂歌词文件和写入音频文件的元数据。',
              children: [
                _SwitchRow(
                  key: const Key('service-download-lyrics'),
                  label: '下载原文歌词文件',
                  value: draft.downloadLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(downloadLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-download-translated-lyrics'),
                  label: '下载翻译歌词文件',
                  value: draft.downloadTranslatedLyrics,
                  enabled: draft.downloadLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(downloadTranslatedLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-download-romanized-lyrics'),
                  label: '下载罗马音歌词文件',
                  value: draft.downloadRomanizedLyrics,
                  enabled: draft.downloadLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(downloadRomanizedLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-download-verbatim-lyrics'),
                  label: '下载逐字歌词文件',
                  value: draft.downloadVerbatimLyrics,
                  enabled: draft.downloadLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(downloadVerbatimLyrics: value),
                  ),
                ),
                _SwitchRow(
                  label: '嵌入封面',
                  value: draft.embedPicture,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(embedPicture: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-embed-lyrics'),
                  label: '嵌入原文歌词',
                  value: draft.embedLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(embedLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-embed-translated-lyrics'),
                  label: '嵌入翻译歌词',
                  value: draft.embedTranslatedLyrics,
                  enabled: draft.embedLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(embedTranslatedLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-embed-romanized-lyrics'),
                  label: '嵌入罗马音歌词',
                  value: draft.embedRomanizedLyrics,
                  enabled: draft.embedLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(embedRomanizedLyrics: value),
                  ),
                ),
                _SwitchRow(
                  key: const Key('service-embed-verbatim-lyrics'),
                  label: '嵌入逐字歌词',
                  value: draft.embedVerbatimLyrics,
                  enabled: draft.embedLyrics,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(embedVerbatimLyrics: value),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(child: Text('歌词文件编码')),
                    SizedBox(
                      width: 140,
                      child: ShadSelect<String>(
                        key: const Key('service-lyric-encoding'),
                        initialValue: draft.lyricEncoding,
                        options: const [
                          ShadOption(value: 'utf8', child: Text('UTF-8')),
                          ShadOption(value: 'gbk', child: Text('GBK')),
                        ],
                        selectedOptionBuilder: (context, value) =>
                            Text(value == 'gbk' ? 'GBK' : 'UTF-8'),
                        onChanged: (value) {
                          if (value != null) {
                            widget.controller.update(
                              draft.copyWith(lyricEncoding: value),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              title: '每日推荐',
              description:
                  '“system”使用 Service 宿主机时区，也可以填写 IANA 时区，例如 Asia/Shanghai。',
              children: [
                const Text('每日边界时区', style: AppTypography.metadata),
                const SizedBox(height: 6),
                AppTextField(
                  key: const Key('service-recommendation-time-zone'),
                  controller: timeZone,
                  placeholder: 'system 或 Asia/Shanghai',
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(recommendationTimeZone: value),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'MusicBrainz Web Service 地址',
                  style: AppTypography.metadata,
                ),
                const SizedBox(height: 6),
                AppTextField(
                  key: const Key('musicbrainz-url-field'),
                  controller: musicBrainzBaseUrl,
                  placeholder: officialMusicBrainzBaseUrl,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(musicBrainzBaseUrl: value),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '默认直连官方服务。也可以填写自建或第三方兼容的 /ws/2/ 地址；清空并保存后会关闭每日推荐。',
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      key: const Key('musicbrainz-test-connection'),
                      variant: ShadButtonVariant.outline,
                      loading: state.testingMusicBrainz,
                      onPressed: musicBrainzBaseUrl.text.trim().isEmpty
                          ? null
                          : _testMusicBrainz,
                      leading: const Icon(LucideIcons.plugZap, size: 18),
                      child: const Text('测试连接'),
                    ),
                    AppButton(
                      key: const Key('musicbrainz-restore-official'),
                      variant: ShadButtonVariant.outline,
                      onPressed: () =>
                          _setMusicBrainzBaseUrl(officialMusicBrainzBaseUrl),
                      leading: const Icon(LucideIcons.rotateCcw, size: 18),
                      child: const Text('恢复官方地址'),
                    ),
                    AppButton(
                      key: const Key('musicbrainz-disable'),
                      variant: ShadButtonVariant.outline,
                      onPressed: () => _setMusicBrainzBaseUrl(''),
                      leading: const Icon(LucideIcons.circleOff, size: 18),
                      child: const Text('关闭推荐'),
                    ),
                  ],
                ),
                if (state.musicBrainzTest case final result?) ...[
                  const SizedBox(height: 12),
                  AppNotice(
                    title: result.ok ? '连接测试成功' : '连接测试失败',
                    message: result.ok
                        ? '兼容地址：${result.normalizedBaseUrl}'
                        : _musicBrainzError(result.errorCode),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              title: 'AI 随心听',
              description: 'AI 只增强喜好分析和候选排序；无论是否启用，都保留本地自动推荐。',
              children: [
                _SwitchRow(
                  label: '启用 AI 推荐增强',
                  value: draft.recommendationAiEnabled,
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(recommendationAiEnabled: value),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('OpenAI 兼容接口地址', style: AppTypography.metadata),
                const SizedBox(height: 6),
                AppTextField(
                  key: const Key('service-recommendation-ai-base-url'),
                  controller: aiBaseUrl,
                  placeholder: 'https://api.openai.com/v1',
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(recommendationAiBaseUrl: value),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('模型', style: AppTypography.metadata),
                const SizedBox(height: 6),
                AppTextField(
                  key: const Key('service-recommendation-ai-model'),
                  controller: aiModel,
                  placeholder: 'gpt-5-mini',
                  onChanged: (value) => widget.controller.update(
                    draft.copyWith(recommendationAiModel: value),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'API Key 仅从 Service 环境变量 TUNEFLOW_RECOMMENDATION_AI_API_KEY 读取，不会进入 Flutter 或设备存储。',
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      key: const Key('service-recommendation-ai-test'),
                      variant: ShadButtonVariant.outline,
                      loading: state.testingAi,
                      onPressed: widget.controller.testAiConnection,
                      leading: const Icon(LucideIcons.plugZap, size: 18),
                      child: const Text('测试连接'),
                    ),
                    AppButton(
                      key: const Key('service-recommendation-ai-reanalyze'),
                      variant: ShadButtonVariant.outline,
                      loading: state.testingAi,
                      onPressed: draft.recommendationAiEnabled
                          ? () => unawaited(widget.controller.reanalyzeAi())
                          : null,
                      leading: const Icon(LucideIcons.refreshCw, size: 18),
                      child: const Text('重新分析喜好'),
                    ),
                  ],
                ),
                if (state.aiTest case final result?) ...[
                  const SizedBox(height: 12),
                  AppNotice(
                    title: result.ok ? 'AI 连接正常' : 'AI 连接失败',
                    message: result.ok
                        ? 'Service 可以调用已配置的模型。'
                        : (result.errorCode ?? '请检查地址、模型和 Service 环境变量。'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  variant: ShadButtonVariant.outline,
                  onPressed: state.dirty && !state.saving
                      ? widget.controller.reset
                      : null,
                  child: const Text('撤销修改'),
                ),
                const SizedBox(width: 10),
                AppButton(
                  key: const Key('service-settings-save'),
                  loading: state.saving,
                  onPressed: state.dirty ? _save : null,
                  child: const Text('保存设置'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

String _musicBrainzError(String? code) => switch (code) {
  'invalid_url' => '地址格式无效，请填写 http 或 https 的 MusicBrainz Web Service 地址。',
  'timeout' => '连接超时，请检查地址和网络。',
  'response_too_large' => '服务响应超过安全限制。',
  'cross_origin_redirect' => '服务跳转到了不同域名，已为安全起见拒绝。',
  'invalid_response' => '服务响应不兼容 MusicBrainz Web Service。',
  'rate_limited' => '服务请求过于频繁，请稍后再试。',
  _ => '无法连接该 MusicBrainz 服务，请检查地址和服务状态。',
};

final class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTypography.section),
        const SizedBox(height: 4),
        Text(
          description,
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

final class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: ShadSwitch(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      label: Text(label),
    ),
  );
}
