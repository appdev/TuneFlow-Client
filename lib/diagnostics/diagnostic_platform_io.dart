import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

Future<DiagnosticLogStore?> openDiagnosticLogStore() async {
  final support = await getApplicationSupportDirectory();
  return FileDiagnosticLogStore(
    Directory('${support.path}${Platform.pathSeparator}diagnostics'),
  );
}

Future<Uint8List> compressDiagnosticPackage(String jsonl) =>
    Isolate.run(() => Uint8List.fromList(gzip.encode(utf8.encode(jsonl))));

final class FileDiagnosticLogStore implements DiagnosticLogStore {
  FileDiagnosticLogStore(this.directory);

  final Directory directory;
  static const maxFileBytes = 512 * 1024;
  File get _file =>
      File('${directory.path}${Platform.pathSeparator}recent.jsonl');
  File get _pending =>
      File('${directory.path}${Platform.pathSeparator}recent.pending');

  @override
  Future<String> read() async {
    if (!await _file.exists()) return '';
    if (await _file.length() > maxFileBytes) return '';
    // Bounded even if a file is externally changed between stat and read.
    final bytes = await _file
        .openRead(0, maxFileBytes)
        .fold<List<int>>(<int>[], (result, chunk) => result..addAll(chunk));
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> write(String jsonl) async {
    final bytes = utf8.encode(jsonl);
    if (bytes.length > maxFileBytes) throw StateError('Log snapshot too large');
    await directory.create(recursive: true);
    await _pending.writeAsBytes(bytes, flush: true);
    // Dart rename replaces an existing file on supported native platforms.
    await _pending.rename(_file.path);
  }
}
