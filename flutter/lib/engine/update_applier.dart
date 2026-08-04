// UpdateApplier — platform-specific "apply the downloaded zip and relaunch".
// The real implementations (macOS/Windows) end by exiting the process so the
// new instance takes over; tests use fakes that return normally.

import 'dart:io';

import 'update_client.dart' show UpdateFetchException;

/// Applies a verified update archive and hands off to the new instance.
abstract class UpdateApplier {
  /// Extracts [zip], swaps it into place and relaunches the app.
  ///
  /// Real implementations terminate the current process after a successful
  /// swap (so [zip] cleanup inside them is their own responsibility);
  /// fakes return normally.
  Future<void> apply(File zip);
}

/// Runs a command and throws [UpdateFetchException] on non-zero exit.
Future<void> runUpdateProcess(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await Process.run(executable, args,
      workingDirectory: workingDirectory);
  if (result.exitCode != 0) {
    throw UpdateFetchException(
        'Command failed (exit ${result.exitCode}): $executable ${args.join(' ')}');
  }
}
