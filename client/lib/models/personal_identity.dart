import 'package:flutter/foundation.dart';

import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_agent_config.dart';
import 'project_icon_ref.dart';
import 'workspace_identity.dart';

/// A solo (no-roster) launch identity. Owns a [ConfigBundle] plus single-agent
/// per-tool tiering and an agent config. Replaces the per-directory
/// `PersonalIdentity`.
@immutable
class PersonalIdentity implements Identity {
  const PersonalIdentity({
    required this.id,
    required this.display,
    this.icon = ProjectIconRef.auto,
    this.bundle = const ConfigBundle(),
    this.providerIdsByTool = const {},
    this.modelsByTool = const {},
    this.effortsByTool = const {},
    this.agent = const ProjectAgentConfig(),
    this.activePresetId,
    this.createdAt = 0,
    this.sortOrder = 0,
  });

  factory PersonalIdentity.fromJson(Map<String, Object?> json) {
    final rawAgent = json['agent'];
    return PersonalIdentity(
      id: (json['id'] as String? ?? '').trim(),
      display: json['display'] as String? ?? '',
      icon: ProjectIconRef.fromJson(json['icon']),
      bundle: ConfigBundle.fromJson(
        json['bundle'] is Map
            ? Map<String, Object?>.from(json['bundle'] as Map)
            : json,
      ),
      providerIdsByTool: _decodeStringMap(json['providerIdsByTool']),
      modelsByTool: _decodeStringMap(json['modelsByTool']),
      effortsByTool: _decodeStringMap(json['effortsByTool']),
      agent: rawAgent is Map
          ? ProjectAgentConfig.fromJson(Map<String, Object?>.from(rawAgent))
          : const ProjectAgentConfig(),
      activePresetId: _nullableTrimmed(json['activePresetId']),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  final String id;
  @override
  final String display;
  @override
  final ProjectIconRef icon;
  @override
  final ConfigBundle bundle;

  final Map<String, String> providerIdsByTool;
  final Map<String, String> modelsByTool;
  final Map<String, String> effortsByTool;
  final ProjectAgentConfig agent;
  final String? activePresetId;
  final int createdAt;
  final int sortOrder;

  @override
  IdentityKind get kind => IdentityKind.personal;

  static Map<String, String> _decodeStringMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k?.toString().trim() ?? '';
      final value = v?.toString().trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    });
    return Map.unmodifiable(out);
  }

  static String? _nullableTrimmed(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  PersonalIdentity copyWith({
    String? display,
    ProjectIconRef? icon,
    ConfigBundle? bundle,
    Map<String, String>? providerIdsByTool,
    Map<String, String>? modelsByTool,
    Map<String, String>? effortsByTool,
    ProjectAgentConfig? agent,
    String? activePresetId,
    int? createdAt,
    int? sortOrder,
  }) =>
      PersonalIdentity(
        id: id,
        display: display ?? this.display,
        icon: icon ?? this.icon,
        bundle: bundle ?? this.bundle,
        providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
        modelsByTool: modelsByTool ?? this.modelsByTool,
        effortsByTool: effortsByTool ?? this.effortsByTool,
        agent: agent ?? this.agent,
        activePresetId: activePresetId ?? this.activePresetId,
        createdAt: createdAt ?? this.createdAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.value,
        'display': display,
        if (icon.toJson() case final iconJson?) 'icon': iconJson,
        'bundle': bundle.toJson(),
        if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
        if (modelsByTool.isNotEmpty) 'modelsByTool': modelsByTool,
        if (effortsByTool.isNotEmpty) 'effortsByTool': effortsByTool,
        'agent': agent.toJson(),
        if (activePresetId != null && activePresetId!.isNotEmpty)
          'activePresetId': activePresetId,
        if (createdAt > 0) 'createdAt': createdAt,
        if (sortOrder > 0) 'sortOrder': sortOrder,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonalIdentity &&
          id == other.id &&
          display == other.display &&
          icon == other.icon &&
          bundle == other.bundle &&
          mapEquals(providerIdsByTool, other.providerIdsByTool) &&
          mapEquals(modelsByTool, other.modelsByTool) &&
          mapEquals(effortsByTool, other.effortsByTool) &&
          agent == other.agent &&
          activePresetId == other.activePresetId &&
          createdAt == other.createdAt &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
        id,
        display,
        icon,
        bundle,
        Object.hashAll(providerIdsByTool.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAll(modelsByTool.entries.map((e) => '${e.key}=${e.value}')),
        Object.hashAll(effortsByTool.entries.map((e) => '${e.key}=${e.value}')),
        agent,
        activePresetId,
        createdAt,
        sortOrder,
      );
}
