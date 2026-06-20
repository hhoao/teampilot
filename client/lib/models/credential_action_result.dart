/// Outcome of a provider credential login / import / revoke action.
enum CredentialActionFailureCode {
  unsupported,
  serviceUnavailable,
  providerNotFound,
  pathRequired,
  sourceMissing,
  sourceUnreadable,
  providerEntryMissing,
  invalidCredential,
  destinationExists,
  requiredFileMissing,
  loginFailed,
  loginProcessError,
  revokeFailed,
  verifyFailed,
  statusRefreshFailed,
}

class CredentialActionFailure {
  const CredentialActionFailure({
    required this.code,
    this.detail,
    this.path,
    this.providerId,
    this.availableProviderIds = const [],
    this.exitCode,
  });

  final CredentialActionFailureCode code;
  final String? detail;
  final String? path;
  final String? providerId;
  final List<String> availableProviderIds;
  final int? exitCode;
}

class CredentialActionResult {
  const CredentialActionResult._({required this.ok, this.failure});

  final bool ok;
  final CredentialActionFailure? failure;

  static const success = CredentialActionResult._(ok: true);

  factory CredentialActionResult.failure(CredentialActionFailure failure) {
    return CredentialActionResult._(ok: false, failure: failure);
  }

  factory CredentialActionResult.unsupported() {
    return CredentialActionResult.failure(
      const CredentialActionFailure(code: CredentialActionFailureCode.unsupported),
    );
  }

  factory CredentialActionResult.serviceUnavailable() {
    return CredentialActionResult.failure(
      const CredentialActionFailure(
        code: CredentialActionFailureCode.serviceUnavailable,
      ),
    );
  }
}
