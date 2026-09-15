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
    this.authorizeError,
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

  /// Thrown by [authorizePublicKey] when set.
  Object? authorizeError;

  /// Optional hook run by [start] — default sets [isListening] when omitted.
  Future<void> Function()? onStart;

  /// Optional hook run by [restart] — lets a test flip [isListening]/[port]
  /// to simulate a successful re-start.
  Future<void> Function()? onRestart;

  /// Optional hook run by [revokePublicKey] so callers can observe order.
  Future<void> Function(String publicKey)? onRevokePublicKey;

  int restarts = 0;
  int stops = 0;
  final revokedPublicKeys = <String>[];

  @override
  Future<void> start() async {
    final hook = onStart;
    if (hook != null) {
      await hook();
    } else {
      isListening = true;
    }
  }

  @override
  Future<void> stop() async {
    stops += 1;
    isListening = false;
  }

  @override
  Future<void> restart() async {
    restarts += 1;
    final error = restartError;
    if (error != null) throw error;
    final hook = onRestart;
    if (hook != null) await hook();
  }

  @override
  Future<void> authorizePublicKey(String publicKey) async {
    final error = authorizeError;
    if (error != null) throw error;
  }

  @override
  Future<void> revokePublicKey(String publicKey) async {
    revokedPublicKeys.add(publicKey);
    final hook = onRevokePublicKey;
    if (hook != null) await hook(publicKey);
  }
}

/// The default listening server most connect tests want: port 54321 with a
/// pinned host key.
final fakeListeningEmbeddedServer = FakeEmbeddedServer();
