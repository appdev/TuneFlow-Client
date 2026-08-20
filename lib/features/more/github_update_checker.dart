import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update.dart';

final class GitHubUpdateChecker implements UpdateChecker {
  GitHubUpdateChecker({
    required http.Client client,
    required Future<PackageInfo> Function() loadPackageInfo,
    Uri? endpoint,
  }) : _client = client,
       _loadPackageInfo = loadPackageInfo,
       endpoint =
           endpoint ??
           Uri.https(
             'api.github.com',
             '/repos/appdev/TuneFlow-Client/releases/latest',
           );

  final http.Client _client;
  final Future<PackageInfo> Function() _loadPackageInfo;
  final Uri endpoint;

  @override
  Future<UpdateCheckResult> check() async {
    try {
      final response = await _client.get(
        endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const UpdateCheckException();
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateCheckException();
      }
      final tagName = decoded['tag_name'];
      final htmlUrl = decoded['html_url'];
      if (tagName is! String ||
          tagName.trim().isEmpty ||
          htmlUrl is! String ||
          htmlUrl.trim().isEmpty) {
        throw const UpdateCheckException();
      }
      final releaseUri = Uri.tryParse(htmlUrl);
      if (releaseUri == null ||
          releaseUri.scheme != 'https' ||
          releaseUri.host.isEmpty) {
        throw const UpdateCheckException();
      }
      final latest = AppVersion.parse(tagName);
      final packageInfo = await _loadPackageInfo();
      final local = AppVersion.fromPackage(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
      );
      if (latest.isNewerThan(local)) {
        return UpdateAvailable(
          local: local,
          latest: latest,
          releaseUri: releaseUri,
        );
      }
      return UpToDate(local: local, latest: latest, releaseUri: releaseUri);
    } on Object {
      throw const UpdateCheckException();
    }
  }
}
