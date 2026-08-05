// macOS update applier: extract the downloaded zip, swap the running
// Compresstor.app for the new one (rm first — never copy over a live bundle,
// taskgated kills the merged bundle), strip quarantine, relaunch, exit.

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'update_applier.dart';
import 'update_client.dart' show UpdateFetchException;

class MacOsUpdateApplier implements UpdateApplier {
  /// The current .app bundle this process is running from.
  static Directory currentAppBundle() {
    final exe = File(Platform.resolvedExecutable);
    return exe.parent.parent.parent; // Contents/MacOS -> Contents -> .app
  }

  @override
  Future<void> apply(File zip) async {
    final current = currentAppBundle();
    await swapBundle(zip, current);

    // Hand off to the new instance; this process exits so the swap is final.
    final binary = '${current.path}/Contents/MacOS/'
        '${Platform.resolvedExecutable.split('/').last}';
    if (!File(binary).existsSync()) {
      throw UpdateFetchException('New app binary not found at $binary.');
    }
    await Process.start(binary, []);
    if (zip.existsSync()) zip.deleteSync();
    exit(0);
  }

  /// Extracts [zip]'s `Compresstor.app`, strips quarantine, and swaps it for
  /// the running [currentBundle] — rm the live bundle first (taskgated rule,
  /// never copy over a live bundle), then mv the new one in. Returns the
  /// bundle now in place. Separated from [apply] so real-file tests can run
  /// it against temp bundles.
  @visibleForTesting
  Future<Directory> swapBundle(File zip, Directory currentBundle) async {
    final installTemp =
        Directory.systemTemp.createTempSync('compresstor-install-');
    try {
      // 1. Strip quarantine from the downloaded zip (browsers/NSURLSession add it).
      await runUpdateProcess(
          'xattr', ['-d', 'com.apple.quarantine', zip.path]).catchError((_) {});

      // 2. Extract the zip (built-in ditto keeps permissions/symlinks).
      //    Retry once on SIGKILL (-9) — macOS occasionally kills ditto under
      //    memory pressure or transient security policy enforcement.
      try {
        await runUpdateProcess(
            '/usr/bin/ditto', ['-x', '-k', zip.path, installTemp.path]);
      } on UpdateFetchException catch (e) {
        if (e.message.contains('exit -9') || e.message.contains('exit 137')) {
          // Wait briefly and retry once.
          await Future<void>.delayed(const Duration(seconds: 2));
          await runUpdateProcess(
              '/usr/bin/ditto', ['-x', '-k', zip.path, installTemp.path]);
        } else {
          rethrow;
        }
      }
      final newApp = Directory('${installTemp.path}/Compresstor.app');
      if (!newApp.existsSync()) {
        throw UpdateFetchException(
            'Update package has no Compresstor.app inside.');
      }

      // 3. Strip quarantine from the extracted bundle.
      await runUpdateProcess(
          'xattr', ['-dr', 'com.apple.quarantine', newApp.path]);

      // 4. Swap: rm the live bundle first (taskgated rule), then move.
      if (currentBundle.existsSync()) {
        await runUpdateProcess('rm', ['-rf', currentBundle.path]);
      }
      await runUpdateProcess('mv', [newApp.path, currentBundle.path]);
      return currentBundle;
    } finally {
      if (installTemp.existsSync()) {
        installTemp.deleteSync(recursive: true);
      }
    }
  }
}
