import 'package:flutter/foundation.dart';

import 'team_config.dart'; // for TeamMemberConfig.decodeDangerouslySkipPermissions

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
      dangerouslySkipPermissions: json.containsKey('dangerouslySkipPermissions')
          ? TeamMemberConfig.decodeDangerouslySkipPermissions(
              json['dangerouslySkipPermissions'],
            )
          : false,
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
