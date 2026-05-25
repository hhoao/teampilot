import 'package:path/path.dart' as p;

import '../models/team_config.dart';
import '../utils/team_member_naming.dart';
import 'claude_team_roster_service.dart';
import 'io/filesystem.dart';

/// Provisions per-member role prompts and coordinator-style settings for Claude.
abstract final class MemberRoleProvision {
  MemberRoleProvision._();

  /// Passed to [LaunchCommandBuilder]; stripped before spawning the PTY.
  static const claudeAppendSystemPromptFileEnvKey =
      'TEAMPILOT_CLAUDE_APPEND_SYSTEM_PROMPT_FILE';

  static const rolePromptsDirName = 'prompts';
  static const rolePromptFileName = 'role.md';

  /// Denied for every Claude team member — roster is provisioned by TeamPilot.
  static const teamSessionDenyTools = <String>['TeamCreate'];

  /// Appended to every team-lead role prompt file (prevents self-messaging loops).
  static const teamLeadAntiSelfLoopAddendum = '''
## Do not message or task yourself

You are the team lead in this terminal. The user talks to you here — reply in the conversation; do not SendMessage to "team-lead" or to your own name.

- Never `SendMessage` with `to: "team-lead"` (or `to: "*"` unless truly needed).
- Never `TaskUpdate` with `owner: "team-lead"` — assign tasks to other member names only.
- Never `Agent` with `name: "team-lead"` — spawn other teammates (developer, reviewer, …) or omit `name` for a one-off subagent, not a second lead.
- Read `~/.claude/teams/<team>/config.json` for teammate names; only message names listed there except team-lead.
''';

  static String memberSlug(TeamMemberConfig member) {
    final name = member.name.trim();
    if (name == TeamMemberNaming.teamLeadName) {
      return TeamMemberNaming.teamLeadName;
    }
    return ClaudeTeamRosterService.safeClaudePathSegment(
      TeamMemberNaming.slugMemberName(name),
    );
  }

  static String rolePromptPath(String memberClaudeToolDir, TeamMemberConfig member) {
    return p.join(
      memberClaudeToolDir,
      rolePromptsDirName,
      memberSlug(member),
      rolePromptFileName,
    );
  }

  /// Writes [member.prompt] under `{toolDir}/prompts/<slug>/role.md`.
  /// Removes the file when prompt is empty. Returns the path when non-empty.
  static Future<String?> syncRolePromptFile({
    required Filesystem fs,
    required String memberClaudeToolDir,
    required TeamMemberConfig member,
  }) async {
    final path = rolePromptPath(memberClaudeToolDir, member);
    final text = member.prompt.trim();
    final stat = await fs.stat(path);
    final isLead = member.name.trim() == TeamMemberNaming.teamLeadName;
    if (text.isEmpty && !isLead) {
      if (stat.exists) {
        await fs.removeRecursive(path);
      }
      return null;
    }
    await fs.ensureDir(p.dirname(path));
    final body = StringBuffer();
    if (text.isNotEmpty) {
      body.writeln(text);
      body.writeln();
    }
    if (isLead) {
      body.writeln(teamLeadAntiSelfLoopAddendum.trim());
      body.writeln();
    }
    await fs.atomicWrite(path, body.toString());
    return path;
  }

  /// Merges deny rules for Claude team sessions (lead and teammates).
  static Map<String, Object?> applyTeamSessionPolicy(
    Map<String, Object?> settings,
  ) {
    final merged = Map<String, Object?>.from(settings);
    final permissions = Map<String, Object?>.from(
      (merged['permissions'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existingDeny = <String>[
      for (final entry in (permissions['deny'] as List?) ?? const [])
        if (entry is String) entry,
    ];
    final deny = <String>{
      ...existingDeny,
      ...teamSessionDenyTools,
    }.toList(growable: false);
    permissions['deny'] = deny;
    merged['permissions'] = permissions;
    return merged;
  }
}
