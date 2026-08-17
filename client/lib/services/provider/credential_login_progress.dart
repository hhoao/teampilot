class CredentialLoginProgress {
  const CredentialLoginProgress({
    required this.deviceCode,
    this.verificationUri,
  });

  final String deviceCode;
  final Uri? verificationUri;
}
