import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'download_repository.dart';

final class DownloadsState {
  const DownloadsState({
    this.jobs = const [],
    this.loading = false,
    this.stale = false,
    this.error,
    this.bytesPerSecond = const {},
    this.lastBulkResult,
    this.clearingHistory = false,
  });

  final List<DownloadJob> jobs;
  final bool loading;
  final bool stale;
  final Object? error;
  final Map<String, double> bytesPerSecond;
  final BulkDownloadResult? lastBulkResult;
  final bool clearingHistory;
}

final class DownloadsController extends ChangeNotifier {
  DownloadsController(this.repository);

  final DownloadRepository repository;
  final Map<(String, String), Future<Uri?>> _pictures = {};
  DownloadsState state = const DownloadsState();
  Timer? _refreshTimer;
  DateTime? _sampledAt;
  Map<String, num> _sampledBytes = const {};
  Future<int>? _clearHistoryOperation;

  int get clearableHistoryCount => state.jobs
      .where(
        (job) =>
            job.status == DownloadStatus.completed ||
            job.status == DownloadStatus.error,
      )
      .length;

  Future<void> refresh() async {
    state = DownloadsState(
      jobs: state.jobs,
      loading: true,
      stale: state.stale,
      error: state.error,
      bytesPerSecond: state.bytesPerSecond,
      lastBulkResult: state.lastBulkResult,
      clearingHistory: state.clearingHistory,
    );
    notifyListeners();
    try {
      final jobs = await repository.list();
      final now = DateTime.now();
      final seconds = _sampledAt == null
          ? 0
          : now.difference(_sampledAt!).inMilliseconds / 1000;
      final speeds = <String, double>{};
      if (seconds > 0) {
        for (final job in jobs.where(
          (job) => job.status == DownloadStatus.running,
        )) {
          final previous = _sampledBytes[job.id];
          if (previous != null && job.downloaded >= previous) {
            speeds[job.id] = (job.downloaded - previous) / seconds;
          }
        }
      }
      _sampledAt = now;
      _sampledBytes = {for (final job in jobs) job.id: job.downloaded};
      state = DownloadsState(
        jobs: jobs,
        bytesPerSecond: speeds,
        clearingHistory: state.clearingHistory,
      );
    } on Object catch (error) {
      state = DownloadsState(
        jobs: state.jobs,
        stale: true,
        error: error,
        bytesPerSecond: state.bytesPerSecond,
        clearingHistory: state.clearingHistory,
      );
    }
    notifyListeners();
  }

  Future<void> start(String id) => _mutate(() => repository.start(id));
  Future<void> pause(String id) => _mutate(() => repository.pause(id));
  Future<void> resume(String id) => _mutate(() => repository.resume(id));
  Future<void> delete(String id) => _mutate(() => repository.delete(id));

  Future<int> clearHistory() =>
      _clearHistoryOperation ??= _performClearHistory().whenComplete(() {
        _clearHistoryOperation = null;
      });

  Future<int> _performClearHistory() async {
    state = DownloadsState(
      jobs: state.jobs,
      loading: state.loading,
      stale: state.stale,
      error: state.error,
      bytesPerSecond: state.bytesPerSecond,
      lastBulkResult: state.lastBulkResult,
      clearingHistory: true,
    );
    notifyListeners();
    try {
      final cleared = await repository.clearHistory();
      await refresh();
      return cleared;
    } finally {
      state = DownloadsState(
        jobs: state.jobs,
        loading: state.loading,
        stale: state.stale,
        error: state.error,
        bytesPerSecond: state.bytesPerSecond,
        lastBulkResult: state.lastBulkResult,
      );
      notifyListeners();
    }
  }

  Future<Uri?> loadPicture(Track track) {
    final embedded = Uri.tryParse(track.raw['pic'] as String? ?? '');
    if (embedded != null && embedded.scheme == 'https') {
      return Future.value(embedded);
    }
    return _pictures.putIfAbsent((track.source, track.id), () async {
      try {
        final resolved = Uri.tryParse(await repository.picture(track));
        if (resolved != null &&
            (resolved.scheme == 'http' || resolved.scheme == 'https')) {
          return resolved;
        }
      } on Object {
        // A missing catalog source must not hide an otherwise usable snapshot.
      }
      return embedded != null &&
              (embedded.scheme == 'http' || embedded.scheme == 'https')
          ? embedded
          : null;
    });
  }

  Future<BulkDownloadResult> pauseAll() async {
    final running = state.jobs
        .where((job) => job.canPause)
        .toList(growable: false);
    final succeeded = <String>[];
    final failures = <String, Object>{};
    for (final job in running) {
      try {
        await repository.pause(job.id);
        succeeded.add(job.id);
      } on Object catch (error) {
        failures[job.id] = error;
      }
    }
    await refresh();
    final result = BulkDownloadResult(
      succeededIds: List.unmodifiable(succeeded),
      failures: Map.unmodifiable(failures),
    );
    state = DownloadsState(
      jobs: state.jobs,
      loading: state.loading,
      stale: state.stale,
      error: state.error,
      bytesPerSecond: state.bytesPerSecond,
      lastBulkResult: result,
      clearingHistory: state.clearingHistory,
    );
    notifyListeners();
    return result;
  }

  Future<void> _mutate(Future<Object?> Function() action) async {
    await action();
    await refresh();
  }

  void invalidate() {
    state = DownloadsState(
      jobs: state.jobs,
      stale: true,
      error: state.error,
      bytesPerSecond: state.bytesPerSecond,
      lastBulkResult: state.lastBulkResult,
      clearingHistory: state.clearingHistory,
    );
    notifyListeners();
    _refreshTimer ??= Timer(Duration.zero, () {
      _refreshTimer = null;
      refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final class BulkDownloadResult {
  const BulkDownloadResult({
    required this.succeededIds,
    required this.failures,
  });

  final List<String> succeededIds;
  final Map<String, Object> failures;
  bool get hasFailures => failures.isNotEmpty;
}
