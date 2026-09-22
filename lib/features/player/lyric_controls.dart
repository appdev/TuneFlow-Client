import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/design_tokens.dart';
import '../../storage/app_preferences.dart';
import 'player_state.dart';

final class LyricControls extends StatelessWidget {
  const LyricControls({
    super.key,
    required this.state,
    required this.onShowTranslation,
    required this.onShowRomanization,
    required this.onFontSize,
    required this.onAlignment,
    required this.onAuxiliaryOrder,
    required this.onUseTraditional,
    required this.onEmphasizeActive,
    required this.onOffset,
  });

  final PlayerState state;
  final ValueChanged<bool> onShowTranslation;
  final ValueChanged<bool> onShowRomanization;
  final ValueChanged<LyricFontSize> onFontSize;
  final ValueChanged<LyricAlignment> onAlignment;
  final ValueChanged<LyricAuxiliaryOrder> onAuxiliaryOrder;
  final ValueChanged<bool> onUseTraditional;
  final ValueChanged<bool> onEmphasizeActive;
  final ValueChanged<Duration> onOffset;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadSwitch(
          key: const Key('lyric-control-translation'),
          value: state.showTranslation,
          onChanged: onShowTranslation,
          label: const Text('显示翻译'),
        ),
        const SizedBox(height: AppSpacing.sm),
        ShadSwitch(
          key: const Key('lyric-control-traditional'),
          value: state.useTraditionalLyrics,
          onChanged: onUseTraditional,
          label: const Text('转换为繁体中文'),
        ),
        const SizedBox(height: AppSpacing.sm),
        ShadSwitch(
          key: const Key('lyric-control-emphasize-active'),
          value: state.emphasizeActiveLyric,
          onChanged: onEmphasizeActive,
          label: const Text('放大当前歌词'),
        ),
        const SizedBox(height: AppSpacing.sm),
        ShadSwitch(
          key: const Key('lyric-control-romanization'),
          value: state.showRomanization,
          onChanged: onShowRomanization,
          label: const Text('显示罗马音'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('歌词字号', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xs),
        _ChoiceRow<LyricFontSize>(
          selected: state.lyricFontSize,
          choices: const {
            LyricFontSize.small: '小',
            LyricFontSize.standard: '标准',
            LyricFontSize.large: '大',
          },
          onChanged: onFontSize,
          keyPrefix: 'lyric-font',
        ),
        const SizedBox(height: AppSpacing.md),
        Text('歌词对齐', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xs),
        _ChoiceRow<LyricAlignment>(
          selected: state.lyricAlignment,
          choices: const {
            LyricAlignment.adaptive: '跟随布局',
            LyricAlignment.left: '居左',
            LyricAlignment.center: '居中',
            LyricAlignment.right: '居右',
          },
          onChanged: onAlignment,
          keyPrefix: 'lyric-align',
        ),
        const SizedBox(height: AppSpacing.md),
        Text('辅助歌词顺序', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xs),
        _ChoiceRow<LyricAuxiliaryOrder>(
          selected: state.lyricAuxiliaryOrder,
          choices: const {
            LyricAuxiliaryOrder.translationFirst: '翻译优先',
            LyricAuxiliaryOrder.romanizationFirst: '罗马音优先',
            LyricAuxiliaryOrder.romanizationAbove: '罗马音在原文上方',
          },
          onChanged: onAuxiliaryOrder,
          keyPrefix: 'lyric-order',
        ),
        const SizedBox(height: AppSpacing.md),
        Text('当前歌曲偏移', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                key: const Key('lyric-offset-minus'),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => onOffset(
                  state.lyricOffset - const Duration(milliseconds: 100),
                ),
                child: const Text('-100ms'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: ShadButton.outline(
                key: const Key('lyric-offset-reset'),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => onOffset(Duration.zero),
                child: Text('${state.lyricOffset.inMilliseconds}ms'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: ShadButton.outline(
                key: const Key('lyric-offset-plus'),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: () => onOffset(
                  state.lyricOffset + const Duration(milliseconds: 100),
                ),
                child: const Text('+100ms'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

final class DesktopLyricSettingsPopover extends StatefulWidget {
  const DesktopLyricSettingsPopover({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopLyricSettingsPopover> createState() =>
      _DesktopLyricSettingsPopoverState();
}

final class _DesktopLyricSettingsPopoverState
    extends State<DesktopLyricSettingsPopover> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadPopover(
    controller: controller,
    popover: (_) => Padding(
      key: const Key('player-desktop-lyric-settings-popover'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: widget.child,
    ),
    child: Semantics(
      button: true,
      label: '歌词设置',
      child: ShadButton.ghost(
        key: const Key('player-desktop-lyric-settings'),
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        onPressed: controller.toggle,
        child: const Tooltip(
          message: '歌词设置',
          child: Icon(LucideIcons.settings2, size: 20),
        ),
      ),
    ),
  );
}

final class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.selected,
    required this.choices,
    required this.onChanged,
    required this.keyPrefix,
  });

  final T selected;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      for (final entry in choices.entries)
        ShadButton.outline(
          key: Key('$keyPrefix-${entry.key}'),
          height: 44,
          onPressed: () => onChanged(entry.key),
          child: Text(
            entry.value,
            style: TextStyle(
              fontWeight: entry.key == selected
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
    ],
  );
}
