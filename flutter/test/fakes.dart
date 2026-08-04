// Fake engine for hermetic unit/widget tests. Swaps the process-spawning
// EngineClient for an in-memory script so no Python is required.

import 'dart:async';

import 'package:compresstor/engine/engine_client.dart';

class FakeEngineClient extends EngineClient {
  FakeEngineClient([Map<String, List<Map<String, dynamic>>>? responses])
    : responses = responses ?? {};

  /// Per-subcommand event scripts (in order) to yield from [run].
  Map<String, List<Map<String, dynamic>>> responses;

  int cancelCalls = 0;
  final List<String> calls = [];
  Map<String, dynamic>? lastRequestMap;

  /// When set, [run] waits this long before yielding each event (lets widget
  /// tests observe the "running" state of the progress dialog).
  Duration? emitDelay;

  void setScript(String subcommand, List<Map<String, dynamic>> script) {
    responses[subcommand] = script;
  }

  @override
  Stream<Map<String, dynamic>> run(
    String subcommand, {
    required Map<String, dynamic> request,
  }) async* {
    calls.add(subcommand);
    lastRequestMap = request;
    for (final event in responses[subcommand] ?? const []) {
      if (emitDelay != null) await Future<void>.delayed(emitDelay!);
      yield event;
    }
    yield {'type': '__exit', 'exit': 0};
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}
