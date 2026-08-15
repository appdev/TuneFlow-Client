import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/playback_history/playback_platform.dart';

void main() {
  test('maps web and every supported native target to the Service enum', () {
    expect(
      playbackPlatformFor(isWeb: true, platform: TargetPlatform.android),
      'web',
    );
    expect(
      {
        for (final platform in TargetPlatform.values)
          platform: playbackPlatformFor(isWeb: false, platform: platform),
      },
      {
        TargetPlatform.android: 'android',
        TargetPlatform.iOS: 'ios',
        TargetPlatform.macOS: 'macos',
        TargetPlatform.windows: 'windows',
        TargetPlatform.linux: 'linux',
        TargetPlatform.fuchsia: 'other',
      },
    );
  });
}
