import 'package:flutter/foundation.dart';

import '../utils/team_member_naming.dart';
import 'skill.dart';
import 'team_config.dart';

/// Source descriptor for a skill a public team depends on (resolved to a local
/// id only at clone time, never stored as a local id in the template).
@immutable
class SkillDependencyRef {
  const SkillDependencyRef({
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
    required this.directory,
    required this.name,
  });

  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final String directory;
  final String name;

  /// Deterministic local [Skill.id] this dep resolves to once installed
  /// (`owner/name:basename`). Lets the UI know whether it is already installed
  /// without downloading, and keeps the installer + UI in agreement.
  String get expectedLocalId =>
      '$repoOwner/$repoName:${directory.split('/').last}';

  /// Payload for [SkillInstallService.installFromDiscovery] during TeamHub clone.
  DiscoverableSkill toDiscoverableSkill() => DiscoverableSkill(
        key: expectedLocalId,
        name: name,
        description: '',
        directory: directory,
        repoOwner: repoOwner,
        repoName: repoName,
        repoBranch: repoBranch,
      );

  factory SkillDependencyRef.fromJson(Map<String, Object?> json) =>
      SkillDependencyRef(
        repoOwner: json['repoOwner'] as String? ?? '',
        repoName: json['repoName'] as String? ?? '',
        repoBranch: json['repoBranch'] as String? ?? 'main',
        directory: json['directory'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
        'repoOwner': repoOwner,
        'repoName': repoName,
        'repoBranch': repoBranch,
        'directory': directory,
        'name': name,
      };

  @override
  bool operator ==(Object other) =>
      other is SkillDependencyRef &&
      repoOwner == other.repoOwner &&
      repoName == other.repoName &&
      repoBranch == other.repoBranch &&
      directory == other.directory &&
      name == other.name;

  @override
  int get hashCode =>
      Object.hash(repoOwner, repoName, repoBranch, directory, name);
}

/// Source descriptor for a plugin dependency (resolved at clone time).
@immutable
class PluginDependencyRef {
  const PluginDependencyRef({
    required this.marketplaceOwner,
    required this.marketplaceName,
    required this.marketplaceBranch,
    required this.entryName,
    required this.name,
  });

  final String marketplaceOwner;
  final String marketplaceName;
  final String marketplaceBranch;
  final String entryName;
  final String name;

  /// Deterministic local `Plugin.id` this dep resolves to once installed
  /// (`owner/name/entryName`).
  String get expectedLocalId =>
      '$marketplaceOwner/$marketplaceName/$entryName';

  factory PluginDependencyRef.fromJson(Map<String, Object?> json) =>
      PluginDependencyRef(
        marketplaceOwner: json['marketplaceOwner'] as String? ?? '',
        marketplaceName: json['marketplaceName'] as String? ?? '',
        marketplaceBranch: json['marketplaceBranch'] as String? ?? 'main',
        entryName: json['entryName'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
        'marketplaceOwner': marketplaceOwner,
        'marketplaceName': marketplaceName,
        'marketplaceBranch': marketplaceBranch,
        'entryName': entryName,
        'name': name,
      };

  @override
  bool operator ==(Object other) =>
      other is PluginDependencyRef &&
      marketplaceOwner == other.marketplaceOwner &&
      marketplaceName == other.marketplaceName &&
      marketplaceBranch == other.marketplaceBranch &&
      entryName == other.entryName &&
      name == other.name;

  @override
  int get hashCode => Object.hash(
        marketplaceOwner,
        marketplaceName,
        marketplaceBranch,
        entryName,
        name,
      );
}

/// Inline MCP server config a public team depends on.
@immutable
class McpDependencyRef {
  const McpDependencyRef({
    required this.id,
    required this.name,
    required this.server,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
  final Map<String, Object?> server;

  factory McpDependencyRef.fromJson(Map<String, Object?> json) =>
      McpDependencyRef(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        server: (json['server'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'server': server,
      };

  @override
  bool operator ==(Object other) =>
      other is McpDependencyRef &&
      id == other.id &&
      name == other.name &&
      description == other.description &&
      mapEquals(server, other.server);

  @override
  int get hashCode => Object.hash(id, name, description, server.length);
}

/// Portable subset of [TeamMemberConfig] (no local id / joinedAt).
@immutable
class DiscoverableTeamMember {
  const DiscoverableTeamMember({
    required this.name,
    this.provider = '',
    this.model = '',
    this.agent = '',
    this.agentType = '',
    this.capabilities = const {},
    this.replicas = 1,
    this.prompt = '',
    this.playbook = '',
    this.extraArgs = '',
  });

  final String name;
  final String provider;
  final String model;
  final String agent;
  final String agentType;

  /// Capability tags for TeamBus task routing — maps to
  /// [TeamMemberConfig.capabilities].
  final Set<String> capabilities;

  /// Pool size for this member type — maps to [TeamMemberConfig.replicas].
  final int replicas;

  /// Responsibilities (WHAT) — maps to [TeamMemberConfig.prompt].
  final String prompt;

  /// Working method (HOW) — maps to [TeamMemberConfig.playbook].
  final String playbook;
  final String extraArgs;

  factory DiscoverableTeamMember.fromJson(Map<String, Object?> json) =>
      DiscoverableTeamMember(
        name: json['name'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        model: json['model'] as String? ?? '',
        agent: json['agent'] as String? ?? '',
        agentType: json['agentType'] as String? ?? '',
        capabilities: {
          for (final c in (json['capabilities'] as List?) ?? const [])
            if (c is String && c.trim().isNotEmpty) c.trim(),
        },
        replicas: (json['replicas'] as num?)?.toInt() ?? 1,
        prompt: json['prompt'] as String? ?? '',
        playbook: json['playbook'] as String? ?? '',
        extraArgs: json['extraArgs'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'provider': provider,
        'model': model,
        'agent': agent,
        if (agentType.isNotEmpty) 'agentType': agentType,
        if (capabilities.isNotEmpty) 'capabilities': capabilities.toList(),
        if (replicas != 1) 'replicas': replicas,
        'prompt': prompt,
        if (playbook.isNotEmpty) 'playbook': playbook,
        'extraArgs': extraArgs,
      };

  TeamMemberConfig toMemberConfig({required int joinedAt}) {
    final id = TeamMemberNaming.isTeamLeadName(name)
        ? TeamMemberNaming.teamLeadName
        : TeamMemberNaming.slugMemberName(name);
    return TeamMemberConfig(
      id: id,
      name: name,
      provider: provider,
      model: model,
      agent: agent,
      agentType: agentType,
      capabilities: capabilities,
      replicas: replicas,
      prompt: prompt,
      playbook: playbook,
      extraArgs: extraArgs,
      joinedAt: joinedAt,
      activePresetId: TeamProfile.inheritPresetId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoverableTeamMember &&
      name == other.name &&
      provider == other.provider &&
      model == other.model &&
      agent == other.agent &&
      agentType == other.agentType &&
      capabilities.length == other.capabilities.length &&
      capabilities.containsAll(other.capabilities) &&
      replicas == other.replicas &&
      prompt == other.prompt &&
      playbook == other.playbook &&
      extraArgs == other.extraArgs;

  @override
  int get hashCode => Object.hash(
        name,
        provider,
        model,
        agent,
        agentType,
        Object.hashAllUnordered(capabilities),
        replicas,
        prompt,
        playbook,
        extraArgs,
      );
}

/// A public team as listed in a TeamHub registry manifest.
@immutable
class DiscoverableTeam {
  const DiscoverableTeam({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.updatedAt,
    this.author,
    this.cli = CliTool.claude,
    this.teamMode = TeamMode.native,
    this.extraArgs = '',
    this.members = const [],
    this.skillDeps = const [],
    this.pluginDeps = const [],
    this.mcpDeps = const [],
  });

  /// Unique discovery key: `owner/name/slug`.
  final String key;
  final String name;
  final String description;
  final String category;
  final String? author;
  final int updatedAt;
  final CliTool cli;
  final TeamMode teamMode;
  final String extraArgs;
  final List<DiscoverableTeamMember> members;
  final List<SkillDependencyRef> skillDeps;
  final List<PluginDependencyRef> pluginDeps;
  final List<McpDependencyRef> mcpDeps;

  factory DiscoverableTeam.fromJson(Map<String, Object?> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, Object?>) f) =>
        raw is List
            ? raw
                .whereType<Map>()
                .map((m) => f(m.cast<String, Object?>()))
                .toList(growable: false)
            : const [];
    return DiscoverableTeam(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      author: json['author'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      cli: CliTool.decode(json['cli']),
      teamMode: TeamMode.decode(json['teamMode']),
      extraArgs: json['extraArgs'] as String? ?? '',
      members: list(json['members'], DiscoverableTeamMember.fromJson),
      skillDeps: list(json['skillDeps'], SkillDependencyRef.fromJson),
      pluginDeps: list(json['pluginDeps'], PluginDependencyRef.fromJson),
      mcpDeps: list(json['mcpDeps'], McpDependencyRef.fromJson),
    );
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'name': name,
        'description': description,
        'category': category,
        if (author != null) 'author': author,
        'updatedAt': updatedAt,
        'cli': cli.value,
        'teamMode': teamMode.value,
        if (extraArgs.isNotEmpty) 'extraArgs': extraArgs,
        'members': members.map((m) => m.toJson()).toList(),
        'skillDeps': skillDeps.map((d) => d.toJson()).toList(),
        'pluginDeps': pluginDeps.map((d) => d.toJson()).toList(),
        'mcpDeps': mcpDeps.map((d) => d.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is DiscoverableTeam &&
      key == other.key &&
      name == other.name &&
      description == other.description &&
      category == other.category &&
      author == other.author &&
      updatedAt == other.updatedAt &&
      cli == other.cli &&
      teamMode == other.teamMode &&
      extraArgs == other.extraArgs &&
      listEquals(members, other.members) &&
      listEquals(skillDeps, other.skillDeps) &&
      listEquals(pluginDeps, other.pluginDeps) &&
      listEquals(mcpDeps, other.mcpDeps);

  @override
  int get hashCode => Object.hash(
        key,
        name,
        description,
        category,
        author,
        updatedAt,
        cli,
        teamMode,
        extraArgs,
        Object.hashAll(members),
        Object.hashAll(skillDeps),
        Object.hashAll(pluginDeps),
        Object.hashAll(mcpDeps),
      );
}
