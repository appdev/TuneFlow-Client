import 'package:flutter/foundation.dart';

import 'source_repository.dart';

final class SourcesState {
  const SourcesState({
    this.items = const [],
    this.loading = false,
    this.saving = false,
    this.mutatingId,
    this.error,
  });

  final List<InstalledMusicSource> items;
  final bool loading;
  final bool saving;
  final String? mutatingId;
  final Object? error;

  List<InstalledMusicSource> get enabledSources =>
      [...items.where((item) => item.enabled)]
        ..sort((a, b) => a.priority!.compareTo(b.priority!));

  InstalledMusicSource? get primarySource => enabledSources.firstOrNull;
  List<InstalledMusicSource> get disabledSources =>
      items.where((item) => !item.enabled).toList(growable: false);
  InstalledMusicSource? get active => primarySource;
  String? get switchingId => mutatingId;

  SourcesState copyWith({
    List<InstalledMusicSource>? items,
    bool? loading,
    bool? saving,
    String? mutatingId,
    bool clearMutating = false,
    Object? error,
    bool clearError = false,
  }) => SourcesState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    mutatingId: clearMutating ? null : mutatingId ?? this.mutatingId,
    error: clearError ? null : error ?? this.error,
  );
}

final class SourcesController extends ChangeNotifier {
  SourcesController(this.repository);
  final SourceRepository repository;

  SourcesState state = const SourcesState();

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    notifyListeners();
    try {
      state = state.copyWith(items: await repository.list(), loading: false);
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
    notifyListeners();
  }

  Future<void> toggle(String id, bool enabled) async {
    final ids = state.enabledSources.map((item) => item.id).toList();
    if (enabled) {
      if (!ids.contains(id)) ids.add(id);
    } else {
      ids.remove(id);
    }
    await _saveOrder(ids, mutatingId: id);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final ids = state.enabledSources.map((item) => item.id).toList();
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final id = ids.removeAt(oldIndex);
    final target = newIndex.clamp(0, ids.length);
    ids.insert(target, id);
    await _saveOrder(ids, mutatingId: id);
  }

  Future<void> _saveOrder(
    List<String> ids, {
    required String mutatingId,
  }) async {
    if (state.saving) return;
    final previous = state.items;
    state = state.copyWith(
      items: _projectOrder(previous, ids),
      saving: true,
      mutatingId: mutatingId,
      clearError: true,
    );
    notifyListeners();
    try {
      state = state.copyWith(
        items: await repository.configureEnabled(ids),
        saving: false,
        clearMutating: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        items: previous,
        saving: false,
        error: error,
        clearMutating: true,
      );
      notifyListeners();
      try {
        state = state.copyWith(items: await repository.list(), error: error);
      } on Object {
        // Keep the rollback snapshot and the original mutation error.
      }
    }
    notifyListeners();
  }
}

List<InstalledMusicSource> _projectOrder(
  List<InstalledMusicSource> items,
  List<String> ids,
) {
  final byId = {for (final item in items) item.id: item};
  final enabled = <InstalledMusicSource>[];
  for (var index = 0; index < ids.length; index++) {
    final item = byId[ids[index]];
    if (item == null) continue;
    enabled.add(
      item.copyWith(active: index == 0, enabled: true, priority: index),
    );
  }
  final enabledIds = ids.toSet();
  return [
    ...enabled,
    for (final item in items)
      if (!enabledIds.contains(item.id))
        item.copyWith(active: false, enabled: false, clearPriority: true),
  ];
}
