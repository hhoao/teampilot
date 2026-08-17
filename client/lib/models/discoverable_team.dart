import 'package:flutter/foundation.dart';

import '../utils/team/team_member_naming.dart';
import 'catalog/catalog_types.dart';
import 'skill.dart';
import 'skill_pack_instruction.dart';
import 'team_config.dart';
import 'team_roster_slot.dart';

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
    this.id,
    this.packId,
    this.install,
    this.scriptUrl,
  });

  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final String directory;
  final String name;

  /// Optional explicit local skill id (preferred for script / pack skills).
  final String? id;

  /// When set, install goes through [SkillPack] (install-once, many skills).
  final String? packId;

  /// Inline Dockerfile-like install when not using [packId].
  final List<SkillPackInstruction>? install;

  /// HTTPS installer URL sugar (synthesizes a [ScriptInstruction]).
  final String? scriptUrl;

  /// Resolved install AST for non-pack deps. Pack deps return null
  /// (engine loads pack.install).
  List<SkillPackInstruction>? get resolvedInstall {
    if (packId != null && packId!.trim().isNotEmpty) return null;
    if (install != null && install!.isNotEmpty) return install;
    if (repoOwner.isNotEmpty && repoName.isNotEmpty && directory.isNotEmpty) {
      final branch = repoBranch.isEmpty ? 'main' : repoBranch;
      return [
        FromInstruction.parseRef('$repoOwner/$repoName@$branch'),
        SkillsInstruction(includeAll: false, include: [directory]),
      ];
    }
    final script = scriptUrl?.trim();
    if (script != null && script.isNotEmpty) {
      return [
        ScriptInstruction(
          url: script,
          id: expectedLocalId,
          primaryDirectory: directory.isEmpty ? null : directory,
        ),
      ];
    }
    return null;
  }

  /// Deterministic local [Skill.id] this dep resolves to once installed.
  String get expectedLocalId {
    final explicit = id?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final pack = packId?.trim();
    if (pack != null && pack.isNotEmpty) {
      final base = directory.split('/').last;
      return '$pack:$base';
    }
    final script = scriptUrl?.trim();
    if (script != null && script.isNotEmpty) {
      return skillScriptIdFromPackageUrl(script);
    }
    final base = directory.split('/').last;
    if (repoOwner.isNotEmpty && repoName.isNotEmpty && base.isNotEmpty) {
      return '$repoOwner/$repoName:$base';
    }
    return base.isEmpty ? 'local:unknown' : 'local:$base';
  }

  /// Payload for discovery-based install paths.
  DiscoverableSkill toDiscoverableSkill() => DiscoverableSkill(
    key: expectedLocalId,
    name: name,
    description: '',
    directory: directory,
    repoOwner: repoOwner,
    repoName: repoName,
    repoBranch: repoBranch,
    id: id,
    packId: packId,
    install: install,
    scriptUrl: scriptUrl,
  );

  factory SkillDependencyRef.fromJson(Map<String, Object?> json) {
    if (json.containsKey('recipe')) {
      throw const FormatException(
        'SkillDependencyRef.recipe is no longer supported; use install/scriptUrl',
      );
    }
    final idRaw = (json['id'] as String?)?.trim();
    final packRaw = (json['packId'] as String?)?.trim();
    final scriptRaw = (json['scriptUrl'] as String?)?.trim();
    final installRaw = json['install'];
    return SkillDependencyRef(
      repoOwner: json['repoOwner'] as String? ?? '',
      repoName: json['repoName'] as String? ?? '',
      repoBranch: json['repoBranch'] as String? ?? 'main',
      directory: json['directory'] as String? ?? '',
      name: json['name'] as String? ?? '',
      id: idRaw == null || idRaw.isEmpty ? null : idRaw,
      packId: packRaw == null || packRaw.isEmpty ? null : packRaw,
      scriptUrl: scriptRaw == null || scriptRaw.isEmpty ? null : scriptRaw,
      install: installRaw is List ? parseSkillPackInstall(installRaw) : null,
    );
  }

  Map<String, Object?> toJson() => {
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
    'directory': directory,
    'name': name,
    if (id != null && id!.isNotEmpty) 'id': id,
    if (packId != null && packId!.isNotEmpty) 'packId': packId,
    if (scriptUrl != null && scriptUrl!.isNotEmpty) 'scriptUrl': scriptUrl,
    if (install != null && install!.isNotEmpty)
      'install': [for (final step in install!) _depInstallToJson(step)],
  };

  @override
  bool operator ==(Object other) =>
      other is SkillDependencyRef &&
      repoOwner == other.repoOwner &&
      repoName == other.repoName &&
      repoBranch == other.repoBranch &&
      directory == other.directory &&
      name == other.name &&
      id == other.id &&
      packId == other.packId &&
      scriptUrl == other.scriptUrl &&
      listEquals(install, other.install);

  @override
  int get hashCode => Object.hash(
    repoOwner,
    repoName,
    repoBranch,
    directory,
    name,
    id,
    packId,
    scriptUrl,
    install == null ? null : Object.hashAll(install!),
  );
}

Map<String, Object?> _depInstallToJson(SkillPackInstruction step) {
  return switch (step) {
    FromInstruction(:final owner, :final name, :final branch) => {
      'FROM': '$owner/$name@$branch',
    },
    ScriptInstruction(
      :final url,
      :final id,
      :final primaryDirectory,
      :final alternatives,
      :final optional,
    ) =>
      {
        'SCRIPT': {
          'url': url,
          if (id != null && id.isNotEmpty) 'id': id,
          if (primaryDirectory != null && primaryDirectory.isNotEmpty)
            'primaryDirectory': primaryDirectory,
          if (alternatives.isNotEmpty) 'alternatives': alternatives,
        },
        if (optional) 'optional': true,
      },
    SkillsInstruction(:final includeAll, :final include, :final exclude) => {
      'SKILLS': includeAll && exclude.isEmpty
          ? '*'
          : {
              if (includeAll) 'include': '*',
              if (!includeAll) 'include': include,
              if (exclude.isNotEmpty) 'exclude': exclude,
            },
    },
    PathInstruction(:final entries) => {
      'PATH': entries.length == 1 ? entries.single : entries,
    },
    EnvInstruction(:final entries) => {'ENV': entries},
    RunInstruction(:final shell, :final exec, :final optional) => {
      'RUN': shell ?? exec,
      if (optional) 'optional': true,
    },
    ShellInstruction(:final wrapper) => {'SHELL': wrapper},
    WorkdirInstruction(:final path) => {'WORKDIR': path},
    CopyInstruction(:final from, :final to) => {
      'COPY': [from, to],
    },
  };
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
  String get expectedLocalId => '$marketplaceOwner/$marketplaceName/$entryName';

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
    this.responsibilities = '',
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

  /// Responsibilities (WHAT) — maps to [TeamMemberConfig.responsibilities].
  final String responsibilities;

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
        responsibilities: json['responsibilities'] as String? ?? '',
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
    'responsibilities': responsibilities,
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
      responsibilities: responsibilities,
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
      responsibilities == other.responsibilities &&
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
    responsibilities,
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
    CliTool? cli,
    TeamMode? teamMode,
    this.extraArgs = '',
    this.roster = const [],
    this.skillDeps = const [],
    this.pluginDeps = const [],
    this.mcpDeps = const [],
    this.metrics = const CatalogMetrics(),
  }) : _cli = cli,
       _teamMode = teamMode;

  /// Unique discovery key: `owner/name/slug`.
  final String key;
  final String name;
  final String description;
  final String category;
  final String? author;
  final int updatedAt;

  /// CLI as declared in the manifest; null when not written.
  final CliTool? _cli;

  /// teamMode as declared in the manifest; null when not written.
  final TeamMode? _teamMode;

  /// Effective CLI: declared value or [CliTool.claude].
  CliTool get cli => _cli ?? CliTool.claude;

  /// Effective team mode: declared value or [TeamMode.native].
  TeamMode get teamMode => _teamMode ?? TeamMode.native;

  bool get cliDeclared => _cli != null;
  bool get teamModeDeclared => _teamMode != null;

  final String extraArgs;
  final List<TeamRosterSlot> roster;
  final List<SkillDependencyRef> skillDeps;
  final List<PluginDependencyRef> pluginDeps;
  final List<McpDependencyRef> mcpDeps;
  final CatalogMetrics metrics;

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
      cli: CliTool.tryParse(json['cli'] as String?),
      teamMode: TeamMode.tryParse(json['teamMode'] as String?),
      extraArgs: json['extraArgs'] as String? ?? '',
      roster: list(json['roster'], TeamRosterSlot.fromJson),
      skillDeps: list(json['skillDeps'], SkillDependencyRef.fromJson),
      pluginDeps: list(json['pluginDeps'], PluginDependencyRef.fromJson),
      mcpDeps: list(json['mcpDeps'], McpDependencyRef.fromJson),
      metrics: _catalogMetricsFromJson(json['metrics']),
    );
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'description': description,
    'category': category,
    if (author != null) 'author': author,
    'updatedAt': updatedAt,
    if (_cli != null) 'cli': _cli.value,
    if (_teamMode != null) 'teamMode': _teamMode.value,
    if (extraArgs.isNotEmpty) 'extraArgs': extraArgs,
    'roster': roster.map((s) => s.toJson()).toList(),
    'skillDeps': skillDeps.map((d) => d.toJson()).toList(),
    'pluginDeps': pluginDeps.map((d) => d.toJson()).toList(),
    'mcpDeps': mcpDeps.map((d) => d.toJson()).toList(),
    if (_hasCatalogMetrics(metrics)) 'metrics': _catalogMetricsToJson(metrics),
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
      _cli == other._cli &&
      _teamMode == other._teamMode &&
      extraArgs == other.extraArgs &&
      listEquals(roster, other.roster) &&
      listEquals(skillDeps, other.skillDeps) &&
      listEquals(pluginDeps, other.pluginDeps) &&
      listEquals(mcpDeps, other.mcpDeps) &&
      _catalogMetricsEquals(metrics, other.metrics);

  @override
  int get hashCode => Object.hash(
    key,
    name,
    description,
    category,
    author,
    updatedAt,
    _cli,
    _teamMode,
    extraArgs,
    Object.hashAll(roster),
    Object.hashAll(skillDeps),
    Object.hashAll(pluginDeps),
    Object.hashAll(mcpDeps),
    _catalogMetricsHash(metrics),
  );
}

CatalogMetrics _catalogMetricsFromJson(Object? raw) {
  if (raw is! Map) return const CatalogMetrics();
  final json = raw.cast<String, Object?>();
  return CatalogMetrics(
    adoptionCount: (json['adoptionCount'] as num?)?.toInt(),
    rating: (json['rating'] as num?)?.toDouble(),
    ratingCount: (json['ratingCount'] as num?)?.toInt(),
    updatedAtMs: (json['updatedAtMs'] as num?)?.toInt(),
    publishedAtMs: (json['publishedAtMs'] as num?)?.toInt(),
  );
}

Map<String, Object?> _catalogMetricsToJson(CatalogMetrics metrics) => {
  if (metrics.adoptionCount != null) 'adoptionCount': metrics.adoptionCount,
  if (metrics.rating != null) 'rating': metrics.rating,
  if (metrics.ratingCount != null) 'ratingCount': metrics.ratingCount,
  if (metrics.updatedAtMs != null) 'updatedAtMs': metrics.updatedAtMs,
  if (metrics.publishedAtMs != null) 'publishedAtMs': metrics.publishedAtMs,
};

bool _hasCatalogMetrics(CatalogMetrics metrics) =>
    metrics.adoptionCount != null ||
    metrics.rating != null ||
    metrics.ratingCount != null ||
    metrics.updatedAtMs != null ||
    metrics.publishedAtMs != null;

bool _catalogMetricsEquals(CatalogMetrics a, CatalogMetrics b) =>
    a.adoptionCount == b.adoptionCount &&
    a.rating == b.rating &&
    a.ratingCount == b.ratingCount &&
    a.updatedAtMs == b.updatedAtMs &&
    a.publishedAtMs == b.publishedAtMs;

int _catalogMetricsHash(CatalogMetrics metrics) => Object.hash(
  metrics.adoptionCount,
  metrics.rating,
  metrics.ratingCount,
  metrics.updatedAtMs,
  metrics.publishedAtMs,
);
