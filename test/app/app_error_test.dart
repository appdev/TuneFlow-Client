import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/app/app_error.dart';

void main() {
  group('appErrorMessage', () {
    test('turns connection failures into actionable copy', () {
      expect(
        appErrorMessage(
          const ServiceException('NETWORK_ERROR', 'Unable to reach Service.'),
          fallback: '操作失败，请稍后重试。',
        ),
        '无法连接到 Service，请检查地址、网络和 Service 是否正在运行。',
      );
      expect(
        appErrorMessage(
          const ServiceException(
            'CONNECTION_TIMEOUT',
            'The Service did not respond in time.',
          ),
          fallback: '操作失败，请稍后重试。',
        ),
        '连接 Service 超时，请检查地址、端口和网络后重试。',
      );
    });

    test(
      'explains compatibility and server failures without raw exceptions',
      () {
        expect(
          appErrorMessage(
            const ServiceException(
              'INVALID_RESPONSE',
              'Service success response is missing the data envelope.',
            ),
            fallback: '加载失败，请稍后重试。',
          ),
          'Service 返回的数据无法识别，请确认客户端与 Service 版本兼容。',
        );
        expect(
          appErrorMessage(
            const ServiceException(
              'HTTP_ERROR',
              'Service request failed with HTTP 503.',
              status: 503,
            ),
            fallback: '加载失败，请稍后重试。',
          ),
          'Service 暂时不可用，请稍后重试。',
        );
      },
    );

    test('uses the caller fallback for unknown and non-service errors', () {
      expect(
        appErrorMessage(
          const ServiceException('SOURCE_UNAVAILABLE', 'internal details'),
          fallback: '当前音源不可用，请切换音源后重试。',
        ),
        '当前音源不可用，请切换音源后重试。',
      );
      expect(
        appErrorMessage(
          StateError('internal details'),
          fallback: '操作失败，请稍后重试。',
        ),
        '操作失败，请稍后重试。',
      );
    });

    test('summarizes exhausted source fallback without exposing details', () {
      expect(
        appErrorMessage(
          const ServiceException(
            'SOURCE_ALL_UNAVAILABLE',
            'internal source failure',
            details: {
              'attempts': [
                {'sourceId': 'a', 'code': 'SOURCE_TIMEOUT'},
                {'sourceId': 'b', 'code': 'SOURCE_NETWORK_ERROR'},
              ],
            },
          ),
          fallback: '播放失败',
        ),
        '已尝试 2 个音源，均网络不可用。',
      );
      expect(
        appErrorMessage(
          const ServiceException(
            'SOURCE_ALL_UNAVAILABLE',
            'do not expose me',
            details: {
              'attempts': [
                {'sourceId': 'a'},
                'invalid',
              ],
            },
          ),
          fallback: '播放失败',
        ),
        '已启用的音源当前均不可用，请稍后重试。',
      );
    });
  });
}
