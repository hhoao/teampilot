import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();
  final clis = CliTool.values.where((c) => registry.tryGet(c) != null);

  AiToolCallPart tool(String name) =>
      AiToolCallPart(toolCallId: '1', toolName: name);

  test('every launch-supported CLI exposes a categoryResolver', () {
    for (final cli in clis) {
      final resolvers = registry.toolCallResolvers(cli);
      expect(resolvers, isNotNull, reason: '$cli');
      expect(resolvers!.categoryResolver, isNotNull, reason: '$cli');
    }
  });

  test('core tools map identically across CLIs', () {
    for (final cli in clis) {
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      expect(resolver.resolve(tool('bash')), AiToolCallCategory.command,
          reason: '$cli');
      expect(resolver.resolve(tool('read')), AiToolCallCategory.read,
          reason: '$cli');
      expect(resolver.resolve(tool('write')), AiToolCallCategory.write,
          reason: '$cli');
      expect(resolver.resolve(tool('strreplace')), AiToolCallCategory.edit,
          reason: '$cli');
      expect(resolver.resolve(tool('mcp__foo')), AiToolCallCategory.mcp,
          reason: '$cli');
      expect(resolver.resolve(tool('unknown_x')), AiToolCallCategory.other,
          reason: '$cli');
    }
  });

  test('cursor maps execute to command', () {
    final resolver = registry.toolCallResolvers(CliTool.cursor)!
        .categoryResolver;
    expect(resolver.resolve(tool('execute')), AiToolCallCategory.command);
  });

  test('opencode-origin tools question/skill resolve explicitly to other '
      '(矩阵 G-3 显式化)', () {
    for (final cli in clis) {
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      expect(resolver.resolve(tool('question')), AiToolCallCategory.other,
          reason: '$cli');
      expect(resolver.resolve(tool('skill')), AiToolCallCategory.other,
          reason: '$cli');
    }
  });

  test('subagentToolNames consistency: every name resolves to subagent', () {
    for (final cli in clis) {
      final history = registry.capability<AiHistoryCapability>(cli)!;
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      for (final name in history.subagentToolNames) {
        expect(resolver.resolve(tool(name)), AiToolCallCategory.subagent,
            reason: '$cli/$name');
      }
    }
  });
}
