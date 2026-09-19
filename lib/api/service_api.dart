import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'service_exception.dart';
import 'service_origin.dart';

typedef ServiceHttpLog = void Function(String message);

void _defaultServiceHttpLog(String message) {
  developer.log(message, name: 'TuneFlow.HTTP');
}

String _safeUri(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri.toString();
  final redacted = <String, String>{
    for (final key in uri.queryParameters.keys) key: '<redacted>',
  };
  return uri.replace(queryParameters: redacted).toString();
}

String _safeError(Object error) => switch (error) {
  ServiceException(:final code) => code,
  _ => error.runtimeType.toString(),
};

final class ServiceApi {
  ServiceApi(ServiceOrigin origin, {http.Client? client, ServiceHttpLog? log})
    : _origin = origin,
      _client = client ?? http.Client(),
      _log = log ?? _defaultServiceHttpLog,
      _ownsClient = client == null;

  ServiceOrigin _origin;
  ServiceOrigin get origin => _origin;
  final http.Client _client;
  final ServiceHttpLog _log;
  final bool _ownsClient;

  void switchOrigin(ServiceOrigin next) {
    _origin = next;
  }

  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = origin.resolve(path);
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;

    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({'accept': 'application/json', ...?headers});
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    if (kDebugMode) {
      _log('[HTTP] --> $method ${_safeUri(uri)}');
      if (request.body.isNotEmpty) {
        _log('[HTTP] Request body omitted (${request.body.length} chars)');
      }
    }

    late http.StreamedResponse streamed;
    late String responseBody;
    try {
      streamed = await _client.send(request);
      responseBody = await streamed.stream.bytesToString();
    } on ServiceException catch (error) {
      if (kDebugMode) {
        _log(
          '[HTTP] xx> $method ${_safeUri(uri)} '
          'error=${_safeError(error)} duration=${stopwatch!.elapsedMilliseconds}ms',
        );
      }
      rethrow;
    } on Object catch (error) {
      if (kDebugMode) {
        _log(
          '[HTTP] xx> $method ${_safeUri(uri)} '
          'error=${_safeError(error)} duration=${stopwatch!.elapsedMilliseconds}ms',
        );
      }
      throw ServiceException(
        'NETWORK_ERROR',
        'Unable to reach the Service.',
        details: error.toString(),
      );
    }

    if (kDebugMode) {
      _log(
        '[HTTP] <-- $method ${_safeUri(uri)} '
        'status=${streamed.statusCode} '
        'duration=${stopwatch!.elapsedMilliseconds}ms '
        'bytes=${responseBody.length}',
      );
    }
    if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
      throw ServiceException(
        'REDIRECT_REJECTED',
        'Service redirects are not accepted.',
        status: streamed.statusCode,
      );
    }
    if (streamed.statusCode == 204) return null;

    Object? decoded;
    try {
      decoded = responseBody.isEmpty ? null : jsonDecode(responseBody);
    } on FormatException catch (error) {
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service returned invalid JSON.',
        status: streamed.statusCode,
        details: error.message,
      );
    }

    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      if (decoded is! Map || !decoded.containsKey('data')) {
        throw ServiceException(
          'INVALID_RESPONSE',
          'Service success response is missing the data envelope.',
          status: streamed.statusCode,
        );
      }
      return decoded['data'];
    }

    if (decoded is Map && decoded['error'] is Map) {
      final error = decoded['error'] as Map;
      final code = error['code'];
      final message = error['message'];
      if (code is String && message is String) {
        throw ServiceException(
          code,
          message,
          status: streamed.statusCode,
          details: error['details'],
        );
      }
    }
    throw ServiceException(
      'HTTP_ERROR',
      'Service request failed with HTTP ${streamed.statusCode}.',
      status: streamed.statusCode,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
