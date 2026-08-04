// UpdateController state-machine tests with a fake applier + MockClient
// transport. RED phase — update_controller.dart does not exist yet.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compresstor/engine/update_applier.dart';
import 'package:compresstor/engine/update_client.dart';
import 'package:compresstor/state/update_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeApplier implements UpdateApplier {
  int calls = 0;
  File? lastZip;

  @override
  Future<void> apply(File zip) async {
    calls++;
    lastZip = zip;
  }
}

const _latestUrl = 'https://api.github.com/repos/ejjat0909/compresstor/releases/latest';

MockClient _releaseHandler({
  String tag = 'v1.0.1',
  String shaLine = '00ffaa  Compresstor-1.0.1-macos.zip',
  int downloadStatus = 200,
  int fetchStatus = 200,
  int fetchCount = 999,
}) {
  return MockClient((req) async {
    if (req.url.toString() == _latestUrl) {
      if (fetchCount <= 0) return http.Response('rate limited', 403);
      fetchCount--;
      if (fetchStatus != 200) return http.Response('oops', fetchStatus);
      return http.Response(
        jsonEncode({
          'tag_name': tag,
          'body': 'Release notes line',
          'assets': [
            {
              'name': 'Compresstor-1.0.1-macos.zip',
              'browser_download_url': 'https://github.com/x/Compresstor-1.0.1-macos.zip',
            },
            {
              'name': 'Compresstor-1.0.1.sha256',
              'browser_download_url': 'https://github.com/x/Compresstor-1.0.1.sha256',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.url.path.endsWith('.sha256')) {
      return http.Response('$shaLine\n', 200);
    }
    // The zip download.
    if (downloadStatus != 200) return http.Response('gone', downloadStatus);
    return http.Response.bytes(List<int>.filled(100, 7), 200);
  });
}

UpdateController _controller(
  MockClient handler, {
  FakeApplier? applier,
  String currentVersion = '1.0.0',
}) {
  return UpdateController(
    client: UpdateClient(httpClient: handler, platform: 'macos'),
    applier: applier ?? FakeApplier(),
    currentVersion: currentVersion,
  );
}

void main() {
  group('checkForUpdates', () {
    test('flags updateAvailable when a newer version exists', () async {
      final c = _controller(_releaseHandler(tag: 'v1.0.1'));
      await c.checkForUpdates();
      expect(c.status, UpdateStatus.updateAvailable);
      expect(c.manifest!.version.toString(), '1.0.1');
      expect(c.manifest!.notes, 'Release notes line');
      expect(c.busy, isFalse);
    });

    test('flags upToDate when the latest is not newer', () async {
      final c = _controller(_releaseHandler(tag: 'v1.0.1'), currentVersion: '1.0.1');
      await c.checkForUpdates();
      expect(c.status, UpdateStatus.upToDate);
      expect(c.manifest, isNull);
    });

    test('surfaces a fetch error and allows retry', () async {
      final c = _controller(_releaseHandler(fetchStatus: 403));
      await c.checkForUpdates();
      expect(c.status, UpdateStatus.error);
      expect(c.error, contains('HTTP 403'));
      // Retry with a healthy handler.
      final c2 = _controller(_releaseHandler());
      await c2.checkForUpdates();
      expect(c2.status, UpdateStatus.updateAvailable);
    });

    test('ignores a second check while one is in flight', () async {
      final gate = Completer<void>();
      var fetches = 0;
      final handler = MockClient((req) async {
        if (req.url.toString() == _latestUrl) {
          fetches++;
          await gate.future;
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.0.1',
              'body': '',
              'assets': [
                {
                  'name': 'Compresstor-1.0.1-macos.zip',
                  'browser_download_url': 'https://github.com/x/a.zip',
                },
                {
                  'name': 'Compresstor-1.0.1.sha256',
                  'browser_download_url': 'https://github.com/x/s.sha256',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('.sha256')) {
          return http.Response('00ffaa  Compresstor-1.0.1-macos.zip\n', 200);
        }
        return http.Response.bytes([1, 2, 3], 200);
      });

      final c = _controller(handler);
      final first = c.checkForUpdates();
      await Future<void>.delayed(Duration.zero);
      final second = c.checkForUpdates(); // must be a no-op
      gate.complete();
      await first;
      await second;
      expect(fetches, 1);
      expect(c.status, UpdateStatus.updateAvailable);
    });
  });

  group('update', () {
    test('downloads, verifies, applies and ends at relaunched', () async {
      final applier = FakeApplier();
      // shaLine must be the real SHA-256 of the payload the handler streams
      // (100 bytes of 0x07).
      final payload = List<int>.filled(100, 7);
      final digest = sha256.convert(payload).toString();
      final c = _controller(
        _releaseHandler(shaLine: '$digest  Compresstor-1.0.1-macos.zip'),
        applier: applier,
      );

      await c.checkForUpdates();
      expect(c.status, UpdateStatus.updateAvailable);

      final states = <UpdateStatus>[];
      c.addListener(() => states.add(c.status));
      await c.update();

      expect(c.status, UpdateStatus.relaunched);
      expect(applier.calls, 1);
      expect(applier.lastZip, isNotNull);
      expect(applier.lastZip!.existsSync(), isFalse,
          reason: 'download temp must be cleaned up');
      expect(states, containsAllInOrder([
        UpdateStatus.downloading,
        UpdateStatus.applying,
        UpdateStatus.relaunched,
      ]));
      expect(c.progress, 1.0);
    });

    test('aborts with error on checksum mismatch, applier untouched', () async {
      final applier = FakeApplier();
      final c = _controller(
        _releaseHandler(shaLine: 'deadbeef  Compresstor-1.0.1-macos.zip'),
        applier: applier,
      );
      await c.checkForUpdates();
      await c.update();

      expect(c.status, UpdateStatus.error);
      expect(c.error, contains('Checksum'));
      expect(applier.calls, 0);
    });

    test('aborts with error when the download fails, applier untouched', () async {
      final applier = FakeApplier();
      final c = _controller(
        _releaseHandler(downloadStatus: 404),
        applier: applier,
      );
      await c.checkForUpdates();
      await c.update();

      expect(c.status, UpdateStatus.error);
      expect(c.error, contains('HTTP 404'));
      expect(applier.calls, 0);
    });

    test('does nothing when no update is available', () async {
      final applier = FakeApplier();
      final c = _controller(_releaseHandler(), applier: applier);
      await c.update(); // idle — nothing to do
      expect(c.status, UpdateStatus.idle);
      expect(applier.calls, 0);
    });
  });

  group('bundled version', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('loadBundledVersion reads the real bundled asset', () async {
      expect(await UpdateController.loadBundledVersion(), '1.0.0');
    });

    test('loadBundledVersion falls back when the asset is missing', () async {
      expect(
        await UpdateController.loadBundledVersion(
            asset: 'assets/does-not-exist.json'),
        '0.0.0-dev',
      );
    });
  });
}
