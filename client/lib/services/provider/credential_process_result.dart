import 'dart:io';

import '../../models/credential_action_result.dart';

Future<CredentialActionResult> loginCommandResult({
  required ProcessResult result,
  required bool ready,
  required String executable,
  Future<void> Function()? clearIncompleteCredentials,
}) async {
  if (result.exitCode != 0) {
    await clearIncompleteCredentials?.call();
    final stderr = result.stderr.toString().trim();
    return CredentialActionResult.failure(
      CredentialActionFailure(
        code: CredentialActionFailureCode.loginFailed,
        exitCode: result.exitCode,
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
    const CredentialActionFailure(code: CredentialActionFailureCode.revokeFailed),
  );
}
