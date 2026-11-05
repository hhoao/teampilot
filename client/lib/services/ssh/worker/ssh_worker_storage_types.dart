import 'dart:convert';
import 'dart:typed_data';

import 'ssh_worker_protocol.dart';

/// Limits apply in both isolates, including requests from low-level callers.
const sshWorkerMaxReadWindow = 16;
const sshWorkerMaxExecOutput = 1024 * 1024;

/// Storage-plane commands (recursive `find`, git, installers) legitimately
/// return far more than a member probe; keep them bounded but not at 1 MiB.
const sshWorkerMaxStorageExecOutput = 32 * 1024 * 1024;

/// Binary exec output with optional remote process exit information.
final class SshWorkerRunResult {
  SshWorkerRunResult({
    required Uint8List stdout,
    required Uint8List stderr,
    this.exitCode,
    this.signalName,
    int maxOutputBytes = sshWorkerMaxExecOutput,
  }) : stdout = Uint8List.fromList(stdout),
       stderr = Uint8List.fromList(stderr) {
    if (stdout.length + stderr.length > maxOutputBytes) {
      throw const SshWorkerTransportException(
        'Exec output limit exceeded',
        code: 'output_limit',
      );
    }
  }

  SshWorkerRunResult._owned({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.signalName,
    required int maxOutputBytes,
  }) {
    if (stdout.length + stderr.length > maxOutputBytes) {
      throw const SshWorkerTransportException(
        'Exec output limit exceeded',
        code: 'output_limit',
      );
    }
  }

  final Uint8List stdout;
  final Uint8List stderr;
  final int? exitCode;
  final String? signalName;

  Map<String, Object?> toWire({int maxOutputBytes = sshWorkerMaxExecOutput}) {
    if (stdout.length + stderr.length > maxOutputBytes) {
      throw const SshWorkerTransportException(
        'Exec output limit exceeded',
        code: 'output_limit',
      );
    }
    return {
      'stdout': stdout,
      'stderr': stderr,
      'exitCode': exitCode,
      'signalName': signalName,
    };
  }

  factory SshWorkerRunResult.fromWire(
    Object? wire, {
    int maxOutputBytes = sshWorkerMaxExecOutput,
  }) {
    final map = _storageMap(wire);
    return SshWorkerRunResult._owned(
      stdout: decodeStorageBytes(
        _storageRequired(map, 'stdout'),
        maxOutputBytes,
      ),
      stderr: decodeStorageBytes(
        _storageRequired(map, 'stderr'),
        maxOutputBytes,
      ),
      exitCode: _storageOptionalInt(map, 'exitCode'),
      signalName: _storageOptionalString(map, 'signalName'),
      maxOutputBytes: maxOutputBytes,
    );
  }
}

/// A sequence-numbered read result or write payload; offsets are file-relative.
final class SshWorkerFileChunk {
  SshWorkerFileChunk({
    required this.sequence,
    required this.offset,
    required Uint8List bytes,
    this.isFinal = false,
  }) : bytes = Uint8List.fromList(bytes) {
    if (sequence < 0 || offset < 0 || bytes.length > sshWorkerMaxChunkSize) {
      throw ArgumentError('Invalid storage chunk');
    }
  }

  /// Wire-decoded bytes are already freshly owned by the receiving isolate.
  SshWorkerFileChunk._owned({
    required this.sequence,
    required this.offset,
    required this.bytes,
    required this.isFinal,
  }) {
    if (sequence < 0 || offset < 0 || bytes.length > sshWorkerMaxChunkSize) {
      throw ArgumentError('Invalid storage chunk');
    }
  }

  final int sequence;
  final int offset;
  final Uint8List bytes;
  final bool isFinal;

  Map<String, Object?> toWire() => {
    'sequence': sequence,
    'offset': offset,
    'bytes': bytes,
    'eof': isFinal,
  };

  factory SshWorkerFileChunk.fromWire(Object? wire) {
    final map = _storageMap(wire);
    return SshWorkerFileChunk._owned(
      sequence: _storageNonNegativeInt(map, 'sequence'),
      offset: _storageNonNegativeInt(map, 'offset'),
      bytes: decodeStorageBytes(
        _storageRequired(map, 'bytes'),
        sshWorkerMaxChunkSize,
      ),
      isFinal: _storageRequiredBool(map, 'eof'),
    );
  }
}

/// Primitive-only SFTP attributes. Unknown file types stay unknown.
final class SshWorkerFileStat {
  const SshWorkerFileStat({this.size, this.modifyTime, required this.kind});
  final int? size;
  final int? modifyTime;
  final String kind;

  Map<String, Object?> toWire() => {
    'size': size,
    'modifyTime': modifyTime,
    'kind': kind,
  };
  factory SshWorkerFileStat.fromWire(Object? wire) {
    final map = _storageMap(wire);
    return SshWorkerFileStat(
      size: _storageOptionalNonNegativeInt(map, 'size'),
      modifyTime: _storageOptionalNonNegativeInt(map, 'modifyTime'),
      kind: _storageRequiredString(map, 'kind'),
    );
  }
}

/// Directory entry without any worker-local SFTP attributes object.
final class SshWorkerDirectoryEntry {
  const SshWorkerDirectoryEntry({required this.name, required this.stat});
  final String name;
  final SshWorkerFileStat stat;

  Map<String, Object?> toWire() => {'name': name, 'stat': stat.toWire()};
  factory SshWorkerDirectoryEntry.fromWire(Object? wire) {
    final map = _storageMap(wire);
    return SshWorkerDirectoryEntry(
      name: _storageRequiredString(map, 'name'),
      stat: SshWorkerFileStat.fromWire(_storageRequired(map, 'stat')),
    );
  }
}

/// A sanitized, machine-readable failure from the storage boundary.
final class SshWorkerTransportException implements SshWorkerCodedException {
  const SshWorkerTransportException(this.message, {this.code});
  final String message;
  @override
  final String? code;
  @override
  String toString() => 'SshWorkerTransportException($code: $message)';
}

/// Validate the encoded size before allocating a decoded binary result.
Uint8List decodeStorageBytes(Object? value, int limit) {
  if (value is Uint8List) {
    if (value.length > limit) {
      throw const FormatException('Storage bytes exceed limit');
    }
    return value;
  }
  // Keep accepting base64 for older in-flight peers/tests during rollout.
  if (value is! String || value.length > ((limit + 2) ~/ 3) * 4) {
    throw const FormatException('Invalid storage bytes');
  }
  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(value));
  } on FormatException {
    throw const FormatException('Invalid storage bytes');
  }
  if (bytes.length > limit)
    throw const FormatException('Storage bytes exceed limit');
  return bytes;
}

Map<Object?, Object?> _storageMap(Object? wire) {
  if (wire is! Map) throw const FormatException('Invalid storage DTO');
  return Map<Object?, Object?>.from(wire);
}

Object? _storageRequired(Map<Object?, Object?> map, String key) {
  if (!map.containsKey(key) || map[key] == null) {
    throw const FormatException('Invalid storage DTO');
  }
  return map[key];
}

String _storageRequiredString(Map<Object?, Object?> map, String key) {
  final value = _storageRequired(map, key);
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid storage DTO');
  }
  return value;
}

String? _storageOptionalString(Map<Object?, Object?> map, String key) {
  if (!map.containsKey(key) || map[key] == null) return null;
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid storage DTO');
  }
  return value;
}

int _storageNonNegativeInt(Map<Object?, Object?> map, String key) {
  final value = _storageRequired(map, key);
  if (value is! int || value < 0) {
    throw const FormatException('Invalid storage DTO');
  }
  return value;
}

int? _storageOptionalInt(Map<Object?, Object?> map, String key) {
  if (!map.containsKey(key) || map[key] == null) return null;
  final value = map[key];
  if (value is! int) throw const FormatException('Invalid storage DTO');
  return value;
}

int? _storageOptionalNonNegativeInt(Map<Object?, Object?> map, String key) {
  final value = _storageOptionalInt(map, key);
  if (value != null && value < 0) {
    throw const FormatException('Invalid storage DTO');
  }
  return value;
}

bool _storageRequiredBool(Map<Object?, Object?> map, String key) {
  final value = _storageRequired(map, key);
  if (value is! bool) throw const FormatException('Invalid storage DTO');
  return value;
}
