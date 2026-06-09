import 'package:flutter/foundation.dart';

import '../utils/team_member_naming.dart';

/// Backend CLI identity (`flashskyai`, `codex`, `claude`, `opencode`, or
/// `cursor`).
///
/// Behavior (launch support, display name, provider catalog, etc.) lives in
/// [CliToolRegistry] capabilities — not on this enum.
enum CliTool {
  claude('claude'),
  codex('codex'),
  flashskyai('flashskyai'),
  opencode('opencode'),
  cursor('cursor');

  const CliTool(this.value);

  final String value;

  static CliTool decode(Object? raw) => tryParse(raw?.toString()) ?? flashskyai;

  static CliTool? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final cli in CliTool.values) {
      if (cli.value == normalized) return cli;
    }
    return null;
  }

  static CliTool parse(Object? raw, {CliTool? fallback}) {
    return tryParse(raw?.toString()) ?? fallback ?? CliTool.claude;
  }
}

/// 团队协调模式：native = 单 CLI 原生团队；mixed = 混合 CLI 走 TeamBus。
enum TeamMode {
  native('native'),
  mixed('mixed');

  const TeamMode(this.value);

  final String value;

  static TeamMode decode(Object? raw) => tryParse(raw?.toString()) ?? native;

  static TeamMode? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final mode in TeamMode.values) {
      if (mode.value == normalized) return mode;
    }
    return null;
  }
}

@immutable
class TeamMemberConfig {
  const TeamMemberConfig({
    /// CLI / roster key ([TeamMemberNaming.slugMemberName]); stable after create.
    required this.id,

    /// Sidebar and forms; may contain spaces; not passed to CLI flags.
    required this.name,
    this.provider = '',
    this.model = '',
    this.agent = '',
    this.agentType = '',
    this.extraArgs = '',
    this.prompt = '',
    this.playbook = '',
    this.joinedAt = 0,
    this.dangerouslySkipPermissions = false,
    this.cli,
    this.effort = '',
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
    final rawId = json['id'] as String? ?? name;
    final id =
        TeamMemberNaming.isTeamLeadName(rawId) ||
            TeamMemberNaming.isTeamLeadName(name)
        ? TeamMemberNaming.teamLeadName
        : TeamMemberNaming.slugMemberName(rawId);
    final displayName = name.trim().isEmpty ? id : name;
    return TeamMemberConfig(
      id: id,
      name: displayName,
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      agentType: json['agentType'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      playbook: json['playbook'] as String? ?? '',
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      dangerouslySkipPermissions: decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
      cli: CliTool.tryParse(json['cli'] as String?),
      effort: json['effort'] as String? ?? '',
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

  /// 职责层：声明这个角色是谁、负责什么（WHAT）。写入 role.md 的 Responsibilities 段。
  final String prompt;

  /// 工作方法层：声明这个角色具体怎么干活（HOW）——自由文本 SOP，可软引用 skill，
  /// 但不绑定 skill 目录。写入 role.md 的 Working method 段，与 [prompt] 平级、语义不同。
  final String playbook;

  final int joinedAt;

  /// When true, launch passes `--dangerously-skip-permissions` (CLI flag).
  final bool dangerouslySkipPermissions;

  /// 成员 CLI 覆盖（仅 mixed 模式生效）；null 回退 [TeamConfig.cli]。
  final CliTool? cli;

  /// Optional per-member effort override (`effortLevel` / `model_reasoning_effort`).
  final String effort;

  /// 成员有效 CLI：native 一律 team.cli；mixed 用成员覆盖、否则 team 默认。
  CliTool cliWithin(TeamConfig team) =>
      team.teamMode == TeamMode.mixed ? (cli ?? team.cli) : team.cli;

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
    String? playbook,
    int? joinedAt,
    bool? dangerouslySkipPermissions,
    CliTool? cli,
    bool updateCli = false,
    String? effort,
    bool updateEffort = false,
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
      playbook: playbook ?? this.playbook,
      joinedAt: joinedAt ?? this.joinedAt,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
      cli: updateCli ? cli : this.cli,
      effort: updateEffort ? (effort ?? '') : this.effort,
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
      if (playbook.isNotEmpty) 'playbook': playbook,
      'joinedAt': joinedAt,
      if (dangerouslySkipPermissions) 'dangerouslySkipPermissions': true,
      if (cli != null) 'cli': cli!.value,
      if (effort.isNotEmpty) 'effort': effort,
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
            playbook == other.playbook &&
            joinedAt == other.joinedAt &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions &&
            cli == other.cli &&
            effort == other.effort;
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
    playbook,
    joinedAt,
    dangerouslySkipPermissions,
    cli,
    effort,
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
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.providerIdsByTool = const {},
    this.cli = CliTool.claude,
    this.teamMode = TeamMode.native,
    this.createdAt = 0,
    this.sortOrder = 0,
    this.loop,
    this.claudeTeammateMode = 'in-process',
    this.claudeEffortLevel = 'high',
    this.cliEffortLevels = const {},
    this.autoLaunchMembers,
    this.forceTeamLeadDelegateMode = true,
    this.forceWaitBeforeStop = true,
  });

  static bool decodeForceTeamLeadDelegateMode(Object? raw) =>
      _decodeDefaultTrueBool(raw);

  static bool decodeForceWaitBeforeStop(Object? raw) =>
      _decodeDefaultTrueBool(raw);

  static bool _decodeDefaultTrueBool(Object? raw) {
    if (raw == null) return true;
    if (raw is bool) return raw;
    if (raw is String) {
      return raw.trim().toLowerCase() == 'true';
    }
    return false;
  }

  static List<String> decodeSkillIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> decodePluginIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> decodeMcpServerIds(Object? raw) {
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
      id: TeamMemberNaming.slugTeamId(json['id'] as String? ?? name),
      name: name,
      description: json['description'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      members: members,
      skillIds: decodeSkillIds(json['skillIds']),
      pluginIds: decodePluginIds(json['pluginIds']),
      mcpServerIds: decodeMcpServerIds(json['mcpServerIds']),
      providerIdsByTool: _decodeProviderIdsByTool(json['providerIdsByTool']),
      cli: CliTool.decode(json['cli']),
      teamMode: TeamMode.decode(json['teamMode']),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      loop: decodeLoop(json['loop']),
      claudeTeammateMode: json['claudeTeammateMode'] as String? ?? 'in-process',
      claudeEffortLevel: json['claudeEffortLevel'] as String? ?? 'high',
      cliEffortLevels: _mergeCliEffortLevels(
        _decodeProviderIdsByTool(json['cliEffortLevels']),
        json['claudeEffortLevel'] as String? ?? 'high',
      ),
      autoLaunchMembers: json['autoLaunchMembers'] as bool?,
      forceTeamLeadDelegateMode: decodeForceTeamLeadDelegateMode(
        json['forceTeamLeadDelegateMode'],
      ),
      forceWaitBeforeStop: decodeForceWaitBeforeStop(
        json['forceWaitBeforeStop'],
      ),
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

  static Map<String, String> _mergeCliEffortLevels(
    Map<String, String> fromJson,
    String claudeEffortLevel,
  ) {
    if (fromJson.isEmpty) return const {};
    final merged = Map<String, String>.from(fromJson);
    merged.putIfAbsent(CliTool.claude.value, () => claudeEffortLevel.trim());
    return merged;
  }

  String effortForCli(CliTool cli) {
    final fromMap = cliEffortLevels[cli.value]?.trim() ?? '';
    if (fromMap.isNotEmpty) return fromMap;
    if (cli == CliTool.claude) return claudeEffortLevel;
    return '';
  }

  TeamConfig withEffortForCli(CliTool cli, String effort) {
    final trimmed = effort.trim();
    final next = Map<String, String>.from(cliEffortLevels);
    if (trimmed.isEmpty) {
      next.remove(cli.value);
    } else {
      next[cli.value] = trimmed;
    }
    return copyWith(
      cliEffortLevels: next,
      claudeEffortLevel: cli == CliTool.claude
          ? (trimmed.isEmpty ? 'high' : trimmed)
          : null,
    );
  }

  /// Canonical slug ([TeamMemberNaming.slugTeamId]); used for paths and [AppSession.sessionTeam].
  final String id;
  final String name;
  final String description;
  final String extraArgs;
  final List<TeamMemberConfig> members;

  /// Manifest [Skill.id] values enabled for this team.
  final List<String> skillIds;

  /// `Plugin.id` values enabled for this team (mirrors [skillIds]).
  final List<String> pluginIds;

  /// [McpServer.id] values enabled for this team.
  final List<String> mcpServerIds;

  /// App-level provider id per tool (`flashskyai`, `codex`, `claude`).
  final Map<String, String> providerIdsByTool;

  /// CLI backend for this team. Set at creation; not user-editable afterward.
  final CliTool cli;

  /// 协调模式（默认 native；老 team 无此字段时回退 native）。
  final TeamMode teamMode;
  final int createdAt;

  /// Sidebar display order; 0 means unset (fall back to [createdAt]).
  final int sortOrder;

  /// When non-null, launch passes `--loop true` or `--loop false` (team mode).
  final bool? loop;

  /// Claude `settings.json` `teammateMode` (`in-process`, `tmux`, …).
  final String claudeTeammateMode;

  /// Claude `settings.json` `effortLevel`.
  final String claudeEffortLevel;

  /// Per-CLI effort defaults (`claude` → effortLevel, `codex` → reasoning effort).
  final Map<String, String> cliEffortLevels;

  /// When non-null, overrides global session pref for auto-launching members.
  final bool? autoLaunchMembers;

  /// When true, team-lead tab blocks Bash/Read/Edit/Write/etc. via PreToolUse hooks.
  final bool forceTeamLeadDelegateMode;

  /// mixed 模式:成员 turn 结束时,Stop hook 是否把它推回 `wait_for_message`
  /// (永不主动结束 turn)。false 时允许成员"休息"(正常停止)。仅经 TeamBus 的
  /// stop-hook 生效;空闲检测(`/idle` → onMemberIdle)无论开关都照常上报。
  final bool forceWaitBeforeStop;

  bool get isValid => name.trim().isNotEmpty;

  TeamConfig copyWith({
    String? id,
    String? name,
    String? description,
    String? extraArgs,
    List<TeamMemberConfig>? members,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    Map<String, String>? providerIdsByTool,
    CliTool? cli,
    TeamMode? teamMode,
    int? createdAt,
    int? sortOrder,
    bool? loop,
    bool updateLoop = false,
    String? claudeTeammateMode,
    String? claudeEffortLevel,
    Map<String, String>? cliEffortLevels,
    bool? autoLaunchMembers,
    bool updateAutoLaunchMembers = false,
    bool? forceTeamLeadDelegateMode,
    bool updateForceTeamLeadDelegateMode = false,
    bool? forceWaitBeforeStop,
    bool updateForceWaitBeforeStop = false,
  }) {
    return TeamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      extraArgs: extraArgs ?? this.extraArgs,
      members: members ?? this.members,
      skillIds: skillIds ?? this.skillIds,
      pluginIds: pluginIds ?? this.pluginIds,
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
      cli: cli ?? this.cli,
      teamMode: teamMode ?? this.teamMode,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      loop: updateLoop ? loop : this.loop,
      claudeTeammateMode: claudeTeammateMode ?? this.claudeTeammateMode,
      claudeEffortLevel: claudeEffortLevel ?? this.claudeEffortLevel,
      cliEffortLevels: cliEffortLevels ?? this.cliEffortLevels,
      autoLaunchMembers: updateAutoLaunchMembers
          ? autoLaunchMembers
          : this.autoLaunchMembers,
      forceTeamLeadDelegateMode: updateForceTeamLeadDelegateMode
          ? (forceTeamLeadDelegateMode ?? true)
          : this.forceTeamLeadDelegateMode,
      forceWaitBeforeStop: updateForceWaitBeforeStop
          ? (forceWaitBeforeStop ?? true)
          : this.forceWaitBeforeStop,
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
      if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
      if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
      if (cli != CliTool.flashskyai) 'cli': cli.value,
      if (teamMode != TeamMode.native) 'teamMode': teamMode.value,
      'createdAt': createdAt,
      if (sortOrder > 0) 'sortOrder': sortOrder,
      if (loop != null) 'loop': loop!,
      if (claudeTeammateMode != 'in-process')
        'claudeTeammateMode': claudeTeammateMode,
      if (claudeEffortLevel != 'high') 'claudeEffortLevel': claudeEffortLevel,
      if (cliEffortLevels.isNotEmpty) 'cliEffortLevels': cliEffortLevels,
      if (autoLaunchMembers != null) 'autoLaunchMembers': autoLaunchMembers!,
      if (forceTeamLeadDelegateMode)
        'forceTeamLeadDelegateMode': forceTeamLeadDelegateMode,
      if (!forceWaitBeforeStop) 'forceWaitBeforeStop': forceWaitBeforeStop,
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
            listEquals(pluginIds, other.pluginIds) &&
            listEquals(mcpServerIds, other.mcpServerIds) &&
            mapEquals(providerIdsByTool, other.providerIdsByTool) &&
            cli == other.cli &&
            teamMode == other.teamMode &&
            createdAt == other.createdAt &&
            sortOrder == other.sortOrder &&
            loop == other.loop &&
            claudeTeammateMode == other.claudeTeammateMode &&
            claudeEffortLevel == other.claudeEffortLevel &&
            mapEquals(cliEffortLevels, other.cliEffortLevels) &&
            autoLaunchMembers == other.autoLaunchMembers &&
            forceTeamLeadDelegateMode == other.forceTeamLeadDelegateMode &&
            forceWaitBeforeStop == other.forceWaitBeforeStop;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    extraArgs,
    Object.hashAll(members),
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpServerIds),
    Object.hashAll(providerIdsByTool.entries),
    cli,
    teamMode,
    createdAt,
    sortOrder,
    loop,
    claudeTeammateMode,
    claudeEffortLevel,
    Object.hashAll(cliEffortLevels.entries),
    autoLaunchMembers,
    forceTeamLeadDelegateMode,
    forceWaitBeforeStop,
  );
}
