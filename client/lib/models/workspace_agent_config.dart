import 'package:flutter/foundation.dart';

@immutable
class WorkspaceAgentConfig {
  const WorkspaceAgentConfig({
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.responsibilities = '',
  });

  factory WorkspaceAgentConfig.fromJson(Map<String, Object?> json) {
    return WorkspaceAgentConfig(
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      responsibilities: json['responsibilities'] as String? ?? '',
    );
  }

  final String agent;
  final String agentType;
  final String extraArgs;
  final String responsibilities;

  WorkspaceAgentConfig copyWith({
    String? agent,
    String? agentType,
    String? extraArgs,
    String? responsibilities,
  }) {
    return WorkspaceAgentConfig(
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      extraArgs: extraArgs ?? this.extraArgs,
      responsibilities: responsibilities ?? this.responsibilities,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'agent': agent,
      if (agentType.isNotEmpty) 'agentType': agentType,
      'extraArgs': extraArgs,
      'responsibilities': responsibilities,
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
            responsibilities == other.responsibilities;
  }

  @override
  int get hashCode =>
      Object.hash(agent, agentType, extraArgs, responsibilities);
}
