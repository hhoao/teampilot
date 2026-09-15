enum ConnectSshBackendKind { embedded, system }

ConnectSshBackendKind parseConnectSshBackendKind(Object? raw) {
  return raw == 'system'
      ? ConnectSshBackendKind.system
      : ConnectSshBackendKind.embedded;
}

ConnectSshBackendKind effectiveConnectSshBackend({
  required ConnectSshBackendKind stored,
  required bool systemSshdSelectable,
}) {
  return systemSshdSelectable && stored == ConnectSshBackendKind.system
      ? ConnectSshBackendKind.system
      : ConnectSshBackendKind.embedded;
}

extension ConnectSshBackendKindJson on ConnectSshBackendKind {
  String get jsonValue =>
      this == ConnectSshBackendKind.system ? 'system' : 'embedded';
}

abstract class ConnectSshBackend {
  bool get isListening;
  int get port;
  List<String> get hostKeyFingerprints;
  bool get isEmbedded;
  Future<void> start();
  Future<void> stop();
  Future<void> restart();
  Future<void> authorizePublicKey(String publicKey);
  Future<void> revokePublicKey(String publicKey);
}
