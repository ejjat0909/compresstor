// UpdateController — state machine driving the Settings -> About "Check for
// updates" flow. Owns: the bundled version, the latest-release manifest, the
// check/download/apply lifecycle and its progress. Pure Dart + ChangeNotifier;
// the transport (UpdateClient) and applier are injectable for tests.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../engine/update_applier.dart';
import '../engine/update_client.dart';

/// Lifecycle of the update flow.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  applying,
  relaunched,
  error,
}

class UpdateController extends ChangeNotifier {
  final UpdateClient client;
  final UpdateApplier applier;

  UpdateController({
    required this.client,
    required this.applier,
    this.currentVersion = '0.0.0-dev',
  });

  String currentVersion;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  double _progress = 0;
  double get progress => _progress;

  String? _error;
  String? get error => _error;

  UpdateManifest? _manifest;
  UpdateManifest? get manifest => _manifest;

  bool get busy =>
      _status == UpdateStatus.checking ||
      _status == UpdateStatus.downloading ||
      _status == UpdateStatus.applying;

  /// Reads the version bundled with the app (assets/version.json, synced by
  /// the build scripts from the repo-root version.json).
  static Future<String> loadBundledVersion({
    String asset = 'assets/version.json',
    String fallback = '0.0.0-dev',
  }) async {
    try {
      final data = await rootBundle.loadString(asset);
      final v = (jsonDecode(data) as Map<String, dynamic>)['version'];
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {
      // fall through to fallback
    }
    return fallback;
  }

  Future<void> loadVersion() async {
    currentVersion = await loadBundledVersion();
    notifyListeners();
  }

  /// Asks the update source whether a newer version exists.
  Future<void> checkForUpdates() async {
    if (busy) return;
    _status = UpdateStatus.checking;
    _error = null;
    notifyListeners();
    try {
      final manifest = await client.fetchManifest();
      if (manifest.version.isNewerThan(UpdateVersion.parse(currentVersion))) {
        _manifest = manifest;
        _status = UpdateStatus.updateAvailable;
      } else {
        _manifest = null;
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      _error = e is UpdateFetchException ? e.message : '$e';
      _status = UpdateStatus.error;
    }
    notifyListeners();
  }

  /// Downloads, verifies and applies the available update.
  Future<void> update() async {
    if (_manifest == null ||
        (_status != UpdateStatus.updateAvailable &&
            _status != UpdateStatus.error)) {
      return;
    }
    final manifest = _manifest!;
    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('compresstor-update-');
      final zip =
          File('${tempDir.path}${Platform.pathSeparator}update.zip');
      _status = UpdateStatus.downloading;
      _progress = 0;
      notifyListeners();
      await client.download(manifest.downloadUrl, zip, onProgress: (p) {
        _progress = p;
        notifyListeners();
      });
      if (!await client.verifySha256(zip, manifest.sha256)) {
        _fail('Checksum verification failed — the download may be corrupted.');
        return;
      }
      _status = UpdateStatus.applying;
      _progress = 1;
      notifyListeners();
      await applier.apply(zip); // real appliers exit the process on success
      _status = UpdateStatus.relaunched;
      notifyListeners();
    } catch (e) {
      _fail(e is UpdateFetchException ? e.message : '$e');
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  void _fail(String message) {
    _error = message;
    _status = UpdateStatus.error;
    notifyListeners();
  }
}
