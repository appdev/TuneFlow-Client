import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/app_breakpoints.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/design_tokens.dart';
import 'app_update.dart';

typedef AppPackageInfoLoader = Future<PackageInfo> Function();
typedef ExternalUriOpener = Future<bool> Function(Uri uri);

final class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.loadPackageInfo,
    required this.openExternalUri,
    this.onBack,
  });

  static final clientRepository = Uri.parse(
    'https://github.com/appdev/TuneFlow-Client',
  );
  static final serviceRepository = Uri.parse(
    'https://github.com/appdev/TuneFlow',
  );

  final AppPackageInfoLoader loadPackageInfo;
  final ExternalUriOpener openExternalUri;
  final VoidCallback? onBack;

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      if (await openExternalUri(uri)) return;
    } on Object {
      // The user-facing fallback below is intentionally platform-agnostic.
    }
    if (!context.mounted) return;
    showAppMessage(
      context,
      title: '无法打开链接',
      message: '请稍后重试，或复制项目地址到浏览器打开。',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTokens.of(context).background,
    child: ListView(
      key: const Key('about-screen'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 124),
      children: [
        AppMobilePageHeader(
          title: '关于',
          eyebrow: '项目与版本',
          onBack:
              classifyLayout(MediaQuery.sizeOf(context)) ==
                  AppLayoutClass.mobile
              ? onBack
              : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        _AboutCard(
          child: Column(
            children: [
              Image.asset(
                'assets/branding/TuneFlow.png',
                width: 72,
                height: 72,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('TuneFlow · 音流', style: AppTypography.section),
              const SizedBox(height: AppSpacing.xs),
              FutureBuilder<PackageInfo>(
                future: loadPackageInfo(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      '版本读取失败',
                      style: AppTypography.metadata.copyWith(
                        color: AppTokens.of(context).muted,
                      ),
                    );
                  }
                  final info = snapshot.data;
                  if (info == null) {
                    return const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final version = AppVersion.fromPackage(
                    version: info.version,
                    buildNumber: info.buildNumber,
                  );
                  return Text(
                    '版本 ${version.label}',
                    style: AppTypography.metadata.copyWith(
                      color: AppTokens.of(context).muted,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _AboutCard(
          child: Text(
            'TuneFlow 是面向桌面与移动设备的跨平台音乐客户端。它连接自托管的 TuneFlow Service，把音乐发现、收藏、歌单、下载与播放集中在一致而安静的体验中。客户端本身不提供音乐内容。',
            style: AppTypography.body,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AboutCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _AboutLink(
                key: const Key('about-client-repository'),
                title: 'TuneFlow Client',
                uri: clientRepository,
                onTap: () => unawaited(_open(context, clientRepository)),
              ),
              Divider(height: 1, color: AppTokens.of(context).border),
              _AboutLink(
                key: const Key('about-service-repository'),
                title: 'TuneFlow Service',
                uri: serviceRepository,
                onTap: () => unawaited(_open(context, serviceRepository)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AboutCard(
          child: Text(
            'TuneFlow 用于个人学习与自托管场景。请遵守所在地法律法规，尊重音乐版权，并妥善保护自己的服务地址与数据。',
            style: AppTypography.body.copyWith(
              color: AppTokens.of(context).foregroundSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppTokens.of(context).surface,
      border: Border.all(color: AppTokens.of(context).border),
      borderRadius: BorderRadius.circular(AppRadii.compactCard),
    ),
    child: child,
  );
}

final class _AboutLink extends StatelessWidget {
  const _AboutLink({
    super.key,
    required this.title,
    required this.uri,
    required this.onTap,
  });

  final String title;
  final Uri uri;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '打开$title 项目地址',
    child: Tooltip(
      message: '在浏览器中打开$title',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.compactCard),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.title),
                        const SizedBox(height: 3),
                        Text(
                          uri.toString(),
                          style: AppTypography.metadata.copyWith(
                            color: AppTokens.of(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(LucideIcons.externalLink, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
