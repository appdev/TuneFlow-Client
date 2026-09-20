import 'dart:typed_data';

import 'app_logger.dart';

Future<DiagnosticLogStore?> openDiagnosticLogStore() async => null;
Future<Uint8List> compressDiagnosticPackage(String jsonl) async =>
    throw UnsupportedError('Native diagnostics only');
