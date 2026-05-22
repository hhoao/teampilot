enum CredentialLinkResult { alreadyPresent, linked, copied, missing }

enum CredentialStatus { missing, ready }

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
