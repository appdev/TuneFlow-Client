import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/catalog/catalog_track_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

final fixtureTrack = Track.fromJson({
  'id': 'track-1',
  'name': '真实歌曲',
  'singer': '真实歌手',
  'albumName': '真实专辑',
  'interval': '03:20',
  'source': 'kw',
});

const providers = [
  CatalogProvider(id: 'kw', name: '酷我', searchKinds: {CatalogSearchKind.track}),
];

void main() {
  testWidgets('desktop catalog list exposes search table behavior', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 1200,
          height: 320,
          child: CatalogTrackList(
            tracks: [fixtureTrack],
            page: 2,
            pageSize: 30,
            total: 31,
            providers: providers,
            aggregate: false,
            mobile: false,
            loadPicture: (_) async => null,
            onPlay: (_) {},
            onFavorite: (_) {},
            actionsFor: (_) => const [],
            onPage: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('catalog-track-kw-track-1')), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('共 31 首'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('mobile catalog list keeps title and accessible actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 360,
          height: 320,
          child: CatalogTrackList(
            tracks: [fixtureTrack],
            page: 1,
            pageSize: 30,
            total: 1,
            providers: providers,
            aggregate: false,
            mobile: true,
            loadPicture: (_) async => null,
            onPlay: (_) {},
            onFavorite: (_) {},
            actionsFor: (_) => const [],
            onMore: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('catalog-track-kw-track-1')), findsOneWidget);
    expect(find.text('真实歌曲'), findsOneWidget);
    expect(find.text('真实歌手'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-favorite-kw-track-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('catalog-more-kw-track-1')), findsOneWidget);
    expect(find.text('专辑'), findsNothing);
  });
}
