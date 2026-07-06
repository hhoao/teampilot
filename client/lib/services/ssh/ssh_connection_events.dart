import 'ssh_client_factory.dart';

/// Shared event sink for SSH connection lifecycle. Injected into
/// [SshClientFactory] and [SshProfileConnectionCoordinator] at bootstrap so
/// neither mutates the other after construction.
class SshConnectionEvents {
  SshProfileTransportClosedHandler? onTransportClosed;
  SshProfileTransportClosedHandler? onKeepAliveFailed;
}
