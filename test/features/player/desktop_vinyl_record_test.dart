import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/desktop_vinyl_record.dart';
import 'package:musicfree_service_client/features/player/vinyl_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('desktop vinyl keeps its groove texture visually subordinate', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp.custom(
        theme: buildDarkTheme(),
        appBuilder: (context) => MaterialApp(
          theme: Theme.of(context),
          home: const Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 400,
                child: DesktopVinylRecord(
                  source: AppArtworkSource.fallback(fallbackSeed: 'kw:vinyl'),
                  seed: 'kw:vinyl',
                  semanticLabel: '唱片封面',
                  rotating: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<VinylGroovesPainter>()
        .single;

    expect(painter.grooveColor.a, lessThanOrEqualTo(.12));
    expect(painter.highlightColor.a, lessThanOrEqualTo(.16));
  });
}
