import 'dart:convert';

import '../../idle_notification.dart';
import '../../persistence/bus_message_page.dart';
import '../../tasks/task_router.dart';
import '../../tasks/team_task.dart';
import '../../team_bus.dart';
import '../../team_message.dart';
import '../../teammate_roster_profile.dart';
import '../../teammate_snapshot.dart';

/// JSON encoders shared by teammate-bus MCP tool handlers.
abstract final class TeammateBusToolFormat {
  static String _encode(Object? value) => jsonEncode(value);

  static Map<String, Object?> _omitEmpty(Map<String, Object?> map) {
    return {
      for (final e in map.entries)
        if (e.value != null &&
            e.value != '' &&
            !(e.value is List && (e.value as List).isEmpty) &&
            !(e.value is Map && (e.value as Map).isEmpty))
          e.key: e.value!,
    };
  }

  static String encodeTasks(
    TeamBus bus,
    List<TeamTask> tasks,
    String memberId,
  ) {
    final caps = bus.capabilitiesOf(memberId);
    return _encode({
      'tasks': [
        for (final t in tasks)
          taskMap(t, memberId: memberId, memberCaps: caps),
      ],
    });
  }

  static String encodeTaskAssignment(TeamTask task) {
    return _encode(taskMap(task, full: true));
  }

  static Map<String, Object?> taskMap(
    TeamTask task, {
    bool full = false,
    String? memberId,
    Set<String>? memberCaps,
  }) {
    return _omitEmpty({
      'id': task.id,
      'status': task.status.name,
      'title': task.title,
      'assignee': task.assignee,
      'depends_on': task.dependsOn.isEmpty ? null : List<String>.from(task.dependsOn),
      'required_capabilities': task.requiredCapabilities.isEmpty
          ? null
          : task.requiredCapabilities.toList(),
      if (memberId != null && memberCaps != null) ...{
        'eligible_for_you': TaskRouter.eligible(memberId, memberCaps, task),
        'match_score': TaskRouter.score(memberCaps, task),
      },
      'result': (task.result != null && task.result!.isNotEmpty)
          ? task.result
          : null,
      'brief': full ? task.brief : null,
    });
  }

  /// Kept for call sites that previously used [formatTask] as a string builder.
  static String formatTask(
    TeamTask task, {
    bool full = false,
    String? memberId,
    Set<String>? memberCaps,
  }) =>
      _encode(
        taskMap(
          task,
          full: full,
          memberId: memberId,
          memberCaps: memberCaps,
        ),
      );

  static String unknownRecipientHint(TeamBus bus) {
    final roster = bus.rosterSnapshot().members;
    return _encode({
      'known_recipients': [
        for (final teammate in roster) _recipientMap(teammate.profile),
      ],
    });
  }

  static Map<String, Object?> _recipientMap(TeammateRosterProfile profile) {
    final alias = profile.agentId.trim();
    return _omitEmpty({
      'member_id': profile.memberId,
      'agent_id': (alias.isEmpty || alias == profile.memberId) ? null : alias,
    });
  }

  static String encodeRoster(TeamBus bus, String callerMemberId) {
    final snapshot = bus.rosterSnapshot();
    final team = snapshot.team;
    return _encode({
      'caller': callerMemberId,
      if (team != null)
        'team': _omitEmpty({
          'team_id': team.teamId,
          'team_name': team.teamName,
          'cli_team_name': team.cliTeamName,
          'team_mode': team.teamMode,
          'lead_agent_id': team.leadAgentId,
          'app_session_id': team.appSessionId,
          'cwd': team.workingDirectory,
          'description': team.description.trim().isEmpty
              ? null
              : team.description.trim(),
          'additional_paths': team.additionalPaths.isEmpty
              ? null
              : List<String>.from(team.additionalPaths),
        }),
      'members': [
        for (final teammate in snapshot.members)
          teammateMap(teammate, callerMemberId == teammate.memberId),
      ],
    });
  }

  static Map<String, Object?> teammateMap(
    TeammateSnapshot teammate,
    bool isSelf,
  ) {
    final profile = teammate.profile;
    final role = profile.isTeamLead ? 'leader' : 'worker';
    final agentId =
        profile.agentId.isEmpty ? profile.memberId : profile.agentId;
    final agentType =
        profile.agentType.isEmpty ? profile.memberId : profile.agentType;
    final cli = profile.cli.isEmpty ? '?' : profile.cli;
    final backendType =
        profile.backendType.isEmpty ? profile.cli : profile.backendType;

    return _omitEmpty({
      'member_id': profile.memberId,
      'display_name': profile.effectiveDisplayName,
      'agent_id': agentId,
      'agent_type': agentType,
      'role': role,
      'agent': profile.agent.isEmpty ? null : profile.agent,
      'model': profile.model.isEmpty ? null : profile.model,
      'provider': profile.provider.isEmpty ? null : profile.provider,
      'cli': cli,
      'backend_type': backendType.isEmpty ? cli : backendType,
      'task_id': profile.taskId.isEmpty ? null : profile.taskId,
      if (profile.machineId.isNotEmpty) ...{
        'machine': profile.machine,
        'machine_kind': profile.machineKind,
        'machine_id': profile.machineId,
      },
      'cwd': profile.cwd.isEmpty ? null : profile.cwd,
      if (isSelf) 'self': true,
      'joined_at': profile.joinedAt > 0 ? profile.joinedAt : null,
      'extra_args': profile.extraArgs.isEmpty ? null : profile.extraArgs,
      'dangerously_skip_permissions': profile.dangerouslySkipPermissions,
      'responsibilities': profile.responsibilities.trim().isEmpty
          ? null
          : profile.responsibilitiesSummary(),
      'bus': {
        'lifecycle': teammate.lifecycle.name,
        'activity': teammate.activity.name,
        'phase': teammate.busPhaseLabel,
        'unread': teammate.unreadCount,
      },
      'claude_is_active': teammate.claudeIsActive,
      'pty_running': teammate.ptyRunning,
    });
  }

  static String formatTeammate(TeammateSnapshot teammate, bool isSelf) =>
      _encode(teammateMap(teammate, isSelf));

  static String encodeMessagePage(BusMessagePage page) {
    return _encode({
      'messages': [for (final m in page.messages) messageMap(m)],
      'total_unread': page.totalUnread,
      'has_more': page.hasMore,
      if (page.nextAfterId != null) 'next_after_id': page.nextAfterId,
    });
  }

  static String encodeBatch(List<TeamMessage> batch) {
    return _encode({
      'messages': [for (final m in batch) messageMap(m)],
    });
  }

  static Map<String, Object?> messageMap(TeamMessage message) {
    if (message.from == TeamBus.userSenderId) {
      return {
        'from': 'user',
        'kind': 'message',
        'content': message.content,
      };
    }
    final idle = IdleNotification.parseTeamMessageContent(message.content);
    if (idle != null) {
      return {
        'from': message.from,
        'kind': 'idle',
        'content': idle.formatForLeader(),
      };
    }
    return {
      'from': message.from,
      'kind': 'message',
      'content': message.content,
    };
  }

  static String formatMessage(TeamMessage message) =>
      _encode(messageMap(message));
}
