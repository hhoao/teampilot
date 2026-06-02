import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import '../team/claude_team_roster_service.dart';
import '../io/filesystem.dart';

/// Provisions per-member role prompts and coordinator-style settings for Claude.
abstract final class MemberRoleProvision {
  MemberRoleProvision._();

  /// Passed to [LaunchCommandBuilder]; stripped before spawning the PTY.
  static const appendSystemPromptFileEnvKey =
      'TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE';

  /// Back-compat alias (Claude + FlashskyAI).
  static const claudeAppendSystemPromptFileEnvKey = appendSystemPromptFileEnvKey;

  static const rolePromptsDirName = 'prompts';
  static const rolePromptFileName = 'role.md';

  /// Denied for every Claude team member — roster is provisioned by TeamPilot.
  static const teamSessionDenyTools = <String>['TeamCreate', 'TeamDelete'];

  /// Appended to every team-lead [role.md] (identity and team layout).
  static const teamLeadRoleAddendum = '''
# Team Leader (Swarm)
You are the **team lead** (display name: `team-lead`). You run in the leader session; teammates are separate agents sharing the same task list and team config.

## Identity
- **Role**: Team Leader — orchestration, synthesis, user-facing communication
- **Not a teammate**: you do not claim tasks meant for workers unless no teammate is available
- Teammates report to you; the user primarily interacts with you

## Core duties
1. **Decompose** the user's request into tasks on the shared task list (create, prioritize, unblock)
2. **Assign** work via clear briefs; **SendMessage** teammates by **name** (e.g. `researcher`, `implementer`) — do not use `Agent` (subagents are not teammate tabs)
3. **Coordinate** parallel research; serialize edits to the same paths
4. **Synthesize** teammate results into one coherent reply—include file paths, decisions, and next steps
5. **Govern** permissions: approve/deny teammate tool, sandbox, and plan requests promptly
6. **Integrate** idle notifications and mailbox messages; do not treat them as user chat
7. **Communicate** with teammates via SendMessage; normal text is invisible to other members

''';

  /// Appended to mixed-mode **team lead** [role.md] (orchestration + never stand down).
  static const mixedTeamLeadRoleAddendum = '''
# Team leader (mixed cross-CLI bus)
You orchestrate teammates via teammate-bus MCP. **Never stand down** — there is no `finish_task` or `leave`; the session ends only when the human closes it.

## Coordination loop (mandatory)
0. `list_teammates()` — roster: member ids, roles, CLI, bus state, unread counts
1. `send_message(to, content)` — assign / reply to teammates by **member id** (or `"*"` broadcast)
2. **`wait_for_message()`** — blocks **indefinitely** until **teammate mail or the human operator's next instruction** arrives (shown as `FROM user (operator):`)
3. Handle the batch, then go back to step 2. **Always** return to `wait_for_message` after handling.

While you are inside `wait_for_message`, the human types in TeamPilot — that text is **not** raw stdin; it arrives in your next batch as `FROM user (operator):`. After every turn, call `wait_for_message` immediately. Stop-hook / bus stdin nudges mean: call `wait_for_message` now.
''';

  /// Appended to mixed-mode **worker** [role.md] (bus coordination via MCP).
  static const mixedTeammateRoleAddendum = '''
# Multi-agent teammate (cross-CLI bus)
You coordinate with teammates ONLY through the teammate-bus MCP tools:
- `list_teammates()` — roster: member ids, roles, CLI, bus state, unread counts
- `send_message(to, content)` — message a teammate by member id (or `"*"` broadcast)
- **`wait_for_message()`** — blocks **indefinitely** until teammate mail or `FROM user (operator):` arrives; after handling, **always** call it again
- **Never stand down** — no `finish_task` / `leave`; stay in the loop until the human closes the session

Stop-hook / bus stdin nudges mean: call `wait_for_message` now.
''';

  /// When [TeamConfig.forceTeamLeadDelegateMode] is on (also enforced via PreToolUse hook).
  static const teamLeadDelegateModeAddendum = '''
## Delegate-only mode (enforced)

This tab is **plan-and-assign only**: Bash, PowerShell, Edit, Write, NotebookEdit, Skill, ExecuteExtraTool, REPL, workflow, EnterWorktree, ExitWorktree, RemoteTrigger, CronCreate, and Agent are blocked here. Use Read/Glob/Grep to inspect the repo; use SendMessage and the task list (TaskCreate/TaskUpdate) so teammate tabs execute local work.

''';

  static String memberSlug(TeamMemberConfig member) {
    return ClaudeTeamRosterService.safeClaudePathSegment(member.id);
  }

  static String rolePromptPath(String memberToolDir, TeamMemberConfig member) {
    return p.join(
      memberToolDir,
      rolePromptsDirName,
      memberSlug(member),
      rolePromptFileName,
    );
  }

  /// Writes [member.prompt] under `{toolDir}/prompts/<slug>/role.md`.
  /// Removes the file when prompt is empty. Returns the path when non-empty.
  static Future<String?> syncRolePromptFile({
    required Filesystem fs,
    required String memberToolDir,
    required TeamMemberConfig member,
    bool forceTeamLeadDelegateMode = false,
    bool mixed = false,
  }) async {
    final path = rolePromptPath(memberToolDir, member);
    final text = member.prompt.trim();
    final stat = await fs.stat(path);
    final isLead = TeamMemberNaming.isTeamLead(member);
    if (text.isEmpty && !isLead && !mixed) {
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
    if (isLead && !mixed) {
      body.writeln(teamLeadRoleAddendum.trim());
      body.writeln();
      if (forceTeamLeadDelegateMode) {
        body.writeln(teamLeadDelegateModeAddendum.trim());
        body.writeln();
      }
    }
    if (isLead && mixed) {
      body.writeln(mixedTeamLeadRoleAddendum.trim());
      body.writeln();
    } else if (mixed) {
      body.writeln(mixedTeammateRoleAddendum.trim());
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
