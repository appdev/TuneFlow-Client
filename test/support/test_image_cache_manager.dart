import 'package:cached_network_image_ce/cached_network_image.dart';

final class TestImageCacheManager implements BaseCacheManager {
  TestImageCacheManager({this.cachedFile, this.fileStream});

  FileInfo? cachedFile;
  Stream<FileResponse>? fileStream;
  int emptyCacheCalls = 0;
  int disposeCalls = 0;
  int fileStreamCalls = 0;

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  Future<void> emptyCache() async => emptyCacheCalls++;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => cachedFile;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    fileStreamCalls++;
    final configured = fileStream;
    if (configured != null) return configured;
    final cached = cachedFile;
    return cached == null
        ? const Stream<FileResponse>.empty()
        : Stream<FileResponse>.value(cached);
  }

  @override
  Future<Never> putFile(
    String url,
    List<int> fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) => Future.error(UnsupportedError('putFile is not used by widget tests'));

  @override
  Future<void> removeFile(String key) async {}
}
