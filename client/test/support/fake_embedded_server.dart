import 'package:teampilot/services/connect/connect_ssh_backend.dart';

/// Shared test double for [ConnectSshBackend].
///
/// Mutable so a test can flip [isListening]/[port] to observe how consumers
/// mirror the handle, with [restarts] recording retry-affordance calls.
class FakeEmbeddedServer implements ConnectSshBackend {
  FakeEmbeddedServer({
    this.isListening = true,
    this.port = 54321,
    this.hostKeyFingerprints = const ['SHA256:host-key'],
    this.isEmbedded = true,
    this.restartError,
  });

  @override
  bool isListening;

  @override
  int port;

  @override
  List<String> hostKeyFingerprints;

  @override
  bool isEmbedded;

  /// Thrown by [restart] when set, simulating a failed re-start.
  Object? restartError;

  /// Optional hook run by [restart] — lets a test flip [isListening]/[port]
  /// to simulate a successful re-start.
  Future<void> Function()? onRestart;

  int restarts = 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restart() async {
    restarts += 1;
    final error = restartError;
    if (error != null) throw error;
    final hook = onRestart;
    if (hook != null) await hook();
  }

  @override
  Future<void> authorizePublicKey(String publicKey) async {}

  @override
  Future<void> revokePublicKey(String publicKey) async {}
}

/// The default listening server most connect tests want: port 54321 with a
/// pinned host key.
final fakeListeningEmbeddedServer = FakeEmbeddedServer();
