import 'package:flutter/foundation.dart';

@immutable
class TeamMemberConfig {
  const TeamMemberConfig({
    required this.id,
    required this.name,
    this.provider = '',
    this.model = '',
    this.agent = '',
    this.extraArgs = '',
    this.prompt = '',
  });

  factory TeamMemberConfig.fromJson(Map<String, Object?> json) {
    return TeamMemberConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String provider;
  final String model;
  final String agent;
  final String extraArgs;
  final String prompt;

  bool get isValid => name.trim().isNotEmpty;

  TeamMemberConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? model,
    String? agent,
    String? extraArgs,
    String? prompt,
  }) {
    return TeamMemberConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      agent: agent ?? this.agent,
      extraArgs: extraArgs ?? this.extraArgs,
      prompt: prompt ?? this.prompt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'model': model,
      'agent': agent,
      'extraArgs': extraArgs,
      'prompt': prompt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamMemberConfig &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            provider == other.provider &&
            model == other.model &&
            agent == other.agent &&
            extraArgs == other.extraArgs &&
            prompt == other.prompt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, provider, model, agent, extraArgs, prompt);
}

@immutable
class TeamConfig {
  const TeamConfig({
    required this.id,
    required this.name,
    required this.workingDirectory,
    this.extraArgs = '',
    this.members = const [],
  });

  factory TeamConfig.fromJson(Map<String, Object?> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
              .whereType<Map>()
              .map(
                (item) =>
                    TeamMemberConfig.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false)
        : const <TeamMemberConfig>[];

    return TeamConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      members: members,
    );
  }

  final String id;
  final String name;
  final String workingDirectory;
  final String extraArgs;
  final List<TeamMemberConfig> members;

  bool get isValid =>
      name.trim().isNotEmpty && workingDirectory.trim().isNotEmpty;

  TeamConfig copyWith({
    String? id,
    String? name,
    String? workingDirectory,
    String? extraArgs,
    List<TeamMemberConfig>? members,
  }) {
    return TeamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      extraArgs: extraArgs ?? this.extraArgs,
      members: members ?? this.members,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'workingDirectory': workingDirectory,
      'extraArgs': extraArgs,
      'members': members.map((member) => member.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamConfig &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            workingDirectory == other.workingDirectory &&
            extraArgs == other.extraArgs &&
            listEquals(members, other.members);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    workingDirectory,
    extraArgs,
    Object.hashAll(members),
  );
}
