import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import '../io/filesystem.dart';

/// Merges TeamPilot member rows into Claude `teams/<name>/config.json`.
class ClaudeTeamRosterService {
  const ClaudeTeamRosterService({required this.fs});

  final Filesystem fs;

  /// Matches Claude Code `sanitizeName` (`teamHelpers.ts`).
  static String safeClaudePathSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();
    return safe.isEmpty ? 'default' : safe;
  }

  static String resolveWorkingDirectory({
    required String workingDirectory,
    required String fallback,
  }) {
    final wd = workingDirectory.trim();
    if (wd.isNotEmpty) return wd;
    return fallback.trim();
  }

  /// Builds merged roster JSON; preserves disk fields when [existing] is set.
  Map<String, Object?> mergeConfig({
    required String cliTeamName,
    required List<TeamMemberConfig> members,
    required String cwd,
    required String teammateMode,
    String description = '',
    String? leadSessionId,
    Map<String, Object?>? existing,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prior = existing ?? const <String, Object?>{};
    final createdAt = (prior['createdAt'] as num?)?.toInt() ?? now;

    final leadAgentId = TeamMemberNaming.leadAgentId(cliTeamName);

    final priorLeadSession = prior['leadSessionId']?.toString().trim() ?? '';
    final nextLeadSession = leadSessionId?.trim() ?? '';
    final resolvedLeadSession = nextLeadSession.isNotEmpty
        ? nextLeadSession
        : priorLeadSession;

    final memberRows = _mergeMemberRows(
      cliTeamName: cliTeamName,
      members: members,
      cwd: cwd,
      teammateMode: teammateMode,
      existingMembers: _readMemberList(prior['members']),
    );

    final config = <String, Object?>{
      'name': cliTeamName,
      'createdAt': createdAt,
      'leadAgentId': leadAgentId,
      'members': memberRows,
    };

    final desc = description.trim().isNotEmpty
        ? description.trim()
        : (prior['description'] as String?)?.trim() ?? '';
    if (desc.isNotEmpty) {
      config['description'] = desc;
    }
    if (resolvedLeadSession.isNotEmpty) {
      config['leadSessionId'] = resolvedLeadSession;
    }

    return config;
  }

  Map<String, Object?> buildMemberEntry({
    required TeamMemberConfig member,
    required String cliTeamName,
    required String cwd,
    required String teammateMode,
  }) {
    final rosterName = member.id;
    final agentId = rosterName == TeamMemberNaming.teamLeadName
        ? TeamMemberNaming.leadAgentId(cliTeamName)
        : TeamMemberNaming.formatAgentId(rosterName, cliTeamName);
    final joinedAt = member.joinedAt > 0
        ? member.joinedAt
        : DateTime.now().millisecondsSinceEpoch;
    final inProcess = teammateMode == 'in-process';

    final entry = <String, Object?>{
      'agentId': agentId,
      'name': rosterName,
      'joinedAt': joinedAt,
      'tmuxPaneId': rosterName == TeamMemberNaming.teamLeadName
          ? ''
          : (inProcess ? 'in-process' : ''),
      'cwd': cwd,
      'subscriptions': <Object?>[],
      // Omit isActive here — Claude sets true/false per turn; default is idle.
      'agentType': TeamMemberNaming.resolveAgentType(
        memberId: rosterName,
        agent: member.agent,
        agentType: member.agentType,
      ),
    };

    if (!inProcess && rosterName != TeamMemberNaming.teamLeadName) {
      entry['backendType'] = teammateMode;
    } else if (rosterName != TeamMemberNaming.teamLeadName) {
      entry['backendType'] = 'in-process';
    }

    final prompt = member.prompt.trim();
    if (prompt.isNotEmpty) {
      entry['prompt'] = prompt;
    }

    final model = member.model.trim();
    if (model.isNotEmpty) {
      entry['model'] = model;
    }

    return entry;
  }

  Future<void> ensureInboxes({
    required String rosterDir,
    required List<TeamMemberConfig> members,
  }) async {
    final inboxDir = fs.pathContext.join(rosterDir, 'inboxes');
    await fs.ensureDir(inboxDir);
    for (final member in members.where((m) => m.isValid)) {
      final file = fs.pathContext.join(
        inboxDir,
        '${safeClaudePathSegment(member.id)}.json',
      );
      final stat = await fs.stat(file);
      if (stat.exists) continue;
      await fs.atomicWrite(file, '[]');
    }
  }

  List<Map<String, Object?>> _mergeMemberRows({
    required String cliTeamName,
    required List<TeamMemberConfig> members,
    required String cwd,
    required String teammateMode,
    required List<Map<String, Object?>> existingMembers,
  }) {
    final valid = members.where((m) => m.isValid).toList();
    final hasLead = valid.any(TeamMemberNaming.isTeamLead);
    final effective = hasLead
        ? valid
        : [
            const TeamMemberConfig(
              id: TeamMemberNaming.teamLeadName,
              name: TeamMemberNaming.teamLeadName,
            ),
            ...valid,
          ];

    final byAgentId = <String, Map<String, Object?>>{};
    for (final row in existingMembers) {
      final id = row['agentId']?.toString() ?? '';
      if (id.isNotEmpty) byAgentId[id] = row;
    }

    final merged = <Map<String, Object?>>[];
    for (final member in effective) {
      final entry = buildMemberEntry(
        member: member,
        cliTeamName: cliTeamName,
        cwd: cwd,
        teammateMode: teammateMode,
      );
      final agentId = entry['agentId'] as String;
      final prior = byAgentId[agentId];
      if (prior != null) {
        final joinedAt = (prior['joinedAt'] as num?)?.toInt();
        if (joinedAt != null && joinedAt > 0) {
          entry['joinedAt'] = joinedAt;
        }
        if (prior.containsKey('isActive')) {
          entry['isActive'] = prior['isActive'];
        }
      }
      merged.add(entry);
      byAgentId.remove(agentId);
    }

    return merged;
  }

  static List<Map<String, Object?>> _readMemberList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          Map<String, Object?>.from(
            item.map((k, v) => MapEntry(k.toString(), v)),
          ),
    ];
  }
}
