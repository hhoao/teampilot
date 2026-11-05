import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../ssh/worker/ssh_worker_exec_proxy.dart';
import 'acp_transport.dart';

/// Narrow seam over one non-PTY SSH exec channel.
///
/// Keeps [AcpSshTransport] unit-testable without a real sshd; production wires
/// [DartSsh2AcpChannel] over the profile worker's exec proxy.
abstract interface class AcpSshChannel {
  /// Remote stdout (NDJSON bytes). Never merged with stderr.
  Stream<Uint8List> get stdout;

  /// Remote stderr, kept separate from [stdout].
  Stream<Uint8List> get stderr;

  /// Completes with the remote exit code once the command finishes.
  Future<int> get exitCode;

  /// Writes one chunk to the remote stdin.
  void write(Uint8List data);

  /// Sends EOF on stdin so the agent can shut down cleanly.
  Future<void> closeStdin();

  /// Hard-kills the remote command.
  void kill();

  /// Releases local channel resources.
  void dispose();
}

/// [AcpSshChannel] over the profile worker's primitive exec proxy.
///
/// The worker keeps dartssh2 on its own isolate; stdout/stderr stay separate
/// and stdin is a bounded payload, which is exactly the ACP framing shape.
final class DartSsh2AcpChannel implements AcpSshChannel {
  DartSsh2AcpChannel(this._channel);

  final SshWorkerExecChannel _channel;

  @override
  Stream<Uint8List> get stdout => _channel.stdout;

  @override
  Stream<Uint8List> get stderr => _channel.stderr;

  @override
  Future<int> get exitCode => _channel.done.catchError((_) => -1);

  @override
  void write(Uint8List data) => _channel.write(data);

  @override
  Future<void> closeStdin() async => _channel.closeStdin();

  @override
  void kill() => _channel.kill();

  @override
  void dispose() => _channel.close();
}

/// [AcpTransport] over an SSH exec channel.
///
/// Mirrors `AcpProcessTransport`: no PTY, stdout carries NDJSON frames, stderr
/// stays separate, and [close] goes EOF → SIGKILL. [processExitCode] feeds the
/// spawner's handshake race so a rejected flag / not-logged-in agent is
/// classified the same way as locally.
class AcpSshTransport implements AcpTransport {
  AcpSshTransport({
    required AcpSshChannel channel,
    required void Function(List<int>)? onStderr,
    this.gracefulShutdownTimeout = const Duration(seconds: 5),
  }) : _channel = channel {
    _stderrController = StreamController<List<int>>.broadcast();
    _stderrSubscription = _channel.stderr.listen(
      (chunk) {
        onStderr?.call(chunk);
        _stderrController.add(chunk);
      },
      onError: _stderrController.addError,
      onDone: _stderrController.close,
    );
  }

  /// How long to wait after EOF before escalating to [AcpSshChannel.kill].
  final Duration gracefulShutdownTimeout;

  final AcpSshChannel _channel;
  late final StreamController<List<int>> _stderrController;
  late final StreamSubscription<List<int>> _stderrSubscription;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _channel.stdout;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  /// Remote exit code; consumed by the spawner's handshake race.
  Future<int> get processExitCode => _channel.exitCode;

  @override
  bool get isClosed => _closed;

  @override
  void write(String frame) {
    if (_closed) return;
    _channel.write(Uint8List.fromList(utf8.encode('$frame\n')));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      await _channel.closeStdin();
    } on Object {
      // stdin may already be closed; best-effort during shutdown.
    }

    var exited = true;
    try {
      await _channel.exitCode.timeout(gracefulShutdownTimeout);
    } on TimeoutException {
      exited = false;
    }

    if (!exited) {
      _channel.kill();
      try {
        await _channel.exitCode.timeout(gracefulShutdownTimeout);
      } on TimeoutException {
        // SIGKILL cannot be ignored by a live process; if this fires the
        // remote process is already gone.
      }
    }

    _channel.dispose();
    await _stderrSubscription.cancel();
    if (!_stderrController.isClosed) {
      await _stderrController.close();
    }
  }
}
