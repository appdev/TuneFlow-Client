import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';

final class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.serviceHost,
    required this.onSources,
    required this.onSettings,
    required this.onDownloads,
    required this.onDisconnect,
  });

  final String serviceHost;
  final VoidCallback onSources;
  final VoidCallback onSettings;
  final VoidCallback onDownloads;
  final Future<void> Function() onDisconnect;

  Future<void> _disconnect(BuildContext context) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '断开当前 Service？',
      message: '将停止使用当前服务器，并返回连接页面。',
      cancelLabel: '取消',
      confirmLabel: '断开连接',
    );
    if (accepted) await onDisconnect();
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
          onTap: onDownloads,
        ),
        _MoreTile(title: '音源管理', onTap: onSources),
        _MoreTile(title: '设置', onTap: onSettings),
        _MoreTile(
          key: const Key('more-disconnect'),
          title: '断开当前 Service',
          onTap: () => unawaited(_disconnect(context)),
        ),
        Semantics(
          label: 'Service $serviceHost 已连接',
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
            onTap: onSettings,
          ),
        ),
      ],
    ),
  );
}

final class _MoreTile extends StatelessWidget {
  const _MoreTile({
    super.key,
    required this.title,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final VoidCallback onTap;
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
