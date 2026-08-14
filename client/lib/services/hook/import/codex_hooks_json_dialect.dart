import '../../../models/team_config.dart';
import 'hook_grouped_json_parser.dart';
import 'hook_json_dialect.dart';

/// codex：`~/.codex/hooks.json`（顶层允许 `description`）。
class CodexHooksJsonDialect implements HookJsonDialect {
  const CodexHooksJsonDialect();

  @override
  CliTool get cli => CliTool.codex;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) =>
      HookGroupedJsonParser.parse(
        jsonText,
        warnings,
        allowedTopLevelKeys: const {'description'},
      );
}
