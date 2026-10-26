import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import '../../../../models/session_usage.dart';
import '../../../../models/team_config.dart';
import '../cli_capability.dart';

@immutable
class UsageScanContext {
  const UsageScanContext({
    required this.fs,
    required this.cli,
    required this.env,
    required this.transcriptRoots,
    required this.taskId,
    required this.nativeSessionId,
    required this.sessionId,
    required this.memberId,
    required this.teamId,
    required this.workingDirectory,
    required this.appDataRoot,
  });

  final Filesystem fs;
  final CliTool cli;
  final Map<String, String> env;
  final List<String> transcriptRoots;

  /// TeamPilot seat task id (pinned native id for client-pinned CLIs).
  final String taskId;

  /// Persisted CLI-native session id, or `''` before capture.
  final String nativeSessionId;

  final String sessionId;
  final String memberId;
  final String teamId;
  final String workingDirectory;
  final String appDataRoot;
}

enum UsageSourceKind {
  jsonl('jsonl'),
  sqlite('sqlite');

  const UsageSourceKind(this.value);

  final String value;

  static UsageSourceKind fromJson(Object? raw) {
    final normalized = raw?.toString();
    for (final value in values) {
      if (value.value == normalized) return value;
    }
    return jsonl;
  }
}

@immutable
class SessionUsageSource extends Equatable {
  const SessionUsageSource({
    required this.id,
    required this.path,
    required this.kind,
    required this.sessionId,
    required this.memberId,
    required this.teamId,
  });

  /// Stable cursor key. Include the file/DB path, not just the session id.
  final String id;
  final String path;
  final UsageSourceKind kind;
  final String sessionId;
  final String memberId;
  final String teamId;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'kind': kind.value,
    'sessionId': sessionId,
    'memberId': memberId,
    'teamId': teamId,
  };

  @override
  List<Object?> get props => [id, path, kind, sessionId, memberId, teamId];
}

@immutable
class UsageCursor extends Equatable {
  const UsageCursor({
    this.byteOffset,
    this.mtimeMs,
    this.size,
    this.tailFingerprint,
    this.lineOffset,
    this.storeToken,
  });

  static const empty = UsageCursor();

  final int? byteOffset;
  final int? mtimeMs;
  final int? size;

  /// 32-bit FNV-1a of up to 4 KiB before [byteOffset], for rewrite detection.
  final int? tailFingerprint;

  /// Complete lines consumed so far (JSONL only).
  final int? lineOffset;

  /// Capability-specific state (OpenCode snapshot token, Codex baseline).
  final String? storeToken;

  bool get isEmpty =>
      byteOffset == null && lineOffset == null && storeToken == null;

  Map<String, Object?> toJson() => {
    if (byteOffset != null) 'byteOffset': byteOffset,
    if (mtimeMs != null) 'mtimeMs': mtimeMs,
    if (size != null) 'size': size,
    if (tailFingerprint != null) 'tailFingerprint': tailFingerprint,
    if (lineOffset != null) 'lineOffset': lineOffset,
    if (storeToken != null) 'storeToken': storeToken,
  };

  factory UsageCursor.fromJson(Map<String, Object?> json) => UsageCursor(
    byteOffset: (json['byteOffset'] as num?)?.toInt(),
    mtimeMs: (json['mtimeMs'] as num?)?.toInt(),
    size: (json['size'] as num?)?.toInt(),
    tailFingerprint: (json['tailFingerprint'] as num?)?.toInt(),
    lineOffset: (json['lineOffset'] as num?)?.toInt(),
    storeToken: json['storeToken']?.toString(),
  );

  @override
  List<Object?> get props => [
    byteOffset,
    mtimeMs,
    size,
    tailFingerprint,
    lineOffset,
    storeToken,
  ];
}

@immutable
class UsageScanResult {
  const UsageScanResult({
    required this.events,
    required this.nextCursor,
    this.partialTail = false,
    this.skippedLines = 0,
  });

  final List<SessionUsageEvent> events;
  final UsageCursor nextCursor;

  /// A trailing incomplete line was held back; [nextCursor] stops before it.
  final bool partialTail;
  final int skippedLines;
}

/// Implemented by each CLI definition that can account token usage.
abstract interface class SessionUsageCapability implements CliCapability {
  Future<List<SessionUsageSource>> discoverUsageSources(UsageScanContext ctx);

  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  });
}
