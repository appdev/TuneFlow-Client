import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import 'about_screen.dart';
import 'app_update.dart';

final class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    required this.serviceHost,
    required this.onSources,
    required this.onSettings,
    required this.onDownloads,
    required this.onAbout,
    required this.updateChecker,
    required this.openExternalUri,
    required this.onDisconnect,
  });

  final String serviceHost;
  final VoidCallback onSources;
  final VoidCallback onSettings;
  final VoidCallback onDownloads;
  final VoidCallback onAbout;
  final UpdateChecker updateChecker;
  final ExternalUriOpener openExternalUri;
  final Future<void> Function() onDisconnect;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

final class _MoreScreenState extends State<MoreScreen> {
  var _checkingUpdate = false;

  Future<void> _disconnect(BuildContext context) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '断开当前 Service？',
      message: '将停止使用当前服务器，并返回连接页面。',
      cancelLabel: '取消',
      confirmLabel: '断开连接',
    );
    if (accepted) await widget.onDisconnect();
  }

  Future<void> _openRelease(Uri uri) async {
    try {
      if (await widget.openExternalUri(uri)) return;
    } on Object {
      // The platform-specific reason is intentionally hidden from UI feedback.
    }
    if (!mounted) return;
    showAppMessage(
      context,
      title: '无法打开下载页面',
      message: '请稍后重试，或前往 TuneFlow Client 项目查看 Release。',
      destructive: true,
    );
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final result = await widget.updateChecker.check();
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
      if (result case final UpdateAvailable available) {
        final open = await AppBottomSheet.showActions<bool>(
          context,
          title: '发现新版本',
          message:
              '当前版本 ${available.local.label}\n'
              '最新版本 ${available.latest.label}',
          cancelLabel: '稍后再说',
          actions: const [
            AppBottomSheetAction(
              key: Key('more-open-release'),
              value: true,
              label: '前往下载',
            ),
          ],
        );
        if (open == true) await _openRelease(available.releaseUri);
      } else {
        await AppBottomSheet.showActions<void>(
          context,
          title: '已是最新版本',
          message: '当前版本 ${result.local.label}',
          cancelLabel: '关闭',
          actions: const [AppBottomSheetAction(value: null, label: '知道了')],
        );
      }
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '检查更新失败',
        message: error.message,
        destructive: true,
      );
    } on Object {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '检查更新失败',
        message: '暂时无法检查更新，请稍后重试。',
        destructive: true,
      );
    } finally {
      if (mounted && _checkingUpdate) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('more-mobile-layout'),
    color: AppTokens.of(context).background,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 124),
      children: [
        const AppMobilePageHeader(
          title: '更多',
          actions: [AppStatusBadge(label: '已连接', tone: StatusTone.success)],
        ),
        const SizedBox(height: 24),
        _MoreTile(
          key: const Key('more-downloads'),
          title: '下载管理',
          onTap: widget.onDownloads,
        ),
        _MoreTile(title: '音源管理', onTap: widget.onSources),
        _MoreTile(
          key: const Key('more-settings'),
          title: '设置',
          onTap: widget.onSettings,
        ),
        _MoreTile(
          key: const Key('more-about'),
          title: '关于',
          onTap: widget.onAbout,
        ),
        _MoreTile(
          key: const Key('more-check-update'),
          title: _checkingUpdate ? '正在检查更新…' : '检查更新',
          onTap: _checkingUpdate ? null : () => unawaited(_checkForUpdate()),
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        _MoreTile(
          key: const Key('more-disconnect'),
          title: '断开当前 Service',
          onTap: () => unawaited(_disconnect(context)),
        ),
        Semantics(
          label: 'Service ${widget.serviceHost} 已连接',
          child: _MoreTile(
            title: 'Service 已连接',
            trailing: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTokens.of(context).success,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

final class _MoreTile extends StatelessWidget {
  const _MoreTile({super.key, required this.title, this.onTap, this.trailing});
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: AppTokens.of(context).surface,
      border: Border.all(color: AppTokens.of(context).border),
      borderRadius: BorderRadius.circular(AppRadii.compactCard),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.compactCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.title)),
              trailing ?? const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}
