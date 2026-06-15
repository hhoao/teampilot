import 'package:flutter/foundation.dart';

import 'team_config.dart';

@immutable
class ProjectAgentConfig {
  const ProjectAgentConfig({
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.prompt = '',
    this.dangerouslySkipPermissions = false,
  });

  factory ProjectAgentConfig.fromJson(Map<String, Object?> json) {
    return ProjectAgentConfig(
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      dangerouslySkipPermissions: TeamMemberConfig.decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
    );
  }

  final String agent;
  final String agentType;
  final String extraArgs;
  final String prompt;
  final bool dangerouslySkipPermissions;

  ProjectAgentConfig copyWith({
    String? agent,
    String? agentType,
    String? extraArgs,
    String? prompt,
    bool? dangerouslySkipPermissions,
  }) {
    return ProjectAgentConfig(
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      extraArgs: extraArgs ?? this.extraArgs,
      prompt: prompt ?? this.prompt,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'agent': agent,
      if (agentType.isNotEmpty) 'agentType': agentType,
      'extraArgs': extraArgs,
      'prompt': prompt,
      if (dangerouslySkipPermissions) 'dangerouslySkipPermissions': true,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProjectAgentConfig &&
            runtimeType == other.runtimeType &&
            agent == other.agent &&
            agentType == other.agentType &&
            extraArgs == other.extraArgs &&
            prompt == other.prompt &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions;
  }

  @override
  int get hashCode => Object.hash(
    agent,
    agentType,
    extraArgs,
    prompt,
    dangerouslySkipPermissions,
  );
}

@immutable
class ProjectProfile {
  const ProjectProfile({
    required this.projectId,
    this.activePresetId,
    this.agent = const ProjectAgentConfig(),
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.updatedAt = 0,
  });

  factory ProjectProfile.fromJson(Map<String, Object?> json) {
    final rawAgent = json['agent'];
    final agent = rawAgent is Map
        ? ProjectAgentConfig.fromJson(Map<String, Object?>.from(rawAgent))
        : const ProjectAgentConfig();
    return ProjectProfile(
      projectId: json['projectId'] as String? ?? '',
      activePresetId: _nullableTrimmedStr(json['activePresetId']),
      agent: agent,
      skillIds: TeamConfig.decodeSkillIds(json['skillIds']),
      pluginIds: TeamConfig.decodePluginIds(json['pluginIds']),
      mcpServerIds: TeamConfig.decodeMcpServerIds(json['mcpServerIds']),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  static String? _nullableTrimmedStr(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  final String projectId;
  final String? activePresetId;
  final ProjectAgentConfig agent;
  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;
  final int updatedAt;

  ProjectProfile copyWith({
    String? projectId,
    String? activePresetId,
    ProjectAgentConfig? agent,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    int? updatedAt,
  }) {
    return ProjectProfile(
      projectId: projectId ?? this.projectId,
      activePresetId: activePresetId ?? this.activePresetId,
      agent: agent ?? this.agent,
      skillIds: skillIds ?? this.skillIds,
      pluginIds: pluginIds ?? this.pluginIds,
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'projectId': projectId,
      if (activePresetId != null && activePresetId!.isNotEmpty)
        'activePresetId': activePresetId,
      'agent': agent.toJson(),
      if (skillIds.isNotEmpty) 'skillIds': skillIds,
      if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
      if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      if (updatedAt > 0) 'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProjectProfile &&
            runtimeType == other.runtimeType &&
            projectId == other.projectId &&
            activePresetId == other.activePresetId &&
            agent == other.agent &&
            listEquals(skillIds, other.skillIds) &&
            listEquals(pluginIds, other.pluginIds) &&
            listEquals(mcpServerIds, other.mcpServerIds) &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    projectId,
    activePresetId,
    agent,
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpServerIds),
    updatedAt,
  );
}
