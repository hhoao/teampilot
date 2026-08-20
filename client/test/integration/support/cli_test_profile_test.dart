import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

import 'cli_test_profile.dart';

void main() {
  test('supportsNativeTeam derives from CliToolRegistry for all five CLIs', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in CliTool.values) {
      final profile = CliTestProfiles.forTool(tool);
      expect(
        profile.supportsNativeTeam,
        registry.supportsNativeTeam(tool),
        reason: '${tool.value} native flag must match registry',
      );
    }
    expect(CliTestProfiles.forTool(CliTool.claude).supportsNativeTeam, isTrue);
    expect(
      CliTestProfiles.forTool(CliTool.flashskyai).supportsNativeTeam,
      isTrue,
    );
    expect(CliTestProfiles.forTool(CliTool.codex).supportsNativeTeam, isFalse);
    expect(
      CliTestProfiles.forTool(CliTool.opencode).supportsNativeTeam,
      isFalse,
    );
    expect(CliTestProfiles.forTool(CliTool.cursor).supportsNativeTeam, isFalse);
  });

  test('wires match matrix plan for each CLI', () {
    expect(CliTestProfiles.forTool(CliTool.claude).wire, CliTestWire.anthropic);
    expect(
      CliTestProfiles.forTool(CliTool.flashskyai).wire,
      CliTestWire.openaiChat,
    );
    expect(CliTestProfiles.forTool(CliTool.flashskyai).providerType, 'openai');
    expect(
      CliTestProfiles.forTool(CliTool.codex).wire,
      CliTestWire.openaiResponses,
    );
    expect(
      CliTestProfiles.forTool(CliTool.opencode).wire,
      CliTestWire.openaiChat,
    );
    expect(CliTestProfiles.forTool(CliTool.cursor).wire, CliTestWire.cursor);
  });

  test('busStyle is doorbell only for cursor', () {
    expect(
      CliTestProfiles.forTool(CliTool.cursor).busStyle,
      CliTestBusStyle.doorbell,
    );
    for (final tool in [
      CliTool.claude,
      CliTool.flashskyai,
      CliTool.codex,
      CliTool.opencode,
    ]) {
      expect(
        CliTestProfiles.forTool(tool).busStyle,
        CliTestBusStyle.longWait,
        reason: '${tool.value} should long-wait on TeamBus',
      );
    }
  });

  test('claude toolName maps teambus, catalog, and native refs', () {
    final profile = CliTestProfiles.forTool(CliTool.claude);
    expect(
      profile.toolName('teambus.send_message'),
      'mcp__${teammateBusMcpServerName}__send_message',
    );
    expect(
      profile.toolName('catalog.search_skills'),
      'mcp__${catalogMcpServerName}__search_skills',
    );
    expect(
      profile.toolName('catalog.create_skill'),
      'mcp__${catalogMcpServerName}__create_skill',
    );
    expect(profile.toolName('native.TeamCreate'), 'TeamCreate');
  });

  test('flashskyai toolName uses mcp__ teambus mapping', () {
    expect(
      CliTestProfiles.forTool(
        CliTool.flashskyai,
      ).toolName('teambus.wait_for_message'),
      'mcp__${teammateBusMcpServerName}__wait_for_message',
    );
    expect(
      CliTestProfiles.forTool(
        CliTool.flashskyai,
      ).toolName('catalog.search_skills'),
      'mcp__${catalogMcpServerName}__search_skills',
    );
  });

  test('codex toolName maps teambus refs to namespaced Responses wire', () {
    final server = teammateBusMcpServerName.replaceAll('-', '_');
    expect(
      CliTestProfiles.forTool(CliTool.codex).toolName('teambus.list_teammates'),
      'mcp__$server::list_teammates',
    );
    expect(
      CliTestProfiles.forTool(
        CliTool.codex,
      ).toolName('teambus.wait_for_message'),
      'mcp__$server::wait_for_message',
    );
    expect(
      CliTestProfiles.forTool(CliTool.codex).toolName('catalog.create_skill'),
      'mcp__$catalogMcpServerName::create_skill',
    );
  });

  test('opencode toolName maps teambus refs to server_tool keys', () {
    expect(
      CliTestProfiles.forTool(
        CliTool.opencode,
      ).toolName('teambus.send_message'),
      '${teammateBusMcpServerName}_send_message',
    );
    expect(
      CliTestProfiles.forTool(
        CliTool.opencode,
      ).toolName('teambus.wait_for_message'),
      '${teammateBusMcpServerName}_wait_for_message',
    );
    expect(
      CliTestProfiles.forTool(
        CliTool.opencode,
      ).toolName('catalog.search_skills'),
      '${catalogMcpServerName}_search_skills',
    );
  });

  test('cursor toolName uses short MCP names', () {
    expect(
      CliTestProfiles.forTool(CliTool.cursor).toolName('teambus.read_messages'),
      'read_messages',
    );
    expect(
      CliTestProfiles.forTool(CliTool.cursor).toolName('catalog.create_skill'),
      'create_skill',
    );
  });

  test('cursor gatewayRedirectNotes records Task 15 BLOCKED spike', () {
    final notes = CliTestProfiles.forTool(CliTool.cursor).gatewayRedirectNotes;
    expect(notes, contains('BLOCKED'));
    expect(notes, contains('agent-cli-local'));
    expect(notes, contains('localAgentRuntime'));
    expect(notes, isNot(contains('TODO(Task 15)')));
  });

  test('assistantVisibleMarkers are simple recipe MARK_A*', () {
    for (final tool in CliTool.values) {
      expect(CliTestProfiles.forTool(tool).assistantVisibleMarkers, [
        'MARK_A1',
        'MARK_A2',
        'MARK_A3',
      ]);
    }
  });
}
