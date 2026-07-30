import 'dart:async';

/// Timeouts for durable SSH storage-plane I/O (SFTP / exec / probes).
class SshStorageIo {
  const SshStorageIo._();

  /// Keepalive probe before reusing a pooled storage client.
  static const probeTimeout = Duration(seconds: 5);

  /// Single SFTP / short shell round-trip.
  static const ioTimeout = Duration(seconds: 30);

  /// CLI locate / path resolve (may run a few remote commands).
  static const locateTimeout = Duration(seconds: 45);

  /// One workspace provision phase (materialize or workspace-config).
  static const provisionPhaseTimeout = Duration(minutes: 2);

  static Future<T> awaitOrThrow<T>(
    Future<T> future, {
    required Duration timeout,
    required String operation,
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'SSH $operation timed out after ${timeout.inSeconds}s',
        timeout,
      );
    }
  }
}
