import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player_controller.dart';

final class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({
    super.key,
    required this.controller,
    required this.child,
  });
  final PlayerController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (event is! KeyDownEvent ||
          focused?.widget is EditableText ||
          focused?.findAncestorWidgetOfExactType<EditableText>() != null ||
          controller.state.current == null) {
        return KeyEventResult.ignored;
      }
      final keyboard = HardwareKeyboard.instance;
      final key = event.logicalKey;
      final modified = keyboard.isControlPressed || keyboard.isMetaPressed;
      Future<void>? operation;
      if (key == LogicalKeyboardKey.space &&
          !modified &&
          !keyboard.isAltPressed &&
          !keyboard.isShiftPressed) {
        operation =
            controller.state.playing || controller.state.isPlaybackLoading
            ? controller.pause()
            : controller.resume();
      } else if (modified && key == LogicalKeyboardKey.arrowLeft) {
        operation = controller.previous();
      } else if (modified && key == LogicalKeyboardKey.arrowRight) {
        operation = controller.next();
      } else if (modified && key == LogicalKeyboardKey.arrowUp) {
        operation = controller.setVolume(controller.state.volume + .05);
      } else if (modified && key == LogicalKeyboardKey.arrowDown) {
        operation = controller.setVolume(controller.state.volume - .05);
      }
      if (operation == null) return KeyEventResult.ignored;
      unawaited(
        operation.catchError((Object error) {
          // 播放控制器已经记录错误；快捷键不能产生未捕获的异步异常。
        }),
      );
      return KeyEventResult.handled;
    },
    child: child,
  );
}
