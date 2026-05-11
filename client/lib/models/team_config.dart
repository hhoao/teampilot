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
    this.joinedAt = 0,
  });

  factory TeamMemberConfig.fromJson(Map<String, Object?> json) {
    final name = json['name'] as String? ?? '';
    return TeamMemberConfig(
      id: json['id'] as String? ?? name,
      name: name,
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String provider;
  final String model;
  final String agent;
  final String extraArgs;
  final String prompt;
  final int joinedAt;

  bool get isValid => name.trim().isNotEmpty;

  TeamMemberConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? model,
    String? agent,
    String? extraArgs,
    String? prompt,
    int? joinedAt,
  }) {
    return TeamMemberConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      agent: agent ?? this.agent,
      extraArgs: extraArgs ?? this.extraArgs,
      prompt: prompt ?? this.prompt,
      joinedAt: joinedAt ?? this.joinedAt,
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
      'joinedAt': joinedAt,
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
            prompt == other.prompt &&
            joinedAt == other.joinedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        provider,
        model,
        agent,
        extraArgs,
        prompt,
        joinedAt,
      );
}

@immutable
class TeamConfig {
  const TeamConfig({
    required this.id,
    required this.name,
    this.extraArgs = '',
    this.members = const [],
    this.createdAt = 0,
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

    final name = json['name'] as String? ?? '';
    return TeamConfig(
      id: json['id'] as String? ?? name,
      name: name,
      extraArgs: json['extraArgs'] as String? ?? '',
      members: members,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String extraArgs;
  final List<TeamMemberConfig> members;
  final int createdAt;

  bool get isValid => name.trim().isNotEmpty;

  TeamConfig copyWith({
    String? id,
    String? name,
    String? extraArgs,
    List<TeamMemberConfig>? members,
    int? createdAt,
  }) {
    return TeamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      extraArgs: extraArgs ?? this.extraArgs,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'extraArgs': extraArgs,
      'members': members.map((member) => member.toJson()).toList(),
      'createdAt': createdAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamConfig &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            extraArgs == other.extraArgs &&
            listEquals(members, other.members) &&
            createdAt == other.createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        extraArgs,
        Object.hashAll(members),
        createdAt,
      );
}
