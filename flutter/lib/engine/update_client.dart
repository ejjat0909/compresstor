// Update transport: fetches the latest release manifest from GitHub Releases,
// downloads the platform update artifact with progress, and verifies its
// SHA-256 checksum. Pure Dart — no UI, injectable http.Client for tests.
//
// Manifest source (docs/update-plan.md, Option A):
//   GET https://api.github.com/repos/<repo>/releases/latest
//   tag_name            -> version ("v1.0.1")
//   body                -> release notes (first line shown in the About card)
//   assets[*].name      -> Compresstor-<ver>-<platform>.zip + Compresstor-<ver>.sha256
//   assets[*].browser_download_url -> download URLs

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Parsed, comparable application version (major.minor.patch[+build]).
class UpdateVersion {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const UpdateVersion(this.major, this.minor, this.patch, this.build);

  /// Parses "1.0.1", "v1.0.1" or "1.0.1+2" (GitHub tags, version.json).
  factory UpdateVersion.parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    var build = 0;
    final plus = s.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(s.substring(plus + 1)) ?? 0;
      s = s.substring(0, plus);
    }
    final ints = s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (ints.length < 3) {
      ints.add(0);
    }
    return UpdateVersion(ints[0], ints[1], ints[2], build);
  }

  int compareTo(UpdateVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool isNewerThan(UpdateVersion other) => compareTo(other) > 0;

  @override
  String toString() =>
      '$major.$minor.$patch${build > 0 ? '+$build' : ''}';

  @override
  bool operator ==(Object other) =>
      other is UpdateVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

/// What the app needs to download and apply an update.
class UpdateManifest {
  final UpdateVersion version;
  final String notes;
  final String sha256;
  final Uri downloadUrl;

  const UpdateManifest({
    required this.version,
    required this.notes,
    required this.sha256,
    required this.downloadUrl,
  });
}

/// Any transport failure (manifest fetch, download, missing checksum).
class UpdateFetchException implements Exception {
  final String message;
  UpdateFetchException(this.message);

  @override
  String toString() => message;
}

/// Fetches manifests and downloads artifacts from GitHub Releases.
class UpdateClient {
  final http.Client _http;
  final String repo;
  final String platform; // 'macos' | 'windows'

  UpdateClient({
    http.Client? httpClient,
    String? platform,
    this.repo = 'ejjat0909/compresstor',
  })  : _http = httpClient ?? http.Client(),
        platform = platform ?? defaultUpdatePlatform();

  /// 'macos' on macOS, 'windows' on Windows, 'macos' elsewhere (tests/dev).
  static String defaultUpdatePlatform() =>
      Platform.operatingSystem == 'windows' ? 'windows' : 'macos';

  /// The latest published update for [platform], or null when the local
  /// version already is the newest (caller compares).
  Future<UpdateManifest> fetchManifest() async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final res = await _http.get(
      uri,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Compresstor-update-check',
      },
    );
    if (res.statusCode != 200) {
      throw UpdateFetchException(
          'Update check failed (HTTP ${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    if (tag.isEmpty) throw UpdateFetchException('Release has no version tag.');

    final version = UpdateVersion.parse(tag);
    final notes = _firstLine((data['body'] as String?) ?? '');
    final assets =
        ((data['assets'] as List?) ?? const []).cast<Map<String, dynamic>>();

    final zipName = _platformAssetName(assets);
    if (zipName == null) {
      throw UpdateFetchException(
          'No $platform update asset in the latest release.');
    }
    Map<String, dynamic>? zipAsset;
    for (final a in assets) {
      if (a['name'] == zipName) {
        zipAsset = a;
        break;
      }
    }
    final downloadUrl =
        Uri.parse(zipAsset!['browser_download_url'] as String);

    final sha256 = await _fetchChecksum(assets, zipName);
    if (sha256.isEmpty) {
      throw UpdateFetchException(
          'Checksum for $zipName is missing from the release.');
    }

    return UpdateManifest(
      version: version,
      notes: notes,
      sha256: sha256,
      downloadUrl: downloadUrl,
    );
  }

  /// Name of the artifact for this platform (Compresstor-<ver>-<platform>.zip).
  String? _platformAssetName(List<Map<String, dynamic>> assets) {
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.endsWith('-$platform.zip')) return name;
    }
    return null;
  }

  /// Reads Compresstor-<ver>.sha256 and returns the digest for [zipName].
  Future<String> _fetchChecksum(
      List<Map<String, dynamic>> assets, String zipName) async {
    Map<String, dynamic>? shaAsset;
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.endsWith('.sha256')) {
        shaAsset = a;
        break;
      }
    }
    if (shaAsset == null) return '';
    final res = await _http
        .get(Uri.parse(shaAsset['browser_download_url'] as String));
    if (res.statusCode != 200) return '';
    for (final line in res.body.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == zipName) return parts[0];
    }
    return '';
  }

  /// Downloads [url] to [target], reporting 0.0–1.0 progress. Deletes any
  /// partial file on failure.
  Future<void> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    final req = http.Request('GET', url);
    final streamed = await _http.send(req);
    if (streamed.statusCode != 200) {
      throw UpdateFetchException(
          'Download failed (HTTP ${streamed.statusCode}).');
    }
    final total = streamed.contentLength ?? 0;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) onProgress(received / total);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (target.existsSync()) target.deleteSync();
      rethrow;
    }
  }

  /// True when [file]'s SHA-256 matches [expected] (case-insensitive).
  Future<bool> verifySha256(File file, String expected) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    return digest.toLowerCase() == expected.trim().toLowerCase();
  }

  String _firstLine(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }
}
