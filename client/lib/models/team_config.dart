import 'package:flutter/foundation.dart';

import '../utils/team_member_naming.dart';
import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_icon_ref.dart';
import 'identity.dart';

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

  static CliTool decode(Object? raw) => tryParse(raw?.toString()) ?? claude;

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

/// 团队协调模式：native = 单 CLI 原生团队（须注册 [NativeTeamCapability]）；
/// mixed = 混合 CLI 走 TeamBus。
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
    this.capabilities = const {},
    this.extraArgs = '',
    this.prompt = '',
    this.playbook = '',
    this.joinedAt = 0,
    this.dangerouslySkipPermissions = true,
    this.cli,
    this.effort = '',
    this.replicas = 1,
    this.forceWaitBeforeStop,
    this.activePresetId,
  });

  static bool decodeDangerouslySkipPermissions(Object? raw) {
    if (raw == null) return true;
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
      capabilities: {
        for (final c in (json['capabilities'] as List?) ?? const [])
          if (c is String && c.trim().isNotEmpty) c.trim(),
      },
      extraArgs: json['extraArgs'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      playbook: json['playbook'] as String? ?? '',
      joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      dangerouslySkipPermissions: decodeDangerouslySkipPermissions(
        json['dangerouslySkipPermissions'],
      ),
      cli: CliTool.tryParse(json['cli'] as String?),
      effort: json['effort'] as String? ?? '',
      replicas: (json['replicas'] as num?)?.toInt() ?? 1,
      forceWaitBeforeStop: json['forceWaitBeforeStop'] is bool
          ? json['forceWaitBeforeStop'] as bool
          : null,
      activePresetId: json['activePresetId'] as String?,
    );
  }

  final String id;
  final String name;
  final String provider;
  final String model;
  final String agent;

  /// Claude roster `agentType` (role name); falls back to [agent] then [name].
  final String agentType;

  /// Capability tags used by TeamBus task routing (mixed mode). Empty ⇒ derived
  /// from [agentType]/[agent] in [TeammateRosterProfile]. Subset-matched against
  /// a task's required capabilities.
  final Set<String> capabilities;
  final String extraArgs;

  /// 职责层：声明这个角色是谁、负责什么（WHAT）。写入 role.md 的 Responsibilities 段。
  final String prompt;

  /// 工作方法层：声明这个角色具体怎么干活（HOW）——自由文本 SOP，可软引用 skill，
  /// 但不绑定 skill 目录。写入 role.md 的 Working method 段，与 [prompt] 平级、语义不同。
  final String playbook;

  final int joinedAt;

  /// When true, launch passes `--dangerously-skip-permissions` (CLI flag).
  final bool dangerouslySkipPermissions;

  /// 成员 CLI 覆盖（仅 mixed 模式生效）；null 回退 [TeamIdentity.cli]。
  final CliTool? cli;

  /// Optional per-member effort override (`effortLevel` / `model_reasoning_effort`).
  final String effort;

  /// Fixed instance/pool size for this member type (mixed-mode replicas).
  /// `1` (default) = a singleton; `> 1` = an interchangeable pool. See
  /// [MemberInstance] / `expandTeamRoster`.
  final int replicas;

  /// 成员级 [TeamIdentity.forceWaitBeforeStop] 覆盖（null=未设，回退 CLI 默认/团队值）。
  /// 见 [effectiveForceWaitBeforeStop]。
  final bool? forceWaitBeforeStop;

  /// Active preset id for this member.
  /// - `null` ⇒ member uses custom config (no preset).
  /// - `TeamIdentity.inheritPresetId` ⇒ inherits the team's [TeamIdentity.activePresetId].
  /// - any other value ⇒ member has an explicit preset override.
  final String? activePresetId;

  /// Whether this member inherits the team's active preset ([TeamIdentity.activePresetId]).
  bool get inheritsTeamPreset => activePresetId == TeamIdentity.inheritPresetId;

  /// Whether this member has an explicit, non-inherit preset id.
  bool get hasExplicitPreset =>
      activePresetId != null && activePresetId != TeamIdentity.inheritPresetId;

  /// Whether this member uses fully custom config (no preset at all).
  bool get usesCustomConfig => activePresetId == null;

  /// 成员有效 CLI：native 一律 team.cli；mixed 用成员覆盖、否则 team 默认。
  CliTool cliWithin(TeamIdentity team) =>
      team.teamMode == TeamMode.mixed ? (cli ?? team.cli) : team.cli;

  /// turn 结束时是否强制把该成员推回 `wait_for_message`（mixed 协议）。优先级：
  /// 成员显式覆盖 [forceWaitBeforeStop] > CLI 默认 > 团队 [TeamIdentity.forceWaitBeforeStop]。
  ///
  /// CLI 默认：**cursor 为 false** —— cursor 的 MCP 工具调用有 ~60s agent 层硬限
  /// （不可配、progress 不续），无法阻塞在 `wait_for_message` 里；改为正常停到
  /// idle-at-prompt，由门铃（stdin 注入 + `read_messages`）push 投递。
  bool effectiveForceWaitBeforeStop(TeamIdentity team) {
    if (forceWaitBeforeStop != null) return forceWaitBeforeStop!;
    if (cliWithin(team) == CliTool.cursor) return false;
    return team.forceWaitBeforeStop;
  }

  bool get isValid => name.trim().isNotEmpty;

  TeamMemberConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? model,
    String? agent,
    String? agentType,
    Set<String>? capabilities,
    String? extraArgs,
    String? prompt,
    String? playbook,
    int? joinedAt,
    bool? dangerouslySkipPermissions,
    CliTool? cli,
    bool updateCli = false,
    String? effort,
    bool updateEffort = false,
    int? replicas,
    bool? forceWaitBeforeStop,
    bool updateForceWaitBeforeStop = false,
    String? activePresetId,
    bool updateActivePresetId = false,
  }) {
    return TeamMemberConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      agent: agent ?? this.agent,
      agentType: agentType ?? this.agentType,
      capabilities: capabilities ?? this.capabilities,
      extraArgs: extraArgs ?? this.extraArgs,
      prompt: prompt ?? this.prompt,
      playbook: playbook ?? this.playbook,
      joinedAt: joinedAt ?? this.joinedAt,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
      cli: updateCli ? cli : this.cli,
      effort: updateEffort ? (effort ?? '') : this.effort,
      replicas: replicas ?? this.replicas,
      forceWaitBeforeStop: updateForceWaitBeforeStop
          ? forceWaitBeforeStop
          : this.forceWaitBeforeStop,
      activePresetId: updateActivePresetId
          ? activePresetId
          : this.activePresetId,
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
      if (capabilities.isNotEmpty) 'capabilities': capabilities.toList(),
      'extraArgs': extraArgs,
      'prompt': prompt,
      if (playbook.isNotEmpty) 'playbook': playbook,
      'joinedAt': joinedAt,
      if (!dangerouslySkipPermissions) 'dangerouslySkipPermissions': false,
      if (cli != null) 'cli': cli!.value,
      if (effort.isNotEmpty) 'effort': effort,
      if (replicas != 1) 'replicas': replicas,
      if (forceWaitBeforeStop != null)
        'forceWaitBeforeStop': forceWaitBeforeStop,
      if (activePresetId != null) 'activePresetId': activePresetId,
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
            capabilities.length == other.capabilities.length &&
            capabilities.containsAll(other.capabilities) &&
            extraArgs == other.extraArgs &&
            prompt == other.prompt &&
            playbook == other.playbook &&
            joinedAt == other.joinedAt &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions &&
            cli == other.cli &&
            effort == other.effort &&
            replicas == other.replicas &&
            forceWaitBeforeStop == other.forceWaitBeforeStop &&
            activePresetId == other.activePresetId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    provider,
    model,
    agent,
    agentType,
    Object.hashAllUnordered(capabilities),
    extraArgs,
    prompt,
    playbook,
    joinedAt,
    dangerouslySkipPermissions,
    cli,
    effort,
    replicas,
    forceWaitBeforeStop,
    activePresetId,
  );
}

@immutable
class TeamIdentity implements Identity {
  /// Sentinel value for [TeamMemberConfig.activePresetId] meaning "inherit the
  /// team's [activePresetId]".
  static const inheritPresetId = '__inherit__';

  const TeamIdentity({
    required this.id,
    required this.name,
    this.description = '',
    this.extraArgs = '',
    this.members = const [],
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.providerIdsByTool = const {},
    this.modelsByTool = const {},
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
    this.activePresetId,
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

  factory TeamIdentity.fromJson(Map<String, Object?> json) {
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
    return TeamIdentity(
      id: TeamMemberNaming.slugTeamId(json['id'] as String? ?? name),
      name: name,
      description: json['description'] as String? ?? '',
      extraArgs: json['extraArgs'] as String? ?? '',
      members: members,
      skillIds: decodeSkillIds(json['skillIds']),
      pluginIds: decodePluginIds(json['pluginIds']),
      mcpServerIds: decodeMcpServerIds(json['mcpServerIds']),
      providerIdsByTool: _decodeProviderIdsByTool(json['providerIdsByTool']),
      modelsByTool: _decodeProviderIdsByTool(json['modelsByTool']),
      cli: json.containsKey('cli')
          ? CliTool.parse(json['cli'])
          : CliTool.claude,
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
      activePresetId: json['activePresetId'] as String?,
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

  /// App-level provider id for [cli] from team custom defaults.
  String providerForCli(CliTool cli) =>
      providerIdsByTool[cli.value]?.trim() ?? '';

  /// Model id for [cli] from team custom defaults.
  String modelForCli(CliTool cli) => modelsByTool[cli.value]?.trim() ?? '';

  /// Whether team custom defaults include a provider for [cli].
  bool hasCustomLaunchDefaultsFor(CliTool cli) =>
      providerForCli(cli).isNotEmpty;

  /// Whether the team has a preset reference or custom launch defaults for [cli].
  bool hasLaunchDefaultsFor(
    CliTool cli, {
    required bool presetExists,
  }) =>
      (activePresetId != null && presetExists) ||
      hasCustomLaunchDefaultsFor(cli);

  TeamIdentity withLaunchDefaultsForCli({
    required CliTool cli,
    required String providerId,
    required String model,
    required String effort,
  }) {
    final trimmedProvider = providerId.trim();
    final trimmedModel = model.trim();
    final nextProviders = Map<String, String>.from(providerIdsByTool);
    final nextModels = Map<String, String>.from(modelsByTool);
    if (trimmedProvider.isEmpty) {
      nextProviders.remove(cli.value);
    } else {
      nextProviders[cli.value] = trimmedProvider;
    }
    if (trimmedModel.isEmpty) {
      nextModels.remove(cli.value);
    } else {
      nextModels[cli.value] = trimmedModel;
    }
    return withEffortForCli(cli, effort).copyWith(
      providerIdsByTool: nextProviders,
      modelsByTool: nextModels,
    );
  }

  TeamIdentity withEffortForCli(CliTool cli, String effort) {
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

  /// Default model id per CLI tool for team-level custom launch defaults.
  final Map<String, String> modelsByTool;

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

  /// Active preset id for this team. `null` means no preset is active.
  final String? activePresetId;

  @override
  IdentityKind get kind => IdentityKind.team;

  @override
  String get display => name;

  @override
  ProjectIconRef get icon => ProjectIconRef.auto;

  @override
  ConfigBundle get bundle => ConfigBundle(
        skillIds: skillIds,
        pluginIds: pluginIds,
        mcpServerIds: mcpServerIds,
      );

  bool get isValid => name.trim().isNotEmpty;

  TeamIdentity copyWith({
    String? id,
    String? name,
    String? description,
    String? extraArgs,
    List<TeamMemberConfig>? members,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    Map<String, String>? providerIdsByTool,
    Map<String, String>? modelsByTool,
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
    String? activePresetId,
    bool updateActivePresetId = false,
  }) {
    return TeamIdentity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      extraArgs: extraArgs ?? this.extraArgs,
      members: members ?? this.members,
      skillIds: skillIds ?? this.skillIds,
      pluginIds: pluginIds ?? this.pluginIds,
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      providerIdsByTool: providerIdsByTool ?? this.providerIdsByTool,
      modelsByTool: modelsByTool ?? this.modelsByTool,
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
      activePresetId: updateActivePresetId
          ? activePresetId
          : this.activePresetId,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.value,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      'extraArgs': extraArgs,
      'members': members.map((member) => member.toJson()).toList(),
      if (skillIds.isNotEmpty) 'skillIds': skillIds,
      if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
      if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      if (providerIdsByTool.isNotEmpty) 'providerIdsByTool': providerIdsByTool,
      if (modelsByTool.isNotEmpty) 'modelsByTool': modelsByTool,
      'cli': cli.value,
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
      if (activePresetId != null) 'activePresetId': activePresetId,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TeamIdentity &&
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
            mapEquals(modelsByTool, other.modelsByTool) &&
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
            forceWaitBeforeStop == other.forceWaitBeforeStop &&
            activePresetId == other.activePresetId;
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
    Object.hash(
      Object.hashAll(providerIdsByTool.entries),
      Object.hashAll(modelsByTool.entries),
    ),
    cli,
    teamMode,
    createdAt,
    sortOrder,
    loop,
    Object.hash(
      claudeTeammateMode,
      claudeEffortLevel,
      Object.hashAll(cliEffortLevels.entries),
      autoLaunchMembers,
      forceTeamLeadDelegateMode,
      forceWaitBeforeStop,
      activePresetId,
    ),
  );
}
