import 'package:flutter/foundation.dart';

String playbackPlatformFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'web';
  return switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'other',
  };
}

String currentPlaybackPlatform() =>
    playbackPlatformFor(isWeb: kIsWeb, platform: defaultTargetPlatform);
