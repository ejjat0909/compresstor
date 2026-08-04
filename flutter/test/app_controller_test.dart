// AppController tests with a fake engine: queue management + compression
// event handling (per-file status, finish, cancel, fatal error).

import 'dart:io';

import 'package:compresstor/engine/models.dart';
import 'package:compresstor/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

FileItem _item(String name, int size) => FileItem(
  path: '/tmp/$name',
  kind: detectKind(name),
  size: size,
  name: name,
  parentDir: '/tmp',
);

const _doneEvent = {
  'type': 'file_done',
  'index': 0,
  'result': {
    'path': '/tmp/a.pdf',
    'name': 'a.pdf',
    'kind': 'pdf',
    'status': 'done',
    'output_path': '/tmp/a_compressed.pdf',
    'original_size': 1000,
    'compressed_size': 400,
    'error': '',
  },
};

const _finishedEvent = {
  'type': 'finished',
  'results': [
    {
      'path': '/tmp/a.pdf',
      'name': 'a.pdf',
      'kind': 'pdf',
      'status': 'done',
      'output_path': '/tmp/a_compressed.pdf',
      'original_size': 1000,
      'compressed_size': 400,
      'error': '',
    },
  ],
};

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('queue', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('controller_test');
      File('${tmp.path}/a.pdf').writeAsBytesSync(List.filled(100, 1));
      File('${tmp.path}/b.png').writeAsBytesSync(List.filled(100, 1));
      File('${tmp.path}/c.txt').writeAsBytesSync(List.filled(100, 1));
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('adds supported files and rejects unsupported/dedup', () {
      final fake = FakeEngineClient();
      final c = AppController(engine: fake, autoLoadSettings: false);
      expect(c.isLoadingSettings, isFalse);

      final result = c.addPaths([
        '${tmp.path}/a.pdf',
        '${tmp.path}/b.png',
        '${tmp.path}/c.txt',
        '${tmp.path}/a.pdf',
      ]);
      expect(result.added.length, 2);
      expect(result.unsupported, ['${tmp.path}/c.txt']);
      expect(c.queue.length, 2);
    });

    test('totalSize sums bytes', () {
      final c = AppController(
        engine: FakeEngineClient(),
        autoLoadSettings: false,
      );
      c.addPaths(['/tmp/a.pdf', '/tmp/b.png']);
      // size comes from the fake FileItem stat (0) so seed the queue directly.
      c.queue.clear();
      c.queue.addAll([_item('a.pdf', 100), _item('b.png', 250)]);
      expect(c.totalSize, 350);
    });

    test('removeItems and removeByPath work', () {
      final c = AppController(
        engine: FakeEngineClient(),
        autoLoadSettings: false,
      );
      c.queue.addAll([_item('a.pdf', 1), _item('b.pdf', 1), _item('c.pdf', 1)]);
      c.removeItems([1]);
      expect(c.queue.length, 2);
      c.removeByPath('/tmp/c.pdf');
      expect(c.queue.map((e) => e.name).toList(), ['a.pdf']);
    });
  });

  group('compression', () {
    test('happy path drives status done + results', () async {
      final fake = FakeEngineClient();
      fake.setScript('compress', const [
        {'type': 'started', 'total': 1},
        _doneEvent,
        _finishedEvent,
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      final items = [_item('a.pdf', 1000)];
      c.queue.addAll(items);

      c.startCompression(items, const CompressionOptions());
      expect(c.running, isTrue);
      expect(c.statusFor('/tmp/a.pdf'), JobStatus.running);

      await _flush();
      expect(c.running, isFalse);
      expect(c.lastResults!.length, 1);
      expect(c.lastResults!.first.status, JobStatus.done);
      expect(c.statusFor('/tmp/a.pdf'), JobStatus.done);
      expect(c.lastError, isNull);
      expect(c.lastCancelled, isFalse);
    });

    test('forward-compatible: ignores unknown event types', () async {
      final fake = FakeEngineClient();
      fake.setScript('compress', const [
        {'type': 'started', 'total': 1},
        {'type': 'future_event', 'blah': 1},
        _doneEvent,
        _finishedEvent,
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      final items = [_item('a.pdf', 1000)];
      c.queue.addAll(items);
      c.startCompression(items, const CompressionOptions());
      await _flush();
      expect(c.running, isFalse);
      expect(c.lastResults!.single.status, JobStatus.done);
    });

    test('empty/duplicate start is a no-op', () {
      final fake = FakeEngineClient();
      final c = AppController(engine: fake, autoLoadSettings: false);
      c.startCompression([], const CompressionOptions());
      expect(c.running, isFalse);
    });

    test('cancel flow flips lastCancelled and returns to pending', () async {
      final fake = FakeEngineClient();
      fake.setScript('compress', const [
        {'type': 'started', 'total': 2},
        {
          'type': 'file_done',
          'index': 0,
          'result': {
            'path': '/tmp/a.pdf',
            'name': 'a.pdf',
            'kind': 'pdf',
            'status': 'done',
            'output_path': '/tmp/a_compressed.pdf',
            'original_size': 1000,
            'compressed_size': 400,
            'error': '',
          },
        },
        {'type': 'cancelled', 'completed': 1},
        {
          'type': 'finished',
          'results': [
            {
              'path': '/tmp/a.pdf',
              'name': 'a.pdf',
              'kind': 'pdf',
              'status': 'done',
              'output_path': '/tmp/a_compressed.pdf',
              'original_size': 1000,
              'compressed_size': 400,
              'error': '',
            },
          ],
        },
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      final items = [_item('a.pdf', 1000), _item('b.png', 500)];
      c.queue.addAll(items);
      c.startCompression(items, const CompressionOptions());
      await _flush();
      expect(c.running, isFalse);
      expect(c.lastCancelled, isTrue);
      // Completed file stays done; unprocessed file returns to pending.
      expect(c.statusFor('/tmp/a.pdf'), JobStatus.done);
      expect(c.statusFor('/tmp/b.png'), JobStatus.pending);
    });

    test('cancelCompression signals the engine', () async {
      final fake = FakeEngineClient();
      fake.setScript('compress', const [
        {'type': 'started', 'total': 1},
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      final items = [_item('a.pdf', 1000)];
      c.queue.addAll(items);
      c.startCompression(items, const CompressionOptions());
      expect(c.running, isTrue);
      await c.cancelCompression();
      expect(fake.cancelCalls, 1);
      expect(c.cancelling, isTrue);
    });

    test('fatal error event surfaces lastError', () async {
      final fake = FakeEngineClient();
      fake.setScript('compress', const [
        {'type': 'started', 'total': 1},
        {'type': 'error', 'message': 'boom'},
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      final items = [_item('a.pdf', 1000)];
      c.queue.addAll(items);
      c.startCompression(items, const CompressionOptions());
      await _flush();
      expect(c.running, isFalse);
      expect(c.lastError, 'boom');
    });
  });

  group('settings', () {
    test('loadSettings applies engine settings', () async {
      final fake = FakeEngineClient();
      fake.setScript('settings', const [
        {
          'type': 'settings',
          'settings': {
            'theme': 'dark',
            'accent_color': '#3b82f6',
            'history_limit': 50,
            'default_level': 'maximum',
            'output_mode': 'overwrite',
            'output_dir': '',
            'overwrite_confirmation': true,
            'add_to_history': false,
          },
        },
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      await c.loadSettings();
      expect(c.isLoadingSettings, isFalse);
      expect(c.settings.defaultCompressionLevel, CompressionLevel.maximum);
    });

    test('saveSettings sends settings set to engine', () async {
      final fake = FakeEngineClient();
      fake.setScript('settings', const [
        {
          'type': 'settings',
          'settings': {
            'accent_color': '#e11d48',
            'history_limit': 100,
            'default_level': 'high',
            'output_mode': 'suffix',
            'output_dir': '',
            'overwrite_confirmation': false,
            'add_to_history': true,
          },
        },
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      const newSettings = AppSettings(
        accentColor: '#e11d48',
        historyLimit: 100,
        defaultLevel: 'high',
        overwriteConfirmation: false,
      );
      await c.saveSettings(newSettings);
      expect(fake.calls, contains('settings'));
      expect(fake.lastRequestMap?['action'], 'set');
      expect(c.settings.accentColor, '#e11d48');
      expect(c.settings.historyLimit, 100);
    });
  });

  group('history', () {
    test('loadHistory populates entries', () async {
      final fake = FakeEngineClient();
      fake.setScript('history', const [
        {
          'type': 'history',
          'entries': [
            {
              'file_name': 'doc.pdf',
              'kind': 'pdf',
              'status': 'done',
              'original_size': 5000,
              'compressed_size': 2000,
              'savings_percent': 60.0,
              'timestamp': 1722700000.0,
              'output_path': '/tmp/doc_compressed.pdf',
            },
          ],
        },
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      await c.loadHistory();
      expect(c.isLoadingHistory, isFalse);
      expect(c.historyEntries.length, 1);
      expect(c.historyEntries.first['file_name'], 'doc.pdf');
    });

    test('clearHistory empties entries', () async {
      final fake = FakeEngineClient();
      fake.setScript('history', const [
        {'type': 'ok'},
      ]);
      final c = AppController(engine: fake, autoLoadSettings: false);
      c.historyEntries = [
        {'file_name': 'a.pdf'},
      ];
      await c.clearHistory();
      expect(c.historyEntries, isEmpty);
      expect(fake.lastRequestMap?['action'], 'clear');
    });

    test('removeHistoryEntry calls engine and reloads', () async {
      final fake = FakeEngineClient();
      fake.responses['history'] = const [
        {'type': 'ok'},
      ];
      final c = AppController(engine: fake, autoLoadSettings: false);
      await c.removeHistoryEntry(
        timestamp: 1722700000.0,
        outputPath: '/tmp/doc.pdf',
      );
      // First call is the remove, second is the reload (loadHistory).
      expect(fake.calls.where((c) => c == 'history').length, 2);
    });
  });
}
