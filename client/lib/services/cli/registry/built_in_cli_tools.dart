import '../../../models/team_config.dart';
import 'cli_tool_registry.dart';
import 'tools/claude_cli_tool.dart';
import 'tools/codex_cli_tool.dart';
import 'tools/cursor_cli_tool.dart';
import 'tools/flashskyai_cli_tool.dart';
import 'tools/opencode_cli_tool.dart';

void registerBuiltInCliTools(CliToolRegistry registry) {
  registry.register(const FlashskyaiCliTool());
  registry.register(const ClaudeCliTool());
  registry.register(const CodexCliTool());
  registry.register(const OpencodeCliTool());
  registry.register(const CursorCliTool());

  assert(
    CliTool.values.every((cli) => registry.tryGet(cli) != null),
    'Every CliTool must have a registered definition',
  );
  assert(
    registry.all.length == CliTool.values.length,
    'Registry must not contain extra definitions beyond CliTool.values',
  );
}
