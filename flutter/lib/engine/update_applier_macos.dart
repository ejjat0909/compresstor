// macOS update applier: extract the downloaded zip, swap the running
// Compresstor.app for the new one (rm first — never copy over a live bundle,
// taskgated kills the merged bundle), strip quarantine, relaunch, exit.

import 'dart:io';

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
    final installTemp =
        Directory.systemTemp.createTempSync('compresstor-install-');
    try {
      // 1. Extract the zip (built-in ditto keeps permissions/symlinks).
      await runUpdateProcess('ditto', ['-x', '-k', zip.path, installTemp.path]);
      final newApp = Directory('${installTemp.path}/Compresstor.app');
      if (!newApp.existsSync()) {
        throw UpdateFetchException(
            'Update package has no Compresstor.app inside.');
      }

      // 2. Downloaded bundles may carry a quarantine attribute.
      await runUpdateProcess(
          'xattr', ['-dr', 'com.apple.quarantine', newApp.path]);

      // 3. Swap: rm the live bundle first (taskgated rule), then move.
      final current = currentAppBundle();
      if (current.existsSync()) {
        await runUpdateProcess('rm', ['-rf', current.path]);
      }
      await runUpdateProcess('mv', [newApp.path, current.path]);

      // 4. Relaunch the new instance; this process exits below.
      final binary = '${current.path}/Contents/MacOS/'
          '${Platform.resolvedExecutable.split('/').last}';
      if (!File(binary).existsSync()) {
        throw UpdateFetchException('New app binary not found at $binary.');
      }
      await Process.start(binary, []);
    } finally {
      if (installTemp.existsSync()) {
        installTemp.deleteSync(recursive: true);
      }
      if (zip.existsSync()) zip.deleteSync();
    }
    exit(0); // hand off to the new instance
  }
}
