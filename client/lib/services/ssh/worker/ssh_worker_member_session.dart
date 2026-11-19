import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../models/ssh_profile.dart';
import '../../connect/profile_connection_mapping.dart';
import '../ssh_forward_channel.dart';
import '../ssh_transport_close.dart';
import 'ssh_worker_exec_proxy.dart';
import 'ssh_profile_worker_manager.dart';
import 'ssh_worker_protocol.dart';
import 'ssh_worker_storage_types.dart';

export 'ssh_worker_exec_proxy.dart'
    show SshWorkerExecChannel, SshWorkerMemberException;

/// UI-safe member-plane transport. Production implementations proxy a worker;
/// direct dartssh2 adapters are retained only for constructor-injected tests.
abstract interface class SshWorkerMemberTransport {
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  });

  Future<SshWorkerRunResult> run(String command, {bool stderr = true});

  Future<SshWorkerExecChannel> startProcess(String command);

  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  });

  Future<void> close();
}

/// Primitive PTY surface that deliberately excludes dartssh2 session objects.
abstract interface class SshWorkerPtyChannel {
  Stream<Uint8List> get output;
  Future<int> get done;
  void write(Uint8List data);
  void resize(int rows, int columns);
  void close();
}

/// Member session facade shared by the UI-facing [SshMemberSession].
final class SshWorkerMemberSession {
  SshWorkerMemberSession._(this.profile, this._transport);

  final SshProfile profile;
  final SshWorkerMemberTransport _transport;
  Future<void>? _closeFuture;

  static Future<SshWorkerMemberSession> open({
    required SshProfile profile,
    required SshWorkerMemberTransport transport,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await transport.open(profile, timeout: timeout);
    return SshWorkerMemberSession._(profile, transport);
  }

  /// Constructs the facade around a caller-supplied pure test transport.
  static SshWorkerMemberSession forTesting(
    SshProfile profile,
    SshWorkerMemberTransport transport,
  ) => SshWorkerMemberSession._(profile, transport);

  Future<String> run(String command) async {
    final result = await _transport.run(command);
    return String.fromCharCodes(result.stdout).trim();
  }

  Future<SshWorkerRunResult> runWithResult(
    String command, {
    bool stderr = true,
  }) => _transport.run(command, stderr: stderr);

  Future<SshWorkerExecChannel> startProcess(String command) =>
      _transport.startProcess(command);

  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => _transport.openPty(
    command: command,
    columns: columns,
    rows: rows,
    environment: environment,
  );

  Future<void> close() => _closeFuture ??= _transport.close();
}

/// Direct dartssh2 adapter retained solely for injected connector and pure
/// unit-test seams. Production member sessions use [SshWorkerLeaseMemberTransport].
final class SshWorkerDirectMemberTransport implements SshWorkerMemberTransport {
  SshWorkerDirectMemberTransport({
    required this.client,
    Future<void> Function()? closeTransport,
  }) : _closeTransport = closeTransport;

  final SSHClient client;
  final Future<void> Function()? _closeTransport;
  Future<void>? _closeFuture;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {}

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    final result = await client.runWithResult(command, stderr: stderr);
    return SshWorkerRunResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      signalName: result.exitSignal?.signalName,
    );
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) async =>
      _SshWorkerDirectExecChannel(await client.execute(command));

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final pty = SSHPtyConfig(
      type: 'xterm-256color',
      width: columns,
      height: rows,
    );
    final session = command == null
        ? await client.shell(pty: pty, environment: environment)
        : await client.execute(command, pty: pty, environment: environment);
    return _SshWorkerDirectPtyChannel(session);
  }

  DartSshReverseTunnel newReverseTunnel({String bindHost = '127.0.0.1'}) =>
      DartSshReverseTunnel(client, bindHost: bindHost);

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      final closeTransport = _closeTransport;
      if (closeTransport != null) {
        await closeTransport();
      } else if (!client.isClosed) {
        await client.disconnect();
      }
    } on Object {
      // Test transports and remote shutdown may race a member close.
    }
  }
}

final class _SshWorkerDirectPtyChannel implements SshWorkerPtyChannel {
  _SshWorkerDirectPtyChannel(this._session);

  final SSHSession _session;
  Stream<Uint8List>? _output;

  @override
  Stream<Uint8List> get output => _output ??= _mergeOutput();

  @override
  Future<int> get done => _session.done.then((_) => _session.exitCode ?? 0);

  @override
  void close() => _session.close();

  @override
  void resize(int rows, int columns) => _session.resizeTerminal(columns, rows);

  @override
  void write(Uint8List data) => _session.write(data);

  Stream<Uint8List> _mergeOutput() {
    late StreamSubscription<Uint8List> stdout;
    late StreamSubscription<Uint8List> stderr;
    var closed = 0;
    final output = StreamController<Uint8List>();
    void onDone() {
      closed++;
      if (closed == 2 && !output.isClosed) unawaited(output.close());
    }

    output.onListen = () {
      stdout = _session.stdout.listen(
        output.add,
        onError: output.addError,
        onDone: onDone,
      );
      stderr = _session.stderr.listen(
        output.add,
        onError: output.addError,
        onDone: onDone,
      );
    };
    output.onCancel = () async {
      await stdout.cancel();
      await stderr.cancel();
    };
    return output.stream;
  }
}

final class _SshWorkerDirectExecChannel implements SshWorkerExecChannel {
  _SshWorkerDirectExecChannel(this._session);

  final SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<int> get done => _session.done.then((_) => _session.exitCode ?? -1);

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void closeStdin() => _session.stdin.close();

  @override
  void kill() {
    try {
      _session.kill(SSHSignal.KILL);
    } on Object {
      _session.close();
    }
  }

  @override
  void close() => _session.close();
}

/// Lease-backed UI proxy for one worker-owned member client.
final class SshWorkerLeaseMemberTransport implements SshWorkerMemberTransport {
  SshWorkerLeaseMemberTransport({
    required SshProfileWorkerLease lease,
    required SshWorkerDialTarget target,
  }) : _lease = lease,
       _target = target {
    _events = lease.events.listen(
      _onEvent,
      onDone: () => _finishTransportClosed(),
    );
  }

  final SshProfileWorkerLease _lease;
  final SshWorkerDialTarget _target;
  final Map<String, _SshWorkerPtyProxy> _ptys = {};
  final Map<String, SshWorkerExecProxy> _execs = {};
  final Map<String, List<SshWorkerEvent>> _openingPtyEvents = {};
  final Map<String, List<SshWorkerEvent>> _openingExecEvents = {};
  late final StreamSubscription<SshWorkerEvent> _events;
  String? _memberId;
  var _ptySequence = 0;
  var _execSequence = 0;
  var _closing = false;
  Future<void>? _closeFuture;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_memberId != null) return;
    // Member ids must be unique across every lease on this worker generation:
    // one profile can host several terminals/members at once.
    final memberId = _lease.resourceId('member');
    final reply = await _request(SshWorkerOperation.openMember, {
      'memberId': memberId,
      ...SshWorkerConnectionRef(
        machineId: profile.id,
        generation: planGenerationOf(profile),
        username: profile.username,
        authType: profile.authType,
      ).toArgs(),
      'target': _target.toWire(),
      'timeoutMs': timeout.inMilliseconds,
    });
    _expectSuccess(reply);
    _memberId = memberId;
  }

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    final reply = await _request(SshWorkerOperation.runMember, {
      'memberId': _requireMemberId(),
      'command': command,
      'stderr': stderr,
    });
    return SshWorkerRunResult.fromWire(_expectSuccess(reply));
  }

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final memberId = _requireMemberId();
    final ptyId = '$memberId/${_ptySequence++}';
    final pendingEvents = <SshWorkerEvent>[];
    _openingPtyEvents[ptyId] = pendingEvents;
    try {
      final reply = await _request(SshWorkerOperation.openPty, {
        'memberId': memberId,
        'ptyId': ptyId,
        'columns': columns,
        'rows': rows,
        'outputWindow': 4,
        if (command != null) 'command': command,
        if (environment != null && environment.isNotEmpty)
          'environment': environment,
      });
      _expectSuccess(reply);
      if (_closing) {
        throw StateError('SSH member transport is closing');
      }
    } on Object {
      _openingPtyEvents.remove(ptyId);
      rethrow;
    }
    final channel = _SshWorkerPtyProxy(
      id: ptyId,
      acknowledge: (sequence) => _request(
        SshWorkerOperation.acknowledgePtyOutput,
        {'ptyId': ptyId, 'sequence': sequence},
      ).then<void>((reply) => _expectSuccess(reply)),
      writeRemote: (data) => _request(SshWorkerOperation.writePty, {
        'ptyId': ptyId,
      }, payload: data).then<void>((reply) => _expectSuccess(reply)),
      resizeRemote: (rows, columns) => _request(SshWorkerOperation.resizePty, {
        'ptyId': ptyId,
        'rows': rows,
        'columns': columns,
      }).then<void>((reply) => _expectSuccess(reply)),
      closeRemote: () => _request(SshWorkerOperation.closeChannel, {
        'channelId': ptyId,
      }).then<void>((reply) => _expectSuccess(reply)),
      onFinished: () => _ptys.remove(ptyId),
    );
    _ptys[ptyId] = channel;
    _openingPtyEvents.remove(ptyId);
    for (final event in pendingEvents) {
      channel.accept(event);
    }
    return channel;
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) async {
    final memberId = _requireMemberId();
    final execId = '$memberId/exec-${_execSequence++}';
    final pendingEvents = <SshWorkerEvent>[];
    _openingExecEvents[execId] = pendingEvents;
    try {
      final reply = await _request(SshWorkerOperation.startMemberExec, {
        'memberId': memberId,
        'execId': execId,
        'command': command,
      });
      _expectSuccess(reply);
      if (_closing) throw StateError('SSH member transport is closing');
    } on Object {
      _openingExecEvents.remove(execId);
      rethrow;
    }
    final channel = SshWorkerExecProxy(
      id: execId,
      acknowledgeRemote: (sequence) => _request(
        SshWorkerOperation.acknowledgeExecOutput,
        {'execId': execId, 'sequence': sequence},
      ).then<void>((reply) => _expectSuccess(reply)),
      writeRemote: (data) => _request(SshWorkerOperation.writeMemberExec, {
        'execId': execId,
      }, payload: data).then<void>((reply) => _expectSuccess(reply)),
      closeStdinRemote: () => _request(
        SshWorkerOperation.closeMemberExecStdin,
        {'execId': execId},
      ).then<void>((reply) => _expectSuccess(reply)),
      killRemote: () => _request(SshWorkerOperation.killMemberExec, {
        'execId': execId,
      }).then<void>((reply) => _expectSuccess(reply)),
      closeRemote: () => _request(SshWorkerOperation.closeChannel, {
        'channelId': execId,
      }).then<void>((reply) => _expectSuccess(reply)),
      onFinished: () => _execs.remove(execId),
    );
    _execs[execId] = channel;
    _openingExecEvents.remove(execId);
    for (final event in pendingEvents) {
      channel.accept(event);
    }
    return channel;
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    final memberId = _memberId;
    try {
      if (memberId != null) {
        final reply = await _request(SshWorkerOperation.closeChannel, {
          'channelId': memberId,
        });
        _expectSuccess(reply);
      }
    } finally {
      for (final pty in _ptys.values.toList(growable: false)) {
        pty.finish(0);
      }
      _ptys.clear();
      for (final exec in _execs.values.toList(growable: false)) {
        exec.finish(0);
      }
      _execs.clear();
      _openingPtyEvents.clear();
      _openingExecEvents.clear();
      await _events.cancel();
      await _lease.release();
    }
  }

  Future<SshWorkerReply> _request(
    SshWorkerOperation operation,
    Map<String, Object?> args, {
    Uint8List? payload,
  }) => _lease.send(
    SshWorkerRequest(
      requestId: _lease.resourceId('member-request'),
      operation: operation,
      args: args,
      payload: payload,
    ),
  );

  Object? _expectSuccess(SshWorkerReply reply) {
    if (reply.kind == SshWorkerReplyKind.success) return reply.result;
    throw SshWorkerMemberException(reply.error?.code ?? 'member_failed');
  }

  String _requireMemberId() {
    final memberId = _memberId;
    if (memberId == null) throw StateError('SSH member transport is not open');
    return memberId;
  }

  void _onEvent(SshWorkerEvent event) {
    if (event.kind == SshWorkerEventKind.outputChunk) {
      final channel = _ptys[event.streamId];
      if (channel != null) {
        channel.accept(event);
      } else {
        _openingPtyEvents[event.streamId]?.add(event);
      }
      return;
    }
    if (event.kind == SshWorkerEventKind.execOutput) {
      final channel = _execs[event.streamId];
      if (channel != null) {
        channel.accept(event);
      } else {
        _openingExecEvents[event.streamId]?.add(event);
      }
      return;
    }
    if (event.kind == SshWorkerEventKind.transportClose &&
        event.plane == SshTransportPlane.member &&
        !_closing) {
      // A member-plane close is scoped to one member connection. Other
      // terminals/members on the same profile worker must stay alive.
      if (event.streamId != null && event.streamId != _memberId) return;
      _finishTransportClosed();
    }
  }

  void _finishTransportClosed() {
    if (_closing) return;
    _closing = true;
    _memberId = null;
    for (final pty in _ptys.values.toList(growable: false)) {
      pty.finishError(StateError('SSH member transport closed'));
    }
    for (final exec in _execs.values.toList(growable: false)) {
      exec.finishError(StateError('SSH member transport closed'));
    }
    _ptys.clear();
    _execs.clear();
    _openingPtyEvents.clear();
    _openingExecEvents.clear();
    unawaited(_events.cancel());
    unawaited(_lease.release());
  }
}

final class _SshWorkerPtyProxy implements SshWorkerPtyChannel {
  _SshWorkerPtyProxy({
    required this.id,
    required this.acknowledge,
    required this.writeRemote,
    required this.resizeRemote,
    required this.closeRemote,
    required this.onFinished,
  });

  final String id;
  final Future<void> Function(int sequence) acknowledge;
  final Future<void> Function(Uint8List data) writeRemote;
  final Future<void> Function(int rows, int columns) resizeRemote;
  final Future<void> Function() closeRemote;
  final void Function() onFinished;
  final StreamController<Uint8List> _output = StreamController<Uint8List>(
    sync: true,
  );
  final Completer<int> _done = Completer<int>();
  var _nextSequence = 0;
  var _closeRequested = false;
  var _finished = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get done => _done.future;

  @override
  void write(Uint8List data) {
    if (!_closeRequested && !_finished) unawaited(_writeQuietly(data));
  }

  @override
  void resize(int rows, int columns) {
    if (!_closeRequested && !_finished) {
      unawaited(_resizeQuietly(rows, columns));
    }
  }

  @override
  void close() {
    if (_closeRequested || _finished) return;
    _closeRequested = true;
    unawaited(_closeRemote());
  }

  void accept(SshWorkerEvent event) {
    if (_finished) return;
    if (event.sequence != _nextSequence) {
      finishError(SshWorkerMemberException('output_sequence'));
      return;
    }
    _nextSequence++;
    final bytes = event.bytes!;
    if (bytes.isNotEmpty) _output.add(bytes);
    if (!event.isFinal!) {
      unawaited(_acknowledgeQuietly(event.sequence!));
      return;
    }
    final errorCode = event.errorCode;
    if (errorCode != null) {
      finishError(SshWorkerMemberException(errorCode));
      return;
    }
    finish(event.exitCode ?? 0);
  }

  Future<void> _acknowledgeQuietly(int sequence) async {
    try {
      await acknowledge(sequence);
    } on Object {
      // A final event can race the worker-side PTY cleanup. ACKs only provide
      // flow control, so a late rejection must not fail the terminal zone.
    }
  }

  Future<void> _writeQuietly(Uint8List data) async {
    try {
      // The protocol caps one payload at sshWorkerMaxChunkSize; large pastes
      // must be sliced instead of failing the whole terminal session.
      for (
        var offset = 0;
        offset < data.length;
        offset += sshWorkerMaxChunkSize
      ) {
        final end = (offset + sshWorkerMaxChunkSize).clamp(0, data.length);
        await writeRemote(Uint8List.sublistView(data, offset, end));
      }
    } on Object catch (error) {
      finishError(error);
    }
  }

  Future<void> _resizeQuietly(int rows, int columns) async {
    try {
      await resizeRemote(rows, columns);
    } on Object catch (error) {
      finishError(error);
    }
  }

  void finish(int exitCode) {
    if (_done.isCompleted) return;
    _finished = true;
    _closeRequested = true;
    _done.complete(exitCode);
    unawaited(_output.close());
    onFinished();
  }

  void finishError(Object error) {
    if (_done.isCompleted) return;
    _finished = true;
    _closeRequested = true;
    _done.completeError(error);
    unawaited(_output.close());
    onFinished();
  }

  Future<void> _closeRemote() async {
    try {
      await closeRemote();
    } on Object catch (error) {
      finishError(error);
    }
  }
}
