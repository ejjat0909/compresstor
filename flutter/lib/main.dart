// Compresstor — Flutter frontend spike (Phase 0).
//
// The "hello world" harness that proves Option A (CLI subprocess) end-to-end
// per docs/adr/0001-flutter-frontend-transport.md: spawn engine_cli.py,
// write a JSON request, read JSON-lines events, render progress + result.
//
// A real UI comes in Phase 2+. Everything here is throwaway wiring except
// [EngineClient], which is designed to survive into the real app.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const CompresstorApp());
}

class CompresstorApp extends StatelessWidget {
  const CompresstorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compresstor',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF3B82F6),
      ),
      home: const SpikeHomePage(),
    );
  }
}

/// Spawns `python -m app.engine.engine_cli SUBCOMMAND` in the repo root and
/// yields one decoded JSON event per line of stdout. Fatal issues surface as
/// synthetic `{type: "error", message: ...}` events so the UI has one shape
/// to handle.
///
/// Overrides (env vars, useful for dev):
///   COMPRESSTOR_ENGINE_PYTHON  — interpreter path (default: `python3`)
///   COMPRESSTOR_ENGINE_CWD     — repo root (default: parent of cwd when the
///                                app is launched from `<repo>/flutter`)
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

class SpikeHomePage extends StatefulWidget {
  const SpikeHomePage({super.key});

  @override
  State<SpikeHomePage> createState() => _SpikeHomePageState();
}

class _SpikeHomePageState extends State<SpikeHomePage> {
  final _pathCtl = TextEditingController();
  final _events = <Map<String, dynamic>>[];
  bool _running = false;
  double _fraction = 0;
  String _status = 'Idle';

  @override
  void dispose() {
    _pathCtl.dispose();
    super.dispose();
  }

  Future<void> _runCompress() async {
    final path = _pathCtl.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Enter a file path first.');
      return;
    }
    setState(() {
      _events.clear();
      _fraction = 0;
      _running = true;
      _status = 'Spawning engine…';
    });

    const client = EngineClient();
    final stream = client.run(
      'compress',
      request: {
        'items': [
          {'path': path},
        ],
        'options': {
          'level': 'balanced',
          'output_mode': 'suffix',
          'suffix': '_compressed',
        },
        'add_to_history': false,
      },
    );

    await for (final event in stream) {
      if (!mounted) return;
      setState(() {
        _events.add(event);
        switch (event['type']) {
          case 'progress':
            _fraction =
                (event['fraction'] as num?)?.toDouble() ?? _fraction;
            _status = event['message']?.toString() ?? _status;
          case 'file_done':
            final r = event['result'] as Map<String, dynamic>?;
            if (r != null) _status = '${r['name']} → ${r['status']}';
          case 'finished':
            _fraction = 1.0;
            _status = 'Done.';
          case 'error':
            _status = 'Error: ${event['message']}';
        }
      });
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compresstor — engine spike')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pathCtl,
              decoration: const InputDecoration(
                labelText: 'Absolute path to a PDF or image',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _running ? null : _runCompress,
              child: Text(
                _running ? 'Compressing…' : 'Compress via engine_cli',
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _running ? _fraction : null),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _events.length,
                itemBuilder: (context, i) => Text(
                  jsonEncode(_events[i]),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
