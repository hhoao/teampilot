import 'dart:convert';

import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';
import '../session/member_role_provision.dart';

/// Superpowers-style TeamBus protocol injected at session start.
abstract final class BusAwarenessPrompt {
  BusAwarenessPrompt._();

  static const _jsonDelimiter = 'TEAMPILOT_BUS_AWARENESS_JSON';

  static String additionalContext({
    required TeamMemberConfig member,
    required bool pushDelivery,
  }) {
    return '<EXTREMELY_IMPORTANT>\n'
        'You are on a mixed TeamPilot team. You MUST coordinate through '
        'teammate-bus MCP tools. Do not wait for the human to mention the team.\n'
        '\n'
        '**Below is the TeamBus protocol for this seat:**\n'
        '\n'
        '${protocolBody(member: member, pushDelivery: pushDelivery)}\n'
        '</EXTREMELY_IMPORTANT>';
  }

  static String protocolBody({
    required TeamMemberConfig member,
    required bool pushDelivery,
  }) {
    if (pushDelivery) {
      return MemberRoleProvision.mixedTeammatePushRoleAddendum.trim();
    }
    if (TeamMemberNaming.isTeamLead(member)) {
      return MemberRoleProvision.mixedTeamLeadRoleAddendum.trim();
    }
    return MemberRoleProvision.mixedTeammateRoleAddendum.trim();
  }

  static Map<String, Object?> sessionStartStdout({
    required CliTool cli,
    required String additionalContext,
  }) {
    if (cli == CliTool.cursor) {
      return {'additional_context': additionalContext};
    }
    return {
      'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': additionalContext,
      },
    };
  }

  static String sessionStartScript({
    required CliTool cli,
    required String additionalContext,
  }) {
    final json = jsonEncode(
      sessionStartStdout(cli: cli, additionalContext: additionalContext),
    );
    return '#!/usr/bin/env bash\n'
        '# TeamPilot bus awareness — do not edit.\n'
        "cat <<'$_jsonDelimiter'\n"
        '$json\n'
        '$_jsonDelimiter\n';
  }
}
