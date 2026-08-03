// EngineClient — spawns `python -m app.engine.engine_cli SUBCOMMAND` and
// yields decoded JSON-lines events. Extracted from main.dart in Phase 2 so
// the shell + pages can consume it as a shared dependency.
//
// See docs/engine-protocol.md for the wire format.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class EngineClient {
  const EngineClient({this.python, this.cwd});

  final String? python;
  final String? cwd;

  Stream<Map<String, dynamic>> run(
    String subcommand, {
    required Map<String, dynamic> request,
  }) async* {
    final env = Platform.environment;
    final interpreter =
        python ?? env['COMPRESSTOR_ENGINE_PYTHON'] ?? 'python3';
    final workingDir =
        cwd ?? env['COMPRESSTOR_ENGINE_CWD'] ?? _defaultRepoRoot();

    final Process process;
    try {
      process = await Process.start(
        interpreter,
        ['-m', 'app.engine.engine_cli', subcommand],
        workingDirectory: workingDir,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      yield {'type': 'error', 'message': 'Cannot start engine: ${e.message}'};
      return;
    }

    process.stdin.writeln(jsonEncode(request));
    unawaited(process.stdin.close());

    yield* process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map<Map<String, dynamic>>((line) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'type': 'error', 'message': 'Non-object JSON line: $line'};
      } on FormatException {
        return {'type': 'error', 'message': 'Bad JSON line: $line'};
      }
    });

    await process.exitCode;
  }

  String _defaultRepoRoot() {
    final here = Directory.current.path;
    if (here.endsWith('/flutter') || here.endsWith(r'\flutter')) {
      return Directory(here).parent.path;
    }
    return here;
  }
}
