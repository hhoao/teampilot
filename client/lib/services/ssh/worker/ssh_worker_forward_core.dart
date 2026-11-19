import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../../models/ssh_profile.dart';
import 'ssh_worker_errors.dart';
import 'ssh_worker_forward_pump.dart';
import 'ssh_worker_protocol.dart';

abstract interface class SshWorkerForwardClient {
  Future<void> get authenticated;
  Future<SshWorkerForwardChannel> forwardLocal(String host, int port);
  Future<SshWorkerRemoteForward?> forwardRemote({
    required String host,
    required int port,
  });
  bool get isClosed;
  Future<void> get done;
  Future<void> disconnect();
}

abstract interface class SshWorkerRemoteForward {
  int get port;
  Stream<SshWorkerForwardChannel> get connections;
  Future<void> close();
}

/// Worker-local adapter from dartssh2 forwarding objects to primitive worker
/// surfaces. The adapter itself is never placed in a protocol message.
final class DartSshWorkerForwardClient implements SshWorkerForwardClient {
  DartSshWorkerForwardClient(this._client, {this.ownsClient = true});

  final SSHClient _client;

  /// When false, [disconnect] only drops this view; the shared worker client
  /// stays alive for storage/member/other forward planes.
  final bool ownsClient;

  @override
  Future<void> get authenticated async {
    await _client.authenticated;
  }

  @override
  Future<SshWorkerForwardChannel> forwardLocal(String host, int port) async =>
      DartSshWorkerForwardChannel(await _client.forwardLocal(host, port));

  @override
  Future<SshWorkerRemoteForward?> forwardRemote({
    required String host,
    required int port,
  }) async {
    final forward = await _client.forwardRemote(host: host, port: port);
    return forward == null ? null : DartSshWorkerRemoteForwardAdapter(forward);
  }

  @override
  bool get isClosed => _client.isClosed;

  @override
  Future<void> get done => _client.done;

  @override
  Future<void> disconnect() async {
    if (ownsClient) await _client.disconnect();
  }
}

final class DartSshWorkerRemoteForwardAdapter
    implements SshWorkerRemoteForward {
  DartSshWorkerRemoteForwardAdapter(this._forward);

  final SSHRemoteForward _forward;

  @override
  int get port => _forward.port;

  @override
  Stream<SshWorkerForwardChannel> get connections => _forward.connections.map(
    (channel) => DartSshWorkerForwardChannel(channel),
  );

  @override
  Future<void> close() => _forward.close();
}

typedef SshWorkerForwardClientOpener =
    Future<SshWorkerForwardClient> Function({
      required SshProfile profile,
      required SshWorkerDialTarget target,
      required Duration timeout,
    });

/// Worker-owned local forwards and reverse tunnels for one profile generation.
final class SshWorkerForwardCore {
  SshWorkerForwardCore({
    required this.profileId,
    required this.openClient,
    required this.sendEvent,
  });

  final String profileId;
  final SshWorkerForwardClientOpener openClient;
  final void Function(SshWorkerEvent event) sendEvent;
  final Map<String, _ForwardRecord> _forwards = {};
  final Map<String, SshWorkerForwardPump> _channels = {};
  final Map<String, String> _channelOwners = {};
  final Set<String> _openingForwardIds = {};
  final Map<String, Completer<void>> _pendingCloseCompletions = {};
  var _stopped = false;

  Future<SshWorkerReply> handle(SshWorkerRequest request) async {
    try {
      if (_stopped) throw const _ForwardFailure('worker_shutting_down');
      final result = await _dispatch(request);
      return SshWorkerReply.success(request.requestId, result: result);
    } on _ForwardFailure catch (error) {
      return _failure(request, error.code);
    } on FormatException {
      return _failure(request, 'invalid_forward_request');
    } on Object catch (error) {
      return _failure(request, sshWorkerErrorCode(error));
    }
  }

  Future<Map<String, Object?>> _dispatch(SshWorkerRequest request) =>
      switch (request.operation) {
        SshWorkerOperation.openForwardLocal => _openLocal(request),
        SshWorkerOperation.openForwardRemote => _openRemote(request),
        SshWorkerOperation.writeForwardChannel => _write(request),
        SshWorkerOperation.acknowledgeForwardOutput => _acknowledge(request),
        SshWorkerOperation.closeForwardChannel => _closeChannel(request),
        SshWorkerOperation.closeForward => _closeForward(request),
        _ => Future<Map<String, Object?>>.error(
          const _ForwardFailure('unsupported_operation'),
        ),
      };

  Future<Map<String, Object?>> _openLocal(SshWorkerRequest request) async {
    final forwardId = _id(request, 'forwardId');
    _ensureForwardAbsent(forwardId);
    _openingForwardIds.add(forwardId);
    try {
      return await _openLocalAfterRegistration(request, forwardId);
    } finally {
      _openingForwardIds.remove(forwardId);
      _completePendingClose(forwardId);
    }
  }

  Future<Map<String, Object?>> _openLocalAfterRegistration(
    SshWorkerRequest request,
    String forwardId,
  ) async {
    final client = await _openForwardClient(request);
    try {
      _ensureRunning();
      final channel = await client.forwardLocal(
        _host(request, 'host'),
        _port(request, 'port'),
      );
      if (_stopped || _pendingCloseCompletions.containsKey(forwardId)) {
        await _closeChannelQuietly(channel);
        throw _ForwardFailure(
          _stopped ? 'worker_shutting_down' : 'forward_closed',
        );
      }
      final record = _ForwardRecord(id: forwardId, client: client);
      _forwards[forwardId] = record;
      _addChannel(record, forwardId, channel);
      return {'forwardId': forwardId, 'channelId': forwardId};
    } on Object {
      await _disconnectQuietly(client);
      rethrow;
    }
  }

  Future<Map<String, Object?>> _openRemote(SshWorkerRequest request) async {
    final forwardId = _id(request, 'forwardId');
    _ensureForwardAbsent(forwardId);
    _openingForwardIds.add(forwardId);
    try {
      return await _openRemoteAfterRegistration(request, forwardId);
    } finally {
      _openingForwardIds.remove(forwardId);
      _completePendingClose(forwardId);
    }
  }

  Future<Map<String, Object?>> _openRemoteAfterRegistration(
    SshWorkerRequest request,
    String forwardId,
  ) async {
    final client = await _openForwardClient(request);
    try {
      _ensureRunning();
      final forward = await client.forwardRemote(
        host: _host(request, 'bindHost'),
        port: 0,
      );
      if (forward == null) throw const _ForwardFailure('forward_refused');
      if (_stopped || _pendingCloseCompletions.containsKey(forwardId)) {
        await _closeRemoteForwardQuietly(forward);
        throw _ForwardFailure(
          _stopped ? 'worker_shutting_down' : 'forward_closed',
        );
      }
      final record = _ForwardRecord(
        id: forwardId,
        client: client,
        remoteForward: forward,
      );
      _forwards[forwardId] = record;
      record.remoteConnections = forward.connections.listen(
        (channel) => _acceptRemoteChannel(record, channel),
        onError: (_, __) =>
            unawaited(_finishForward(record, errorCode: 'transport_error')),
        onDone: () => unawaited(_finishForward(record)),
        cancelOnError: true,
      );
      return {'forwardId': forwardId, 'port': forward.port};
    } on Object {
      await _disconnectQuietly(client);
      rethrow;
    }
  }

  Future<Map<String, Object?>> _write(SshWorkerRequest request) async {
    _channel(request).write(request.payload!);
    return const {};
  }

  Future<Map<String, Object?>> _acknowledge(SshWorkerRequest request) async {
    final channel = _channels[_id(request, 'channelId')];
    if (channel != null) channel.acknowledge(_nonNegative(request, 'sequence'));
    return const {};
  }

  Future<Map<String, Object?>> _closeChannel(SshWorkerRequest request) async {
    final channelId = _id(request, 'channelId');
    final channel = _channels[channelId];
    if (channel != null) await channel.close();
    return const {};
  }

  Future<Map<String, Object?>> _closeForward(SshWorkerRequest request) async {
    final forwardId = _id(request, 'forwardId');
    final record = _forwards[forwardId];
    if (record != null) await _finishForward(record);
    if (record == null && _openingForwardIds.contains(forwardId)) {
      final completion = _pendingCloseCompletions.putIfAbsent(
        forwardId,
        Completer<void>.new,
      );
      await completion.future;
    }
    return const {};
  }

  void _acceptRemoteChannel(
    _ForwardRecord record,
    SshWorkerForwardChannel channel,
  ) {
    if (!identical(_forwards[record.id], record)) {
      unawaited(channel.close());
      return;
    }
    final channelId = '${record.id}/channel-${record.nextChannelId++}';
    sendEvent(
      SshWorkerEvent.forwardChannelOpened(
        forwardId: record.id,
        channelId: channelId,
      ),
    );
    _addChannel(record, channelId, channel);
  }

  void _addChannel(
    _ForwardRecord record,
    String channelId,
    SshWorkerForwardChannel channel,
  ) {
    final pump = SshWorkerForwardPump(
      id: channelId,
      channel: channel,
      sendEvent: sendEvent,
      onFinished: (errorCode) =>
          unawaited(_finishChannel(record, channelId, errorCode: errorCode)),
    );
    _channels[channelId] = pump;
    _channelOwners[channelId] = record.id;
    pump.start();
  }

  Future<void> _finishChannel(
    _ForwardRecord record,
    String channelId, {
    String? errorCode,
  }) async {
    _channels.remove(channelId);
    _channelOwners.remove(channelId);
    if (record.remoteForward == null) {
      await _finishForward(record, errorCode: errorCode);
    }
  }

  Future<void> _finishForward(
    _ForwardRecord record, {
    String? errorCode,
  }) async {
    if (!identical(_forwards[record.id], record) || record.finishing) return;
    record.finishing = true;
    _forwards.remove(record.id);
    await record.remoteConnections?.cancel();
    final channelIds = _channelOwners.entries
        .where((entry) => entry.value == record.id)
        .map((entry) => entry.key)
        .toList(growable: false);
    await Future.wait([
      for (final channelId in channelIds)
        if (_channels[channelId] case final channel?) channel.close(),
    ]);
    try {
      await record.remoteForward?.close();
    } on Object {
      // Transport closure below is still required after a remote race.
    }
    await _disconnectQuietly(record.client);
    sendEvent(
      SshWorkerEvent.forwardClosed(forwardId: record.id, errorCode: errorCode),
    );
  }

  Future<SshWorkerForwardClient> _openForwardClient(
    SshWorkerRequest request,
  ) async {
    final target = SshWorkerDialTarget.fromWire(request.args['target']);
    final profile = _profile(request, target);
    final client = await openClient(
      profile: profile,
      target: target,
      timeout: _timeout(request),
    );
    try {
      await client.authenticated;
      _watchForwardClient(client);
      return client;
    } on Object {
      await _disconnectQuietly(client);
      rethrow;
    }
  }

  void _watchForwardClient(SshWorkerForwardClient client) {
    void transportLost() {
      if (_stopped) return;
      for (final record
          in _forwards.values
              .where((record) => identical(record.client, client))
              .toList(growable: false)) {
        unawaited(_finishForward(record, errorCode: 'transport_error'));
      }
    }

    unawaited(
      client.done.then<void>(
        (_) => transportLost(),
        onError: (Object _, StackTrace __) => transportLost(),
      ),
    );
  }

  void _completePendingClose(String forwardId) {
    final completion = _pendingCloseCompletions.remove(forwardId);
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  SshWorkerForwardPump _channel(SshWorkerRequest request) {
    final channel = _channels[_id(request, 'channelId')];
    if (channel == null) throw const _ForwardFailure('channel_not_found');
    return channel;
  }

  void _ensureForwardAbsent(String forwardId) {
    if (_forwards.containsKey(forwardId)) {
      throw const _ForwardFailure('forward_exists');
    }
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
    milliseconds: _positive(
      request,
      'timeoutMs',
      defaultValue: const Duration(seconds: 10).inMilliseconds,
    ),
  );

  Future<void> shutdown() async {
    beginShutdown();
    await Future.wait(
      _forwards.values.toList(growable: false).map(_finishForward),
    );
  }

  /// Stops new resources from being registered while existing opens drain.
  void beginShutdown() {
    _stopped = true;
  }

  void _ensureRunning() {
    if (_stopped) throw const _ForwardFailure('worker_shutting_down');
  }

  SshWorkerReply _failure(SshWorkerRequest request, String code) =>
      SshWorkerReply.failure(
        request.requestId,
        SshWorkerErrorRecord(code: code, message: 'Forward operation failed'),
      );
}

final class _ForwardRecord {
  _ForwardRecord({required this.id, required this.client, this.remoteForward});

  final String id;
  final SshWorkerForwardClient client;
  final SshWorkerRemoteForward? remoteForward;
  StreamSubscription<SshWorkerForwardChannel>? remoteConnections;
  var nextChannelId = 0;
  var finishing = false;
}

String _id(SshWorkerRequest request, String key) {
  final value = request.args[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String _host(SshWorkerRequest request, String key) => _id(request, key);

int _port(SshWorkerRequest request, String key) {
  final value = request.args[key];
  if (value is! int || value < 1 || value > 65535) {
    throw const FormatException();
  }
  return value;
}

int _positive(
  SshWorkerRequest request,
  String key, {
  required int defaultValue,
}) {
  final value = request.args[key] ?? defaultValue;
  if (value is! int || value < 1) throw const FormatException();
  return value;
}

int _nonNegative(SshWorkerRequest request, String key) {
  final value = request.args[key];
  if (value is! int || value < 0) throw const FormatException();
  return value;
}

Future<void> _disconnectQuietly(SshWorkerForwardClient client) async {
  try {
    if (!client.isClosed) await client.disconnect();
  } on Object {
    // Shutdown and remote close races are expected during forwarding cleanup.
  }
}

Future<void> _closeChannelQuietly(SshWorkerForwardChannel channel) async {
  try {
    await channel.close();
  } on Object {
    // The client disconnect below remains authoritative during shutdown.
  }
}

Future<void> _closeRemoteForwardQuietly(SshWorkerRemoteForward forward) async {
  try {
    await forward.close();
  } on Object {
    // The client disconnect below remains authoritative during shutdown.
  }
}

final class _ForwardFailure implements Exception {
  const _ForwardFailure(this.code);

  final String code;
}
