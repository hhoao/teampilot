import '../cursor/provider/cursor_workspace_warm_tier.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';

/// Workspace-level shared warm-tier paths (relative to workspace root).
class CliSessionManifestShared {
  const CliSessionManifestShared({
    required this.root,
    required this.projectsDir,
    required this.cliConfigBase,
    required this.pluginsLocalDir,
    required this.skillsCursorDir,
    required this.mcpBase,
    required this.settingsJson,
  });

  final String root;
  final String projectsDir;
  final String cliConfigBase;
  final String pluginsLocalDir;
  final String skillsCursorDir;
  final String mcpBase;
  final String settingsJson;

  Map<String, Object?> toJson() => {
    'root': root,
    'projectsDir': projectsDir,
    'cliConfigBase': cliConfigBase,
    'pluginsLocalDir': pluginsLocalDir,
    'skillsCursorDir': skillsCursorDir,
    'mcpBase': mcpBase,
    'settingsJson': settingsJson,
  };

  factory CliSessionManifestShared.fromJson(Map<String, Object?> json) {
    final root = _requireString(json, 'root');
    final warmPaths = CursorWorkspaceWarmTier.manifestPaths(root);
    return CliSessionManifestShared(
      root: root,
      projectsDir: _requireString(json, 'projectsDir'),
      cliConfigBase: _requireString(json, 'cliConfigBase'),
      pluginsLocalDir:
          _optionalString(json, 'pluginsLocalDir') ?? warmPaths.pluginsLocalDir,
      skillsCursorDir:
          _optionalString(json, 'skillsCursorDir') ?? warmPaths.skillsCursorDir,
      mcpBase: _optionalString(json, 'mcpBase') ?? warmPaths.mcpBase,
      settingsJson:
          _optionalString(json, 'settingsJson') ?? warmPaths.settingsJson,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestShared &&
          root == other.root &&
          projectsDir == other.projectsDir &&
          cliConfigBase == other.cliConfigBase &&
          pluginsLocalDir == other.pluginsLocalDir &&
          skillsCursorDir == other.skillsCursorDir &&
          mcpBase == other.mcpBase &&
          settingsJson == other.settingsJson;

  @override
  int get hashCode => Object.hash(
    root,
    projectsDir,
    cliConfigBase,
    pluginsLocalDir,
    skillsCursorDir,
    mcpBase,
    settingsJson,
  );
}

/// Per-member workspace state recorded in the lifecycle manifest.
class CliSessionManifestMember {
  const CliSessionManifestMember({
    required this.homeRoot,
    this.chatId,
    this.resumeCapturedAtMs,
  });

  final String homeRoot;
  final String? chatId;
  final int? resumeCapturedAtMs;

  Map<String, Object?> toJson() => {
    'homeRoot': homeRoot,
    if (chatId != null) 'chatId': chatId,
    if (resumeCapturedAtMs != null) 'resumeCapturedAtMs': resumeCapturedAtMs,
  };

  factory CliSessionManifestMember.fromJson(Map<String, Object?> json) {
    return CliSessionManifestMember(
      homeRoot: _requireString(json, 'homeRoot'),
      chatId: _optionalString(json, 'chatId'),
      resumeCapturedAtMs: _optionalInt(json, 'resumeCapturedAtMs'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestMember &&
          homeRoot == other.homeRoot &&
          chatId == other.chatId &&
          resumeCapturedAtMs == other.resumeCapturedAtMs;

  @override
  int get hashCode => Object.hash(homeRoot, chatId, resumeCapturedAtMs);
}

/// Per-session bus overlay generation for one roster member.
class CliSessionManifestSessionOverlay {
  const CliSessionManifestSessionOverlay({required this.overlayGeneration});

  final int overlayGeneration;

  Map<String, Object?> toJson() => {'overlayGeneration': overlayGeneration};

  factory CliSessionManifestSessionOverlay.fromJson(Map<String, Object?> json) {
    return CliSessionManifestSessionOverlay(
      overlayGeneration: _optionalInt(json, 'overlayGeneration') ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifestSessionOverlay &&
          overlayGeneration == other.overlayGeneration;

  @override
  int get hashCode => overlayGeneration.hashCode;
}

/// `init.json` lifecycle manifest for a workspace+team CLI warm tier.
class CliSessionManifest {
  const CliSessionManifest({
    this.schemaVersion = 4,
    required this.tool,
    required this.workspaceId,
    required this.teamId,
    required this.workspacePathHash,
    required this.workspaceSlug,
    required this.phase,
    this.phaseUpdatedAtMs,
    required this.shared,
    this.members = const {},
    this.sessionOverlays = const {},
  });

  final int schemaVersion;
  final String tool;
  final String workspaceId;
  final String teamId;
  final String workspacePathHash;
  final String workspaceSlug;
  final CliSessionPhase phase;
  final int? phaseUpdatedAtMs;
  final CliSessionManifestShared shared;
  final Map<String, CliSessionManifestMember> members;
  final Map<String, Map<String, CliSessionManifestSessionOverlay>> sessionOverlays;

  CliSessionManifestSessionOverlay? overlayFor(String sessionId, String memberId) {
    return sessionOverlays[sessionId]?[memberId];
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'tool': tool,
    'workspaceId': workspaceId,
    'teamId': teamId,
    'workspacePathHash': workspacePathHash,
    'workspaceSlug': workspaceSlug,
    'phase': phase.name,
    if (phaseUpdatedAtMs != null) 'phaseUpdatedAtMs': phaseUpdatedAtMs,
    'shared': shared.toJson(),
    'members': {
      for (final entry in members.entries) entry.key: entry.value.toJson(),
    },
    'sessionOverlays': {
      for (final sessionEntry in sessionOverlays.entries)
        sessionEntry.key: {
          for (final memberEntry in sessionEntry.value.entries)
            memberEntry.key: memberEntry.value.toJson(),
        },
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

    final overlaysRaw = json['sessionOverlays'];
    final sessionOverlays =
        <String, Map<String, CliSessionManifestSessionOverlay>>{};
    if (overlaysRaw is Map) {
      for (final sessionEntry in overlaysRaw.entries) {
        final sessionId = sessionEntry.key;
        final memberMap = sessionEntry.value;
        if (sessionId is! String || memberMap is! Map) continue;
        final overlays = <String, CliSessionManifestSessionOverlay>{};
        for (final memberEntry in memberMap.entries) {
          final memberId = memberEntry.key;
          final overlayJson = memberEntry.value;
          if (memberId is! String || overlayJson is! Map) continue;
          overlays[memberId] = CliSessionManifestSessionOverlay.fromJson(
            overlayJson.cast<String, Object?>(),
          );
        }
        sessionOverlays[sessionId] = overlays;
      }
    }

    return CliSessionManifest(
      schemaVersion: _requireSchemaVersion(json),
      tool: _requireString(json, 'tool'),
      workspaceId: _requireString(json, 'workspaceId'),
      teamId: _requireString(json, 'teamId'),
      workspacePathHash: _requireString(json, 'workspacePathHash'),
      workspaceSlug: _requireString(json, 'workspaceSlug'),
      phase: _parsePhase(_requireString(json, 'phase')),
      phaseUpdatedAtMs: _optionalInt(json, 'phaseUpdatedAtMs'),
      shared: CliSessionManifestShared.fromJson(
        _requireMap(json, 'shared'),
      ),
      members: members,
      sessionOverlays: sessionOverlays,
    );
  }

  CliSessionManifest copyWith({
    int? schemaVersion,
    String? tool,
    String? workspaceId,
    String? teamId,
    String? workspacePathHash,
    String? workspaceSlug,
    CliSessionPhase? phase,
    int? phaseUpdatedAtMs,
    CliSessionManifestShared? shared,
    Map<String, CliSessionManifestMember>? members,
    Map<String, Map<String, CliSessionManifestSessionOverlay>>? sessionOverlays,
  }) {
    return CliSessionManifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      tool: tool ?? this.tool,
      workspaceId: workspaceId ?? this.workspaceId,
      teamId: teamId ?? this.teamId,
      workspacePathHash: workspacePathHash ?? this.workspacePathHash,
      workspaceSlug: workspaceSlug ?? this.workspaceSlug,
      phase: phase ?? this.phase,
      phaseUpdatedAtMs: phaseUpdatedAtMs ?? this.phaseUpdatedAtMs,
      shared: shared ?? this.shared,
      members: members ?? this.members,
      sessionOverlays: sessionOverlays ?? this.sessionOverlays,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CliSessionManifest &&
          schemaVersion == other.schemaVersion &&
          tool == other.tool &&
          workspaceId == other.workspaceId &&
          teamId == other.teamId &&
          workspacePathHash == other.workspacePathHash &&
          workspaceSlug == other.workspaceSlug &&
          phase == other.phase &&
          phaseUpdatedAtMs == other.phaseUpdatedAtMs &&
          shared == other.shared &&
          _mapEquals(members, other.members) &&
          _nestedOverlayEquals(sessionOverlays, other.sessionOverlays);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    tool,
    workspaceId,
    teamId,
    workspacePathHash,
    workspaceSlug,
    phase,
    phaseUpdatedAtMs,
    shared,
    Object.hashAllUnordered(members.entries),
    Object.hashAllUnordered(
      sessionOverlays.entries.map(
        (e) => Object.hash(e.key, Object.hashAllUnordered(e.value.entries)),
      ),
    ),
  );
}

int _requireSchemaVersion(Map<String, Object?> json) {
  final version = _optionalInt(json, 'schemaVersion');
  if (version == null || version != 4) {
    throw FormatException(
      'unsupported cli session manifest schemaVersion: $version',
    );
  }
  return version;
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

bool _nestedOverlayEquals(
  Map<String, Map<String, CliSessionManifestSessionOverlay>> a,
  Map<String, Map<String, CliSessionManifestSessionOverlay>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final otherMembers = b[entry.key];
    if (otherMembers == null || !_mapEquals(entry.value, otherMembers)) {
      return false;
    }
  }
  return true;
}
