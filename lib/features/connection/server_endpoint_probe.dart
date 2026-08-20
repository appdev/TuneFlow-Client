import '../../api/service_exception.dart';
import '../../api/service_origin.dart';

typedef HealthRequest = Future<Object?> Function(ServiceOrigin origin);
typedef ProbeDelay = Future<void> Function(Duration duration);

final class HealthSnapshot {
  const HealthSnapshot({
    required this.origin,
    required this.lanOrigin,
    required this.externalOrigin,
    required this.latency,
  });

  final ServiceOrigin origin;
  final ServiceOrigin? lanOrigin;
  final ServiceOrigin? externalOrigin;
  final Duration latency;
}

final class ProbeCancelledException implements Exception {
  const ProbeCancelledException();
}

final class ServerEndpointProbe {
  ServerEndpointProbe({
    required HealthRequest requestHealth,
    ProbeDelay? delay,
    this.timeout = const Duration(seconds: 3),
    this.retryInterval = const Duration(seconds: 2),
    this.maxAttempts = 3,
  }) : _requestHealth = requestHealth,
       _delay = delay ?? Future<void>.delayed;

  final HealthRequest _requestHealth;
  final ProbeDelay _delay;
  final Duration timeout;
  final Duration retryInterval;
  final int maxAttempts;

  Future<HealthSnapshot> probe(
    String value, {
    bool Function()? cancelled,
  }) async {
    final origin = ServiceOrigin.parse(value);
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      _throwIfCancelled(cancelled);
      final stopwatch = Stopwatch()..start();
      try {
        final response = await _requestHealth(
          origin,
        ).timeout(timeout, onTimeout: _timeout);
        stopwatch.stop();
        if (response is! Map || response['status'] != 'ok') {
          throw const ServiceException(
            'SERVICE_UNHEALTHY',
            'The configured Service is not healthy.',
          );
        }
        return HealthSnapshot(
          origin: origin,
          lanOrigin: _parseAdvertisedOrigin(response['lanOrigin']),
          externalOrigin: _parseAdvertisedOrigin(response['externalOrigin']),
          latency: stopwatch.elapsed,
        );
      } on ProbeCancelledException {
        rethrow;
      } on Object catch (error, stackTrace) {
        stopwatch.stop();
        lastError = error;
        lastStackTrace = stackTrace;
      }

      if (attempt + 1 < maxAttempts) {
        await _delay(retryInterval);
        _throwIfCancelled(cancelled);
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  static ServiceOrigin? _parseAdvertisedOrigin(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    try {
      return ServiceOrigin.parse(value);
    } on ServiceException {
      return null;
    }
  }

  static void _throwIfCancelled(bool Function()? cancelled) {
    if (cancelled?.call() ?? false) {
      throw const ProbeCancelledException();
    }
  }

  static Never _timeout() => throw const ServiceException(
    'CONNECTION_TIMEOUT',
    'The Service did not respond in time. Check the address and port.',
  );
}
