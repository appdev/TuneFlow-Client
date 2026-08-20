import '../../api/service_api.dart';
import '../../api/service_exception.dart';

const _autoDownloadOnPlayKey = 'player.autoDownloadOnPlay';
const _lanOriginKey = 'service.lanOrigin';
const _externalOriginKey = 'service.externalOrigin';

final class ServiceAccessOrigins {
  const ServiceAccessOrigins({
    required this.lanOrigin,
    required this.externalOrigin,
  });

  final String lanOrigin;
  final String externalOrigin;

  @override
  bool operator ==(Object other) =>
      other is ServiceAccessOrigins &&
      other.lanOrigin == lanOrigin &&
      other.externalOrigin == externalOrigin;

  @override
  int get hashCode => Object.hash(lanOrigin, externalOrigin);
}

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

  Future<ServiceAccessOrigins> getAccessOrigins() async =>
      _readAccessOrigins(await api.request('GET', '/api/v1/settings'));

  Future<ServiceAccessOrigins> updateAccessOrigins(
    ServiceAccessOrigins value,
  ) async => _readAccessOrigins(
    await api.request(
      'PATCH',
      '/api/v1/settings',
      body: {
        _lanOriginKey: value.lanOrigin,
        _externalOriginKey: value.externalOrigin,
      },
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

  ServiceAccessOrigins _readAccessOrigins(Object? value) {
    if (value case final Map data) {
      final lanOrigin = data[_lanOriginKey];
      final externalOrigin = data[_externalOriginKey];
      if (lanOrigin is String && externalOrigin is String) {
        return ServiceAccessOrigins(
          lanOrigin: lanOrigin,
          externalOrigin: externalOrigin,
        );
      }
    }
    throw const ServiceException(
      'INVALID_RESPONSE',
      'Service settings response is missing access origins.',
    );
  }
}
