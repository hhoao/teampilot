import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/side_resolver.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/terminal_tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('history capabilities expose toolResultEnricher', () {
    for (final cap in [
      const ClaudeAiHistoryCapability(),
      const FlashskyaiAiHistoryCapability(),
      const CursorAiHistoryCapability(),
      const CodexAiHistoryCapability(),
      const OpencodeAiHistoryCapability(),
    ]) {
      expect(cap.toolResultEnricher, isNotNull);
    }
    expect(
      const ClaudeAiHistoryCapability().toolResultEnricher,
      isA<ClaudeCompatibleToolResultEnricher>(),
    );
    expect(
      const FlashskyaiAiHistoryCapability().toolResultEnricher,
      isA<ClaudeCompatibleToolResultEnricher>(),
    );
    expect(
      const CursorAiHistoryCapability().toolResultEnricher,
      isA<CursorTerminalToolResultEnricher>(),
    );
    expect(
      const CodexAiHistoryCapability().toolResultEnricher,
      isA<NoOpToolResultEnricher>(),
    );
    expect(
      const OpencodeAiHistoryCapability().toolResultEnricher,
      isA<NoOpToolResultEnricher>(),
    );
  });

  test('Claude capability recognizes Workflow as a subagent tool', () {
    final cap = const ClaudeAiHistoryCapability();
    expect(cap.subagentToolNames, contains('workflow'));
    expect(cap.subagentToolNames, contains('agent'));
    expect(cap.subagentToolNames, contains('task'));
    expect(cap.subagentSideResolver, isA<ClaudeSideResolver>());
  });

  test('all launch CLIs expose AiHistoryCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in [
      CliTool.claude,
      CliTool.flashskyai,
      CliTool.codex,
      CliTool.opencode,
      CliTool.cursor,
    ]) {
      expect(
        registry.capability<AiHistoryCapability>(cli),
        isNotNull,
        reason: '$cli',
      );
    }
  });
}
