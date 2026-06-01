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
/// Enablement model: app-level [globalEnabled] is the default; [teamOverrides]
/// per `(teamId, extensionId)` win when present.
class ExtensionState {
  const ExtensionState({
    this.installed = const {},
    this.globalEnabled = const {},
    this.teamOverrides = const {},
    this.migrations = const {},
  });

  final Map<String, InstalledExtension> installed;
  final Set<String> globalEnabled;
  final Map<String, Map<String, bool>> teamOverrides;

  /// One-shot migration markers (kept out of [teamOverrides] so a real team id
  /// can never collide with a marker key).
  final Set<String> migrations;

  bool effectiveEnabled(String teamId, String extensionId) {
    final override = teamOverrides[teamId]?[extensionId];
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

  ExtensionState withInstalled(String id, String version, int installedAt) {
    final next = Map<String, InstalledExtension>.from(installed);
    next[id] = InstalledExtension(id: id, version: version, installedAt: installedAt);
    return _copy(installed: next);
  }

  ExtensionState withUninstalled(String id) {
    final next = Map<String, InstalledExtension>.from(installed)..remove(id);
    return _copy(installed: next);
  }

  ExtensionState withMigration(String key) =>
      _copy(migrations: {...migrations, key});

  ExtensionState _copy({
    Map<String, InstalledExtension>? installed,
    Set<String>? globalEnabled,
    Map<String, Map<String, bool>>? teamOverrides,
    Set<String>? migrations,
  }) =>
      ExtensionState(
        installed: installed ?? this.installed,
        globalEnabled: globalEnabled ?? this.globalEnabled,
        teamOverrides: teamOverrides ?? this.teamOverrides,
        migrations: migrations ?? this.migrations,
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
        'migrations': migrations.toList()..sort(),
      };

  factory ExtensionState.fromJson(Map<String, Object?> json) {
    final installedRaw = json['installed'];
    final globalRaw = json['globalEnabled'];
    final overridesRaw = json['teamOverrides'];
    final migrationsRaw = json['migrations'];
    return ExtensionState(
      migrations: migrationsRaw is List
          ? migrationsRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet()
          : const {},
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
    );
  }
}
