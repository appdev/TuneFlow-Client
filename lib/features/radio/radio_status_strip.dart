import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/design_tokens.dart';
import 'radio_controller.dart';
import 'radio_models.dart';

final class RadioStatusStrip extends StatelessWidget {
  const RadioStatusStrip({super.key, required this.controller});
  final RadioController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final session = controller.state.session;
      if (session == null) return const SizedBox.shrink();
      final label = switch (session.aiStatus) {
        RadioAiStatus.enhanced => 'AI 随心听',
        RadioAiStatus.profileOnly => '画像推荐',
        RadioAiStatus.local || RadioAiStatus.disabled => '本地推荐',
        RadioAiStatus.unavailable => '推荐已降级',
      };
      final tokens = AppTokens.of(context);
      return Semantics(
        button: true,
        label: '$label，停止随心听',
        child: Tooltip(
          message: '停止随心听',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: ShadButton.outline(
              key: const Key('radio-status-strip'),
              onPressed: () => unawaited(controller.stop()),
              leading: Icon(
                LucideIcons.radioTower,
                size: 16,
                color: tokens.accent,
              ),
              child: Text(label),
            ),
          ),
        ),
      );
    },
  );
}
