import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/design_tokens.dart';
import '../../diagnostics/diagnostic_reporter.dart';

final class DiagnosticsCard extends StatelessWidget {
  const DiagnosticsCard({super.key, this.reporter, this.serviceOrigin});

  final DiagnosticReporter? reporter;
  final String? serviceOrigin;

  @override
  Widget build(BuildContext context) {
    final value = reporter;
    if (value == null) return _content(context);
    return ListenableBuilder(
      listenable: value,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final tokens = AppTokens.of(context);
    final value = reporter;
    final available = value?.available ?? false;
    return Container(
      key: const Key('settings-diagnostics'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('帮助与诊断', style: AppTypography.section),
          const SizedBox(height: 8),
          Text(
            '日志仅保存在本机。遇到问题时，可主动上传最近的诊断日志。',
            style: AppTypography.metadata.copyWith(color: tokens.muted),
          ),
          if (!available) ...[
            const SizedBox(height: 8),
            const Text('此版本暂未启用日志上传。', key: Key('diagnostics-unavailable')),
          ],
          const SizedBox(height: 16),
          AppButton(
            key: const Key('diagnostics-upload'),
            variant: ShadButtonVariant.outline,
            leading: const Icon(LucideIcons.upload, size: 18),
            loading: value?.busy ?? false,
            onPressed: available
                ? () => unawaited(
                    value!.submit(
                      serviceOrigin: serviceOrigin,
                      confirm: (package) => _confirm(context, package),
                    ),
                  )
                : null,
            child: Text(value?.busy == true ? '正在处理诊断包…' : '上传日志'),
          ),
          if (value?.errorMessage case final message?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                key: const Key('diagnostics-error'),
                style: TextStyle(color: tokens.danger),
              ),
            ),
          ],
          if (value?.eventId case final id?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: const Text('已发送到 Sentry。反馈问题时请附上报告编号：'),
            ),
            const SizedBox(height: 8),
            SelectableText(id, key: const Key('diagnostics-event-id')),
            const SizedBox(height: 8),
            AppButton(
              variant: ShadButtonVariant.outline,
              onPressed: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: id))),
              child: const Text('复制报告编号'),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, DiagnosticPackage package) async {
    if (!context.mounted) return false;
    return await AppBottomSheet.showContent<bool>(
          context,
          title: '上传诊断日志？',
          child: Builder(
            builder: (dialogContext) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '最近 ${package.entryCount} 条日志 · 压缩后 ${(package.bytes.length / 1024).toStringAsFixed(1)} KB',
                ),
                const SizedBox(height: 12),
                const Text(
                  '将发送到 TuneFlow 的 Sentry 项目，仅项目维护者可查看。包含应用版本、平台、错误代码、代码位置和操作结果。',
                ),
                if (package.serviceHost case final host?) ...[
                  const SizedBox(height: 8),
                  Text('同时包含当前 Service 主机和端口：$host'),
                ],
                const SizedBox(height: 8),
                const Text('不包含请求正文、凭据、搜索词、歌曲名称或本地文件路径。不会自动上传或自动重试。'),
                const SizedBox(height: 20),
                AppButton(
                  key: const Key('diagnostics-confirm-upload'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('同意并上传'),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const Key('diagnostics-cancel-upload'),
                  variant: ShadButtonVariant.outline,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }
}
