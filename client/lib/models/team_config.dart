import 'package:flutter/foundation.dart';

/// Backend CLI for a team session (`flashskyai`, `codex`, or `claude`).
enum TeamCli {
  flashskyai('flashskyai'),
  codex('codex'),
  claude('claude');

  const TeamCli(this.value);

  final String value;

  static TeamCli decode(Object? raw) => tryParse(raw?.toString()) ?? flashskyai;

  static TeamCli? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final cli in TeamCli.values) {
      if (cli.value == normalized) return cli;
    }
    return null;
  }

  /// Whether TeamPilot can launch a team terminal with this CLI today.
  bool get isLaunchSupported =>
      this == TeamCli.flashskyai || this == TeamCli.claude;
}

@immutable
class TeamMemberConfig {
  const TeamMemberConfig({
    required this.id,
    required this.name,
    this.provider = '',
    this.model = '',
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.prompt = '',
    this.joinedAt = 0,
    this.dangerouslySkipPermissions = false,
  });

  static bool decodeDangerouslySkipPermissions(Object? raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is String) {
      return raw.trim().toLowerCase() == 'true';
    }
    return false;
  }

  factory TeamMemberConfig.fromJson(Map<String, Object?> json) {
    final name = json['name'] as String? ?? '';
    return TeamMemberConfig(
      id: json['id'] as String? ?? name,
      name: name,
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      dangerouslySkipPermissions: decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
    );
  }

  final String id;
  final String name;
  final String provider;
  final String model;
  final String agent;

  /// Claude roster `agentType` (role name); falls back to [agent] then [name].
  final String agentType;
  final String extraArgs;
  final String prompt;
  final int joinedAt;

  /// When true, launch passes `--dangerously-skip-permissions` (CLI flag).
  final bool dangerouslySkipPermissions;

  bool get isValid => name.trim().isNotEmpty;

  TeamMemberConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? model,
    String? agent,
    String? agentType,
    String? extraArgs,
    String? prompt,
    int? joinedAt,
    bool? dangerouslySkipPermissions,
  }) {
    return TeamMemberConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      extraArgs: extraArgs ?? this.extraArgs,
      prompt: prompt ?? this.prompt,
      joinedAt: joinedAt ?? this.joinedAt,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'model': model,
      'agent': agent,
      if (agentType.isNotEmpty) 'agentType': agentType,
      'extraArgs': extraArgs,
      'prompt': prompt,
      'joinedAt': joinedAt,
      if (dangerouslySkipPermissions) 'dangerouslySkipPermissions': true,
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
            agentType == other.agentType &&
            extraArgs == other.extraArgs &&
            prompt == other.prompt &&
            joinedAt == other.joinedAt &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    provider,
    model,
    agent,
    agentType,
    extraArgs,
    prompt,
    joinedAt,
    dangerouslySkipPermissions,
  );
}

@immutable
class TeamConfig {
  const TeamConfig({
    required this.id,
    required this.name,
    this.description = '',
    this.extraArgs = '',
    this.members = const [],
    this.skillIds = const [],
    this.providerIdsByTool = const {},
    this.cli = TeamCli.claude,
    this.createdAt = 0,
    this.loop,
    this.claudeTeammateMode = 'in-process',
    this.claudeEffortLevel = 'xhigh',
    this.autoLaunchMembers,
  });

  static List<String> decodeSkillIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  /// `--loop` for `--team` mode: `true` / `false`; otherwise returns null.
  static bool? decodeLoop(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is String) {
      final s = raw.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

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
      description: json['description'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      members: members,
      skillIds: decodeSkillIds(json['skillIds']),
      providerIdsByTool: _decodeProviderIdsByTool(json['providerIdsByTool']),
      cli: TeamCli.decode(json['cli']),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      loop: decodeLoop(json['loop']),
      claudeTeammateMode:
          json['claudeTeammateMode'] as String? ?? 'in-process',
      claudeEffortLevel: json['claudeEffortLevel'] as String? ?? 'xhigh',
      autoLaunchMembers: json['autoLaunchMembers'] as bool?,
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

  final String id;
  final String name;
  final String description;
  final String extraArgs;
  final List<TeamMemberConfig> members;

  /// Manifest [Skill.id] values enabled for this team.
  final List<String> skillIds;

  /// App-level provider id per tool (`flashskyai`, `codex`, `claude`).
  final Map<String, String> providerIdsByTool;

  /// CLI backend for this team. Set at creation; not user-editable afterward.
  final TeamCli cli;
  final int createdAt;

  /// When non-null, launch passes `--loop true` or `--loop false` (team mode).
  final bool? loop;

  /// Claude `settings.json` `teammateMode` (`in-process`, `tmux`, …).
  final String claudeTeammateMode;

  /// Claude `settings.json` `effortLevel`.
  final String claudeEffortLevel;

  /// When non-null, overrides global session pref for auto-launching members.
  final bool? autoLaunchMembers;

  bool get isValid => name.trim().isNotEmpty;

  TeamConfig copyWith({
    String? id,
    String? name,
    String? description,
    String? extraArgs,
    List<TeamMemberConfig>? members,
    List<String>? skillIds,
    Map<String, String>? providerIdsByTool,
    TeamCli? cli,
    int? createdAt,
    bool? loop,
    bool updateLoop = false,
    String? claudeTeammateMode,
    String? claudeEffortLevel,
    bool? autoLaunchMembers,
    bool updateAutoLaunchMembers = false,
  }) {
    return TeamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      extraArgs: extraArgs ?? this.extraArgs,
      members: members ?? this.members,
      skillIds: skillIds ?? this.skillIds,
      providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
      cli: cli ?? this.cli,
      createdAt: createdAt ?? this.createdAt,
      loop: updateLoop ? loop : this.loop,
      claudeTeammateMode: claudeTeammateMode ?? this.claudeTeammateMode,
      claudeEffortLevel: claudeEffortLevel ?? this.claudeEffortLevel,
      autoLaunchMembers: updateAutoLaunchMembers
          ? autoLaunchMembers
          : this.autoLaunchMembers,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      'extraArgs': extraArgs,
      'members': members.map((member) => member.toJson()).toList(),
      if (skillIds.isNotEmpty) 'skillIds': skillIds,
      if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
      if (cli != TeamCli.flashskyai) 'cli': cli.value,
      'createdAt': createdAt,
      if (loop != null) 'loop': loop!,
      if (claudeTeammateMode != 'in-process')
        'claudeTeammateMode': claudeTeammateMode,
      if (claudeEffortLevel != 'xhigh') 'claudeEffortLevel': claudeEffortLevel,
      if (autoLaunchMembers != null) 'autoLaunchMembers': autoLaunchMembers!,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamConfig &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            description == other.description &&
            extraArgs == other.extraArgs &&
            listEquals(members, other.members) &&
            listEquals(skillIds, other.skillIds) &&
            mapEquals(providerIdsByTool, other.providerIdsByTool) &&
            cli == other.cli &&
            createdAt == other.createdAt &&
            loop == other.loop &&
            claudeTeammateMode == other.claudeTeammateMode &&
            claudeEffortLevel == other.claudeEffortLevel &&
            autoLaunchMembers == other.autoLaunchMembers;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    extraArgs,
    Object.hashAll(members),
    Object.hashAll(skillIds),
    Object.hashAll(providerIdsByTool.entries),
    cli,
    createdAt,
    loop,
    claudeTeammateMode,
    claudeEffortLevel,
    autoLaunchMembers,
  );
}
