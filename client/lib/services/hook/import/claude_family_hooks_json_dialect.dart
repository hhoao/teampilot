import '../../../models/team_config.dart';
import 'hook_grouped_json_parser.dart';
import 'hook_json_dialect.dart';

/// claude / flashskyai：settings.json 的 `hooks` map（或只贴 hooks 段）。
class ClaudeFamilyHooksJsonDialect implements HookJsonDialect {
  const ClaudeFamilyHooksJsonDialect();

  @override
  CliTool get cli => CliTool.claude;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) =>
      HookGroupedJsonParser.parse(jsonText, warnings);
}
