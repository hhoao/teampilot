import 'package:teampilot/services/connect/embedded_ssh_server.dart';

/// Shared test double for [EmbeddedSshServerHandle].
///
/// Mutable so a test can flip [isListening]/[port] to observe how consumers
/// mirror the handle, with [restarts] recording retry-affordance calls.
class FakeEmbeddedServer implements EmbeddedSshServerHandle {
  FakeEmbeddedServer({
    this.isListening = true,
    this.port = 54321,
    this.hostKeyFingerprints = const ['SHA256:host-key'],
    this.restartError,
  });

  @override
  bool isListening;

  @override
  int port;

  @override
  List<String> hostKeyFingerprints;

  /// Thrown by [restart] when set, simulating a failed re-start.
  Object? restartError;

  /// Optional hook run by [restart] — lets a test flip [isListening]/[port]
  /// to simulate a successful re-start.
  Future<void> Function()? onRestart;

  int restarts = 0;

  @override
  Future<void> restart() async {
    restarts += 1;
    final error = restartError;
    if (error != null) throw error;
    final hook = onRestart;
    if (hook != null) await hook();
  }
}

/// The default listening server most connect tests want: port 54321 with a
/// pinned host key.
final fakeListeningEmbeddedServer = FakeEmbeddedServer();
