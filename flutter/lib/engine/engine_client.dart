// EngineClient — spawns the Python engine CLI and yields decoded JSON-lines
// events. See docs/engine-protocol.md for the wire format.
//
// Phase 3 additions over the Phase 2 skeleton:
//   - Auto-discovers the repo's `.venv` interpreter + working directory (so
//     `flutter run` works without env vars and without relying on whichever
//     `python3` is on PATH, which may lack PyMuPDF/Pillow).
//   - Exposes [cancel] so the dashboard can terminate a running batch
//     (SIGTERM on macOS/Linux; hard kill on Windows).
//   - Emits a synthetic `{'type': '__exit', 'exit': N}` event after EOF so
//     callers can distinguish normal (0), cancelled (2) and fatal (1) runs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class EngineClient {
  EngineClient({this.python, this.cwd});

  final String? python;
  final String? cwd;

  Process? _process;

  static const String exitEvent = '__exit';
  static const int exitCancelled = 2;

  /// The python interpreter to use. Priority:
  ///   1. explicit [python] arg
  ///   2. COMPRESSTOR_ENGINE_PYTHON env
  ///   3. `<repoRoot>/.venv/bin/python` (sig/linux) or `.venv/Scripts/python.exe` (win)
  ///   4. `python3`
  String get _interpreter {
    final env = Platform.environment;
    if (python != null) return python!;
    final envPy = env['COMPRESSTOR_ENGINE_PYTHON'];
    if (envPy != null && envPy.isNotEmpty) return envPy;
    final root = _repoRoot;
    final venvPy = Platform.isWindows
        ? '$root/.venv/Scripts/python.exe'
        : '$root/.venv/bin/python';
    if (File(venvPy).existsSync()) return venvPy;
    return 'python3';
  }

  String get _repoRoot {
    if (cwd != null) return cwd!;
    final envCwd = Platform.environment['COMPRESSTOR_ENGINE_CWD'];
    if (envCwd != null && envCwd.isNotEmpty) return envCwd;
    return _discoverRepoRoot();
  }

  static String _discoverRepoRoot() {
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}/app/engine/engine_cli.py').existsSync()) {
        return dir.path;
      }
      if (Directory('${dir.path}/.venv').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current.path;
  }

  /// Runs one engine subcommand with *request*, yielding decoded events.
  ///
  /// A synthetic `{'type':'__exit__','exit':N}` event is appended after the
  /// process completes so callers can react to success (0) vs cancellation (2).
  Stream<Map<String, dynamic>> run(
    String subcommand, {
    required Map<String, dynamic> request,
  }) async* {
    final Process process;
    try {
      process = await Process.start(
        _interpreter,
        ['-m', 'app.engine.engine_cli', subcommand],
        workingDirectory: _repoRoot,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      yield {'type': 'error', 'message': 'Cannot start engine: ${e.message}'};
      yield {'type': exitCode, 'exit': 1};
      return;
    }
    _process = process;

    try {
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
              return {
                'type': 'error',
                'message': 'Non-object JSON line: $line',
              };
            } on FormatException {
              return {'type': 'error', 'message': 'Bad JSON line: $line'};
            }
          });

      final exit = await process.exitCode;
      yield {'type': exitCode, 'exit': exit};
    } finally {
      _process = null;
    }
  }

  /// Signals the running process to stop. On Unix this is SIGTERM (the engine
  /// checks a flag between files and exits with code 2); Windows has no
  /// SIGTERM so we hard-kill.
  Future<void> cancel() async {
    final p = _process;
    if (p == null) return;
    if (Platform.isWindows) {
      p.kill(ProcessSignal.sigkill);
    } else {
      p.kill(ProcessSignal.sigterm);
    }
  }
}
