// Real-file tests for the platform appliers. `test()` (not testWidgets) so
// dart:io runs on the real event loop. The macOS swap runs against temp
// bundle dirs (never the running app), exercising the real ditto extract +
// quarantine strip + rm-then-mv sequence.

import 'dart:io';

import 'package:compresstor/engine/update_applier.dart';
import 'package:compresstor/engine/update_applier_macos.dart';
import 'package:compresstor/engine/update_applier_windows.dart';
import 'package:compresstor/engine/update_client.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Directory> _makeBundle(Directory dir, {required String marker}) async {
  final bundle = Directory('${dir.path}/Compresstor.app')
    ..createSync(recursive: true);
  File('${bundle.path}/Contents/MacOS/compresstor').createSync(recursive: true);
  File('${bundle.path}/$marker').writeAsStringSync(marker);
  return bundle;
}

void main() {
  group('MacOsUpdateApplier.swapBundle', () {
    test('extracts, strips quarantine and rm-then-mv swaps the bundle',
        () async {
      final tmp = Directory.systemTemp.createTempSync('applier-test-');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // Running bundle: some old file we expect to disappear.
      final currentRoot = Directory('${tmp.path}/Current');
      final current =
          await _makeBundle(currentRoot, marker: 'old-marker.txt');
      expect(current.existsSync(), isTrue);

      // New bundle inside a zip.
      final newRoot = Directory('${tmp.path}/New');
      final newApp = await _makeBundle(newRoot, marker: 'new-marker.txt');
      final zip = File('${tmp.path}/update.zip');
      await runUpdateProcess(
          'ditto', ['-c', '-k', '--keepParent', newApp.path, zip.path]);

      final applier = MacOsUpdateApplier();
      final result = await applier.swapBundle(zip, current);

      expect(result.path, current.path);
      expect(current.existsSync(), isTrue, reason: 'new bundle in place');
      expect(File('${current.path}/new-marker.txt').existsSync(), isTrue,
          reason: 'new bundle content present');
      expect(File('${current.path}/old-marker.txt').existsSync(), isFalse,
          reason: 'old bundle content gone (rm-then-mv, not merged)');
    });

    test('creates the bundle when it did not exist before', () async {
      final tmp = Directory.systemTemp.createTempSync('applier-test-');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final newApp = await _makeBundle(Directory('${tmp.path}/New'),
          marker: 'new-marker.txt');
      final zip = File('${tmp.path}/update.zip');
      await runUpdateProcess(
          'ditto', ['-c', '-k', '--keepParent', newApp.path, zip.path]);

      final target = Directory('${tmp.path}/Missing/Compresstor.app');
      Directory('${tmp.path}/Missing').createSync(recursive: true);
      final result = await MacOsUpdateApplier().swapBundle(zip, target);
      expect(result.existsSync(), isTrue);
      expect(File('${result.path}/new-marker.txt').existsSync(), isTrue);
    });

    test('throws when the zip has no Compresstor.app', () async {
      final tmp = Directory.systemTemp.createTempSync('applier-test-');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // A zip with an unrelated file at the root.
      final stub = File('${tmp.path}/not-an-app.txt')..writeAsStringSync('x');
      final zip = File('${tmp.path}/bad.zip');
      await runUpdateProcess('ditto', ['-c', '-k', stub.path, zip.path]);

      final target = Directory('${tmp.path}/Tgt/Compresstor.app');
      expect(
        MacOsUpdateApplier().swapBundle(zip, target),
        throwsA(isA<UpdateFetchException>()),
      );
    });
  });

  group('WindowsUpdateApplier.batScript', () {
    test('embeds the install dir and the full swap sequence', () {
      const installDir = r'C:\Users\Me\AppData\Local\Compresstor';
      final script = WindowsUpdateApplier().batScript(installDir);

      expect(script, contains('set "EXEDIR=$installDir"'));
      expect(script, contains('tasklist'));
      expect(script, contains(r'compresstor.exe'));
      expect(script, contains('rmdir /s /q "%EXEDIR%"'));
      expect(script, contains('xcopy /e /i /q "%SRC%*" "%EXEDIR%\\"'));
      expect(script, contains('start "" "%EXEDIR%\\compresstor.exe"'));
      expect(script, contains('del "%~f0"'));
    });
  });
}