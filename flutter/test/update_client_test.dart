// Tests for the update transport: manifest fetch (GitHub Releases latest),
// version comparison, download with progress, and SHA-256 verification.
// RED phase — update_client.dart does not exist yet.

import 'dart:convert';
import 'dart:io';

import 'package:compresstor/engine/update_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _repo = 'ejjat0909/compresstor';
const _latestUrl = 'https://api.github.com/repos/$_repo/releases/latest';

Map<String, dynamic> _githubRelease({
  String tag = 'v1.0.1',
  String body = 'Line one\nLine two',
}) {
  return {
    'tag_name': tag,
    'body': body,
    'assets': [
      {
        'name': 'Compresstor-1.0.1-macos.zip',
        'browser_download_url':
            'https://github.com/$_repo/releases/download/v1.0.1/Compresstor-1.0.1-macos.zip',
      },
      {
        'name': 'Compresstor-1.0.1-windows.zip',
        'browser_download_url':
            'https://github.com/$_repo/releases/download/v1.0.1/Compresstor-1.0.1-windows.zip',
      },
      {
        'name': 'Compresstor-1.0.1.sha256',
        'browser_download_url':
            'https://github.com/$_repo/releases/download/v1.0.1/Compresstor-1.0.1.sha256',
      },
    ],
  };
}

void main() {
  group('UpdateVersion', () {
    test('parses plain, v-prefixed and +build forms', () {
      expect(UpdateVersion.parse('1.0.1').toString(), '1.0.1');
      expect(UpdateVersion.parse('v1.0.1').toString(), '1.0.1');
      expect(UpdateVersion.parse('1.2.3+7').toString(), '1.2.3+7');
      expect(UpdateVersion.parse('v2.0.0').build, 0);
    });

    test('compares semver, then build number', () {
      expect(UpdateVersion.parse('1.0.1').isNewerThan(UpdateVersion.parse('1.0.0')), isTrue);
      expect(UpdateVersion.parse('1.9.9').isNewerThan(UpdateVersion.parse('1.10.0')), isFalse);
      expect(UpdateVersion.parse('1.0.0+2').isNewerThan(UpdateVersion.parse('1.0.0+1')), isTrue);
      expect(UpdateVersion.parse('1.0.0').isNewerThan(UpdateVersion.parse('1.0.0')), isFalse);
    });
  });

  group('UpdateClient.fetchManifest', () {
    test('parses the latest GitHub release for macos', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async {
          if (req.url.toString() == _latestUrl) {
            return http.Response(jsonEncode(_githubRelease()), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path.endsWith('.sha256')) {
            return http.Response(
                'a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6  Compresstor-1.0.1-macos.zip\n',
                200);
          }
          return http.Response('not found', 404);
        }),
        platform: 'macos',
      );

      final m = await client.fetchManifest();
      expect(m.version.toString(), '1.0.1');
      expect(m.notes, 'Line one');
      expect(m.sha256, 'a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6');
      expect(m.downloadUrl.toString(), contains('Compresstor-1.0.1-macos.zip'));
    });

    test('picks the windows asset on windows', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async {
          if (req.url.toString() == _latestUrl) {
            return http.Response(jsonEncode(_githubRelease()), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path.endsWith('.sha256')) {
            return http.Response(
                '00ff  Compresstor-1.0.1-windows.zip\n00aa  Compresstor-1.0.1-macos.zip\n',
                200);
          }
          return http.Response('not found', 404);
        }),
        platform: 'windows',
      );

      final m = await client.fetchManifest();
      expect(m.downloadUrl.toString(), contains('Compresstor-1.0.1-windows.zip'));
      expect(m.sha256, '00ff');
    });

    test('throws UpdateFetchException on non-200', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async => http.Response('oops', 403)),
        platform: 'macos',
      );
      expect(
        () => client.fetchManifest(),
        throwsA(isA<UpdateFetchException>()),
      );
    });

    test('throws when no matching platform asset exists', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async {
          final release = _githubRelease();
          (release['assets'] as List).removeWhere(
              (a) => (a['name'] as String).contains('macos'));
          return http.Response(jsonEncode(release), 200,
              headers: {'content-type': 'application/json'});
        }),
        platform: 'macos',
      );
      expect(
        () => client.fetchManifest(),
        throwsA(isA<UpdateFetchException>()),
      );
    });
  });

  group('UpdateClient.fetchManifest (self-hosted latest.json)', () {
    const base = 'http://127.0.0.1:9999';
    Map<String, dynamic> latestJson({String version = '1.0.1'}) => {
          'version': version,
          'build': 2,
          'notes': 'Self-hosted notes line.',
          'platforms': {
            'macos': {
              'url': '$base/Compresstor-1.0.1-macos.zip',
              'sha256': 'aa11bb',
            },
            'windows': {
              'url': '$base/Compresstor-1.0.1-windows.zip',
              'sha256': 'cc22dd',
            },
          },
        };

    test('parses the platform entry from latest.json', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async {
          expect(req.url.toString(), '$base/latest.json');
          return http.Response(jsonEncode(latestJson()), 200,
              headers: {'content-type': 'application/json'});
        }),
        platform: 'macos',
        baseUrl: base,
      );
      final m = await client.fetchManifest();
      expect(m.version.toString(), '1.0.1');
      expect(m.notes, 'Self-hosted notes line.');
      expect(m.sha256, 'aa11bb');
      expect(m.downloadUrl.toString(), '$base/Compresstor-1.0.1-macos.zip');
    });

    test('picks the windows entry for windows', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async =>
            http.Response(jsonEncode(latestJson()), 200)),
        platform: 'windows',
        baseUrl: base,
      );
      final m = await client.fetchManifest();
      expect(m.downloadUrl.toString(), '$base/Compresstor-1.0.1-windows.zip');
      expect(m.sha256, 'cc22dd');
    });

    test('throws when the platform entry is missing', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async => http.Response(
            jsonEncode({'version': '1.0.1', 'platforms': <String, Object>{}}),
            200)),
        platform: 'macos',
        baseUrl: base,
      );
      expect(client.fetchManifest(),
          throwsA(isA<UpdateFetchException>()));
    });

    test('throws when the checksum is missing', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async => http.Response(
            jsonEncode({
              'version': '1.0.1',
              'platforms': {
                'macos': {'url': '$base/x.zip'},
              },
            }),
            200)),
        platform: 'macos',
        baseUrl: base,
      );
      expect(client.fetchManifest(),
          throwsA(isA<UpdateFetchException>()));
    });
  });

  group('UpdateClient.download', () {
    test('writes bytes to the target and reports progress', () async {
      final bytes = List<int>.generate(1000, (i) => i % 251);
      final client = UpdateClient(
        httpClient: MockClient((req) async => http.Response.bytes(bytes, 200)),
        platform: 'macos',
      );

      final dir = Directory.systemTemp.createTempSync('upd_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/dl.bin');

      final progress = <double>[];
      await client.download(
        Uri.parse('https://example.com/Compresstor-1.0.1-macos.zip'),
        file,
        onProgress: progress.add,
      );

      expect(file.readAsBytesSync(), bytes);
      expect(progress.last, 1.0);
      expect(progress.first, greaterThan(0));
    });

    test('leaves no partial file when the download fails', () async {
      final client = UpdateClient(
        httpClient: MockClient((req) async => http.Response('gone', 404)),
        platform: 'macos',
      );
      final dir = Directory.systemTemp.createTempSync('upd_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/dl.bin');

      await expectLater(
        client.download(Uri.parse('https://example.com/x.zip'), file),
        throwsA(isA<UpdateFetchException>()),
      );
      expect(file.existsSync(), isFalse);
    });
  });

  group('UpdateClient.verifySha256', () {
    test('matches the digest and rejects a wrong one', () async {
      final bytes = utf8.encode('hello world');
      final dir = Directory.systemTemp.createTempSync('upd_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/f.bin')..writeAsBytesSync(bytes);

      final digest = sha256.convert(bytes).toString();
      final client = UpdateClient(platform: 'macos');
      expect(await client.verifySha256(file, digest), isTrue);
      expect(await client.verifySha256(file, 'deadbeef'), isFalse);
    });
  });
}
