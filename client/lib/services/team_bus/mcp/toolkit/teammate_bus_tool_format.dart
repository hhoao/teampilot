import '../../idle_notification.dart';
import '../../persistence/bus_message_page.dart';
import '../../tasks/task_router.dart';
import '../../tasks/team_task.dart';
import '../../team_bus.dart';
import '../../team_message.dart';
import '../../teammate_snapshot.dart';

/// Text encoders shared by teammate-bus MCP tool handlers.
abstract final class TeammateBusToolFormat {
  static String encodeTasks(
    TeamBus bus,
    List<TeamTask> tasks,
    String memberId,
  ) {
    if (tasks.isEmpty) return 'No tasks on the queue.';
    final caps = bus.capabilitiesOf(memberId);
    final buffer = StringBuffer('Work queue (${tasks.length}):\n\n');
    buffer.write(tasks
        .map((t) => formatTask(t, memberId: memberId, memberCaps: caps))
        .join('\n\n'));
    return buffer.toString().trimRight();
  }

  static String encodeTaskAssignment(TeamTask task) {
    return 'ASSIGNED TASK (claimed for you from the shared work queue):\n'
        '${formatTask(task, full: true)}\n\n'
        'Do this task now. When finished, call '
        'update_task(task_id: "${task.id}", status: "done" | "failed", result?), '
        'then call wait_for_message again.';
  }

  static String formatTask(
    TeamTask task, {
    bool full = false,
    String? memberId,
    Set<String>? memberCaps,
  }) {
    final lines = <String>[
      '--- ${task.id} [${task.status.name}] ---',
      'title: ${task.title}',
      if (task.assignee != null) 'assignee: ${task.assignee}',
      if (task.dependsOn.isNotEmpty) 'depends_on: ${task.dependsOn.join(', ')}',
      if (task.requiredCapabilities.isNotEmpty)
        'required_capabilities: ${task.requiredCapabilities.join(', ')}',
      if (memberId != null && memberCaps != null) ...[
        'eligible_for_you: ${TaskRouter.eligible(memberId, memberCaps, task)}',
        'match_score: ${TaskRouter.score(memberCaps, task)}',
      ],
      if (task.result != null && task.result!.isNotEmpty)
        'result: ${task.result}',
      if (full) 'brief:\n${task.brief}',
    ];
    return lines.join('\n');
  }

  static String unknownRecipientHint(TeamBus bus) {
    final roster = bus.rosterSnapshot().members;
    if (roster.isEmpty) return '';
    final lines = <String>[' Known recipients:'];
    for (final teammate in roster) {
      final profile = teammate.profile;
      final alias = profile.agentId.trim();
      if (alias.isNotEmpty && alias != profile.memberId) {
        lines.add('- ${profile.memberId} (agentId: $alias)');
      } else {
        lines.add('- ${profile.memberId}');
      }
    }
    return lines.join('\n');
  }

  static String encodeRoster(TeamBus bus, String callerMemberId) {
    final snapshot = bus.rosterSnapshot();
    if (snapshot.members.isEmpty) {
      return 'No teammates registered on the bus.';
    }
    final buffer = StringBuffer();
    final team = snapshot.team;
    if (team != null) {
      buffer.writeln('=== Team: ${team.teamName} (${team.cliTeamName}) ===');
      if (team.description.trim().isNotEmpty) {
        buffer.writeln('description: ${team.description.trim()}');
      }
      buffer.writeln('team_id: ${team.teamId}');
      buffer.writeln('team_mode: ${team.teamMode}');
      buffer.writeln('lead_agent_id: ${team.leadAgentId}');
      buffer.writeln('app_session_id: ${team.appSessionId}');
      buffer.writeln('cwd: ${team.workingDirectory}');
      if (team.additionalPaths.isNotEmpty) {
        buffer.writeln('additional_paths: ${team.additionalPaths.join(', ')}');
      }
      buffer.writeln('');
    }
    buffer.writeln(
      'Roster (${snapshot.members.length} members). You (caller): $callerMemberId',
    );
    buffer.writeln('');
    for (final teammate in snapshot.members) {
      buffer.writeln(formatTeammate(teammate, callerMemberId == teammate.memberId));
      buffer.writeln('');
    }
    return buffer.toString().trimRight();
  }

  static String formatTeammate(TeammateSnapshot teammate, bool isSelf) {
    final profile = teammate.profile;
    final role = profile.isTeamLead ? 'leader' : 'worker';
    final lines = <String>[
      '--- ${profile.memberId}${isSelf ? ' (self)' : ''} ---',
      'name: ${profile.memberId}',
      'display_name: ${profile.effectiveDisplayName}',
      'agentId: ${profile.agentId.isEmpty ? profile.memberId : profile.agentId}',
      'agentType: ${profile.agentType.isEmpty ? profile.memberId : profile.agentType}',
      'role: $role',
      if (profile.agent.isNotEmpty) 'agent: ${profile.agent}',
      if (profile.model.isNotEmpty) 'model: ${profile.model}',
      if (profile.provider.isNotEmpty) 'provider: ${profile.provider}',
      'cli: ${profile.cli.isEmpty ? '?' : profile.cli}',
      'backendType: ${profile.backendType.isEmpty ? profile.cli : profile.backendType}',
      if (profile.taskId.isNotEmpty) 'taskId: ${profile.taskId}',
      if (profile.cwd.isNotEmpty) 'cwd: ${profile.cwd}',
      if (profile.joinedAt > 0) 'joinedAt: ${profile.joinedAt}',
      if (profile.extraArgs.isNotEmpty) 'extraArgs: ${profile.extraArgs}',
      'dangerouslySkipPermissions: ${profile.dangerouslySkipPermissions}',
      'prompt: ${profile.promptSummary()}',
      'bus.lifecycle: ${teammate.lifecycle.name}',
      'bus.activity: ${teammate.activity.name}',
      'bus.phase: ${teammate.busPhaseLabel}',
      if (teammate.claudeIsActive != null)
        'claude.isActive: ${teammate.claudeIsActive}',
      'bus.unread: ${teammate.unreadCount}',
      'pty.running: ${teammate.ptyRunning}',
    ];
    return lines.join('\n');
  }

  static String encodeMessagePage(BusMessagePage page) {
    if (page.messages.isEmpty) {
      return 'No messages (total_unread=${page.totalUnread}).';
    }
    final buffer = StringBuffer(
      'Messages (${page.messages.length}, total_unread=${page.totalUnread}, '
      'has_more=${page.hasMore}',
    );
    if (page.nextAfterId != null) {
      buffer.write(', next_after_id=${page.nextAfterId}');
    }
    buffer.writeln('):');
    buffer.writeln();
    buffer.write(page.messages.map(formatMessage).join('\n\n---\n\n'));
    return buffer.toString().trimRight();
  }

  static String encodeBatch(List<TeamMessage> batch) {
    if (batch.isEmpty) {
      return 'EMPTY: no messages (unexpected — wait_for_message should block until mail arrives).';
    }
    return batch.map(formatMessage).join('\n\n---\n\n');
  }

  static String formatMessage(TeamMessage message) {
    if (message.from == TeamBus.userSenderId) {
      return 'FROM user (operator):\n${message.content}';
    }
    final idle = IdleNotification.parseTeamMessageContent(message.content);
    if (idle != null) {
      return 'FROM ${message.from}:\n${idle.formatForLeader()}';
    }
    return 'FROM ${message.from}:\n${message.content}';
  }
}
