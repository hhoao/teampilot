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
