import '../api/service_exception.dart';

String appErrorMessage(Object error, {required String fallback}) {
  if (error is! ServiceException) return fallback;

  return switch (error.code) {
    'INVALID_SERVICE_ORIGIN' => '请输入有效的 Service 地址，例如 http://127.0.0.1:3124。',
    'INVALID_SERVICE_PATH' => '请求地址无效，请重启应用后重试。',
    'NETWORK_ERROR' => '无法连接到 Service，请检查地址、网络和 Service 是否正在运行。',
    'CONNECTION_TIMEOUT' => '连接 Service 超时，请检查地址、端口和网络后重试。',
    'SERVICE_UNHEALTHY' => 'Service 当前不可用，请确认服务已正常启动后重试。',
    'UNSUPPORTED_API_VERSION' => 'Service 版本与当前客户端不兼容，请更新 Service 后重试。',
    'REDIRECT_REJECTED' => 'Service 地址发生了重定向，请填写最终的 Service 地址。',
    'INVALID_RESPONSE' => 'Service 返回的数据无法识别，请确认客户端与 Service 版本兼容。',
    'INVALID_STREAM_URL' => 'Service 返回了无效的播放地址，请切换音源或稍后重试。',
    'SOURCE_ALL_UNAVAILABLE' => _allSourcesUnavailableMessage(error.details),
    'HTTP_ERROR' => _httpErrorMessage(error.status, fallback),
    _ => fallback,
  };
}

String _allSourcesUnavailableMessage(Object? details) {
  final attempts = details is Map ? details['attempts'] : null;
  if (attempts is! List || attempts.isEmpty) {
    return '已启用的音源当前均不可用，请稍后重试。';
  }
  final valid = attempts.every(
    (attempt) =>
        attempt is Map &&
        attempt['sourceId'] is String &&
        attempt['code'] is String,
  );
  if (!valid) return '已启用的音源当前均不可用，请稍后重试。';
  return '已尝试 ${attempts.length} 个音源，均网络不可用。';
}

String _httpErrorMessage(int? status, String fallback) {
  if (status == 401 || status == 403) {
    return 'Service 拒绝了请求，请检查访问权限。';
  }
  if (status == 404) {
    return 'Service 未提供所需接口，请确认地址和版本。';
  }
  if (status != null && status >= 500) {
    return 'Service 暂时不可用，请稍后重试。';
  }
  return fallback;
}
