typedef SshProfileTransportClosedHandler = void Function(
  String profileId,
  Object error,
  StackTrace stackTrace,
);

/// Shared event sink for SSH connection lifecycle. Injected into
/// the SSH factory and reconnect coordinator at bootstrap so
/// neither mutates the other after construction.
class SshConnectionEvents {
  SshProfileTransportClosedHandler? onTransportClosed;
  SshProfileTransportClosedHandler? onKeepAliveFailed;
}
