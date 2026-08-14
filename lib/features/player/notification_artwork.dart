import 'dart:io';

import 'package:flutter/services.dart';

const notificationPlaceholderAsset = 'assets/artwork/default_track_artwork.png';

Future<Uri> prepareNotificationPlaceholderArtwork({
  required Directory supportDirectory,
  AssetBundle? assetBundle,
}) async {
  final bytes = await (assetBundle ?? rootBundle).load(
    notificationPlaceholderAsset,
  );
  final directory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}notification-artwork',
  );
  await directory.create(recursive: true);
  final file = File(
    '${directory.path}${Platform.pathSeparator}default-track-artwork-v1.png',
  );
  await file.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
  return file.uri;
}
