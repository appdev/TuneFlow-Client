import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/search/adaptive_track_actions.dart';
import 'package:musicfree_service_client/features/search/search_track_metadata.dart';
import 'package:musicfree_service_client/features/search/track_action.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('mobile track actions use the shared ActionSheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <TrackActionId>[];
    final track = Track.fromJson({
      'id': 'one',
      'name': 'One',
      'singer': 'Artist',
      'source': 'kw',
      'types': ['flac'],
    });
    final actions = TrackActionId.values
        .map(
          (id) => TrackAction(
            id: id,
            label: id.name,
            icon: LucideIcons.music,
            invoke: () async => calls.add(id),
          ),
        )
        .toList();
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => showMobileTrackActions(
                context,
                track: track,
                metadata: SearchTrackMetadata.fromTrack(track),
                actions: actions,
              ),
              child: const Text('打开'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    for (final id in TrackActionId.values) {
      expect(find.byKey(Key('track-action-${id.name}')), findsOneWidget);
    }

    expect(find.byKey(const Key('app-action-sheet-actions')), findsOneWidget);
    expect(
      find.byKey(const Key('app-action-sheet-cancel-group')),
      findsOneWidget,
    );
    expect(find.byType(ShadSheet), findsNothing);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Artist · 无损'), findsOneWidget);

    await tester.tap(find.byKey(const Key('track-action-playNow')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-action-sheet-actions')), findsNothing);
    expect(calls, [TrackActionId.playNow]);
  });
}
