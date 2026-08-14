import '../../api/service_api.dart';
import '../../api/service_exception.dart';

const _autoDownloadOnPlayKey = 'player.autoDownloadOnPlay';

final class ServiceSettingsRepository {
  const ServiceSettingsRepository(this.api);

  final ServiceApi api;

  Future<bool> getAutoDownloadOnPlay() async =>
      _readBoolean(await api.request('GET', '/api/v1/settings'));

  Future<bool> setAutoDownloadOnPlay(bool value) async => _readBoolean(
    await api.request(
      'PATCH',
      '/api/v1/settings',
      body: {_autoDownloadOnPlayKey: value},
    ),
  );

  bool _readBoolean(Object? value) {
    if (value case final Map data) {
      final setting = data[_autoDownloadOnPlayKey];
      if (setting is bool) return setting;
    }
    throw const ServiceException(
      'INVALID_RESPONSE',
      'Service settings response is missing player.autoDownloadOnPlay.',
    );
  }
}
