import 'package:flutter/foundation.dart';

import 'launch_security_policy.dart';

@immutable
class WorkspaceAgentConfig {
  const WorkspaceAgentConfig({
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.responsibilities = '',
    this.launchSecurityPolicy = const LaunchSecurityPolicy(),
  });

  factory WorkspaceAgentConfig.fromJson(Map<String, Object?> json) {
    return WorkspaceAgentConfig(
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      responsibilities: json['responsibilities'] as String? ?? '',
      launchSecurityPolicy: LaunchSecurityPolicy.fromJson(
        json['launchSecurityPolicy'],
      ),
    );
  }

  final String agent;
  final String agentType;
  final String extraArgs;
  final String responsibilities;
  final LaunchSecurityPolicy launchSecurityPolicy;

  WorkspaceAgentConfig copyWith({
    String? agent,
    String? agentType,
    String? extraArgs,
    String? responsibilities,
    LaunchSecurityPolicy? launchSecurityPolicy,
  }) {
    return WorkspaceAgentConfig(
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      extraArgs: extraArgs ?? this.extraArgs,
      responsibilities: responsibilities ?? this.responsibilities,
      launchSecurityPolicy: launchSecurityPolicy ?? this.launchSecurityPolicy,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'agent': agent,
      if (agentType.isNotEmpty) 'agentType': agentType,
      'extraArgs': extraArgs,
      'responsibilities': responsibilities,
      'launchSecurityPolicy': launchSecurityPolicy.toJson(),
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
            launchSecurityPolicy == other.launchSecurityPolicy;
  }

  @override
  int get hashCode => Object.hash(
    agent,
    agentType,
    extraArgs,
    responsibilities,
    launchSecurityPolicy,
  );
}
