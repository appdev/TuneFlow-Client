import '../../api/models.dart';
import '../../api/service_exception.dart';
import 'download_repository.dart';

typedef ConfirmRedownload = Future<bool> Function(String message);

final class UserDownloadResult {
  const UserDownloadResult({this.job, required this.replaced});

  final DownloadJob? job;
  final bool replaced;
}

final class UserDownloadCoordinator {
  const UserDownloadCoordinator(this.repository);

  final DownloadRepository repository;

  Future<UserDownloadResult> create(
    Track track,
    String quality, {
    Object? qualityList,
    String? listId,
    required ConfirmRedownload confirmReplacement,
  }) async {
    try {
      final job = await repository.create(
        track,
        quality,
        qualityList: qualityList,
        listId: listId,
        existingFilePolicy: ExistingFilePolicy.error,
      );
      return UserDownloadResult(job: job, replaced: false);
    } on ServiceException catch (error) {
      if (error.code != 'DOWNLOAD_ALREADY_EXISTS') rethrow;
      if (!await confirmReplacement('重新下载成功后将替换现有文件。')) {
        return const UserDownloadResult(replaced: false);
      }
      final job = await repository.create(
        track,
        quality,
        qualityList: qualityList,
        listId: listId,
        existingFilePolicy: ExistingFilePolicy.replace,
      );
      return UserDownloadResult(job: job, replaced: true);
    }
  }
}
