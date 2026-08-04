// End-to-end update integration against the REAL release artifacts over a
// real local HTTP server (no MockClient). Using plain `test()` so dart:io and
// the http package run on the real event loop.
//
// Serves release/Compresstor-<ver>-macos.zip + release/Compresstor-<ver>.sha256
// (produced by scripts/build_macos.sh) via a `latest.json` manifest, then runs
// the full UpdateController flow: check -> download -> SHA-256 verify -> apply.
// Skipped when the release artifacts haven't been built.

import 'dart:convert';
import 'dart:io';

import 'package:compresstor/engine/update_applier.dart';
import 'package:compresstor/engine/update_client.dart';
import 'package:compresstor/state/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingApplier implements UpdateApplier {
  int calls = 0;
  File? lastZip;

  @override
  Future<void> apply(File zip) async {
    calls++;
    lastZip = zip;
  }
}

void main() {
  test(
      'real client + controller download and verify the real release artifact',
      () async {
    const ver = '1.0.0';
    final shaFile = File('../release/Compresstor-$ver.sha256');
    final zip = File('../release/Compresstor-$ver-macos.zip');
    if (!shaFile.existsSync() || !zip.existsSync()) {
      markTestSkipped(
          'release artifacts not built — run scripts/build_macos.sh first');
      return;
    }

    // Read the real checksum line for the macos zip (client-parse format).
    String? digest;
    for (final line in shaFile.readAsLinesSync()) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == 'Compresstor-$ver-macos.zip') {
        digest = parts[0];
      }
    }
    expect(digest, isNotNull, reason: 'sha256 file must name the macos zip');

    // Local HTTP server serving the manifest + the real zip.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}';

    server.listen((req) async {
      if (req.uri.path == '/latest.json') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'version': '1.0.1', // newer than the running 1.0.0
          'build': 2,
          'notes': 'Integration test release.',
          'platforms': {
            'macos': {
              'url': '$base/Compresstor-$ver-macos.zip',
              'sha256': digest,
            },
          },
        }));
      } else {
        final f = File('../release${req.uri.path}');
        if (f.existsSync()) {
          req.response.headers.contentType = ContentType.binary;
          req.response.add(await f.readAsBytes());
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
      }
      await req.response.close();
    });

    final applier = RecordingApplier();
    final uc = UpdateController(
      client: UpdateClient(baseUrl: base, platform: 'macos'),
      applier: applier,
      currentVersion: '1.0.0',
    );

    await uc.checkForUpdates();
    expect(uc.status, UpdateStatus.updateAvailable);
    expect(uc.manifest!.version.toString(), '1.0.1');

    await uc.update();
    expect(uc.status, UpdateStatus.relaunched);
    expect(applier.calls, 1);

    // The server served the REAL release zip (tens of MB), not a stub.
    expect(zip.lengthSync(), greaterThan(1000000));
    expect(uc.progress, 1.0);

    // The controller cleaned up its download temp dir afterwards.
    expect(applier.lastZip!.existsSync(), isFalse);
  });
}