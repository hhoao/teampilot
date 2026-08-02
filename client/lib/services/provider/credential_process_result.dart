import 'dart:io';

import '../../models/credential_action_result.dart';
import '../host/host_run_result.dart';

Future<CredentialActionResult> loginCommandResult({
  ProcessResult? result,
  HostRunResult? hostResult,
  required bool ready,
  required String executable,
  Future<void> Function()? clearIncompleteCredentials,
}) async {
  final resolved = hostResult ??
      (result != null
          ? HostRunResult.fromProcess(result)
          : (throw ArgumentError(
              'loginCommandResult requires result or hostResult',
            )));
  if (resolved.exitCode != 0) {
    await clearIncompleteCredentials?.call();
    final stderr = resolved.stderr.trim();
    return CredentialActionResult.failure(
      CredentialActionFailure(
        code: CredentialActionFailureCode.loginFailed,
        exitCode: resolved.exitCode,
        detail: stderr.isEmpty ? null : stderr,
      ),
    );
  }
  if (!ready) {
    await clearIncompleteCredentials?.call();
    return CredentialActionResult.failure(
      const CredentialActionFailure(
        code: CredentialActionFailureCode.verifyFailed,
      ),
    );
  }
  return CredentialActionResult.success;
}

CredentialActionResult loginProcessError(String executable) {
  return CredentialActionResult.failure(
    CredentialActionFailure(
      code: CredentialActionFailureCode.loginProcessError,
      detail: executable,
    ),
  );
}

CredentialActionResult revokeVerifyResult(bool cleared) {
  if (cleared) return CredentialActionResult.success;
  return CredentialActionResult.failure(
    const CredentialActionFailure(
      code: CredentialActionFailureCode.revokeFailed,
    ),
  );
}
