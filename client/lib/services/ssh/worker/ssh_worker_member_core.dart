import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

import '../../../models/ssh_profile.dart';
import '../ssh_transport_close.dart';
import 'ssh_worker_errors.dart';
import 'ssh_worker_protocol.dart';
import 'ssh_worker_exec_pump.dart';
import 'ssh_worker_pty_pump.dart';
import 'ssh_worker_storage_types.dart';

typedef SshWorkerMemberClientOpener =
    Future<SSHClient> Function({
      required SshProfile profile,
      required SshWorkerDialTarget target,
      required Duration timeout,
    });

/// Worker-owned member clients and PTY channels for one profile generation.
final class SshWorkerMemberCore {
  SshWorkerMemberCore({
    required this.profileId,
    required this.openClient,
    required this.sendEvent,
  });

  final String profileId;
  final SshWorkerMemberClientOpener openClient;
  final void Function(SshWorkerEvent event) sendEvent;
  final Map<String, SSHClient> _members = {};
  final Map<String, SshWorkerExecPump> _execs = {};
  final Map<String, SshWorkerPtyPump> _ptys = {};
  var _stopped = false;

  Future<SshWorkerReply> handle(SshWorkerRequest request) async {
    try {
      if (_stopped) throw const _MemberFailure('worker_shutting_down');
      final result = await _dispatch(request);
      return SshWorkerReply.success(request.requestId, result: result);
    } on _MemberFailure catch (error) {
      return _failure(request, error.code);
    } on FormatException {
      return _failure(request, 'invalid_member_request');
    } on Object catch (error) {
      return _failure(request, sshWorkerErrorCode(error));
    }
  }

  Future<Map<String, Object?>> _dispatch(SshWorkerRequest request) async {
    switch (request.operation) {
      case SshWorkerOperation.openMember:
        return _openMember(request);
      case SshWorkerOperation.runMember:
        return _run(request);
      case SshWorkerOperation.startMemberExec:
        return _startExec(request);
      case SshWorkerOperation.writeMemberExec:
        _exec(request).write(request.payload!);
        return const {};
      case SshWorkerOperation.closeMemberExecStdin:
        _exec(request).closeStdin();
        return const {};
      case SshWorkerOperation.killMemberExec:
        _exec(request).kill();
        return const {};
      case SshWorkerOperation.acknowledgeExecOutput:
        _exec(request).acknowledge(_integer(request, 'sequence', minimum: 0));
        return const {};
      case SshWorkerOperation.openPty:
        return _openPty(request);
      case SshWorkerOperation.writePty:
        _pty(request).write(request.payload!);
        return const {};
      case SshWorkerOperation.resizePty:
        _pty(request).resize(
          _integer(request, 'rows', minimum: 1),
          _integer(request, 'columns', minimum: 1),
        );
        return const {};
      case SshWorkerOperation.acknowledgePtyOutput:
        _pty(request).acknowledge(_integer(request, 'sequence', minimum: 0));
        return const {};
      case SshWorkerOperation.closeChannel:
        return _closeChannel(request);
      default:
        throw const _MemberFailure('unsupported_operation');
    }
  }

  Future<Map<String, Object?>> _openMember(SshWorkerRequest request) async {
    final memberId = _string(request, 'memberId');
    if (_members.containsKey(memberId)) {
      throw const _MemberFailure('member_exists');
    }
    final target = SshWorkerDialTarget.fromWire(request.args['target']);
    final profile = _profile(request, target);
    final client = await openClient(
      profile: profile,
      target: target,
      timeout: _timeout(request),
    );
    try {
      await client.authenticated;
      if (_stopped) throw const _MemberFailure('worker_shutting_down');
      _members[memberId] = client;
      _watchMemberTransport(memberId, client);
      sendEvent(
        SshWorkerEvent.stateChanged(
          state: SshWorkerState.connected,
          plane: SshTransportPlane.member,
        ),
      );
      return {'memberId': memberId};
    } on Object {
      // The shared worker client owns the transport; closing it here would
      // also tear down other member/forward/storage planes.
      rethrow;
    }
  }

  Future<Map<String, Object?>> _run(SshWorkerRequest request) async {
    final session = await _member(request).execute(_string(request, 'command'));
    final stdout = BytesBuilder(copy: false);
    final stderr = BytesBuilder(copy: false);
    final captureStderr = _boolean(request, 'stderr', defaultValue: true);
    var total = 0;
    Future<void> collect(
      Stream<Uint8List> stream,
      BytesBuilder target,
      bool capture,
    ) async {
      await for (final bytes in stream) {
        if (!capture) continue;
        total += bytes.length;
        if (total > sshWorkerMaxExecOutput) {
          session.close();
          throw const _MemberFailure('output_limit');
        }
        target.add(bytes);
      }
    }

    try {
      await Future.wait([
        collect(session.stdout, stdout, true),
        collect(session.stderr, stderr, captureStderr),
        session.done,
      ], eagerError: true);
    } finally {
      session.close();
    }
    return SshWorkerRunResult(
      stdout: stdout.takeBytes(),
      stderr: stderr.takeBytes(),
      exitCode: session.exitCode,
      signalName: session.exitSignal?.signalName,
    ).toWire();
  }

  void _watchMemberTransport(String memberId, SSHClient client) {
    client.done.then<void>(
      (_) => _handleMemberTransportClosed(memberId, client),
      onError: (_, __) => _handleMemberTransportClosed(memberId, client),
    );
  }

  Future<void> _handleMemberTransportClosed(
    String memberId,
    SSHClient client,
  ) async {
    if (!identical(_members[memberId], client)) return;
    _members.remove(memberId);
    final ptys = _ptys.entries
        .where((entry) => entry.value.memberId == memberId)
        .map((entry) => entry.value)
        .toList(growable: false);
    final execs = _execs.values
        .where((exec) => exec.id.startsWith('$memberId/'))
        .toList(growable: false);
    await Future.wait([
      ...ptys.map((pty) => pty.close()),
      ...execs.map((exec) => exec.close()),
    ]);
    sendEvent(
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.member,
        reason: SshTransportCloseReason.transportError,
        streamId: memberId,
      ),
    );
  }

  Future<Map<String, Object?>> _startExec(SshWorkerRequest request) async {
    final execId = _string(request, 'execId');
    if (_execs.containsKey(execId)) {
      throw const _MemberFailure('channel_exists');
    }
    final session = await _member(request).execute(_string(request, 'command'));
    if (_stopped) {
      session.close();
      throw const _MemberFailure('worker_shutting_down');
    }
    final exec = SshWorkerExecPump(
      id: execId,
      session: DartSshWorkerExecSession(session),
      sendEvent: sendEvent,
      onFinished: () => _execs.remove(execId),
    );
    _execs[execId] = exec;
    exec.start();
    return {'execId': execId};
  }

  Future<Map<String, Object?>> _openPty(SshWorkerRequest request) async {
    final ptyId = _string(request, 'ptyId');
    if (_ptys.containsKey(ptyId)) throw const _MemberFailure('channel_exists');
    final columns = _integer(request, 'columns', minimum: 1);
    final rows = _integer(request, 'rows', minimum: 1);
    final command = _optionalString(request, 'command');
    final environment = _environment(request.args['environment']);
    final session = command == null
        ? await _member(request).shell(
            pty: SSHPtyConfig(
              type: 'xterm-256color',
              width: columns,
              height: rows,
            ),
            environment: environment,
          )
        : await _member(request).execute(
            command,
            pty: SSHPtyConfig(
              type: 'xterm-256color',
              width: columns,
              height: rows,
            ),
            environment: environment,
          );
    if (_stopped) {
      session.close();
      throw const _MemberFailure('worker_shutting_down');
    }
    final pty = SshWorkerPtyPump(
      id: ptyId,
      memberId: _string(request, 'memberId'),
      session: DartSshWorkerPtySession(session),
      sendEvent: sendEvent,
      onFinished: () => _ptys.remove(ptyId),
      outputWindow: _integer(
        request,
        'outputWindow',
        defaultValue: 4,
        minimum: 1,
        maximum: 64,
      ),
    );
    _ptys[ptyId] = pty;
    pty.start();
    return {'ptyId': ptyId};
  }

  Future<Map<String, Object?>> _closeChannel(SshWorkerRequest request) async {
    final channelId = _string(request, 'channelId');
    final pty = _ptys[channelId];
    if (pty != null) {
      await pty.close();
      return const {};
    }
    final exec = _execs[channelId];
    if (exec != null) {
      await exec.close();
      return const {};
    }
    final member = _members.remove(channelId);
    // Close is idempotent: final events can remove a channel before a
    // concurrent teardown reaches the worker.
    if (member == null) return const {};
    final ownedPtys = _ptys.entries
        .where((entry) => entry.value.memberId == channelId)
        .map((entry) => entry.key)
        .toList(growable: false);
    final ownedExecs = _execs.values
        .where((exec) => exec.id.startsWith('$channelId/'))
        .toList(growable: false);
    await Future.wait([
      for (final ptyId in ownedPtys)
        if (_ptys[ptyId] case final pty?) pty.close(),
      ...ownedExecs.map((exec) => exec.close()),
    ]);
    sendEvent(
      SshWorkerEvent.transportClosed(
        plane: SshTransportPlane.member,
        reason: SshTransportCloseReason.memberSessionClosed,
        streamId: channelId,
      ),
    );
    return const {};
  }

  Future<void> shutdown() async {
    if (_stopped) return;
    _stopped = true;
    final ptys = _ptys.values.toList(growable: false);
    _ptys.clear();
    final execs = _execs.values.toList(growable: false);
    _execs.clear();
    await Future.wait([
      ...ptys.map((pty) => pty.close()),
      ...execs.map((exec) => exec.close()),
    ]);
    _members.clear();
  }

  SSHClient _member(SshWorkerRequest request) {
    final member = _members[_string(request, 'memberId')];
    if (member == null) throw const _MemberFailure('member_not_found');
    return member;
  }

  SshWorkerPtyPump _pty(SshWorkerRequest request) {
    final pty = _ptys[_string(request, 'ptyId')];
    if (pty == null) throw const _MemberFailure('channel_not_found');
    return pty;
  }

  SshWorkerExecPump _exec(SshWorkerRequest request) {
    final exec = _execs[_string(request, 'execId')];
    if (exec == null) throw const _MemberFailure('channel_not_found');
    return exec;
  }

  SshProfile _profile(
    SshWorkerRequest request,
    SshWorkerDialTarget target,
  ) {
    final ref = SshWorkerConnectionRef.fromArgs(request.args);
    if (ref.machineId != profileId) throw const FormatException();
    return ref.profileFor(target);
  }

  Duration _timeout(SshWorkerRequest request) => Duration(
    milliseconds: _integer(
      request,
      'timeoutMs',
      defaultValue: const Duration(seconds: 10).inMilliseconds,
      minimum: 1,
    ),
  );

  SshWorkerReply _failure(SshWorkerRequest request, String code) =>
      SshWorkerReply.failure(
        request.requestId,
        SshWorkerErrorRecord(code: code, message: 'Member operation failed'),
      );
}

String _string(SshWorkerRequest request, String key) {
  final value = request.args[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String? _optionalString(SshWorkerRequest request, String key) {
  final value = request.args[key];
  if (value == null) return null;
  if (value is! String) throw const FormatException();
  return value;
}

int _integer(
  SshWorkerRequest request,
  String key, {
  int? defaultValue,
  required int minimum,
  int? maximum,
}) {
  final value = request.args[key] ?? defaultValue;
  if (value is! int ||
      value < minimum ||
      (maximum != null && value > maximum)) {
    throw const FormatException();
  }
  return value;
}

bool _boolean(
  SshWorkerRequest request,
  String key, {
  required bool defaultValue,
}) {
  final value = request.args[key] ?? defaultValue;
  if (value is! bool) throw const FormatException();
  return value;
}

Map<String, String>? _environment(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw const FormatException();
  final environment = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const FormatException();
    }
    environment[entry.key as String] = entry.value as String;
  }
  return environment;
}

final class _MemberFailure implements Exception {
  const _MemberFailure(this.code);

  final String code;
}
