import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart';
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
      const CodexAiHistoryCapability().toolResultEnricher,
      isA<NoOpToolResultEnricher>(),
    );
    expect(
      const OpencodeAiHistoryCapability().toolResultEnricher,
      isA<NoOpToolResultEnricher>(),
    );
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
