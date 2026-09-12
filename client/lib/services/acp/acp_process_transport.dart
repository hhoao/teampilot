import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'acp_transport.dart';

/// [AcpTransport] backed by a `dart:io` [Process].
///
/// Launches the agent directly (no PTY, no shell) and keeps stderr fully
/// separate from the NDJSON stdout channel — deliberately the opposite of
/// `SshPtyTransport`'s stderr-merge semantics.
class AcpProcessTransport implements AcpTransport {
  /// Wraps an already-running [process].
  ///
  /// [onStderr] is invoked for every stderr chunk, and [stderr] exposes the
  /// same data as a broadcast stream (a `dart:io` process stderr is
  /// single-subscription, so it is drained once and fanned out here).
  AcpProcessTransport({
    required Process process,
    required void Function(List<int>) onStderr,
    this.gracefulShutdownTimeout = const Duration(seconds: 5),
  }) : _process = process,
       _onStderr = onStderr {
    _stderrController = StreamController<List<int>>.broadcast();
    _stderrSubscription = _process.stderr.listen(
      (chunk) {
        _onStderr(chunk);
        _stderrController.add(chunk);
      },
      onError: _stderrController.addError,
      onDone: _stderrController.close,
    );
  }

  /// How long to wait after each signal before escalating.
  final Duration gracefulShutdownTimeout;

  final Process _process;
  final void Function(List<int>) _onStderr;

  late final StreamController<List<int>> _stderrController;
  late final StreamSubscription<List<int>> _stderrSubscription;

  bool _closed = false;

  /// Spawns [executable] with [args] (no shell, no PTY) in
  /// [workingDirectory] with the given [environment].
  static Future<AcpProcessTransport> start({
    required String executable,
    required List<String> args,
    required Map<String, String> environment,
    required String workingDirectory,
    void Function(List<int>)? onStderr,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    return AcpProcessTransport(process: process, onStderr: onStderr ?? (_) {});
  }

  @override
  Stream<Uint8List> get input => _process.stdout.map(Uint8List.fromList);

  @override
  void write(String frame) {
    if (_closed) return;
    _process.stdin.write('$frame\n');
  }

  /// Agent stderr, kept separate from [input] (never merged).
  ///
  /// Live-only broadcast stream: it does not replay chunks emitted before a
  /// listener subscribes, and it closes once the process is closed. Subscribe
  /// early or use the constructor's [onStderr] callback to guarantee delivery
  /// of every chunk.
  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  /// The wrapped process's exit code (completes when the process dies).
  ///
  /// Consumed by the production spawner to classify an immediate non-zero
  /// exit during the ACP handshake as a rejected flag candidate.
  Future<int> get processExitCode => _process.exitCode;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      await _process.stdin.close();
    } on Object {
      // stdin may already be closed when the process died; closing is
      // best-effort during shutdown.
    }

    // SIGTERM → exitCode timeout → SIGKILL.
    _signal(ProcessSignal.sigterm);
    var exited = true;
    try {
      await _process.exitCode.timeout(gracefulShutdownTimeout);
    } on TimeoutException {
      // Process ignored SIGTERM; escalate.
      exited = false;
    }

    if (!exited) {
      _signal(ProcessSignal.sigkill);
      try {
        await _process.exitCode.timeout(gracefulShutdownTimeout);
      } on TimeoutException {
        // SIGKILL cannot be ignored by a live process; if this fires the
        // process is already gone (e.g. a reaped zombie) — nothing to do.
      }
    }

    await _stderrSubscription.cancel();
    if (!_stderrController.isClosed) {
      await _stderrController.close();
    }
  }

  void _signal(ProcessSignal signal) {
    if (Platform.isWindows) {
      _process.kill();
      return;
    }
    _process.kill(signal);
  }
}
