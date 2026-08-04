// AppController — Flutter-side coordinator, the analogue of the Python
// AppController. Owns the queue, loads persisted settings from the engine,
// and orchestrates one compress run (spawning the engine via [EngineClient]
// and feeding the resulting events back to the UI through [ChangeNotifier]).
//
// The dashboard reads queue rows + per-path statuses from here; compression
// progress is surfaced via [progressFraction] / [progressMessage]; a finished
// run's outcomes are exposed through [lastResults] / [lastError] /
// [lastCancelled].

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';
import '../engine/models.dart';

class AddPathsResult {
  const AddPathsResult({required this.added, required this.unsupported});
  final List<FileItem> added;
  final List<String> unsupported; // file paths that were not PDF/image.
}

class AppController extends ChangeNotifier {
  AppController({EngineClient? engine, bool autoLoadSettings = true})
    : engine = engine ?? EngineClient() {
    if (autoLoadSettings) loadSettings();
  }

  final EngineClient engine;

  final List<FileItem> queue = [];
  final Map<String, JobStatus> _statuses = {};
  final Map<String, JobResult> _results = {};

  AppSettings settings = const AppSettings();
  bool isLoadingSettings = false;

  bool running = false;
  bool cancelling = false;
  double progressFraction = 0;
  String progressMessage = '';

  List<JobResult>? lastResults;
  String? lastError;
  bool lastCancelled = false;

  /// Number of files in the most recent run (for the progress modal header).
  int runTotal = 0;

  StreamSubscription<Map<String, dynamic>>? _sub;
  int _runId = 0;

  // ----------------------------------------------------------------- queue --

  JobStatus statusFor(String path) => _statuses[path] ?? JobStatus.pending;
  JobResult? resultFor(String path) => _results[path];

  AddPathsResult addPaths(List<String> paths) {
    final existing = queue.map((e) => e.path).toSet();
    final added = <FileItem>[];
    final unsupported = <String>[];
    for (final path in paths) {
      final item = FileItem.fromPath(path);
      if (item.kind == FileKind.unsupported) {
        unsupported.add(path);
        continue;
      }
      if (existing.contains(item.path) || item.size <= 0) continue;
      queue.add(item);
      existing.add(item.path);
      added.add(item);
    }
    notifyListeners();
    return AddPathsResult(added: added, unsupported: unsupported);
  }

  void removeItems(List<int> indices) {
    final sorted = [...indices]..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      if (i < 0 || i >= queue.length) continue;
      _statuses.remove(queue[i].path);
      _results.remove(queue[i].path);
      queue.removeAt(i);
    }
    notifyListeners();
  }

  void removeByPath(String path) {
    final idx = queue.indexWhere((e) => e.path == path);
    if (idx >= 0) removeItems([idx]);
  }

  void clearQueue() {
    queue.clear();
    _statuses.clear();
    _results.clear();
    notifyListeners();
  }

  int get totalSize => queue.fold(0, (sum, e) => sum + e.size);

  // ------------------------------------------------------------- settings --

  Future<void> loadSettings() async {
    isLoadingSettings = true;
    notifyListeners();
    try {
      await for (final ev in engine.run(
        'settings',
        request: {'action': 'get'},
      )) {
        if (ev['type'] == 'settings') {
          settings = AppSettings.fromJson(
            ev['settings'] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      // Keep defaults on a start failure; the dashboard still works.
    } finally {
      isLoadingSettings = false;
      notifyListeners();
    }
  }

  Future<void> saveSettings(AppSettings newSettings) async {
    settings = newSettings;
    notifyListeners();
    try {
      await for (final ev in engine.run(
        'settings',
        request: {
          'action': 'set',
          'settings': {
            'theme': newSettings.theme,
            'accent_color': newSettings.accentColor,
            'history_limit': newSettings.historyLimit,
            'default_level': newSettings.defaultLevel,
            'output_mode': newSettings.outputMode,
            'output_dir': newSettings.outputDir,
            'overwrite_confirmation': newSettings.overwriteConfirmation,
            'add_to_history': newSettings.addToHistory,
          },
        },
      )) {
        if (ev['type'] == 'settings') {
          settings = AppSettings.fromJson(
            ev['settings'] as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      // Best-effort; local state already updated.
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- history --

  List<Map<String, dynamic>> historyEntries = [];
  bool isLoadingHistory = false;

  Future<void> loadHistory() async {
    isLoadingHistory = true;
    notifyListeners();
    try {
      await for (final ev in engine.run(
        'history',
        request: {'action': 'list', 'limit': settings.historyLimit},
      )) {
        if (ev['type'] == 'history') {
          historyEntries = List<Map<String, dynamic>>.from(
            ev['entries'] ?? [],
          );
        }
      }
    } catch (_) {
      // Keep whatever we had.
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> removeHistoryEntry({
    required double timestamp,
    required String outputPath,
  }) async {
    try {
      await for (final _ in engine.run(
        'history',
        request: {
          'action': 'remove',
          'timestamp': timestamp,
          'output_path': outputPath,
        },
      )) {}
    } catch (_) {}
    await loadHistory();
  }

  Future<void> clearHistory() async {
    try {
      await for (final _ in engine.run(
        'history',
        request: {'action': 'clear'},
      )) {}
    } catch (_) {}
    historyEntries = [];
    notifyListeners();
  }

  // ----------------------------------------------------------- compression --

  /// Starts a compression batch for *items* using *options*. The caller should
  /// also open the progress UI; status updates arrive via [ChangeNotifier].
  void startCompression(List<FileItem> items, CompressionOptions options) {
    if (running || items.isEmpty) return;

    _runId++;
    final runId = _runId;
    running = true;
    cancelling = false;
    progressFraction = 0;
    progressMessage = '0 of ${items.length} files';
    runTotal = items.length;
    lastResults = null;
    lastError = null;
    lastCancelled = false;

    _statuses.clear();
    _results.clear();
    for (final f in items) {
      _statuses[f.path] = JobStatus.running;
    }
    notifyListeners();

    final request = <String, dynamic>{
      'items': [
        for (final f in items) {'path': f.path},
      ],
      'options': options.toJson(),
      'add_to_history': settings.addToHistory,
    };

    _sub?.cancel();
    _sub = engine
        .run('compress', request: request)
        .listen(
          (event) => _handleEvent(event, runId),
          onError: (Object e) {
            if (runId != _runId) return;
            _finalizeWithError('Engine error: $e');
          },
          onDone: () => _finalizeIfStuck(runId),
        );
  }

  Future<void> cancelCompression() async {
    if (!running) return;
    cancelling = true;
    notifyListeners();
    await engine.cancel();
  }

  void _handleEvent(Map<String, dynamic> event, int runId) {
    if (runId != _runId || !running) return;
    final type = event['type'];
    switch (type) {
      case 'progress':
        progressFraction =
            (event['fraction'] as num?)?.toDouble() ?? progressFraction;
        progressMessage = event['message'] as String? ?? progressMessage;
        notifyListeners();
        break;
      case 'file_done':
        final r = JobResult.fromJson(event['result'] as Map<String, dynamic>);
        _statuses[r.path] = r.status;
        _results[r.path] = r;
        notifyListeners();
        break;
      case 'cancelled':
        lastCancelled = true;
        break;
      case 'finished':
        final raw = (event['results'] as List? ?? [])
            .map((e) => JobResult.fromJson(e as Map<String, dynamic>))
            .toList();
        _finalize(raw);
        break;
      case 'error':
        lastError = event['message'] as String? ?? 'Unknown engine error';
        break;
      default:
        // Unknown event types (including EngineClientExitEvent) are ignored
        // per the protocol's forward-compatibility rule; exit is handled in
        // the stream's onDone below via _finalizeIfStuck.
        break;
    }
  }

  void _finalize(List<JobResult> results) {
    lastResults = results;
    for (final r in results) {
      _statuses[r.path] = r.status;
      _results[r.path] = r;
    }
    // Files still running (e.g. after a cancel) fall back to pending so the
    // queue can be re-run cleanly.
    for (final e in _statuses.entries.toList()) {
      if (e.value == JobStatus.running) _statuses[e.key] = JobStatus.pending;
    }
    running = false;
    cancelling = false;
    notifyListeners();
  }

  void _finalizeWithError(String message) {
    lastError ??= message;
    for (final e in _statuses.entries.toList()) {
      if (e.value == JobStatus.running) _statuses[e.key] = JobStatus.pending;
    }
    running = false;
    cancelling = false;
    notifyListeners();
  }

  /// Safety net: if the process died without emitting finished/error (e.g. a
  /// hard kill on Windows), close out the run so the UI never sticks.
  void _finalizeIfStuck(int runId) {
    if (runId != _runId || !running) return;
    if (lastError == null && lastResults == null) {
      lastError = 'Engine exited unexpectedly.';
    }
    _finalizeWithError(lastError!);
  }
}
