import 'package:flutter/foundation.dart';

import 'service_settings_repository.dart';

final class ServiceFunctionSettingsState {
  const ServiceFunctionSettingsState({
    this.saved,
    this.draft,
    this.loading = false,
    this.saving = false,
    this.testingMusicBrainz = false,
    this.musicBrainzTest,
    this.testingAi = false,
    this.aiTest,
    this.error,
  });

  final ServiceFunctionSettings? saved;
  final ServiceFunctionSettings? draft;
  final bool loading;
  final bool saving;
  final bool testingMusicBrainz;
  final MusicBrainzConnectionTestResult? musicBrainzTest;
  final bool testingAi;
  final AiConnectionTestResult? aiTest;
  final Object? error;

  bool get dirty => saved != null && draft != null && saved != draft;

  ServiceFunctionSettingsState copyWith({
    ServiceFunctionSettings? saved,
    ServiceFunctionSettings? draft,
    bool? loading,
    bool? saving,
    bool? testingMusicBrainz,
    MusicBrainzConnectionTestResult? musicBrainzTest,
    bool clearMusicBrainzTest = false,
    bool? testingAi,
    AiConnectionTestResult? aiTest,
    bool clearAiTest = false,
    Object? error,
    bool clearError = false,
  }) => ServiceFunctionSettingsState(
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    testingMusicBrainz: testingMusicBrainz ?? this.testingMusicBrainz,
    musicBrainzTest: clearMusicBrainzTest
        ? null
        : musicBrainzTest ?? this.musicBrainzTest,
    testingAi: testingAi ?? this.testingAi,
    aiTest: clearAiTest ? null : aiTest ?? this.aiTest,
    error: clearError ? null : error ?? this.error,
  );
}

final class ServiceFunctionSettingsController extends ChangeNotifier {
  ServiceFunctionSettingsController(this.repository);

  final ServiceSettingsRepository repository;
  ServiceFunctionSettingsState state = const ServiceFunctionSettingsState();
  bool _disposed = false;

  Future<void> load() async {
    if (state.loading || state.saving) return;
    state = state.copyWith(loading: true, clearError: true);
    _notify();
    try {
      final value = await repository.getFunctionSettings();
      if (_disposed) return;
      state = ServiceFunctionSettingsState(saved: value, draft: value);
    } on Object catch (error) {
      if (_disposed) return;
      state = ServiceFunctionSettingsState(error: error);
    }
    _notify();
  }

  void update(ServiceFunctionSettings value) {
    if (_disposed || state.saving) return;
    state = state.copyWith(
      draft: value,
      clearError: true,
      clearMusicBrainzTest: true,
    );
    _notify();
  }

  void reset() {
    final saved = state.saved;
    if (saved == null || state.saving) return;
    state = state.copyWith(draft: saved, clearError: true);
    _notify();
  }

  Future<bool> save() async {
    final value = state.draft;
    if (value == null || state.saving) return false;
    state = state.copyWith(saving: true, clearError: true);
    _notify();
    try {
      final confirmed = await repository.updateFunctionSettings(value);
      if (_disposed) return true;
      state = ServiceFunctionSettingsState(saved: confirmed, draft: confirmed);
      _notify();
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(saving: false, error: error);
        _notify();
      }
      return false;
    }
  }

  Future<MusicBrainzConnectionTestResult?> testMusicBrainzConnection(
    String baseUrl,
  ) async {
    if (_disposed || state.testingMusicBrainz || state.saving) return null;
    state = state.copyWith(
      testingMusicBrainz: true,
      clearError: true,
      clearMusicBrainzTest: true,
    );
    _notify();
    try {
      final result = await repository.testMusicBrainzConnection(baseUrl);
      if (_disposed) return result;
      final draft = state.draft;
      state = state.copyWith(
        draft: result.ok && draft != null
            ? draft.copyWith(musicBrainzBaseUrl: result.normalizedBaseUrl)
            : draft,
        testingMusicBrainz: false,
        musicBrainzTest: result,
      );
      _notify();
      return result;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(testingMusicBrainz: false, error: error);
        _notify();
      }
      return null;
    }
  }

  Future<AiConnectionTestResult?> testAiConnection() async {
    if (_disposed || state.testingAi || state.saving) return null;
    state = state.copyWith(
      testingAi: true,
      clearError: true,
      clearAiTest: true,
    );
    _notify();
    try {
      final result = await repository.testRecommendationAiConnection();
      if (!_disposed) {
        state = state.copyWith(testingAi: false, aiTest: result);
        _notify();
      }
      return result;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(testingAi: false, error: error);
        _notify();
      }
      return null;
    }
  }

  Future<bool> reanalyzeAi() async {
    if (_disposed || state.testingAi || state.saving) return false;
    state = state.copyWith(testingAi: true, clearError: true);
    _notify();
    try {
      await repository.reanalyzeRecommendationAi();
      if (!_disposed) {
        state = state.copyWith(testingAi: false);
        _notify();
      }
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(testingAi: false, error: error);
        _notify();
      }
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
