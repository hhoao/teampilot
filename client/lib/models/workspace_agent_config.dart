import 'package:flutter/foundation.dart';

import 'team_config.dart'; // for TeamMemberConfig.decodeDangerouslySkipPermissions

@immutable
class WorkspaceAgentConfig {
  const WorkspaceAgentConfig({
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.responsibilities = '',
    this.dangerouslySkipPermissions = false,
  });

  factory WorkspaceAgentConfig.fromJson(Map<String, Object?> json) {
    return WorkspaceAgentConfig(
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      responsibilities: json['responsibilities'] as String? ?? '',
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
  final String responsibilities;
  final bool dangerouslySkipPermissions;

  WorkspaceAgentConfig copyWith({
    String? agent,
    String? agentType,
    String? extraArgs,
    String? responsibilities,
    bool? dangerouslySkipPermissions,
  }) {
    return WorkspaceAgentConfig(
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      extraArgs: extraArgs ?? this.extraArgs,
      responsibilities: responsibilities ?? this.responsibilities,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'agent': agent,
      if (agentType.isNotEmpty) 'agentType': agentType,
      'extraArgs': extraArgs,
      'responsibilities': responsibilities,
      if (dangerouslySkipPermissions) 'dangerouslySkipPermissions': true,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorkspaceAgentConfig &&
            runtimeType == other.runtimeType &&
            agent == other.agent &&
            agentType == other.agentType &&
            extraArgs == other.extraArgs &&
            responsibilities == other.responsibilities &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions;
  }

  @override
  int get hashCode => Object.hash(
    agent,
    agentType,
    extraArgs,
    responsibilities,
    dangerouslySkipPermissions,
  );
}
