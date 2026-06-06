import 'package:flutter/foundation.dart';

import 'team_config.dart';

@immutable
class ProjectAgentConfig {
  const ProjectAgentConfig({
    this.provider = '',
    this.model = '',
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.prompt = '',
    this.dangerouslySkipPermissions = false,
  });

  factory ProjectAgentConfig.fromJson(Map<String, Object?> json) {
    return ProjectAgentConfig(
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      dangerouslySkipPermissions: TeamMemberConfig.decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
    );
  }

  final String provider;
  final String model;
  final String agent;
  final String agentType;
  final String extraArgs;
  final String prompt;
  final bool dangerouslySkipPermissions;

  ProjectAgentConfig copyWith({
    String? provider,
    String? model,
    String? agent,
    String? agentType,
    String? extraArgs,
    String? prompt,
    bool? dangerouslySkipPermissions,
  }) {
    return ProjectAgentConfig(
      provider: provider ?? this.provider,
      model: model ?? this.model,
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
      'provider': provider,
      'model': model,
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
            provider == other.provider &&
            model == other.model &&
            agent == other.agent &&
            agentType == other.agentType &&
            extraArgs == other.extraArgs &&
            prompt == other.prompt &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions;
  }

  @override
  int get hashCode => Object.hash(
    provider,
    model,
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
    this.cli = CliTool.claude,
    this.agent = const ProjectAgentConfig(),
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.providerIdsByTool = const {},
    this.updatedAt = 0,
  });

  factory ProjectProfile.fromJson(Map<String, Object?> json) {
    final rawAgent = json['agent'];
    final agent = rawAgent is Map
        ? ProjectAgentConfig.fromJson(Map<String, Object?>.from(rawAgent))
        : const ProjectAgentConfig();
    return ProjectProfile(
      projectId: json['projectId'] as String? ?? '',
      cli: CliTool.parse(json['cli'], fallback: CliTool.claude),
      agent: agent,
      skillIds: TeamConfig.decodeSkillIds(json['skillIds']),
      pluginIds: TeamConfig.decodePluginIds(json['pluginIds']),
      mcpServerIds: TeamConfig.decodeMcpServerIds(json['mcpServerIds']),
      providerIdsByTool: _decodeProviderIdsByTool(json['providerIdsByTool']),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, String> _decodeProviderIdsByTool(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String &&
            entry.value != null &&
            entry.value.toString().trim().isNotEmpty)
          entry.key as String: entry.value.toString().trim(),
    };
  }

  final String projectId;
  final CliTool cli;
  final ProjectAgentConfig agent;
  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;
  final Map<String, String> providerIdsByTool;
  final int updatedAt;

  ProjectProfile copyWith({
    String? projectId,
    CliTool? cli,
    ProjectAgentConfig? agent,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    Map<String, String>? providerIdsByTool,
    int? updatedAt,
  }) {
    return ProjectProfile(
      projectId: projectId ?? this.projectId,
      cli: cli ?? this.cli,
      agent: agent ?? this.agent,
      skillIds: skillIds ?? this.skillIds,
      pluginIds: pluginIds ?? this.pluginIds,
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'projectId': projectId,
      'cli': cli.value,
      'agent': agent.toJson(),
      if (skillIds.isNotEmpty) 'skillIds': skillIds,
      if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
      if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
      if (updatedAt > 0) 'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProjectProfile &&
            runtimeType == other.runtimeType &&
            projectId == other.projectId &&
            cli == other.cli &&
            agent == other.agent &&
            listEquals(skillIds, other.skillIds) &&
            listEquals(pluginIds, other.pluginIds) &&
            listEquals(mcpServerIds, other.mcpServerIds) &&
            mapEquals(providerIdsByTool, other.providerIdsByTool) &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    projectId,
    cli,
    agent,
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpServerIds),
    Object.hashAll(providerIdsByTool.entries),
    updatedAt,
  );
}
