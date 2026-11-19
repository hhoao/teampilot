import 'dart:isolate';
import 'dart:typed_data';

import '../../../models/ssh_auth_type.dart';
import '../../../models/ssh_profile.dart';
import '../ssh_transport_close.dart';

/// The version of the isolate protocol. It is deliberately independent of
/// persisted profile schema versions.
const int sshWorkerProtocolVersion = 2;

/// Payloads crossing the worker boundary may not contain SSH library objects.
const int sshWorkerMaxChunkSize = 1024 * 1024;

/// A `runStorage` stdin payload is a one-shot launch/provisioning blob, not a
/// streamed terminal write. It may exceed the per-chunk limit but stays
/// bounded to the same budget as storage exec output.
const int sshWorkerMaxStorageStdinBytes = 32 * 1024 * 1024;

/// Stable error codes carried across the worker boundary.
///
/// The UI isolate cannot inspect dartssh2 exception types once the failure is
/// flattened into a reply, so worker-side classification preserves the few
/// codes that drive retry, pairing, and user-facing messages.
abstract interface class SshWorkerCodedException implements Exception {
  String? get code;
}

enum SshWorkerOperation {
  connectStorage,
  disconnectStorage,
  runStorage,
  openSftpRead,
  readSftpChunk,
  openSftpWrite,
  writeSftpChunk,
  closeSftpStream,
  acknowledgeSftpChunk,
  statSftp,
  listSftpDirectory,
  readlinkSftp,
  realpathSftp,
  mkdirSftp,
  removeSftp,
  openMember,
  runMember,
  startMemberExec,
  writeMemberExec,
  closeMemberExecStdin,
  killMemberExec,
  acknowledgeExecOutput,
  openPty,
  writePty,
  resizePty,
  acknowledgePtyOutput,
  openForwardLocal,
  openForwardRemote,
  writeForwardChannel,
  acknowledgeForwardOutput,
  closeForwardChannel,
  closeForward,
  closeChannel,
  cancelRequest,
  shutdown,
}

enum SshWorkerReplyKind { success, failure, cancellation, streamCompletion }

enum SshWorkerEventKind {
  stateChange,
  execOutput,
  outputChunk,
  forwardChannelOpened,
  forwardClosed,
  transportClose,
}

enum SshWorkerState { connecting, connected, disconnecting, disconnected }

enum SshWorkerAuthChallengeKind {
  password,
  privateKey,
  privateKeyPassphrase,
  hostKey,
  dialTarget,
}

enum SshWorkerExecStream { stdout, stderr }

/// A primitive, correlated auth request sent from a profile worker to the UI.
class SshWorkerAuthChallenge {
  SshWorkerAuthChallenge._({
    required this.requestId,
    required this.profileId,
    required this.kind,
    this.keyType,
    Uint8List? fingerprint,
  }) : fingerprint = fingerprint == null
           ? null
           : Uint8List.fromList(fingerprint);

  factory SshWorkerAuthChallenge.password({
    required String requestId,
    required String profileId,
  }) => SshWorkerAuthChallenge._(
    requestId: requestId,
    profileId: profileId,
    kind: SshWorkerAuthChallengeKind.password,
  );

  factory SshWorkerAuthChallenge.privateKey({
    required String requestId,
    required String profileId,
  }) => SshWorkerAuthChallenge._(
    requestId: requestId,
    profileId: profileId,
    kind: SshWorkerAuthChallengeKind.privateKey,
  );

  factory SshWorkerAuthChallenge.privateKeyPassphrase({
    required String requestId,
    required String profileId,
  }) => SshWorkerAuthChallenge._(
    requestId: requestId,
    profileId: profileId,
    kind: SshWorkerAuthChallengeKind.privateKeyPassphrase,
  );

  factory SshWorkerAuthChallenge.hostKey({
    required String requestId,
    required String profileId,
    required String keyType,
    required Uint8List fingerprint,
  }) => SshWorkerAuthChallenge._(
    requestId: requestId,
    profileId: profileId,
    kind: SshWorkerAuthChallengeKind.hostKey,
    keyType: keyType,
    fingerprint: fingerprint,
  );

  factory SshWorkerAuthChallenge.dialTarget({
    required String requestId,
    required String profileId,
  }) => SshWorkerAuthChallenge._(
    requestId: requestId,
    profileId: profileId,
    kind: SshWorkerAuthChallengeKind.dialTarget,
  );

  final String requestId;
  final String profileId;
  final SshWorkerAuthChallengeKind kind;
  final String? keyType;
  final Uint8List? fingerprint;

  SshWorkerAuthChallenge withRequestId(String value) =>
      SshWorkerAuthChallenge._(
        requestId: value,
        profileId: profileId,
        kind: kind,
        keyType: keyType,
        fingerprint: fingerprint,
      );

  Map<String, Object?> toWire() => {
    'version': sshWorkerProtocolVersion,
    'type': 'authChallenge',
    'requestId': requestId,
    'profileId': profileId,
    'kind': kind.name,
    if (keyType != null) 'keyType': keyType,
    if (fingerprint != null) 'fingerprint': Uint8List.fromList(fingerprint!),
  };

  factory SshWorkerAuthChallenge.fromWire(Object? wire) {
    final map = _map(wire);
    _version(map);
    _expect(map['type'] == 'authChallenge');
    final kind = _enumValue(
      SshWorkerAuthChallengeKind.values,
      _requiredString(map, 'kind'),
    );
    final keyType = _optionalString(map, 'keyType');
    final fingerprint = _bytes(map['fingerprint']);
    if (kind == SshWorkerAuthChallengeKind.hostKey &&
        (keyType == null || fingerprint == null)) {
      throw _malformed();
    }
    if (kind != SshWorkerAuthChallengeKind.hostKey &&
        (keyType != null || fingerprint != null)) {
      throw _malformed();
    }
    return SshWorkerAuthChallenge._(
      requestId: _requiredString(map, 'requestId'),
      profileId: _requiredString(map, 'profileId'),
      kind: kind,
      keyType: keyType,
      fingerprint: fingerprint,
    );
  }
}

/// A correlated UI reply to [SshWorkerAuthChallenge].
class SshWorkerAuthReply {
  const SshWorkerAuthReply._({
    required this.requestId,
    this.secretValue,
    this.hasSecret = false,
    this.accepted,
    this.target,
    this.errorCode,
  });

  const SshWorkerAuthReply.secret({
    required String requestId,
    required String? value,
  }) : this._(requestId: requestId, secretValue: value, hasSecret: true);

  const SshWorkerAuthReply.decision({
    required String requestId,
    required bool value,
  }) : this._(requestId: requestId, accepted: value);

  const SshWorkerAuthReply.dialTarget({
    required String requestId,
    required SshWorkerDialTarget value,
  }) : this._(requestId: requestId, target: value);

  const SshWorkerAuthReply.failure({
    required String requestId,
    required String errorCode,
  }) : this._(requestId: requestId, errorCode: errorCode);

  final String requestId;
  final String? secretValue;
  final bool hasSecret;
  final bool? accepted;
  final SshWorkerDialTarget? target;
  final String? errorCode;

  Map<String, Object?> toWire() => {
    'version': sshWorkerProtocolVersion,
    'type': 'authReply',
    'requestId': requestId,
    if (hasSecret) 'secret': secretValue,
    if (accepted != null) 'accepted': accepted,
    if (target != null) 'target': target!.toWire(),
    if (errorCode != null) 'errorCode': errorCode,
  };

  factory SshWorkerAuthReply.fromWire(Object? wire) {
    final map = _map(wire);
    _version(map);
    _expect(map['type'] == 'authReply');
    final hasSecret = map.containsKey('secret');
    final secret = map['secret'];
    if (secret != null && secret is! String) throw _malformed();
    final accepted = _optionalBool(map, 'accepted');
    final target = map['target'];
    final errorCode = _optionalString(map, 'errorCode');
    final values = [
      hasSecret,
      accepted != null,
      target != null,
      errorCode != null,
    ].where((value) => value).length;
    if (values != 1) throw _malformed();
    return SshWorkerAuthReply._(
      requestId: _requiredString(map, 'requestId'),
      secretValue: secret as String?,
      hasSecret: hasSecret,
      accepted: accepted,
      target: target == null ? null : SshWorkerDialTarget.fromWire(target),
      errorCode: errorCode,
    );
  }
}

typedef SshWorkerAuthChallengeHandler =
    Future<SshWorkerAuthReply> Function(SshWorkerAuthChallenge challenge);

class SshWorkerRequest {
  const SshWorkerRequest({
    required this.requestId,
    required this.operation,
    this.args = const {},
    this.payload,
  });

  final String requestId;
  final SshWorkerOperation operation;
  final Map<String, Object?> args;
  final Uint8List? payload;

  Map<String, Object?> toWire() {
    _validatePayload(operation, payload);
    return {
      'version': sshWorkerProtocolVersion,
      'type': 'request',
      'requestId': requestId,
      'operation': operation.name,
      'args': _primitiveMap(args),
      if (payload != null) 'payload': payload!,
    };
  }

  factory SshWorkerRequest.fromWire(Object? wire) {
    final map = _map(wire);
    _version(map);
    _expect(map['type'] == 'request');
    final requestId = _requiredString(map, 'requestId');
    final operation = _enumValue(
      SshWorkerOperation.values,
      _requiredString(map, 'operation'),
    );
    final payload = _bytes(map['payload']);
    _validatePayload(operation, payload);
    final rawArgs = map['args'];
    if (rawArgs != null && rawArgs is! Map) {
      throw _malformed();
    }
    final args = rawArgs == null
        ? const <String, Object?>{}
        : _primitiveMap((rawArgs as Map).cast<Object?, Object?>());
    final declaredChunkSize = args['chunkSize'];
    if (declaredChunkSize is int && declaredChunkSize > sshWorkerMaxChunkSize) {
      throw _malformed();
    }
    return SshWorkerRequest(
      requestId: requestId,
      operation: operation,
      args: args,
      payload: payload,
    );
  }
}

class SshWorkerErrorRecord {
  const SshWorkerErrorRecord({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  Map<String, Object?> toWire() => {
    'code': code,
    'message': message,
    'retryable': retryable,
  };

  factory SshWorkerErrorRecord.fromWire(Object? wire) {
    final map = _map(wire);
    return SshWorkerErrorRecord(
      code: _requiredString(map, 'code'),
      message: _requiredString(map, 'message'),
      retryable: _optionalBool(map, 'retryable') ?? false,
    );
  }
}

class SshWorkerReply {
  const SshWorkerReply._({
    required this.requestId,
    required this.kind,
    this.result = const {},
    this.error,
  });

  final String requestId;
  final SshWorkerReplyKind kind;
  final Map<String, Object?> result;
  final SshWorkerErrorRecord? error;

  factory SshWorkerReply.success(
    String requestId, {
    Map<String, Object?> result = const {},
  }) => SshWorkerReply._(
    requestId: requestId,
    kind: SshWorkerReplyKind.success,
    result: result,
  );

  factory SshWorkerReply.failure(
    String requestId,
    SshWorkerErrorRecord error,
  ) => SshWorkerReply._(
    requestId: requestId,
    kind: SshWorkerReplyKind.failure,
    error: error,
  );

  factory SshWorkerReply.cancellation(String requestId) => SshWorkerReply._(
    requestId: requestId,
    kind: SshWorkerReplyKind.cancellation,
  );

  factory SshWorkerReply.streamCompletion(
    String requestId, {
    Map<String, Object?> result = const {},
  }) => SshWorkerReply._(
    requestId: requestId,
    kind: SshWorkerReplyKind.streamCompletion,
    result: result,
  );

  Map<String, Object?> toWire() => {
    'version': sshWorkerProtocolVersion,
    'type': 'reply',
    'requestId': requestId,
    'kind': kind.name,
    if (kind == SshWorkerReplyKind.success ||
        kind == SshWorkerReplyKind.streamCompletion)
      'result': _primitiveMap(result),
    if (error != null) 'error': error!.toWire(),
  };

  factory SshWorkerReply.fromWire(Object? wire) {
    final map = _map(wire);
    _version(map);
    _expect(map['type'] == 'reply');
    final kind = _enumValue(
      SshWorkerReplyKind.values,
      _requiredString(map, 'kind'),
    );
    final requestId = _requiredString(map, 'requestId');
    final rawResult = map['result'];
    if (rawResult != null && rawResult is! Map) throw _malformed();
    final rawError = map['error'];
    final error = rawError == null
        ? null
        : SshWorkerErrorRecord.fromWire(rawError);
    if (kind == SshWorkerReplyKind.failure && error == null) throw _malformed();
    if (kind != SshWorkerReplyKind.failure && error != null) throw _malformed();
    return SshWorkerReply._(
      requestId: requestId,
      kind: kind,
      result: rawResult == null
          ? const {}
          : _primitiveMap((rawResult as Map).cast<Object?, Object?>()),
      error: error,
    );
  }
}

class SshWorkerEvent {
  const SshWorkerEvent._({
    required this.kind,
    this.streamId,
    this.stream,
    this.sequence,
    this.bytes,
    this.isFinal,
    this.exitCode,
    this.state,
    this.plane,
    this.reason,
    this.forwardId,
    this.channelId,
    this.errorCode,
  });

  final SshWorkerEventKind kind;
  final String? streamId;
  final SshWorkerExecStream? stream;
  final int? sequence;
  final Uint8List? bytes;
  final bool? isFinal;
  final int? exitCode;
  final SshWorkerState? state;
  final SshTransportPlane? plane;
  final SshTransportCloseReason? reason;
  final String? forwardId;
  final String? channelId;
  final String? errorCode;

  factory SshWorkerEvent.outputChunk({
    required String streamId,
    required int sequence,
    required Uint8List bytes,
    required bool isFinal,
    int? exitCode,
    String? errorCode,
  }) {
    _checkNonNegative(sequence);
    _checkChunkSize(bytes.length);
    return SshWorkerEvent._(
      kind: SshWorkerEventKind.outputChunk,
      streamId: streamId,
      sequence: sequence,
      bytes: bytes,
      isFinal: isFinal,
      exitCode: exitCode,
      errorCode: errorCode,
    );
  }

  factory SshWorkerEvent.execOutput({
    required String streamId,
    required int sequence,
    SshWorkerExecStream? stream,
    required Uint8List bytes,
    bool isFinal = false,
    int? exitCode,
    String? errorCode,
  }) {
    _checkNonNegative(sequence);
    _checkChunkSize(bytes.length);
    if (!isFinal && stream == null) throw _malformed();
    if (isFinal && stream != null) throw _malformed();
    if (errorCode != null && !isFinal) throw _malformed();
    return SshWorkerEvent._(
      kind: SshWorkerEventKind.execOutput,
      streamId: streamId,
      sequence: sequence,
      stream: stream,
      bytes: bytes,
      isFinal: isFinal,
      exitCode: exitCode,
      errorCode: errorCode,
    );
  }

  factory SshWorkerEvent.stateChanged({
    required SshWorkerState state,
    required SshTransportPlane plane,
  }) => SshWorkerEvent._(
    kind: SshWorkerEventKind.stateChange,
    state: state,
    plane: plane,
  );

  factory SshWorkerEvent.transportClosed({
    required SshTransportPlane plane,
    required SshTransportCloseReason reason,
    String? streamId,
  }) => SshWorkerEvent._(
    kind: SshWorkerEventKind.transportClose,
    streamId: streamId,
    plane: plane,
    reason: reason,
  );

  factory SshWorkerEvent.forwardChannelOpened({
    required String forwardId,
    required String channelId,
  }) => SshWorkerEvent._(
    kind: SshWorkerEventKind.forwardChannelOpened,
    forwardId: forwardId,
    channelId: channelId,
  );

  factory SshWorkerEvent.forwardClosed({
    required String forwardId,
    String? errorCode,
  }) => SshWorkerEvent._(
    kind: SshWorkerEventKind.forwardClosed,
    forwardId: forwardId,
    errorCode: errorCode,
  );

  Map<String, Object?> toWire() {
    if (kind == SshWorkerEventKind.outputChunk) {
      _checkChunkSize(bytes!.length);
    }
    return {
      'version': sshWorkerProtocolVersion,
      'type': 'event',
      'kind': kind.name,
      if (streamId != null) 'streamId': streamId,
      if (stream != null) 'stream': stream!.name,
      if (sequence != null) 'sequence': sequence,
      if (bytes != null) 'bytes': bytes,
      if (isFinal != null) 'isFinal': isFinal,
      if (exitCode != null) 'exitCode': exitCode,
      if (state != null) 'state': state!.name,
      if (plane != null) 'plane': plane!.name,
      if (reason != null) 'reason': reason!.name,
      if (forwardId != null) 'forwardId': forwardId,
      if (channelId != null) 'channelId': channelId,
      if (errorCode != null) 'errorCode': errorCode,
    };
  }

  factory SshWorkerEvent.fromWire(Object? wire) {
    final map = _map(wire);
    _version(map);
    _expect(map['type'] == 'event');
    final kind = _enumValue(
      SshWorkerEventKind.values,
      _requiredString(map, 'kind'),
    );
    final streamId = _optionalString(map, 'streamId');
    final stream = _optionalEnum<SshWorkerExecStream>(
      map,
      'stream',
      SshWorkerExecStream.values,
    );
    final sequence = _optionalInt(map, 'sequence');
    final bytes = _bytes(map['bytes']);
    final isFinal = _optionalBool(map, 'isFinal');
    final exitCode = _optionalInt(map, 'exitCode');
    final state = _optionalEnum<SshWorkerState>(
      map,
      'state',
      SshWorkerState.values,
    );
    final plane = _optionalEnum<SshTransportPlane>(
      map,
      'plane',
      SshTransportPlane.values,
    );
    final reason = _optionalEnum<SshTransportCloseReason>(
      map,
      'reason',
      SshTransportCloseReason.values,
    );
    final forwardId = _optionalString(map, 'forwardId');
    final channelId = _optionalString(map, 'channelId');
    final errorCode = _optionalString(map, 'errorCode');
    if (kind == SshWorkerEventKind.outputChunk) {
      if (streamId == null ||
          sequence == null ||
          bytes == null ||
          isFinal == null) {
        throw _malformed();
      }
      _checkNonNegative(sequence);
      _checkChunkSize(bytes.length);
      if (exitCode != null && !isFinal) throw _malformed();
      if (errorCode != null && !isFinal) throw _malformed();
    }
    if (kind == SshWorkerEventKind.execOutput) {
      if (streamId == null ||
          sequence == null ||
          bytes == null ||
          isFinal == null) {
        throw _malformed();
      }
      _checkNonNegative(sequence);
      _checkChunkSize(bytes.length);
      if (isFinal && stream != null) throw _malformed();
      if (!isFinal && stream == null) throw _malformed();
      if (exitCode != null && !isFinal) throw _malformed();
    }
    if (kind == SshWorkerEventKind.stateChange &&
        (state == null || plane == null)) {
      throw _malformed();
    }
    if (kind == SshWorkerEventKind.transportClose &&
        (plane == null || reason == null)) {
      throw _malformed();
    }
    if (kind == SshWorkerEventKind.forwardChannelOpened &&
        (forwardId == null || channelId == null)) {
      throw _malformed();
    }
    if (kind == SshWorkerEventKind.forwardClosed && forwardId == null) {
      throw _malformed();
    }
    return SshWorkerEvent._(
      kind: kind,
      streamId: streamId,
      stream: stream,
      sequence: sequence,
      bytes: bytes,
      isFinal: isFinal,
      exitCode: exitCode,
      state: state,
      plane: plane,
      reason: reason,
      forwardId: forwardId,
      channelId: channelId,
      errorCode: errorCode,
    );
  }
}

/// Identity and account of the connection a worker request acts on.
///
/// The wire never carries a profile copy. A request names a machine and the
/// plan generation it was issued under; the address travels separately as an
/// endpoint attempt ([SshWorkerDialTarget]), because picking an endpoint is a
/// dial-time decision, not part of the connection's identity.
final class SshWorkerConnectionRef {
  const SshWorkerConnectionRef({
    required this.machineId,
    required this.generation,
    required this.username,
    required this.authType,
  });

  factory SshWorkerConnectionRef.fromArgs(Map<String, Object?> args) {
    final machineId = args['machineId'];
    final generation = args['generation'];
    final username = args['username'];
    final authTypeRaw = args['authType'];
    if (machineId is! String || machineId.isEmpty) throw _malformed();
    if (generation is! int || generation < 1) throw _malformed();
    if (username is! String || username.isEmpty) throw _malformed();
    SshAuthType? authType;
    for (final value in SshAuthType.values) {
      if (value.name == authTypeRaw) authType = value;
    }
    if (authType == null) throw _malformed();
    return SshWorkerConnectionRef(
      machineId: machineId,
      generation: generation,
      username: username,
      authType: authType,
    );
  }

  final String machineId;
  final int generation;
  final String username;
  final SshAuthType authType;

  Map<String, Object?> toArgs() => {
    'machineId': machineId,
    'generation': generation,
    'username': username,
    'authType': authType.name,
  };

  /// The domain view the worker dialer still speaks. [target] is this request's
  /// endpoint attempt; it is deliberately not part of the identity.
  SshProfile profileFor(SshWorkerDialTarget target) => SshProfile(
    id: machineId,
    name: machineId,
    host: target.host,
    port: target.port,
    username: username,
    authType: authType,
    hostKeyFingerprints: target.hostKeyFingerprints,
  );
}

class SshWorkerDialTarget {
  const SshWorkerDialTarget({
    required this.host,
    required this.port,
    this.hostKeyFingerprints = const [],
  });

  final String host;
  final int port;
  final List<String> hostKeyFingerprints;

  Map<String, Object?> toWire() => {
    'host': host,
    'port': port,
    if (hostKeyFingerprints.isNotEmpty)
      'hostKeyFingerprints': List<String>.from(hostKeyFingerprints),
  };

  factory SshWorkerDialTarget.fromWire(Object? wire) {
    final map = _map(wire);
    final fingerprints = map['hostKeyFingerprints'];
    if (fingerprints != null &&
        (fingerprints is! List ||
            fingerprints.any((value) => value is! String))) {
      throw _malformed();
    }
    final port = _requiredInt(map, 'port');
    if (port < 1 || port > 65535) throw _malformed();
    return SshWorkerDialTarget(
      host: _requiredString(map, 'host'),
      port: port,
      hostKeyFingerprints: fingerprints == null
          ? const []
          : List<String>.unmodifiable((fingerprints as List).cast<String>()),
    );
  }
}

Map<String, Object?> _primitiveMap(Map<Object?, Object?> input) {
  final result = <String, Object?>{};
  for (final entry in input.entries) {
    if (entry.key is! String || !_isPrimitive(entry.value)) throw _malformed();
    result[entry.key as String] = entry.value;
  }
  return Map.unmodifiable(result);
}

bool _isPrimitive(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return true;
  }
  // Typed data is isolate-safe and avoids base64 inflation for file/exec
  // payloads. Check it before the generic List branch so we do not iterate
  // every byte.
  if (value is Uint8List) return true;
  if (value is List) return value.every(_isPrimitive);
  if (value is Map) {
    return value.entries.every(
      (entry) => entry.key is String && _isPrimitive(entry.value),
    );
  }
  return false;
}

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) throw _malformed();
  return value.cast<Object?, Object?>();
}

void _version(Map<Object?, Object?> map) {
  if (map['version'] != sshWorkerProtocolVersion) throw _malformed();
}

void _expect(bool condition) {
  if (!condition) throw _malformed();
}

String _requiredString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) throw _malformed();
  return value;
}

String? _optionalString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) throw _malformed();
  return value;
}

int _requiredInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw _malformed();
  return value;
}

int? _optionalInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int) throw _malformed();
  return value;
}

bool? _optionalBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! bool) throw _malformed();
  return value;
}

T _enumValue<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw _malformed();
}

T? _optionalEnum<T extends Enum>(
  Map<Object?, Object?> map,
  String key,
  List<T> values,
) {
  final raw = map[key];
  if (raw == null) return null;
  if (raw is! String) throw _malformed();
  return _enumValue(values, raw);
}

Uint8List? _bytes(Object? value) {
  if (value == null) return null;
  // SendPort already copies typed data; materialized transferables are also
  // freshly owned. Avoid a second full-buffer copy on the receiving isolate.
  if (value is Uint8List) return value;
  if (value is TransferableTypedData) {
    return value.materialize().asUint8List();
  }
  throw _malformed();
}

void _checkNonNegative(int value) {
  if (value < 0) throw _malformed();
}

void _checkChunkSize(int size) {
  if (size > sshWorkerMaxChunkSize) throw _malformed();
}

void _validatePayload(SshWorkerOperation operation, Uint8List? payload) {
  final requiresPayload =
      operation == SshWorkerOperation.writeSftpChunk ||
      operation == SshWorkerOperation.writePty ||
      operation == SshWorkerOperation.writeMemberExec ||
      operation == SshWorkerOperation.writeForwardChannel;
  if (requiresPayload && payload == null) throw _malformed();
  if (!requiresPayload &&
      payload != null &&
      operation != SshWorkerOperation.runStorage) {
    throw _malformed();
  }
  if (payload != null) {
    final max = operation == SshWorkerOperation.runStorage
        ? sshWorkerMaxStorageStdinBytes
        : sshWorkerMaxChunkSize;
    if (payload.length > max) throw _malformed();
  }
}

FormatException _malformed() =>
    const FormatException('Malformed SSH worker protocol message');
