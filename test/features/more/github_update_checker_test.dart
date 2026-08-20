import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/features/more/app_update.dart';
import 'package:musicfree_service_client/features/more/github_update_checker.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<PackageInfo> packageInfo({
  String version = '1.0.4',
  String build = '5',
}) async => PackageInfo(
  appName: 'TuneFlow',
  packageName: 'musicfree_service_client',
  version: version,
  buildNumber: build,
);

void main() {
  test('requests and returns the latest GitHub release update', () async {
    late http.Request captured;
    final checker = GitHubUpdateChecker(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.5+6',
            'html_url': 'https://github.com/appdev/TuneFlow-Client/releases/1',
          }),
          200,
        );
      }),
      loadPackageInfo: packageInfo,
    );

    final result = await checker.check();

    expect(result, isA<UpdateAvailable>());
    expect(result.local.label, '1.0.4+5');
    expect(result.latest.label, '1.0.5+6');
    expect(captured.url.path, '/repos/appdev/TuneFlow-Client/releases/latest');
    expect(captured.headers['Accept'], 'application/vnd.github+json');
    expect(captured.headers['X-GitHub-Api-Version'], '2022-11-28');
  });

  test('same core release without build is up to date', () async {
    final checker = GitHubUpdateChecker(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.0.4',
            'html_url': 'https://github.com/appdev/TuneFlow-Client/releases/1',
          }),
          200,
        ),
      ),
      loadPackageInfo: packageInfo,
    );

    expect(await checker.check(), isA<UpToDate>());
  });

  group('rejects unsafe or invalid GitHub responses', () {
    final cases = <String, http.Response>{
      'non-success status': http.Response('{}', 403),
      'malformed JSON': http.Response('{', 200),
      'missing fields': http.Response(jsonEncode({'tag_name': 'v1.0.5'}), 200),
      'non-HTTPS release URL': http.Response(
        jsonEncode({
          'tag_name': 'v1.0.5',
          'html_url': 'http://github.com/appdev/TuneFlow-Client/releases/1',
        }),
        200,
      ),
      'invalid version': http.Response(
        jsonEncode({
          'tag_name': 'latest',
          'html_url': 'https://github.com/appdev/TuneFlow-Client/releases/1',
        }),
        200,
      ),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final checker = GitHubUpdateChecker(
          client: MockClient((_) async => entry.value),
          loadPackageInfo: packageInfo,
        );

        await expectLater(
          checker.check(),
          throwsA(isA<UpdateCheckException>()),
        );
      });
    }
  });

  test('converts transport failures to a safe update exception', () async {
    final checker = GitHubUpdateChecker(
      client: MockClient((_) async => throw StateError('private details')),
      loadPackageInfo: packageInfo,
    );

    await expectLater(
      checker.check(),
      throwsA(
        isA<UpdateCheckException>().having(
          (error) => error.message,
          'message',
          '暂时无法检查更新，请稍后重试。',
        ),
      ),
    );
  });
}
