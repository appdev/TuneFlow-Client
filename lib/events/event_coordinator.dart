import '../api/models.dart';

final class EventCoordinator {
  EventCoordinator({
    required this.invalidateSources,
    required this.invalidatePlaylists,
    required this.invalidateDownloads,
    required this.invalidateLibrary,
    required this.invalidatePlaylistDetail,
    this.trackResourcesUpdated,
  });

  final void Function() invalidateSources;
  final void Function() invalidatePlaylists;
  final void Function() invalidateDownloads;
  final void Function() invalidateLibrary;
  final void Function(String id) invalidatePlaylistDetail;
  final void Function(String source, String trackId, Set<String> resources)?
  trackResourcesUpdated;
  int sequence = 0;

  bool accept(DomainEvent event) {
    if (event.sequence <= sequence) return false;
    sequence = event.sequence;
    if (event.type.startsWith('sources.')) invalidateSources();
    if (event.type.startsWith('playlists.')) invalidatePlaylists();
    if (event.type.startsWith('downloads.')) invalidateDownloads();
    if (event.type.startsWith('library.')) invalidateLibrary();
    if (event.type == 'track.resources.updated') {
      final data = event.data;
      if (data is Map &&
          data['resources'] is List &&
          data['source'] is String &&
          data['trackId'] is String) {
        final resources = (data['resources']! as List)
            .whereType<String>()
            .where((resource) => resource == 'lyrics' || resource == 'picture')
            .toSet();
        if (resources.isNotEmpty) {
          trackResourcesUpdated?.call(
            data['source']! as String,
            data['trackId']! as String,
            resources,
          );
        }
      }
    }
    if (event.type.startsWith('playlist.')) {
      invalidatePlaylists();
      final data = event.data;
      if (data is Map && data['id'] is String) {
        invalidatePlaylistDetail(data['id']! as String);
      } else {
        invalidatePlaylists();
      }
    }
    return true;
  }

  void bootstrap(EventSnapshot snapshot) {
    final events = [...snapshot.events]
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    for (final event in events) {
      accept(event);
    }
    if (snapshot.sequence > sequence) sequence = snapshot.sequence;
  }
}
