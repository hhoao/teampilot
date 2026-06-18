/// One installed underlying tool, recorded after a successful acquisition.
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    this.version = '',
    this.installedAt = 0,
  });

  final String id;
  final String version;
  final int installedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'installedAt': installedAt,
      };

  factory InstalledExtension.fromJson(Map<String, Object?> json) =>
      InstalledExtension(
        id: (json['id'] as String?)?.trim() ?? '',
        version: json['version'] as String? ?? '',
        installedAt: (json['installedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persistent extension install + enablement state.
///
/// Enablement model: app-level [globalEnabled] is the default;
/// [teamOverrides] per `(teamId, extensionId)` and [workspaceOverrides] per
/// `(workspaceId, extensionId)` win when present.
class ExtensionState {
  const ExtensionState({
    this.installed = const {},
    this.globalEnabled = const {},
    this.teamOverrides = const {},
    this.workspaceOverrides = const {},
  });

  final Map<String, InstalledExtension> installed;
  final Set<String> globalEnabled;
  final Map<String, Map<String, bool>> teamOverrides;
  final Map<String, Map<String, bool>> workspaceOverrides;

  bool effectiveEnabled(String teamId, String extensionId) {
    final override = teamOverrides[teamId]?[extensionId];
    if (override != null) return override;
    return globalEnabled.contains(extensionId);
  }

  bool effectiveEnabledForWorkspace(String workspaceId, String extensionId) {
    final override = workspaceOverrides[workspaceId]?[extensionId];
    if (override != null) return override;
    return globalEnabled.contains(extensionId);
  }

  ExtensionState withGlobalEnabled(String id, bool enabled) {
    final next = Set<String>.from(globalEnabled);
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return _copy(globalEnabled: next);
  }

  /// [value] null clears the override (fall back to global).
  ExtensionState withTeamOverride(String teamId, String id, bool? value) {
    final next = {
      for (final entry in teamOverrides.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
    final team = next.putIfAbsent(teamId, () => <String, bool>{});
    if (value == null) {
      team.remove(id);
    } else {
      team[id] = value;
    }
    if (team.isEmpty) next.remove(teamId);
    return _copy(teamOverrides: next);
  }

  /// [value] null clears the override (fall back to global).
  ExtensionState withWorkspaceOverride(String workspaceId, String id, bool? value) {
    final next = {
      for (final entry in workspaceOverrides.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
    final workspace = next.putIfAbsent(workspaceId, () => <String, bool>{});
    if (value == null) {
      workspace.remove(id);
    } else {
      workspace[id] = value;
    }
    if (workspace.isEmpty) next.remove(workspaceId);
    return _copy(workspaceOverrides: next);
  }

  ExtensionState withInstalled(String id, String version, int installedAt) {
    final next = Map<String, InstalledExtension>.from(installed);
    next[id] = InstalledExtension(id: id, version: version, installedAt: installedAt);
    return _copy(installed: next);
  }

  ExtensionState withUninstalled(String id) {
    final next = Map<String, InstalledExtension>.from(installed)..remove(id);
    return _copy(installed: next);
  }

  ExtensionState _copy({
    Map<String, InstalledExtension>? installed,
    Set<String>? globalEnabled,
    Map<String, Map<String, bool>>? teamOverrides,
    Map<String, Map<String, bool>>? workspaceOverrides,
  }) =>
      ExtensionState(
        installed: installed ?? this.installed,
        globalEnabled: globalEnabled ?? this.globalEnabled,
        teamOverrides: teamOverrides ?? this.teamOverrides,
        workspaceOverrides: workspaceOverrides ?? this.workspaceOverrides,
      );

  Map<String, Object?> toJson() => {
        'installed': {
          for (final entry in installed.entries) entry.key: entry.value.toJson(),
        },
        'globalEnabled': globalEnabled.toList()..sort(),
        'teamOverrides': {
          for (final entry in teamOverrides.entries)
            entry.key: Map<String, bool>.from(entry.value),
        },
        'workspaceOverrides': {
          for (final entry in workspaceOverrides.entries)
            entry.key: Map<String, bool>.from(entry.value),
        },
      };

  factory ExtensionState.fromJson(Map<String, Object?> json) {
    final installedRaw = json['installed'];
    final globalRaw = json['globalEnabled'];
    final overridesRaw = json['teamOverrides'];
    final workspaceOverridesRaw = json['workspaceOverrides'];
    return ExtensionState(
      installed: installedRaw is Map
          ? {
              for (final entry in installedRaw.entries)
                entry.key.toString(): InstalledExtension.fromJson(
                  (entry.value as Map).cast<String, Object?>(),
                ),
            }
          : const {},
      globalEnabled: globalRaw is List
          ? globalRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet()
          : const {},
      teamOverrides: overridesRaw is Map
          ? {
              for (final entry in overridesRaw.entries)
                entry.key.toString(): {
                  if (entry.value is Map)
                    for (final inner in (entry.value as Map).entries)
                      inner.key.toString(): inner.value == true,
                },
            }
          : const {},
      workspaceOverrides: workspaceOverridesRaw is Map
          ? {
              for (final entry in workspaceOverridesRaw.entries)
                entry.key.toString(): {
                  if (entry.value is Map)
                    for (final inner in (entry.value as Map).entries)
                      inner.key.toString(): inner.value == true,
                },
            }
          : const {},
    );
  }
}
