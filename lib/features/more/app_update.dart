import 'package:flutter/foundation.dart';

@immutable
final class AppVersion {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
  });

  factory AppVersion.parse(String input) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(input.trim());
    if (match == null) {
      throw FormatException('Unsupported app version', input);
    }
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: switch (match.group(4)) {
        final value? => int.parse(value),
        null => null,
      },
    );
  }

  factory AppVersion.fromPackage({
    required String version,
    required String buildNumber,
  }) {
    if (version.contains('+') || buildNumber.trim().isEmpty) {
      return AppVersion.parse(version);
    }
    final build = int.tryParse(buildNumber.trim());
    return AppVersion.parse(build == null ? version : '$version+$build');
  }

  final int major;
  final int minor;
  final int patch;
  final int? build;

  String get label => '$major.$minor.$patch${build == null ? '' : '+$build'}';

  bool isNewerThan(AppVersion installed) {
    final candidateCore = [major, minor, patch];
    final installedCore = [installed.major, installed.minor, installed.patch];
    for (var index = 0; index < candidateCore.length; index++) {
      if (candidateCore[index] != installedCore[index]) {
        return candidateCore[index] > installedCore[index];
      }
    }
    if (build == null) return false;
    return build! > (installed.build ?? 0);
  }
}

sealed class UpdateCheckResult {
  const UpdateCheckResult({
    required this.local,
    required this.latest,
    required this.releaseUri,
  });

  final AppVersion local;
  final AppVersion latest;
  final Uri releaseUri;
}

final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required super.local,
    required super.latest,
    required super.releaseUri,
  });
}

final class UpToDate extends UpdateCheckResult {
  const UpToDate({
    required super.local,
    required super.latest,
    required super.releaseUri,
  });
}

abstract interface class UpdateChecker {
  Future<UpdateCheckResult> check();
}

final class UpdateCheckException implements Exception {
  const UpdateCheckException([this.message = '暂时无法检查更新，请稍后重试。']);

  final String message;

  @override
  String toString() => message;
}
