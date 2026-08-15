import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import 'source_repository.dart';
import 'sources_controller.dart';

final class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, required this.controller});
  final SourcesController controller;

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

final class _SourcesScreenState extends State<SourcesScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _toggle(InstalledMusicSource source, bool enabled) async {
    if (!enabled && widget.controller.state.enabledSources.length == 1) {
      final accepted = await showAppDestructiveDialog(
        context,
        title: '禁用最后一个音源？',
        message: '在线播放和下载将不可用，本地音乐不受影响。',
        cancelLabel: '取消',
        confirmLabel: '仍要禁用',
      );
      if (!accepted || !mounted) return;
    }
    await widget.controller.toggle(source.id, enabled);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      return ColoredBox(
        key: Key(mobile ? 'sources-mobile-layout' : 'sources-wide-layout'),
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
              const AppMobilePageHeader(
                title: '音源管理',
                eyebrow: 'GET /api/v1/sources',
              )
            else ...[
              const Text('GET /api/v1/sources', style: AppTypography.metadata),
              const SizedBox(height: 4),
              const Text('音源管理', style: AppTypography.display),
            ],
            if (state.loading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 18),
              AppNotice.error(
                title: '音源操作失败',
                message: appErrorMessage(
                  state.error!,
                  fallback: '音源列表暂时无法加载，请稍后重试。',
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!state.loading && state.items.isEmpty)
              const _EmptySources()
            else ...[
              if (state.enabledSources.isNotEmpty) ...[
                const Text('已启用音源', style: AppTypography.section),
                const SizedBox(height: 12),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, _) => child,
                  itemCount: state.enabledSources.length,
                  onReorderItem: state.saving
                      ? (_, _) {}
                      : widget.controller.reorder,
                  itemBuilder: (context, index) {
                    final source = state.enabledSources[index];
                    return Padding(
                      key: ValueKey('enabled-source-${source.id}'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SourceCard(
                        source: source,
                        mobile: mobile,
                        label: index == 0 ? '首选' : '备用 $index',
                        saving: state.saving,
                        onToggle: (value) => _toggle(source, value),
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          enabled: !state.saving,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(LucideIcons.gripVertical, size: 18),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (state.disabledSources.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('未启用音源', style: AppTypography.section),
                const SizedBox(height: 12),
                for (final source in state.disabledSources)
                  Padding(
                    key: ValueKey('disabled-source-${source.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SourceCard(
                      source: source,
                      mobile: mobile,
                      label: '未启用',
                      saving: state.saving,
                      onToggle: (value) => _toggle(source, value),
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

final class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.mobile,
    required this.label,
    required this.saving,
    required this.onToggle,
    this.dragHandle,
  });
  final InstalledMusicSource source;
  final bool mobile;
  final String label;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source.name.isEmpty ? source.id : source.name,
                      style: AppTypography.title,
                    ),
                  ),
                  if (!mobile)
                    AppStatusBadge(
                      label: label,
                      tone: source.enabled
                          ? StatusTone.success
                          : StatusTone.neutral,
                    ),
                ],
              ),
              Text(
                '${sourceVersionLabel(source.version)} · '
                '${source.enabled ? label : '已安装 · 未启用'}',
                style: AppTypography.metadata.copyWith(
                  color: AppTokens.of(context).foregroundSecondary,
                ),
              ),
              if (!mobile) ...[
                const SizedBox(height: 8),
                Text(
                  source.description,
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).foregroundSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AppStatusBadge(
                    label: mobile
                        ? source.providers.map((item) => item.id).join(' / ')
                        : 'sources: ${source.providers.map((item) => item.id).join(' / ')}',
                  ),
                  if (!mobile)
                    AppStatusBadge(
                      label:
                          'qualitys: ${source.providers.expand((item) => item.qualities).toSet().join(' / ')}',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        if (dragHandle != null) ...[dragHandle!, const SizedBox(width: 6)],
        ShadSwitch(
          value: source.enabled,
          onChanged: saving ? null : onToggle,
          label: Text(source.enabled ? '已启用' : '未启用'),
        ),
      ],
    ),
  );
}

String sourceVersionLabel(String version) {
  final normalized = version.trim().replaceFirst(RegExp(r'^[vV]+'), '');
  return normalized.isEmpty ? '版本未知' : 'v$normalized';
}

final class _EmptySources extends StatelessWidget {
  const _EmptySources();

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(
          LucideIcons.audioLines,
          size: 32,
          color: AppTokens.of(context).muted,
        ),
        const SizedBox(height: 12),
        const Text('尚未安装音源', style: AppTypography.section),
        const SizedBox(height: 6),
        Text(
          '请先在 Service 管理端安装音源脚本。',
          style: AppTypography.body.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
      ],
    ),
  );
}
