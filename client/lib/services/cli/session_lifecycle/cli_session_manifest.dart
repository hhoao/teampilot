import '../registry/capabilities/cli_session_lifecycle_capability.dart';

/// Session-level shared warm-tier paths (relative to session runtime root).
class CliSessionManifestShared {
  const CliSessionManifestShared({
    required this.root,
    required this.projectsDir,
    required this.cliConfigBase,
    required this.authDir,
  });

  final String root;
  final String projectsDir;
  final String cliConfigBase;
  final String authDir;

  Map<String, Object?> toJson() => {
    'root': root,
    'projectsDir': projectsDir,
    'cliConfigBase': cliConfigBase,
    'authDir': authDir,
  };

  factory CliSessionManifestShared.fromJson(Map<String, Object?> json) {
    return CliSessionManifestShared(
      root: _requireString(json, 'root'),
      projectsDir: _requireString(json, 'projectsDir'),
      cliConfigBase: _requireString(json, 'cliConfigBase'),
      authDir: _requireString(json, 'authDir'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestShared &&
          root == other.root &&
          projectsDir == other.projectsDir &&
          cliConfigBase == other.cliConfigBase &&
          authDir == other.authDir;

  @override
  int get hashCode => Object.hash(root, projectsDir, cliConfigBase, authDir);
}

/// Indexing phase metadata for the session warm tier.
class CliSessionManifestIndex {
  const CliSessionManifestIndex({
    this.leaderMemberId,
    this.startedAtMs,
    this.finishedAtMs,
    this.lastError,
  });

  final String? leaderMemberId;
  final int? startedAtMs;
  final int? finishedAtMs;
  final String? lastError;

  Map<String, Object?> toJson() => {
    if (leaderMemberId != null) 'leaderMemberId': leaderMemberId,
    if (startedAtMs != null) 'startedAtMs': startedAtMs,
    if (finishedAtMs != null) 'finishedAtMs': finishedAtMs,
    if (lastError != null) 'lastError': lastError,
  };

  factory CliSessionManifestIndex.fromJson(Map<String, Object?> json) {
    return CliSessionManifestIndex(
      leaderMemberId: _optionalString(json, 'leaderMemberId'),
      startedAtMs: _optionalInt(json, 'startedAtMs'),
      finishedAtMs: _optionalInt(json, 'finishedAtMs'),
      lastError: _optionalString(json, 'lastError'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestIndex &&
          leaderMemberId == other.leaderMemberId &&
          startedAtMs == other.startedAtMs &&
          finishedAtMs == other.finishedAtMs &&
          lastError == other.lastError;

  @override
  int get hashCode =>
      Object.hash(leaderMemberId, startedAtMs, finishedAtMs, lastError);
}

/// Per-member overlay state recorded in the session manifest.
class CliSessionManifestMember {
  const CliSessionManifestMember({
    required this.homeRoot,
    this.overlayGeneration = 0,
    this.chatId,
    this.resumeCapturedAtMs,
  });

  final String homeRoot;
  final int overlayGeneration;
  final String? chatId;
  final int? resumeCapturedAtMs;

  Map<String, Object?> toJson() => {
    'homeRoot': homeRoot,
    'overlayGeneration': overlayGeneration,
    if (chatId != null) 'chatId': chatId,
    if (resumeCapturedAtMs != null) 'resumeCapturedAtMs': resumeCapturedAtMs,
  };

  factory CliSessionManifestMember.fromJson(Map<String, Object?> json) {
    return CliSessionManifestMember(
      homeRoot: _requireString(json, 'homeRoot'),
      overlayGeneration: _optionalInt(json, 'overlayGeneration') ?? 0,
      chatId: _optionalString(json, 'chatId'),
      resumeCapturedAtMs: _optionalInt(json, 'resumeCapturedAtMs'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestMember &&
          homeRoot == other.homeRoot &&
          overlayGeneration == other.overlayGeneration &&
          chatId == other.chatId &&
          resumeCapturedAtMs == other.resumeCapturedAtMs;

  @override
  int get hashCode =>
      Object.hash(homeRoot, overlayGeneration, chatId, resumeCapturedAtMs);
}

/// `init.json` manifest for CLI session lifecycle on the work plane.
class CliSessionManifest {
  const CliSessionManifest({
    this.schemaVersion = 1,
    required this.tool,
    required this.workspaceId,
    required this.sessionId,
    required this.workspacePathHash,
    required this.workspaceSlug,
    required this.phase,
    this.phaseUpdatedAtMs,
    required this.shared,
    required this.index,
    this.members = const {},
  });

  final int schemaVersion;
  final String tool;
  final String workspaceId;
  final String sessionId;
  final String workspacePathHash;
  final String workspaceSlug;
  final CliSessionPhase phase;
  final int? phaseUpdatedAtMs;
  final CliSessionManifestShared shared;
  final CliSessionManifestIndex index;
  final Map<String, CliSessionManifestMember> members;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'tool': tool,
    'workspaceId': workspaceId,
    'sessionId': sessionId,
    'workspacePathHash': workspacePathHash,
    'workspaceSlug': workspaceSlug,
    'phase': phase.name,
    if (phaseUpdatedAtMs != null) 'phaseUpdatedAtMs': phaseUpdatedAtMs,
    'shared': shared.toJson(),
    'index': index.toJson(),
    'members': {
      for (final entry in members.entries) entry.key: entry.value.toJson(),
    },
  };

  factory CliSessionManifest.fromJson(Map<String, Object?> json) {
    final membersRaw = json['members'];
    final members = <String, CliSessionManifestMember>{};
    if (membersRaw is Map) {
      for (final entry in membersRaw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        members[key] = CliSessionManifestMember.fromJson(
          value.cast<String, Object?>(),
        );
      }
    }

    return CliSessionManifest(
      schemaVersion: _optionalInt(json, 'schemaVersion') ?? 1,
      tool: _requireString(json, 'tool'),
      workspaceId: _requireString(json, 'workspaceId'),
      sessionId: _requireString(json, 'sessionId'),
      workspacePathHash: _requireString(json, 'workspacePathHash'),
      workspaceSlug: _requireString(json, 'workspaceSlug'),
      phase: _parsePhase(_requireString(json, 'phase')),
      phaseUpdatedAtMs: _optionalInt(json, 'phaseUpdatedAtMs'),
      shared: CliSessionManifestShared.fromJson(
        _requireMap(json, 'shared'),
      ),
      index: CliSessionManifestIndex.fromJson(_requireMap(json, 'index')),
      members: members,
    );
  }

  CliSessionManifest copyWith({
    int? schemaVersion,
    String? tool,
    String? workspaceId,
    String? sessionId,
    String? workspacePathHash,
    String? workspaceSlug,
    CliSessionPhase? phase,
    int? phaseUpdatedAtMs,
    CliSessionManifestShared? shared,
    CliSessionManifestIndex? index,
    Map<String, CliSessionManifestMember>? members,
  }) {
    return CliSessionManifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      tool: tool ?? this.tool,
      workspaceId: workspaceId ?? this.workspaceId,
      sessionId: sessionId ?? this.sessionId,
      workspacePathHash: workspacePathHash ?? this.workspacePathHash,
      workspaceSlug: workspaceSlug ?? this.workspaceSlug,
      phase: phase ?? this.phase,
      phaseUpdatedAtMs: phaseUpdatedAtMs ?? this.phaseUpdatedAtMs,
      shared: shared ?? this.shared,
      index: index ?? this.index,
      members: members ?? this.members,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifest &&
          schemaVersion == other.schemaVersion &&
          tool == other.tool &&
          workspaceId == other.workspaceId &&
          sessionId == other.sessionId &&
          workspacePathHash == other.workspacePathHash &&
          workspaceSlug == other.workspaceSlug &&
          phase == other.phase &&
          phaseUpdatedAtMs == other.phaseUpdatedAtMs &&
          shared == other.shared &&
          index == other.index &&
          _mapEquals(members, other.members);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    tool,
    workspaceId,
    sessionId,
    workspacePathHash,
    workspaceSlug,
    phase,
    phaseUpdatedAtMs,
    shared,
    index,
    Object.hashAllUnordered(members.entries),
  );
}

CliSessionPhase _parsePhase(String raw) {
  return CliSessionPhase.values.firstWhere(
    (phase) => phase.name == raw.trim(),
    orElse: () => throw FormatException('unknown CliSessionPhase: $raw'),
  );
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('missing or invalid string for $key');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('invalid string for $key');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('invalid int for $key');
}

Map<String, Object?> _requireMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('missing or invalid map for $key');
  }
  return value.cast<String, Object?>();
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
