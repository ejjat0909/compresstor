// EngineClient unit tests — hermetic event parsing against a fake engine
// module (test/fixtures/fake_engine) driven by environment variables. No
// Python engine, PyMuPDF or network involved; only a stdlib-only fake script.
//
// Covers the wire protocol contract from docs/engine-protocol.md:
//   - JSON-lines events decode in order
//   - a synthetic __exit event carries the process exit code
//   - non-JSON lines surface as error events without killing the stream
//   - a failed process spawn yields an error event + exit 1
//   - cancel() terminates a running process (SIGTERM on Unix)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compresstor/engine/engine_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Absolute path to a python interpreter (repo venv preferred, python3 fallback).
String get _python {
  final here = Directory.current.path;
  final root = here.endsWith('flutter') ? Directory(here).parent.path : here;
  final venv = File('$root/.venv/bin/python');
  if (venv.existsSync()) return venv.path;
  return Platform.isWindows ? 'python' : 'python3';
}

/// Root of the fake engine module tree (contains app/engine/engine_cli.py).
String get _fakeEngineRoot {
  final here = Directory.current.path;
  return here.endsWith('flutter')
      ? '$here/test/fixtures/fake_engine'
      : '$here/flutter/test/fixtures/fake_engine';
}

Future<List<Map<String, dynamic>>> _collect(
  Stream<Map<String, dynamic>> stream,
) async {
  final events = <Map<String, dynamic>>[];
  await for (final e in stream) {
    events.add(e);
  }
  return events;
}

void main() {
  final events = [
    {'type': 'started', 'total': 2},
    {'type': 'progress', 'index': 0, 'fraction': 0.5, 'message': 'working'},
    {'type': 'finished', 'results': []},
  ];

  test('decodes JSON-lines events in order and appends __exit 0', () async {
    final client = EngineClient(
      python: _python,
      cwd: _fakeEngineRoot,
      environment: {
        'FAKE_ENGINE_EVENTS': jsonEncode(events),
        'FAKE_ENGINE_EXIT': '0',
      },
    );
    final got = await _collect(client.run('compress', request: {'a': 1}));

    expect(got[0], {'type': 'started', 'total': 2});
    expect(got[1]['type'], 'progress');
    expect(got[1]['fraction'], 0.5);
    expect(got[2]['type'], 'finished');
    expect(got.last, {'type': EngineClient.exitEvent, 'exit': 0});
  });

  test('engine error event passes through and exit code 1 is reported',
      () async {
    final client = EngineClient(
      python: _python,
      cwd: _fakeEngineRoot,
      environment: {
        'FAKE_ENGINE_EVENTS': jsonEncode([
          {'type': 'error', 'message': 'boom'},
        ]),
        'FAKE_ENGINE_EXIT': '1',
      },
    );
    final got = await _collect(
      client.run('compress', request: {'items': []}),
    );
    expect(got.first, {'type': 'error', 'message': 'boom'});
    expect(got.last, {'type': EngineClient.exitEvent, 'exit': 1});
  });

  test('non-JSON stdout lines surface as error events, stream survives', () async {
    final client = EngineClient(
      python: _python,
      cwd: _fakeEngineRoot,
      environment: {
        'FAKE_ENGINE_EVENTS': jsonEncode(events),
        'FAKE_ENGINE_EXIT': '0',
        'FAKE_ENGINE_BAD_LINE': '1',
      },
    );
    final got = await _collect(client.run('compress', request: {}));

    final bad = got.where((e) => e['type'] == 'error').toList();
    expect(bad, hasLength(1));
    expect(bad.single['message'], contains('Bad JSON line'));
    // The rest of the stream still decodes.
    expect(got.any((e) => e['type'] == 'finished'), isTrue);
    expect(got.last, {'type': EngineClient.exitEvent, 'exit': 0});
  });

  test('unstartable interpreter yields error event and exit 1', () async {
    final client = EngineClient(
      python: '/nonexistent/python-binary',
      cwd: _fakeEngineRoot,
    );
    final got = await _collect(client.run('compress', request: {}));

    expect(got.first['type'], 'error');
    expect(got.first['message'], contains('Cannot start engine'));
    expect(got.last, {'type': EngineClient.exitEvent, 'exit': 1});
  });

  test('cancel() terminates a running process', () async {
    final client = EngineClient(
      python: _python,
      cwd: _fakeEngineRoot,
      environment: {
        'FAKE_ENGINE_EVENTS': jsonEncode([
          {'type': 'started', 'total': 1},
        ]),
        'FAKE_ENGINE_SLEEP': '30',
      },
    );
    final got = <Map<String, dynamic>>[];
    final done = Completer<void>();
    final stream = client.run('compress', request: {});
    stream.listen(got.add, onDone: done.complete);

    // Wait for the first event, then cancel (SIGTERM on Unix).
    while (got.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(got.first['type'], 'started');
    await client.cancel();

    // The process died from the signal — the stream must still terminate
    // cleanly with a __exit event (exit code is platform-signal dependent).
    await done.future.timeout(const Duration(seconds: 15));
    expect(got.last['type'], EngineClient.exitEvent);
  });
}
