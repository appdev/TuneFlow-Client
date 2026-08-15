import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/events/event_coordinator.dart';

void main() {
  test('rejects stale sequence and targets resource invalidation', () {
    var sources = 0;
    var playlists = 0;
    var downloads = 0;
    var library = 0;
    final details = <String>[];
    final coordinator = EventCoordinator(
      invalidateSources: () => sources++,
      invalidatePlaylists: () => playlists++,
      invalidateDownloads: () => downloads++,
      invalidateLibrary: () => library++,
      invalidatePlaylistDetail: details.add,
    );

    coordinator.accept(
      const DomainEvent(type: 'playlists.updated', data: null, sequence: 4),
    );
    coordinator.accept(
      const DomainEvent(type: 'downloads.updated', data: null, sequence: 3),
    );
    coordinator.accept(
      const DomainEvent(
        type: 'playlist.updated',
        data: {'id': 'one'},
        sequence: 5,
      ),
    );

    expect(playlists, 2);
    expect(downloads, 0);
    expect(library, 0);
    expect(details, ['one']);
    expect(sources, 0);
    expect(coordinator.sequence, 5);
  });

  test('snapshot bootstrapping accepts only increasing events', () {
    var downloads = 0;
    final coordinator = EventCoordinator(
      invalidateSources: () {},
      invalidatePlaylists: () {},
      invalidateDownloads: () => downloads++,
      invalidateLibrary: () {},
      invalidatePlaylistDetail: (_) {},
    );

    coordinator.bootstrap(
      const EventSnapshot(
        sequence: 9,
        events: [
          DomainEvent(type: 'downloads.updated', data: null, sequence: 8),
          DomainEvent(type: 'downloads.updated', data: null, sequence: 8),
        ],
      ),
    );

    expect(downloads, 1);
    expect(coordinator.sequence, 9);
  });

  test('library and download events invalidate authoritative local music', () {
    var downloads = 0;
    var library = 0;
    final coordinator = EventCoordinator(
      invalidateSources: () {},
      invalidatePlaylists: () {},
      invalidateDownloads: () => downloads++,
      invalidateLibrary: () => library++,
      invalidatePlaylistDetail: (_) {},
    );

    coordinator.accept(
      const DomainEvent(type: 'library.updated', data: null, sequence: 1),
    );
    coordinator.accept(
      const DomainEvent(type: 'downloads.completed', data: null, sequence: 2),
    );
    coordinator.accept(
      const DomainEvent(type: 'downloads.updated', data: null, sequence: 1),
    );

    expect(library, 2);
    expect(downloads, 1);
  });

  test('source events invalidate source routes once per fresh event', () {
    var sources = 0;
    final coordinator = EventCoordinator(
      invalidateSources: () => sources++,
      invalidatePlaylists: () {},
      invalidateDownloads: () {},
      invalidateLibrary: () {},
      invalidatePlaylistDetail: (_) {},
    );

    coordinator.accept(
      const DomainEvent(type: 'sources.updated', data: null, sequence: 1),
    );
    coordinator.accept(
      const DomainEvent(type: 'sources.updated', data: null, sequence: 1),
    );

    expect(sources, 1);
  });
}
