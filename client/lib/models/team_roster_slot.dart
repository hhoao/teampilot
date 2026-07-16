import 'package:flutter/foundation.dart';

import 'team_config.dart';
import '../utils/team/team_member_naming.dart';

/// Per-team/per-slot launch overrides. Persona text lives on the catalog expert.
@immutable
class TeamRosterSlotOverrides {
  const TeamRosterSlotOverrides({
    this.provider = '',
    this.model = '',
    this.effort = '',
    this.extraArgs = '',
    this.cli,
    this.replicas = 1,
    this.capabilities = const {},
    this.activePresetId,
  });

  final String provider;
  final String model;
  final String effort;
  final String extraArgs;
  final CliTool? cli;
  final int replicas;
  final Set<String> capabilities;
  final String? activePresetId;

  factory TeamRosterSlotOverrides.fromJson(Map<String, Object?> json) {
    final rawCli = json['cli'];
    return TeamRosterSlotOverrides(
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      effort: json['effort'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      cli: rawCli == null ? null : CliTool.tryParse(rawCli.toString()),
      replicas: (json['replicas'] as num?)?.toInt().clamp(0, 999) ?? 1,
      capabilities: {
        for (final c in (json['capabilities'] as List?) ?? const [])
          if (c is String && c.trim().isNotEmpty) c.trim(),
      },
      activePresetId: json['activePresetId'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    if (provider.isNotEmpty) 'provider': provider,
    if (model.isNotEmpty) 'model': model,
    if (effort.isNotEmpty) 'effort': effort,
    if (extraArgs.isNotEmpty) 'extraArgs': extraArgs,
    if (cli != null) 'cli': cli!.value,
    if (replicas != 1) 'replicas': replicas,
    if (capabilities.isNotEmpty) 'capabilities': capabilities.toList(),
    if (activePresetId != null && activePresetId!.isNotEmpty)
      'activePresetId': activePresetId,
  };

  TeamRosterSlotOverrides copyWith({
    String? provider,
    String? model,
    String? effort,
    String? extraArgs,
    CliTool? cli,
    bool updateCli = false,
    int? replicas,
    Set<String>? capabilities,
    String? activePresetId,
    bool updateActivePresetId = false,
  }) {
    return TeamRosterSlotOverrides(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      extraArgs: extraArgs ?? this.extraArgs,
      cli: updateCli ? cli : (cli ?? this.cli),
      replicas: replicas ?? this.replicas,
      capabilities: capabilities ?? this.capabilities,
      activePresetId: updateActivePresetId
          ? activePresetId
          : (activePresetId ?? this.activePresetId),
    );
  }

  TeamMemberConfig applyTo(TeamMemberConfig base) {
    var next = base.copyWith(
      provider: provider.isNotEmpty ? provider : base.provider,
      model: model.isNotEmpty ? model : base.model,
      effort: effort.isNotEmpty ? effort : base.effort,
      extraArgs: extraArgs.isNotEmpty ? extraArgs : base.extraArgs,
      replicas: replicas,
      capabilities: capabilities.isNotEmpty ? capabilities : base.capabilities,
      activePresetId: activePresetId ?? base.activePresetId,
      updateActivePresetId: activePresetId != null,
    );
    if (cli != null) {
      return next.copyWith(cli: cli, updateCli: true);
    }
    if (activePresetId == TeamProfile.inheritPresetId) {
      return next.copyWith(cli: null, updateCli: true);
    }
    return next;
  }

  @override
  bool operator ==(Object other) =>
      other is TeamRosterSlotOverrides &&
      provider == other.provider &&
      model == other.model &&
      effort == other.effort &&
      extraArgs == other.extraArgs &&
      cli == other.cli &&
      replicas == other.replicas &&
      setEquals(capabilities, other.capabilities) &&
      activePresetId == other.activePresetId;

  @override
  int get hashCode => Object.hash(
    provider,
    model,
    effort,
    extraArgs,
    cli,
    replicas,
    Object.hashAllUnordered(capabilities),
    activePresetId,
  );
}

/// Persisted team roster entry — references a catalog expert by key.
@immutable
class TeamRosterSlot {
  const TeamRosterSlot({
    required this.id,
    required this.expertKey,
    this.overrides = const TeamRosterSlotOverrides(),
    this.joinedAt = 0,
  });

  final String id;
  final String expertKey;
  final TeamRosterSlotOverrides overrides;
  final int joinedAt;

  factory TeamRosterSlot.fromJson(Map<String, Object?> json) {
    final rawId = json['id'] as String? ?? '';
    final id = TeamMemberNaming.isTeamLeadName(rawId)
        ? TeamMemberNaming.teamLeadName
        : TeamMemberNaming.slugMemberName(rawId);
    return TeamRosterSlot(
      id: id,
      expertKey: json['expertKey'] as String? ?? '',
      overrides: json['overrides'] is Map
          ? TeamRosterSlotOverrides.fromJson(
              (json['overrides'] as Map).cast<String, Object?>(),
            )
          : const TeamRosterSlotOverrides(),
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'expertKey': expertKey,
    if (overrides != const TeamRosterSlotOverrides()) 'overrides': overrides.toJson(),
    if (joinedAt != 0) 'joinedAt': joinedAt,
  };

  TeamRosterSlot copyWith({
    String? id,
    String? expertKey,
    TeamRosterSlotOverrides? overrides,
    int? joinedAt,
  }) {
    return TeamRosterSlot(
      id: id ?? this.id,
      expertKey: expertKey ?? this.expertKey,
      overrides: overrides ?? this.overrides,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeamRosterSlot &&
      id == other.id &&
      expertKey == other.expertKey &&
      overrides == other.overrides &&
      joinedAt == other.joinedAt;

  @override
  int get hashCode => Object.hash(id, expertKey, overrides, joinedAt);
}
