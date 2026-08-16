import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../design/components/app_bottom_sheet.dart';
import 'download_repository.dart';
import 'user_download_coordinator.dart';

abstract interface class RedownloadConfirmation {
  Future<bool> confirm(BuildContext context, String message);
}

final class AppRedownloadConfirmation implements RedownloadConfirmation {
  const AppRedownloadConfirmation();

  @override
  Future<bool> confirm(BuildContext context, String message) async {
    if (!context.mounted) return false;
    return await AppBottomSheet.showActions<bool>(
          context,
          title: '重新下载',
          message: message,
          actions: const [AppBottomSheetAction(value: true, label: '确定')],
        ) ??
        false;
  }
}

final class AppUserDownloadCoordinator {
  const AppUserDownloadCoordinator({
    this.confirmation = const AppRedownloadConfirmation(),
  });

  final RedownloadConfirmation confirmation;

  Future<UserDownloadResult> create(
    BuildContext context,
    DownloadRepository repository,
    Track track,
    String quality, {
    Object? qualityList,
    String? listId,
  }) => UserDownloadCoordinator(repository).create(
    track,
    quality,
    qualityList: qualityList,
    listId: listId,
    confirmReplacement: (message) => confirmation.confirm(context, message),
  );
}
