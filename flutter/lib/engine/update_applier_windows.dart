// Windows update applier: launches the Python apply_update.py script detached,
// then exits. The script waits for this process to die, replaces the install
// directory contents, and relaunches compresstor.exe.

import 'dart:io';

import 'update_applier.dart';
import 'update_client.dart' show UpdateFetchException;

class WindowsUpdateApplier implements UpdateApplier {
  /// The install directory containing compresstor.exe.
  static Directory currentInstallDir() =>
      File(Platform.resolvedExecutable).parent;

  /// Resolve the bundled Python updater script path.
  static File _updaterScript() {
    final installDir = currentInstallDir();

    // Release: bundled next to the exe under data/app/updater/
    final bundled =
        File('${installDir.path}\\data\\app\\updater\\apply_update.py');
    if (bundled.existsSync()) return bundled;

    // Alt release location: directly in install dir
    final alt = File('${installDir.path}\\app\\updater\\apply_update.py');
    if (alt.existsSync()) return alt;

    // Dev: walk up from exe to find project root
    var dir = installDir;
    for (var i = 0; i < 10; i++) {
      final candidate = File('${dir.path}\\app\\updater\\apply_update.py');
      if (candidate.existsSync()) return candidate;
      dir = dir.parent;
    }

    throw UpdateFetchException(
        'Cannot find apply_update.py updater script.');
  }

  @override
  Future<void> apply(File zip) async {
    final installDir = currentInstallDir();
    final script = _updaterScript();
    final exeName = Platform.resolvedExecutable.split('\\').last;

    // Writable pre-check
    final probe = File('${installDir.path}\\.compresstor-update-probe');
    try {
      probe.writeAsStringSync('x');
      probe.deleteSync();
    } catch (_) {
      throw UpdateFetchException(
          'Update failed — run Compresstor as administrator to update.');
    }

    // Launch the Python updater detached
    await Process.start(
      'python',
      [
        script.path,
        '--platform', 'windows',
        '--zip', zip.path,
        '--target', installDir.path,
        '--pid', '$pid',
        '--exe-name', exeName,
      ],
      mode: ProcessStartMode.detached,
    );

    // Exit so the script can replace the directory
    exit(0);
  }
}
