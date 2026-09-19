import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import 'source_repository.dart';
import 'sources_controller.dart';

final class SourcesScreen extends StatefulWidget {
  const SourcesScreen({
    super.key,
    required this.controller,
    this.onBack,
    this.onExport,
    this.pickSourceFile,
  });
  final SourcesController controller;
  final VoidCallback? onBack;
  final Future<void> Function(Uri uri)? onExport;
  final Future<XFile?> Function()? pickSourceFile;

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

final class _SourcesScreenState extends State<SourcesScreen> {
  bool _importing = false;
  String? _fileError;

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
      final accepted = await AppBottomSheet.showDestructive(
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

  Future<void> _importLocal() async {
    if (_importing || widget.controller.state.saving) return;
    setState(() {
      _importing = true;
      _fileError = null;
    });
    try {
      final file =
          await (widget.pickSourceFile?.call() ??
              openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'JavaScript 音源',
                    extensions: ['js'],
                    uniformTypeIdentifiers: ['com.netscape.javascript-source'],
                  ),
                ],
                confirmButtonText: '导入',
              ));
      if (!mounted || file == null) return;
      if (!file.name.toLowerCase().endsWith('.js')) {
        setState(() => _fileError = '请选择 .js 格式的音源文件。');
        return;
      }
      final script = (await file.readAsString())
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .trim();
      if (!mounted) return;
      if (script.isEmpty) {
        setState(() => _fileError = '音源文件为空，请选择包含脚本的 .js 文件。');
        return;
      }
      await widget.controller.installScript(script);
    } on Object {
      if (mounted) {
        setState(() => _fileError = '无法读取音源文件，请确认文件可访问且使用 UTF-8 编码后重试。');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importUrl() async {
    setState(() => _fileError = null);
    final url = await AppBottomSheet.showContent<String>(
      context,
      title: '从 URL 导入',
      message: '仅支持可直接访问的 HTTP 或 HTTPS 音源脚本地址。',
      child: const _SourceTextForm(
        placeholder: 'https://example.com/source.js',
        submitLabel: '导入',
      ),
    );
    if (!mounted || url == null || url.trim().isEmpty) return;
    await widget.controller.importUrl(url);
  }

  Future<void> _delete(InstalledMusicSource source) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '删除音源？',
      message:
          '将从 Service 删除「${source.name.isEmpty ? source.id : source.name}」及其脚本。',
      confirmLabel: '删除',
    );
    if (!accepted || !mounted) return;
    await widget.controller.delete(source.id);
  }

  Future<void> _export() async {
    final export = widget.onExport;
    if (export == null) return;
    try {
      await export(widget.controller.repository.exportUri);
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '导出失败',
        message: appErrorMessage(error, fallback: '无法打开音源导出地址。'),
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final busy = state.saving || _importing;
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
              AppMobilePageHeader(
                title: '音源管理',
                eyebrow: 'GET /api/v1/sources',
                onBack: widget.onBack,
              )
            else ...[
              const Text('GET /api/v1/sources', style: AppTypography.metadata),
              const SizedBox(height: 4),
              const Text('音源管理', style: AppTypography.display),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  key: const Key('source-import-local'),
                  onPressed: busy ? null : _importLocal,
                  leading: const Icon(LucideIcons.filePlus2, size: 16),
                  child: Text(_importing ? '正在导入…' : '从本地导入'),
                ),
                AppButton(
                  key: const Key('source-import-url'),
                  variant: ShadButtonVariant.outline,
                  onPressed: busy ? null : _importUrl,
                  leading: const Icon(LucideIcons.link, size: 16),
                  child: const Text('从 URL 导入'),
                ),
                if (widget.onExport != null)
                  AppButton(
                    key: const Key('source-export'),
                    variant: ShadButtonVariant.outline,
                    onPressed: busy || state.loading || state.items.isEmpty
                        ? null
                        : _export,
                    leading: const Icon(LucideIcons.archive, size: 16),
                    child: const Text('导出全部'),
                  ),
              ],
            ),
            if (state.loading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_fileError != null || state.error != null) ...[
              const SizedBox(height: 18),
              AppNotice.error(
                title: '音源操作失败',
                message:
                    _fileError ??
                    appErrorMessage(
                      state.error!,
                      fallback: '音源操作失败，请检查音源文件或地址后重试。',
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
                  onReorderItem: busy ? (_, _) {} : widget.controller.reorder,
                  itemBuilder: (context, index) {
                    final source = state.enabledSources[index];
                    return Padding(
                      key: ValueKey('enabled-source-${source.id}'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SourceCard(
                        source: source,
                        mobile: mobile,
                        label: index == 0 ? '首选' : '备用 $index',
                        saving: busy,
                        onToggle: (value) => _toggle(source, value),
                        onDelete: () => _delete(source),
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          enabled: !busy,
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
                      saving: busy,
                      onToggle: (value) => _toggle(source, value),
                      onDelete: () => _delete(source),
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
    required this.onDelete,
    this.dragHandle,
  });
  final InstalledMusicSource source;
  final bool mobile;
  final String label;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
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
                '${source.enabled ? label : '已导入 · 未启用'}',
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
        IconButton(
          key: Key('delete-source-${source.id}'),
          tooltip: '删除音源',
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          onPressed: saving ? null : onDelete,
          icon: const Icon(LucideIcons.trash2, size: 18),
        ),
        const SizedBox(width: 4),
        ShadSwitch(
          value: source.enabled,
          onChanged: saving ? null : onToggle,
          label: Text(source.enabled ? '已启用' : '未启用'),
        ),
      ],
    ),
  );
}

final class _SourceTextForm extends StatefulWidget {
  const _SourceTextForm({required this.placeholder, required this.submitLabel});

  final String placeholder;
  final String submitLabel;

  @override
  State<_SourceTextForm> createState() => _SourceTextFormState();
}

final class _SourceTextFormState extends State<_SourceTextForm> {
  late final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppTextField(
        key: const Key('source-url-input'),
        controller: controller,
        placeholder: widget.placeholder,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      AppButton(
        key: const Key('source-form-submit'),
        onPressed: _submit,
        expands: true,
        child: Text(widget.submitLabel),
      ),
    ],
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
        const Text('尚未导入音源', style: AppTypography.section),
        const SizedBox(height: 6),
        Text(
          '从本地选择 .js 音源文件，或通过 URL 导入。',
          style: AppTypography.body.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
      ],
    ),
  );
}
