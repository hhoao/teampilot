import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../services/cli/registry/capabilities/team_behavior_capability.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import 'cli_preset.dart';
import 'team_config.dart';

@immutable
final class GenerateModelPoolEntry {
  factory GenerateModelPoolEntry({
    required String presetId,
    String description = '',
    List<String> tags = const [],
  }) {
    return GenerateModelPoolEntry._internal(
      presetId: presetId,
      description: description,
      tags: _freezeTags(tags),
    );
  }

  const GenerateModelPoolEntry._internal({
    required this.presetId,
    this.description = '',
    this.tags = const [],
  });

  factory GenerateModelPoolEntry.fromJson(Map<String, Object?> json) {
    return GenerateModelPoolEntry(
      presetId: (json['presetId'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
      tags: [
        for (final value in (json['tags'] as List? ?? const []))
          if (value is String && value.trim().isNotEmpty) value.trim(),
      ],
    );
  }

  final String presetId;
  final String description;
  final List<String> tags;

  GenerateModelPoolEntry normalized() {
    if (presetId.trim() == presetId &&
        description.trim() == description &&
        _sameList(tags, _normalizeTags(tags))) {
      return this;
    }
    return GenerateModelPoolEntry(
      presetId: presetId.trim(),
      description: description.trim(),
      tags: _normalizeTags(tags),
    );
  }

  Map<String, Object?> toJson() => {
    'presetId': presetId,
    if (description.isNotEmpty) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GenerateModelPoolEntry &&
            presetId == other.presetId &&
            description == other.description &&
            listEquals(tags, other.tags);
  }

  @override
  int get hashCode => Object.hash(presetId, description, Object.hashAll(tags));
}

@immutable
final class EffectiveGenerateModelPoolEntry {
  factory EffectiveGenerateModelPoolEntry({
    required int rank,
    required GenerateModelPoolEntry source,
    required CliPreset preset,
  }) {
    return EffectiveGenerateModelPoolEntry._internal(
      rank: rank,
      source: source,
      preset: preset,
    );
  }

  const EffectiveGenerateModelPoolEntry._internal({
    required this.rank,
    required this.source,
    required this.preset,
  });

  final int rank;
  final GenerateModelPoolEntry source;
  final CliPreset preset;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EffectiveGenerateModelPoolEntry &&
            rank == other.rank &&
            source == other.source &&
            preset == other.preset;
  }

  @override
  int get hashCode => Object.hash(rank, source, preset);
}

@immutable
final class TeamGenerationSettings {
  factory TeamGenerationSettings({
    int schemaVersion = 1,
    TeamMode teamMode = TeamMode.mixed,
    CliTool nativeCli = CliTool.claude,
    List<GenerateModelPoolEntry> modelPool = const [],
  }) {
    return TeamGenerationSettings._internal(
      schemaVersion: schemaVersion,
      teamMode: teamMode,
      nativeCli: nativeCli,
      modelPool: _freezeModelPool(modelPool),
    );
  }

  const TeamGenerationSettings._internal({
    this.schemaVersion = 1,
    this.teamMode = TeamMode.mixed,
    this.nativeCli = CliTool.claude,
    this.modelPool = const [],
  });

  factory TeamGenerationSettings.fromJson(Map<String, Object?> json) {
    final rawPool = json['modelPool'] as List?;
    return TeamGenerationSettings(
      schemaVersion: _schemaVersionFromJson(json['schemaVersion']),
      teamMode: TeamMode.decode(json['teamMode']),
      nativeCli: CliTool.parse(json['nativeCli']),
      modelPool:
          rawPool
              ?.map(
                (entry) => entry is Map
                    ? GenerateModelPoolEntry.fromJson(
                        entry.cast<String, Object?>(),
                      )
                    : null,
              )
              .whereType<GenerateModelPoolEntry>()
              .toList() ??
          const [],
    ).normalized();
  }

  final int schemaVersion;
  final TeamMode teamMode;
  final CliTool nativeCli;
  final List<GenerateModelPoolEntry> modelPool;

  TeamGenerationSettings normalized() {
    final normalizedPool = <GenerateModelPoolEntry>[];
    final seenPresetIds = <String>{};
    for (final entry in modelPool) {
      final normalized = entry.normalized();
      if (normalized.presetId.isEmpty ||
          seenPresetIds.contains(normalized.presetId)) {
        continue;
      }
      seenPresetIds.add(normalized.presetId);
      normalizedPool.add(normalized);
    }
    final immutablePool = List<GenerateModelPoolEntry>.unmodifiable(
      normalizedPool,
    );
    if (schemaVersion == 1 &&
        teamMode == this.teamMode &&
        nativeCli == this.nativeCli &&
        _sameList(modelPool, immutablePool)) {
      return this;
    }
    return TeamGenerationSettings(
      schemaVersion: 1,
      teamMode: teamMode,
      nativeCli: nativeCli,
      modelPool: immutablePool,
    );
  }

  Map<String, Object?> toJson() {
    final normalizedSettings = normalized();
    return {
      'schemaVersion': normalizedSettings.schemaVersion,
      'teamMode': normalizedSettings.teamMode.value,
      'nativeCli': normalizedSettings.nativeCli.value,
      'modelPool': [
        for (final entry in normalizedSettings.modelPool) entry.toJson(),
      ],
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamGenerationSettings &&
            schemaVersion == other.schemaVersion &&
            teamMode == other.teamMode &&
            nativeCli == other.nativeCli &&
            listEquals(modelPool, other.modelPool);
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    teamMode,
    nativeCli,
    Object.hashAll(modelPool),
  );
}

@immutable
final class TeamGenerationSettingsSnapshot {
  factory TeamGenerationSettingsSnapshot({
    required String revision,
    required int capturedAt,
    required TeamMode teamMode,
    required CliTool nativeCli,
    required List<EffectiveGenerateModelPoolEntry> modelPool,
  }) {
    return TeamGenerationSettingsSnapshot._internal(
      revision: revision,
      capturedAt: capturedAt,
      teamMode: teamMode,
      nativeCli: nativeCli,
      modelPool: _freezeEffectiveModelPool(modelPool),
    );
  }

  const TeamGenerationSettingsSnapshot._internal({
    required this.revision,
    required this.capturedAt,
    required this.teamMode,
    required this.nativeCli,
    required this.modelPool,
  });

  final String revision;
  final int capturedAt;
  final TeamMode teamMode;
  final CliTool nativeCli;
  final List<EffectiveGenerateModelPoolEntry> modelPool;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamGenerationSettingsSnapshot &&
            revision == other.revision &&
            capturedAt == other.capturedAt &&
            teamMode == other.teamMode &&
            nativeCli == other.nativeCli &&
            listEquals(modelPool, other.modelPool);
  }

  @override
  int get hashCode => Object.hash(
    revision,
    capturedAt,
    teamMode,
    nativeCli,
    Object.hashAll(modelPool),
  );
}

@immutable
final class TeamGenerationGeneratorSnapshot {
  factory TeamGenerationGeneratorSnapshot({
    required String revision,
    required int capturedAt,
    required TeamMode teamMode,
    required CliTool nativeCli,
    required List<EffectiveGenerateModelPoolEntry> modelPool,
  }) {
    return TeamGenerationGeneratorSnapshot._internal(
      revision: revision,
      capturedAt: capturedAt,
      teamMode: teamMode,
      nativeCli: nativeCli,
      modelPool: _freezeEffectiveModelPool(modelPool),
    );
  }

  const TeamGenerationGeneratorSnapshot._internal({
    required this.revision,
    required this.capturedAt,
    required this.teamMode,
    required this.nativeCli,
    required this.modelPool,
  });

  factory TeamGenerationGeneratorSnapshot.fromSettingsSnapshot(
    TeamGenerationSettingsSnapshot snapshot,
  ) {
    return TeamGenerationGeneratorSnapshot(
      revision: snapshot.revision,
      capturedAt: snapshot.capturedAt,
      teamMode: snapshot.teamMode,
      nativeCli: snapshot.nativeCli,
      modelPool: snapshot.modelPool,
    );
  }

  final String revision;
  final int capturedAt;
  final TeamMode teamMode;
  final CliTool nativeCli;
  final List<EffectiveGenerateModelPoolEntry> modelPool;
}

TeamGenerationSettingsSnapshot resolveTeamGenerationSettingsSnapshot({
  required TeamGenerationSettings settings,
  required List<CliPreset> presets,
  required CliToolRegistry registry,
  required int capturedAt,
}) {
  final normalizedSettings = settings.normalized();
  final byId = {for (final preset in presets) preset.id.trim(): preset};
  final effective = <EffectiveGenerateModelPoolEntry>[];
  for (final entry in normalizedSettings.modelPool) {
    final preset = byId[entry.presetId.trim()];
    if (preset == null ||
        registry.tryGet(preset.cli)?.isLaunchSupported != true) {
      continue;
    }
    if (normalizedSettings.teamMode == TeamMode.native) {
      final behavior = registry.capability<TeamBehaviorCapability>(preset.cli);
      if (preset.cli != normalizedSettings.nativeCli ||
          behavior?.supportsNativeTeam != true) {
        continue;
      }
    }
    effective.add(
      EffectiveGenerateModelPoolEntry(
        rank: effective.length + 1,
        source: entry,
        preset: preset,
      ),
    );
  }
  final canonical = jsonEncode({
    'teamMode': normalizedSettings.teamMode.value,
    'nativeCli': normalizedSettings.nativeCli.value,
    'modelPool': [
      for (final entry in effective)
        {
          'rank': entry.rank,
          'source': entry.source.toJson(),
          'preset': {
            'id': entry.preset.id,
            'name': entry.preset.name,
            'cli': entry.preset.cli.value,
            'provider': entry.preset.provider,
            'model': entry.preset.model,
            'effort': entry.preset.effort,
          },
        },
    ],
  });
  return TeamGenerationSettingsSnapshot(
    revision: sha256.convert(utf8.encode(canonical)).toString(),
    capturedAt: capturedAt,
    teamMode: normalizedSettings.teamMode,
    nativeCli: normalizedSettings.nativeCli,
    modelPool: List<EffectiveGenerateModelPoolEntry>.unmodifiable(effective),
  );
}

List<String> _normalizeTags(List<String> tags) {
  return _freezeTags(tags);
}

List<String> _freezeTags(List<String> tags) {
  return List<String>.unmodifiable({
    for (final value in tags)
      if (value.trim().isNotEmpty) value.trim(),
  });
}

List<GenerateModelPoolEntry> _freezeModelPool(
  List<GenerateModelPoolEntry> pool,
) {
  return List<GenerateModelPoolEntry>.unmodifiable(pool);
}

List<EffectiveGenerateModelPoolEntry> _freezeEffectiveModelPool(
  List<EffectiveGenerateModelPoolEntry> pool,
) {
  return List<EffectiveGenerateModelPoolEntry>.unmodifiable(pool);
}

bool _sameList<T>(List<T> a, List<T> b) {
  return identical(a, b) || listEquals(a, b);
}

int _schemaVersionFromJson(Object? raw) {
  final value = (raw as num?)?.toInt() ?? 1;
  return value > 0 ? value : 1;
}
