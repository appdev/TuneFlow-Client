import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/components/app_bottom_sheet.dart';
import 'search_track_metadata.dart';
import 'track_action.dart';

bool get usesMobileTrackActions =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<void> showMobileTrackActions(
  BuildContext context, {
  required Track track,
  required SearchTrackMetadata metadata,
  required List<TrackAction> actions,
}) async {
  final message = [
    track.artist.trim(),
    metadata.qualityLabel?.trim() ?? '',
  ].where((value) => value.isNotEmpty).join(' · ');
  final selected = await AppBottomSheet.showMobileActionList<TrackActionId>(
    context,
    title: track.title.isEmpty ? track.id : track.title,
    message: message.isEmpty ? null : message,
    actions: [
      for (final action in actions)
        AppBottomSheetAction<TrackActionId>(
          key: Key('track-action-${action.id.name}'),
          value: action.id,
          label: action.disabledReason ?? action.label,
          enabled: action.enabled,
        ),
    ],
  );
  if (selected == null) return;
  await actions.firstWhere((action) => action.id == selected).invoke();
}

final class DesktopTrackActionsButton extends StatefulWidget {
  const DesktopTrackActionsButton({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<TrackAction> actions;
  final Widget Function(VoidCallback open) child;

  @override
  State<DesktopTrackActionsButton> createState() =>
      _DesktopTrackActionsButtonState();
}

final class _DesktopTrackActionsButtonState
    extends State<DesktopTrackActionsButton> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadPopover(
    key: const Key('desktop-track-action-popover'),
    controller: controller,
    popover: (_) => SizedBox(
      width: 230,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _actionItems(widget.actions, close: controller.hide),
      ),
    ),
    child: widget.child(controller.toggle),
  );
}

final class DesktopTrackContextRegion extends StatelessWidget {
  const DesktopTrackContextRegion({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<TrackAction> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShadContextMenuRegion(
    key: const Key('desktop-track-context-region'),
    constraints: const BoxConstraints(minWidth: 230),
    items: _actionItems(actions),
    child: child,
  );
}

List<Widget> _actionItems(List<TrackAction> actions, {VoidCallback? close}) =>
    actions
        .map(
          (action) => ShadContextMenuItem(
            key: Key('desktop-track-action-${action.id.name}'),
            enabled: action.enabled,
            leading: Icon(action.icon, size: 16),
            onPressed: action.enabled
                ? () {
                    close?.call();
                    unawaited(action.invoke());
                  }
                : null,
            child: Text(action.disabledReason ?? action.label),
          ),
        )
        .toList(growable: false);
