import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/team_bus/bus_awareness_prompt.dart';

void main() {
  const lead = TeamMemberConfig(id: 'team-lead', name: 'Team Lead');
  const worker = TeamMemberConfig(id: 'implementer', name: 'Implementer');

  test('lead additionalContext wraps the mixed lead protocol', () {
    final text = BusAwarenessPrompt.additionalContext(
      member: lead,
      pushDelivery: false,
    );
    expect(text, contains('<EXTREMELY_IMPORTANT>'));
    expect(text, contains('teammate-bus'));
    expect(
      text,
      contains(MemberRoleProvision.mixedTeamLeadRoleAddendum.trim()),
    );
    expect(text, isNot(contains('DO NOT call wait_for_message')));
  });

  test('worker additionalContext wraps the mixed worker protocol', () {
    final text = BusAwarenessPrompt.additionalContext(
      member: worker,
      pushDelivery: false,
    );
    expect(
      text,
      contains(MemberRoleProvision.mixedTeammateRoleAddendum.trim()),
    );
  });

  test('push additionalContext wraps the push protocol even for lead', () {
    final text = BusAwarenessPrompt.additionalContext(
      member: lead,
      pushDelivery: true,
    );
    expect(
      text,
      contains(MemberRoleProvision.mixedTeammatePushRoleAddendum.trim()),
    );
  });

  test('claude SessionStart stdout uses hookSpecificOutput.additionalContext', () {
    final context = BusAwarenessPrompt.additionalContext(
      member: worker,
      pushDelivery: false,
    );
    final payload = BusAwarenessPrompt.sessionStartStdout(
      cli: CliTool.claude,
      additionalContext: context,
    );
    expect(payload['additional_context'], isNull);
    final hook = payload['hookSpecificOutput'] as Map;
    expect(hook['hookEventName'], 'SessionStart');
    expect(hook['additionalContext'], context);
  });

  test('cursor SessionStart stdout uses additional_context', () {
    final context = BusAwarenessPrompt.additionalContext(
      member: worker,
      pushDelivery: true,
    );
    final payload = BusAwarenessPrompt.sessionStartStdout(
      cli: CliTool.cursor,
      additionalContext: context,
    );
    expect(payload['additional_context'], context);
    expect(payload.containsKey('hookSpecificOutput'), isFalse);
  });

  test('sessionStartScript prints the JSON payload on stdout', () {
    final context = BusAwarenessPrompt.additionalContext(
      member: worker,
      pushDelivery: false,
    );
    final payload = BusAwarenessPrompt.sessionStartStdout(
      cli: CliTool.codex,
      additionalContext: context,
    );
    final script = BusAwarenessPrompt.sessionStartScript(
      cli: CliTool.codex,
      additionalContext: context,
    );
    expect(script, startsWith('#!/usr/bin/env bash'));
    expect(script, contains(jsonEncode(payload)));
  });
}
