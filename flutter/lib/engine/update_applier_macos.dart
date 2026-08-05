// macOS update applier: launches the Python apply_update.py script detached,
// then exits. The script waits for this process to die, swaps the .app bundle,
// strips quarantine, and relaunches.

import 'dart:io';

import 'update_applier.dart';
import 'update_client.dart' show UpdateFetchException;

class MacOsUpdateApplier implements UpdateApplier {
  /// The current .app bundle this process is running from.
  static Directory currentAppBundle() {
    final exe = File(Platform.resolvedExecutable);
    return exe.parent.parent.parent; // Contents/MacOS -> Contents -> .app
  }

  /// Resolve the bundled Python updater script path.
  /// In dev mode it's at app/updater/apply_update.py relative to the project.
  /// In release builds it's bundled inside the .app at
  /// Contents/Resources/app/updater/apply_update.py (via Flutter assets or
  /// the build script copying it).
  static File _updaterScript() {
    final bundle = currentAppBundle();
    // Release: bundled inside app
    final bundled =
        File('${bundle.path}/Contents/Resources/app/updater/apply_update.py');
    if (bundled.existsSync()) return bundled;

    // Dev: look relative to the executable (project root)
    final exe = File(Platform.resolvedExecutable);
    // In dev, exe is inside build/macos/Build/Products/Debug/... or Release/...
    // Walk up to find app/updater/apply_update.py
    var dir = exe.parent;
    for (var i = 0; i < 10; i++) {
      final candidate = File('${dir.path}/app/updater/apply_update.py');
      if (candidate.existsSync()) return candidate;
      dir = dir.parent;
    }

    throw UpdateFetchException(
        'Cannot find apply_update.py updater script.');
  }

  @override
  Future<void> apply(File zip) async {
    final bundle = currentAppBundle();
    final script = _updaterScript();
    final exeName = Platform.resolvedExecutable.split('/').last;

    // Launch the Python updater detached
    await Process.start(
      'python3',
      [
        script.path,
        '--platform', 'macos',
        '--zip', zip.path,
        '--target', bundle.path,
        '--pid', '$pid',
        '--exe-name', exeName,
      ],
      mode: ProcessStartMode.detached,
    );

    // Exit so the script can replace the bundle
    exit(0);
  }
}
