part of 'launch_adapter_client.dart';

/// stdin/stdout handle for one Launch Adapter child process.
class LaunchAdapterProcess {
  LaunchAdapterProcess({
    required this.stdin,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required this.exitCode,
    required void Function([ProcessSignal signal]) kill,
  }) : _stdout = stdout,
       _stderr = stderr,
       _kill = kill;

  factory LaunchAdapterProcess.fromIo({
    required IOSink stdin,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required Future<int> exitCode,
    required void Function([ProcessSignal signal]) kill,
  }) {
    return LaunchAdapterProcess(
      stdin: stdin,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      kill: kill,
    );
  }

  final IOSink stdin;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final Future<int> exitCode;
  final void Function([ProcessSignal signal]) _kill;

  Stream<List<int>> get stdout => _stdout;
  Stream<List<int>> get stderr => _stderr;

  void kill([ProcessSignal signal = ProcessSignal.sigterm]) => _kill(signal);
}

/// Spawns (or returns) an adapter process for the given expanded command.
typedef LaunchAdapterProcessStarter =
    Future<LaunchAdapterProcess> Function({
      required String command,
      required List<String> args,
    });

class _StickyPoolKey {
  const _StickyPoolKey(this.type, this.targetId);

  final String type;
  final String targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StickyPoolKey &&
          type == other.type &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(type, targetId);
}

class _PendingRequest {
  _PendingRequest(this.completer);

  final Completer<Map<String, Object?>> completer;
}

class _AdapterConnection {
  _AdapterConnection({
    required this.process,
    required this.lifecycle,
    required this.type,
    required this.targetId,
    this.oneshotSessionId,
  });

  final LaunchAdapterProcess process;
  final LaunchAdapterLifecycle lifecycle;
  final String type;
  final String targetId;

  /// Non-null when this connection is a oneshot process for one session.
  final String? oneshotSessionId;

  final Map<Object, _PendingRequest> pending = {};
  final Set<String> activeSessions = {};
  var nextId = 1;
  var initialized = false;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;
  var closed = false;

  Object allocId() => nextId++;

  bool get isOneshot => lifecycle == LaunchAdapterLifecycle.oneshot;
}
