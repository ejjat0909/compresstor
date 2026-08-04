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

import 'package:flutter/foundation.dart';

class EngineClient {
  EngineClient({this.python, this.cwd, this.environment});

  final String? python;
  final String? cwd;

  /// Extra environment variables merged over the inherited environment for
  /// the engine subprocess. Used by tests to isolate the engine's JSON
  /// stores (COMPRESSTOR_DATA_DIR) and to script a fake engine.
  final Map<String, String>? environment;

  Process? _process;

  /// Path to a bundled engine sidecar when running inside a packaged app.
  ///
  ///   macOS    `<Compresstor.app>/Contents/Resources/engine/engine_cli`
  ///   Windows  `<exe dir>\engine\engine_cli.exe`
  ///
  /// Returns null in development (`flutter run` / `flutter test`), where the
  /// engine is spawned as `python -m app.engine.engine_cli` from the repo.
  String? get _bundledEngine => bundledEngineFor(Platform.resolvedExecutable);

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
    final bundled = _bundledEngine;
    try {
      process = await Process.start(
        bundled ?? _interpreter,
        bundled == null
            ? ['-m', 'app.engine.engine_cli', subcommand]
            : [subcommand],
        workingDirectory: bundled == null ? _repoRoot : null,
        runInShell: false,
        environment: environment,
      );
    } on ProcessException catch (e) {
      yield {'type': 'error', 'message': 'Cannot start engine: ${e.message}'};
      yield {'type': exitEvent, 'exit': 1};
      return;
    }
    _process = process;

    // Send the request, then close stdin. addStream/close return a Future
    // that errors if the engine exited before reading (broken pipe), so we
    // catch it instead of leaking an unhandled SocketException — which happens
    // when the interpreter/cwd is wrong (e.g. an unpackaged .app where the
    // repo + .venv aren't discoverable). In that case we still drain stdout
    // below so the caller sees the process end gracefully.
    try {
      final requestBytes = utf8.encode('${jsonEncode(request)}\n');
      await process.stdin.addStream(Stream.value(requestBytes));
      await process.stdin.close();
    } catch (_) {
      // Engine exited before consuming stdin (missing module / bad
      // interpreter). Keep going — the stdout stream below ends promptly.
    }

    try {
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
      yield {'type': exitEvent, 'exit': exit};
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

/// Returns the bundled engine sidecar path for a packaged app, or null when
/// [executable] is not a packaged app (development / tests).
///
///   macOS    `<Compresstor.app>/Contents/Resources/engine/engine_cli`
///   Windows  `<exe dir>\engine\engine_cli.exe` (or `<exe dir>\Resources\engine\`)
///
/// Split out from EngineClient so it is unit-testable against a temp layout
/// without touching the real Platform.resolvedExecutable.
@visibleForTesting
String? bundledEngineFor(String executable) {
  if (executable.isEmpty) return null;
  if (Platform.isMacOS) {
    final idx = executable.indexOf('.app/Contents/MacOS');
    if (idx > 0) {
      final candidate = '${executable.substring(0, idx)}.app/Contents/'
          'Resources/engine/engine_cli';
      if (File(candidate).existsSync()) return candidate;
    }
  } else if (Platform.isWindows) {
    final dir = File(executable).parent.path;
    for (final c in [
      '$dir/engine/engine_cli.exe',
      '$dir/Resources/engine/engine_cli.exe',
    ]) {
      if (File(c).existsSync()) return c;
    }
  }
  return null;
}
