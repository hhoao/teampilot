import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/cli/registry/capabilities/team_behavior_capability.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import 'cli_preset.dart';
import 'team_config.dart';

@immutable
final class GenerateModelPoolEntry {
  factory GenerateModelPoolEntry({
    String? id,
    CliTool? cli,
    String provider = '',
    String model = '',
    String effort = '',
    String description = '',
    List<String> tags = const [],
    @Deprecated('Use the inline id/cli/provider/model fields') String? presetId,
  }) {
    final normalizedLegacyPresetId = presetId?.trim() ?? '';
    if (normalizedLegacyPresetId.isNotEmpty &&
        id == null &&
        cli == null &&
        provider.trim().isEmpty &&
        model.trim().isEmpty) {
      return GenerateModelPoolEntry._internal(
        id: normalizedLegacyPresetId,
        cli: CliTool.claude,
        provider: '',
        model: '',
        effort: effort.trim(),
        description: description.trim(),
        tags: _freezeTags(tags),
        legacyPresetId: normalizedLegacyPresetId,
      );
    }
    final normalizedId = (id ?? '').trim();
    return GenerateModelPoolEntry._internal(
      id: normalizedId.isEmpty ? const Uuid().v4() : normalizedId,
      cli: cli ?? CliTool.claude,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      description: description.trim(),
      tags: _freezeTags(tags),
    );
  }

  const GenerateModelPoolEntry._internal({
    required this.id,
    required this.cli,
    required this.provider,
    required this.model,
    this.effort = '',
    this.description = '',
    this.tags = const [],
    this.legacyPresetId,
  });

  factory GenerateModelPoolEntry.fromJson(Map<String, Object?> json) {
    final cli = CliTool.tryParse(json['cli']?.toString());
    final provider = (json['provider'] as String? ?? '').trim();
    final model = (json['model'] as String? ?? '').trim();
    final effort = (json['effort'] as String? ?? '').trim();
    final description = (json['description'] as String? ?? '').trim();
    final tags = [
      for (final value in (json['tags'] as List? ?? const []))
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
    if (cli != null && (provider.isNotEmpty || model.isNotEmpty)) {
      return GenerateModelPoolEntry(
        id: (json['id'] as String? ?? '').trim(),
        cli: cli,
        provider: provider,
        model: model,
        effort: effort,
        description: description,
        tags: tags,
      );
    }

    final legacyPresetId = (json['presetId'] as String? ?? '').trim();
    return GenerateModelPoolEntry._internal(
      id: legacyPresetId.isNotEmpty
          ? legacyPresetId
          : (json['id'] as String? ?? '').trim(),
      cli: cli ?? CliTool.claude,
      provider: provider,
      model: model,
      effort: effort,
      description: description,
      tags: _freezeTags(tags),
      legacyPresetId: legacyPresetId.isEmpty ? null : legacyPresetId,
    );
  }

  final String id;
  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final String description;
  final List<String> tags;
  final String? legacyPresetId;

  @Deprecated('Use id')
  String get presetId => legacyPresetId ?? id;

  bool get isInline =>
      legacyPresetId == null &&
      id.isNotEmpty &&
      provider.isNotEmpty &&
      model.isNotEmpty;

  GenerateModelPoolEntry normalized() {
    final normalizedTags = _normalizeTags(tags);
    final normalizedLegacyPresetId = legacyPresetId?.trim();
    if (id.trim() == id &&
        provider.trim() == provider &&
        model.trim() == model &&
        effort.trim() == effort &&
        description.trim() == description &&
        normalizedLegacyPresetId == legacyPresetId &&
        _sameList(tags, normalizedTags)) {
      return this;
    }
    return GenerateModelPoolEntry._internal(
      id: id.trim(),
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      description: description.trim(),
      tags: normalizedTags,
      legacyPresetId: normalizedLegacyPresetId?.isEmpty == true
          ? null
          : normalizedLegacyPresetId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'cli': cli.value,
    'provider': provider,
    'model': model,
    if (effort.isNotEmpty) 'effort': effort,
    if (description.isNotEmpty) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GenerateModelPoolEntry &&
            id == other.id &&
            cli == other.cli &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            description == other.description &&
            listEquals(tags, other.tags) &&
            legacyPresetId == other.legacyPresetId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    cli,
    provider,
    model,
    effort,
    description,
    Object.hashAll(tags),
    legacyPresetId,
  );
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
    final seenIds = <String>{};
    for (final entry in modelPool) {
      final normalized = entry.normalized();
      if (normalized.id.isEmpty || seenIds.contains(normalized.id)) {
        continue;
      }
      seenIds.add(normalized.id);
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

  factory TeamGenerationSettingsSnapshot.fromJson(Map<String, Object?> json) {
    TeamMode decodeMode() {
      final raw = json['teamMode']?.toString().trim() ?? '';
      return TeamMode.values.firstWhere(
        (mode) => mode.value == raw,
        orElse: () => TeamMode.mixed,
      );
    }

    CliTool decodeCli() => CliTool.parse(json['nativeCli']);
    final rawPool = json['modelPool'];
    return TeamGenerationSettingsSnapshot(
      revision: json['revision'] as String? ?? '',
      capturedAt: (json['capturedAt'] as num?)?.toInt() ?? 0,
      teamMode: decodeMode(),
      nativeCli: decodeCli(),
      modelPool: [
        for (final value in rawPool is List ? rawPool : const [])
          if (value is Map)
            _effectivePoolEntryFromJson(value.cast<String, Object?>()),
      ],
    );
  }

  static EffectiveGenerateModelPoolEntry _effectivePoolEntryFromJson(
    Map<String, Object?> entry,
  ) {
    final presetMap = ((entry['preset'] as Map?) ?? const {})
        .cast<String, Object?>();
    final source = GenerateModelPoolEntry.fromJson(
      ((entry['source'] as Map?) ?? const {}).cast<String, Object?>(),
    );
    final nestedId = (presetMap['id'] as String?)?.trim() ?? '';
    final presetId = nestedId.isNotEmpty ? nestedId : source.id;
    return EffectiveGenerateModelPoolEntry(
      rank: (entry['rank'] as num?)?.toInt() ?? 0,
      source: source,
      preset: CliPreset(
        id: presetId,
        name: presetMap['name'] as String? ?? '',
        cli: CliTool.parse(presetMap['cli']),
        provider: presetMap['provider'] as String? ?? '',
        model: presetMap['model'] as String? ?? '',
        effort: presetMap['effort'] as String? ?? '',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'revision': revision,
    'capturedAt': capturedAt,
    'teamMode': teamMode.value,
    'nativeCli': nativeCli.value,
    'modelPool': [
      for (final entry in modelPool)
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
  };

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

TeamGenerationSettings hydrateTeamGenerationSettings({
  required TeamGenerationSettings settings,
  required List<CliPreset> presets,
}) {
  final normalizedSettings = settings.normalized();
  final presetsById = {
    for (final preset in presets)
      if (preset.id.trim().isNotEmpty) preset.id.trim(): preset,
  };
  return TeamGenerationSettings(
    schemaVersion: normalizedSettings.schemaVersion,
    teamMode: normalizedSettings.teamMode,
    nativeCli: normalizedSettings.nativeCli,
    modelPool: [
      for (final entry in normalizedSettings.modelPool)
        if (entry.legacyPresetId case final legacyPresetId?)
          if (presetsById[legacyPresetId] case final preset?)
            GenerateModelPoolEntry(
              id: entry.id,
              cli: preset.cli,
              provider: preset.provider,
              model: preset.model,
              effort: preset.effort,
              description: entry.description,
              tags: entry.tags,
            )
          else
            entry
        else
          entry,
    ],
  ).normalized();
}

CliPreset syntheticPoolPreset(GenerateModelPoolEntry entry) {
  final summary = [
    entry.provider,
    entry.model,
    if (entry.effort.isNotEmpty) entry.effort,
  ].join(' / ');
  return CliPreset(
    id: entry.id,
    name: summary,
    cli: entry.cli,
    provider: entry.provider,
    model: entry.model,
    effort: entry.effort,
    createdAt: 0,
    updatedAt: 0,
  );
}

TeamGenerationSettingsSnapshot resolveTeamGenerationSettingsSnapshot({
  required TeamGenerationSettings settings,
  required List<CliPreset> presets,
  required CliToolRegistry registry,
  required int capturedAt,
}) {
  final normalizedSettings = hydrateTeamGenerationSettings(
    settings: settings,
    presets: presets,
  );
  final effective = <EffectiveGenerateModelPoolEntry>[];
  for (final entry in normalizedSettings.modelPool) {
    if (!entry.isInline ||
        registry.tryGet(entry.cli)?.isLaunchSupported != true) {
      continue;
    }
    if (normalizedSettings.teamMode == TeamMode.native) {
      final behavior = registry.capability<TeamBehaviorCapability>(entry.cli);
      if (entry.cli != normalizedSettings.nativeCli ||
          behavior?.supportsNativeTeam != true) {
        continue;
      }
    }
    effective.add(
      EffectiveGenerateModelPoolEntry(
        rank: effective.length + 1,
        source: entry,
        preset: syntheticPoolPreset(entry),
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
