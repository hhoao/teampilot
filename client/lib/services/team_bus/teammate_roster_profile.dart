import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

/// 成员静态配置（对齐 Claude `teams/<name>/config.json` member 行 + TeamPilot 字段）。
class TeammateRosterProfile {
  const TeammateRosterProfile({
    required this.memberId,
    this.displayName = '',
    this.agentId = '',
    this.agentType = '',
    this.agent = '',
    this.model = '',
    this.provider = '',
    this.cli = '',
    this.extraArgs = '',
    this.prompt = '',
    this.joinedAt = 0,
    this.isTeamLead = false,
    this.dangerouslySkipPermissions = false,
    this.taskId = '',
    this.cwd = '',
    this.backendType = '',
    this.capabilities = const {},
  });

  /// 测试 / 最小节点（仅 member id）。
  factory TeammateRosterProfile.minimal(
    String memberId, {
    String? displayName,
    String? cli,
    bool isTeamLead = false,
    Set<String> capabilities = const {},
  }) {
    return TeammateRosterProfile(
      memberId: memberId,
      displayName: displayName ?? memberId,
      cli: cli ?? '',
      isTeamLead: isTeamLead || TeamMemberNaming.isTeamLeadName(memberId),
      agentId: memberId,
      agentType: TeamMemberNaming.isTeamLeadName(memberId)
          ? TeamMemberNaming.teamLeadName
          : memberId,
      capabilities: {memberId, ...capabilities},
    );
  }

  factory TeammateRosterProfile.fromMember({
    required TeamMemberConfig member,
    required TeamProfile team,
    required String cliTeamName,
    required String cwd,
    String? taskId,
  }) {
    final rosterName = member.id;
    final isLead = TeamMemberNaming.isTeamLead(member);
    final agentId = isLead
        ? TeamMemberNaming.leadAgentId(cliTeamName)
        : TeamMemberNaming.formatAgentId(rosterName, cliTeamName);
    final joinedAt = member.joinedAt > 0
        ? member.joinedAt
        : DateTime.now().millisecondsSinceEpoch;
    final cli = member.cliWithin(team);
    final caps = <String>{rosterName, ...member.capabilities};
    return TeammateRosterProfile(
      memberId: rosterName,
      displayName: member.name,
      agentId: agentId,
      agentType: TeamMemberNaming.resolveAgentType(
        memberId: rosterName,
        agent: member.agent,
        agentType: member.agentType,
      ),
      agent: member.agent.trim(),
      model: member.model.trim(),
      provider: member.provider.trim(),
      cli: cli.value,
      extraArgs: member.extraArgs.trim(),
      prompt: member.prompt.trim(),
      joinedAt: joinedAt,
      isTeamLead: isLead,
      dangerouslySkipPermissions: member.dangerouslySkipPermissions,
      taskId: taskId?.trim() ?? '',
      cwd: cwd.trim(),
      backendType: cli.value,
      capabilities: caps,
    );
  }

  final String memberId;
  final String displayName;
  final String agentId;
  final String agentType;
  final String agent;
  final String model;
  final String provider;
  final String cli;
  final String extraArgs;
  final String prompt;
  final int joinedAt;
  final bool isTeamLead;
  final bool dangerouslySkipPermissions;
  final String taskId;
  final String cwd;
  final String backendType;

  /// Capability tags for TeamBus task routing. Derived from [TeamMemberConfig].
  final Set<String> capabilities;

  String get effectiveDisplayName {
    final name = displayName.trim();
    return name.isEmpty ? memberId : name;
  }

  String promptSummary({int excerptChars = 160}) {
    final text = prompt.trim();
    if (text.isEmpty) return '(none)';
    if (text.length <= excerptChars) return text;
    return '${text.substring(0, excerptChars)}… (${text.length} chars total)';
  }
}

/// Session 级团队上下文（对齐 Claude TeamFile 头 + TeamPilot session）。
class TeamSessionContext {
  const TeamSessionContext({
    required this.cliTeamName,
    required this.teamId,
    required this.teamName,
    this.description = '',
    this.workingDirectory = '',
    this.teamMode = 'mixed',
    this.leadAgentId = '',
    this.appSessionId = '',
    this.additionalPaths = const [],
  });

  final String cliTeamName;
  final String teamId;
  final String teamName;
  final String description;
  final String workingDirectory;
  final String teamMode;
  final String leadAgentId;
  final String appSessionId;
  final List<String> additionalPaths;
}
