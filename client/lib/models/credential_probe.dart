/// Credential readiness state for a provider row.
enum CredentialStatus { missing, ready }

/// Credential readiness probe result for a provider row.
class CredentialProbe {
  const CredentialProbe({
    required this.providerId,
    required this.status,
    required this.credentialPath,
    this.updatedAt,
  });

  final String providerId;
  final CredentialStatus status;
  final String credentialPath;
  final DateTime? updatedAt;

  bool get isReady => status == CredentialStatus.ready;
}
