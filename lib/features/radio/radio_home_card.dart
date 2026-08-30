import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/app_button.dart';
import '../../design/design_tokens.dart';
import 'radio_controller.dart';

final class RadioHomeCard extends StatelessWidget {
  const RadioHomeCard({super.key, required this.controller});
  final RadioController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1180;
        final compact = constraints.maxWidth >= 720;
        final tokens = AppTokens.of(context);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.radioTower, size: 18, color: tokens.accent),
                const SizedBox(width: 8),
                Text(
                  'AI 随心听',
                  style: AppTypography.metadata.copyWith(color: tokens.accent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              wide ? '从此刻开始，一直播下去' : '听你此刻想听的',
              style: wide ? AppTypography.pageTitle : AppTypography.section,
            ),
            const SizedBox(height: 6),
            Text(
              '结合当前歌曲、收听时段与长期喜好；AI 不可用时自动切换本地推荐。',
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: tokens.foregroundSecondary,
              ),
            ),
            if (controller.state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                '暂时无法获取下一首，请稍后重试。',
                style: AppTypography.metadata.copyWith(color: tokens.danger),
              ),
            ],
            const SizedBox(height: 12),
            ShadSwitch(
              key: const Key('radio-auto-continuation'),
              value: controller.state.autoContinuation,
              onChanged: (value) =>
                  unawaited(controller.setAutoContinuation(value)),
              label: const Text('队列结束后自动续播'),
            ),
          ],
        );
        final action = AppButton(
          key: const Key('radio-start'),
          loading: controller.state.loading,
          onPressed: () => unawaited(controller.startDedicated()),
          leading: const Icon(LucideIcons.audioLines, size: 18),
          expands: !compact,
          child: Text(controller.state.session == null ? '开始随心听' : '重新开始'),
        );
        return Container(
          key: Key(
            wide
                ? 'radio-home-wide'
                : compact
                ? 'radio-home-compact'
                : 'radio-home-mobile',
          ),
          width: double.infinity,
          padding: EdgeInsets.all(wide ? 28 : 20),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.accent.withValues(alpha: .32)),
            borderRadius: BorderRadius.circular(AppRadii.panel),
            boxShadow: AppShadows.panel,
          ),
          child: compact
              ? Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 24),
                    action,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [content, const SizedBox(height: 18), action],
                ),
        );
      },
    ),
  );
}
