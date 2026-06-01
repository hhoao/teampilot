import 'cli_tool_registry.dart';
import 'tools/claude_cli_tool.dart';
import 'tools/codex_cli_tool.dart';
import 'tools/flashskyai_cli_tool.dart';
import 'tools/opencode_cli_tool.dart';

void registerBuiltInCliTools(CliToolRegistry registry) {
  registry.register(const FlashskyaiCliTool());
  registry.register(const ClaudeCliTool());
  registry.register(const CodexCliTool());
  registry.register(const OpencodeCliTool());
}
