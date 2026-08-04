// Windows update applier: extract the downloaded zip to a temp dir, drop a
// detached apply_update.bat in that temp dir (it must survive the install-dir
// swap), launch it minimized and exit — the bat waits for compresstor.exe to
// stop, deletes the install dir, copies the new build in and relaunches.
//
// The bat lives in the EXTRACT dir (%~dp0 = extract dir), NOT the install dir,
// because the install dir is removed while it runs. User data (%APPDATA%) is
// outside the install dir and never touched.

import 'dart:io';

import 'update_applier.dart';
import 'update_client.dart' show UpdateFetchException;

class WindowsUpdateApplier implements UpdateApplier {
  /// The install directory containing compresstor.exe.
  static Directory currentInstallDir() => File(Platform.resolvedExecutable).parent;

  @override
  Future<void> apply(File zip) async {
    final exeDir = currentInstallDir();

    // 1. Writable pre-check: Program Files installs need elevation.
    final probe = File('${exeDir.path}\\.compresstor-update-probe');
    try {
      probe.writeAsStringSync('x');
      probe.deleteSync();
    } catch (_) {
      throw UpdateFetchException(
          'Update failed — run Compresstor as administrator to update.');
    }

    // 2. Extract the zip next to the bat that applies it.
    final installTemp =
        Directory.systemTemp.createTempSync('compresstor-install-');
    try {
      await runUpdateProcess('tar', ['-xf', zip.path, '-C', installTemp.path]);

      // 3. Write the detached updater bat into the extract dir.
      final bat = File('${installTemp.path}\\apply_update.bat');
      bat.writeAsStringSync(_batScript(exeDir.path));
      if (!File('${installTemp.path}\\compresstor.exe').existsSync()) {
        throw UpdateFetchException(
            'Update package has no compresstor.exe inside.');
      }

      // 4. Launch it minimized, detached; this process exits below.
      await Process.run(
          'cmd', ['/c', 'start', '', '/min', bat.path],
          workingDirectory: installTemp.path);
    } finally {
      if (zip.existsSync()) zip.deleteSync();
    }
    exit(0); // the bat waits for this process to end, then swaps
  }

  String _batScript(String exeDir) {
    return '''
@echo off
setlocal
set "EXEDIR=$exeDir"
set "SRC=%~dp0"
:wait
tasklist /fi "IMAGENAME eq compresstor.exe" | find /i "compresstor.exe" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait
)
rmdir /s /q "%EXEDIR%"
xcopy /e /i /q "%SRC%*" "%EXEDIR%\\" >nul
start "" "%EXEDIR%\\compresstor.exe"
del "%~f0"
''';
  }
}
