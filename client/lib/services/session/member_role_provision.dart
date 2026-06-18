import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import '../team/claude_team_roster_service.dart';
import '../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../io/filesystem.dart';

/// Provisions per-member role prompts and coordinator-style settings for Claude.
abstract final class MemberRoleProvision {
  MemberRoleProvision._();

  /// Passed to [LaunchCommandBuilder]; stripped before spawning the PTY.
  static const appendSystemPromptFileEnvKey =
      'TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE';

  static const rolePromptsDirName = 'prompts';
  static const rolePromptFileName = 'role.md';

  /// Denied for every Claude team member — roster is provisioned by TeamPilot.
  static const teamSessionDenyTools = <String>['TeamCreate', 'TeamDelete'];

  /// Auto-allowed in mixed mode so the teammate-bus MCP tools (list_teammates,
  /// send_message, wait_for_message, add_tasks, update_task, …) never prompt.
  /// `mcp__<server>` whitelists every tool exposed by that MCP server.
  static const mixedTeamSessionAllowTools = <String>[
    'mcp__$teammateBusMcpServerName',
  ];

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
2. **Assign** work via clear briefs; **SendMessage** teammates by **name** (e.g. `researcher`, `implementer`) — each teammate is a live agent with its own terminal that runs the hands-on work for you
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

## Execution model
Every teammate is a **separate live agent with its own terminal**, already running and idling in `wait_for_message` until you hand it work. You drive all execution by routing tasks to them — `send_message` for targeted work, `add_tasks` for the shared pull queue — then synthesize what they return. Your own tools are for **reading and coordinating**: use `Read`/`Glob`/`Grep` to inspect the repo, and the bus tools to assign and collect. The hands-on Bash/Edit/Write runs in the teammates' terminals, so a brief handed to the right teammate is how anything gets done.

## Coordination loop (mandatory)
0. `list_teammates()` — roster + live unread counts
1. `read_messages(after_id?, limit?, unread_only?, mark_read?)` — page persisted mail (default unread)
2. `send_message(to, content)` — assign / reply to teammates by **member id** (or `"*"` broadcast)
3. **`wait_for_message()`** — blocks **indefinitely** until **teammate mail or the human operator's next instruction** arrives (shown as `FROM user (operator):`)
4. Handle the batch, then go back to step 3. **Always** return to `wait_for_message` after handling.

## Shared work queue (preferred for parallel work)
For batches of comparable tasks, prefer the **pull queue** over manual `send_message` assignment — idle workers self-balance:
- `add_tasks([{title, brief, depends_on?}])` — enqueue work; workers pull it automatically
- `list_tasks(status?)` — board view (pending | claimed | done | failed | cancelled)
Workers receive a queued task directly from their own `wait_for_message` (it is auto-claimed for them), execute it, then `update_task`. You never claim tasks yourself. Use `send_message` for targeted coordination/replies; use the queue for distributable work.

While you are inside `wait_for_message`, the human types in TeamPilot — that text is **not** raw stdin; it arrives in your next batch as `FROM user (operator):`. After every turn, call `wait_for_message` immediately. The bus doorbell (injected notice) appears only when you have **unread teammate mail**.

**Idle notifications:** when a worker finishes a turn, the bus auto-delivers `IDLE NOTIFICATION from <member>` to your mailbox (Claude-style). Treat as "teammate is available" — assign with `send_message` or pull via `wait_for_message` / `read_messages`. Use explicit `send_message` from workers for task **results**, not only idle pings.
''';

  /// Appended to mixed-mode **worker** [role.md] (bus coordination via MCP).
  static const mixedTeammateRoleAddendum = '''
# Multi-agent teammate (cross-CLI bus)
You coordinate with teammates ONLY through the teammate-bus MCP tools:
- `list_teammates()` — roster + live unread counts
- `read_messages(...)` — page unread/history mail without blocking
- `send_message(to, content)` — message a teammate by member id (or `"*"` broadcast)
- **`wait_for_message()`** — your single idle loop; see below
- `update_task(task_id, status, result?)` — report a task you were handed as `done` / `failed`
- **Never stand down** — no `finish_task` / `leave`; stay in the loop until the human closes the session

## Your idle loop (one tool)
`wait_for_message()` is the **only** thing you call when you have nothing in hand. It blocks until there is something to do, then returns ONE of:
1. **An ASSIGNED TASK** — already claimed for you from the shared queue. Do it, then `update_task(task_id, status, result?)` with `done` / `failed`.
2. **Messages** — teammate mail or `FROM user (operator):` input. Handle them.
Either way, call `wait_for_message()` again afterwards. You never poll or claim manually — the bus hands you the next task or message the instant one is available.
''';

  /// Mixed-mode addendum for **push-delivery** CLIs (e.g. cursor) whose MCP tool
  /// calls can't block long (~60s agent cap, not configurable). They never call
  /// `wait_for_message`; the bus injects a doorbell notice into their terminal
  /// when mail arrives, and they pull it with the non-blocking `read_messages`.
  static const mixedTeammatePushRoleAddendum = '''
# Multi-agent teammate (cross-CLI bus, push delivery)
You coordinate with teammates through the teammate-bus MCP tools:
- `list_teammates()` — roster + live unread counts
- `read_messages(mark_read: true)` — read AND consume your unread mail (returns immediately)
- `send_message(to, content)` — message a teammate by member id (or `"*"` broadcast)
- `update_task(task_id, status, result?)` — report a handed task as `done` / `failed`

## Your idle model — DO NOT call wait_for_message
Your CLI cannot block inside a tool call, so **never call `wait_for_message`** — it would time out. Instead:
1. Do the work in front of you. When you have nothing in hand, **just stop** — end your turn normally.
2. The bus watches your mailbox. When teammate mail or `FROM user (operator):` input arrives, it **injects a notice into your terminal** telling you to read.
3. On that notice, call `read_messages(mark_read: true)`, handle the batch (do the task, reply via `send_message`, report via `update_task`), then stop again.
You are event-driven: spend no turns polling. Stopping when idle is correct and expected — the bus wakes you.
''';

  /// When [TeamIdentity.forceTeamLeadDelegateMode] is on (also enforced via PreToolUse hook).
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

  /// Composes the user-authored role body — the two layers a roster member owns:
  /// `# Responsibilities` (member.prompt, WHAT the role is) and `# Working method`
  /// (member.playbook, HOW it operates). No mode addenda. Used standalone for the
  /// native Claude roster entry and as the base of [composeRolePrompt].
  /// Returns the empty string when both layers are empty.
  static String composeMemberRoleBody(TeamMemberConfig member) {
    final responsibilities = member.prompt.trim();
    final method = member.playbook.trim();
    final body = StringBuffer();
    if (responsibilities.isNotEmpty) {
      body.writeln('# Responsibilities');
      body.writeln(responsibilities);
      body.writeln();
    }
    if (method.isNotEmpty) {
      body.writeln('# Working method');
      body.writeln(method);
      body.writeln();
    }
    return body.toString();
  }

  /// Composes the full role-prompt body ([composeMemberRoleBody] + mode addenda)
  /// for any CLI. Transport-agnostic: Claude/flashskyai write it to `role.md`
  /// (fed via `--append-system-prompt-file`), codex writes it to
  /// `$CODEX_HOME/AGENTS.md`. Returns the empty string when there is nothing to
  /// inject.
  static String composeRolePrompt({
    required TeamMemberConfig member,
    bool forceTeamLeadDelegateMode = false,
    bool mixed = false,
    bool pushDelivery = false,
  }) {
    final isLead = TeamMemberNaming.isTeamLead(member);
    final body = StringBuffer();
    final roleBody = composeMemberRoleBody(member);
    if (roleBody.isNotEmpty) {
      body.write(roleBody);
    }
    if (isLead && !mixed) {
      body.writeln(teamLeadRoleAddendum.trim());
      body.writeln();
      if (forceTeamLeadDelegateMode) {
        body.writeln(teamLeadDelegateModeAddendum.trim());
        body.writeln();
      }
    }
    if (mixed && pushDelivery) {
      // push-投递 CLI（cursor）即使是 lead 也不能阻塞在 wait_for_message → 一律
      // 用事件驱动的 push 变体（门铃 + read_messages）。
      body.writeln(mixedTeammatePushRoleAddendum.trim());
      body.writeln();
    } else if (isLead && mixed) {
      body.writeln(mixedTeamLeadRoleAddendum.trim());
      body.writeln();
    } else if (mixed) {
      body.writeln(mixedTeammateRoleAddendum.trim());
      body.writeln();
    }
    return body.toString();
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
    final hasRoleBody = composeMemberRoleBody(member).isNotEmpty;
    final stat = await fs.stat(path);
    final isLead = TeamMemberNaming.isTeamLead(member);
    if (!hasRoleBody && !isLead && !mixed) {
      if (stat.exists) {
        await fs.removeRecursive(path);
      }
      return null;
    }
    await fs.ensureDir(p.dirname(path));
    final body = composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
    );
    await fs.atomicWrite(path, body);
    return path;
  }

  /// Merges deny rules for Claude team sessions (lead and teammates). In mixed
  /// mode also pre-allows the teammate-bus MCP tools so they never prompt.
  static Map<String, Object?> applyTeamSessionPolicy(
    Map<String, Object?> settings, {
    bool mixed = false,
  }) {
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
    if (mixed) {
      final existingAllow = <String>[
        for (final entry in (permissions['allow'] as List?) ?? const [])
          if (entry is String) entry,
      ];
      permissions['allow'] = <String>{
        ...existingAllow,
        ...mixedTeamSessionAllowTools,
      }.toList(growable: false);
    }
    merged['permissions'] = permissions;
    return merged;
  }
}
