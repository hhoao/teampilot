import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/hook/import/hook_import_parser.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  HookImportParser parser({String? home}) =>
      HookImportParser(fs: fs, teampilotRoot: '/root', homeDir: home);

  test('claude json → drafts with mapped event and script copy', () async {
    await fs.writeString('/x/guard.sh', 'exit 2');
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {"PreToolUse": [
  {"matcher": "Bash", "hooks": [
    {"type": "command", "command": "bash /x/guard.sh", "timeout": 5,
     "async": true}
  ]}
]}}''',
    );
    expect(result.warnings, isEmpty);
    final draft = result.drafts.single;
    expect(draft.definition.event, HookEvent.preToolUse);
    expect(draft.definition.matcher, 'Bash');
    expect(draft.definition.timeoutSec, 5);
    expect(draft.definition.native, {'async': true});
    expect(draft.unsupportedFields, ['async']);
    final action = draft.definition.action as CommandHookAction;
    expect(
      action.command,
      'bash "/root/hooks/${draft.definition.id}/guard.sh"',
    );
    expect(draft.scriptFileName, 'guard.sh');
    expect(draft.scriptContent, 'exit 2');
    expect(draft.definition.id, startsWith('import-'));
    expect(draft.definition.id, hasLength('import-'.length + 12));
  });

  test('script copy rewrites quoted path when teampilotRoot contains spaces', () async {
    await fs.writeString('/x/guard.sh', 'exit 2');
    final result = await HookImportParser(fs: fs, teampilotRoot: '/root/App Support/tp')
        .parseJson(
          cli: CliTool.claude,
          jsonText: '''
{"hooks": {"Stop": [
  {"hooks": [{"type": "command", "command": "bash /x/guard.sh"}]}
]}}''',
        );
    final draft = result.drafts.single;
    final command = (draft.definition.action as CommandHookAction).command;
    expect(
      command,
      'bash "/root/App Support/tp/hooks/${draft.definition.id}/guard.sh"',
    );
    // 整个路径必须是单个引号包裹的 token（不再被 shell 按空格拆词）。
    expect(
      RegExp(r'^bash "/root/App Support/tp/hooks/[^"]+/guard\.sh"$')
          .hasMatch(command!),
      isTrue,
    );
  });

  test('script copy escapes backslashes in rewritten path', () async {
    await fs.writeString('/x/a\\b.sh', 'exit 2');
    final result = await HookImportParser(fs: fs, teampilotRoot: '/root').parseJson(
      cli: CliTool.claude,
      jsonText:
          '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "bash /x/a\\\\b.sh"}]}]}}',
    );
    final draft = result.drafts.single;
    final command = (draft.definition.action as CommandHookAction).command;
    expect(command, 'bash "/root/hooks/${draft.definition.id}/a\\\\b.sh"');
  });

  test('raw command stays raw; unsupported event dropped with warning', () async {
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {
  "PostCompact": [{"hooks": [{"type": "command", "command": "echo a"}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]
}}''',
    );
    expect(result.drafts, hasLength(1));
    expect(result.warnings, ['hook_import_event_unsupported_PostCompact']);
    expect(
      (result.drafts.single.definition.action as CommandHookAction).command,
      'echo done',
    );
  });

  test('cursor json maps lowercase events; http keeps url', () async {
    final result = await parser().parseJson(
      cli: CliTool.cursor,
      jsonText: '''
{"version": 1, "hooks": {
  "beforeSubmitPrompt": [{"command": "echo a"}]
}}''',
    );
    final draft = result.drafts.single;
    expect(draft.definition.event, HookEvent.userPromptSubmit);
  });

  test('http handler becomes HttpHookAction', () async {
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {"Stop": [
  {"hooks": [{"type": "http", "url": "http://127.0.0.1:1/h", "headers": {"X-A": "b"}}]}
]}}''',
    );
    final action = result.drafts.single.definition.action as HttpHookAction;
    expect(action.url, 'http://127.0.0.1:1/h');
    expect(action.headers, {'X-A': 'b'});
  });

  test('id is deterministic and differs across entries', () async {
    const json = '''
{"hooks": {"Stop": [
  {"hooks": [{"type": "command", "command": "echo a"}]},
  {"hooks": [{"type": "command", "command": "echo b"}]}
]}}''';
    final a = await parser().parseJson(cli: CliTool.claude, jsonText: json);
    final b = await parser().parseJson(cli: CliTool.claude, jsonText: json);
    expect(a.drafts[0].definition.id, b.drafts[0].definition.id);
    expect(a.drafts[0].definition.id, isNot(a.drafts[1].definition.id));
  });

  test('bad json produces warning and no drafts', () async {
    final result =
        await parser().parseJson(cli: CliTool.claude, jsonText: 'not json');
    expect(result.drafts, isEmpty);
    expect(result.warnings.single, startsWith('hook_import_invalid_json'));
  });

  test('opencode cli is unsupported', () async {
    final result =
        await parser().parseJson(cli: CliTool.opencode, jsonText: '{}');
    expect(result.drafts, isEmpty);
    expect(result.warnings, ['hook_import_cli_unsupported_opencode']);
  });
}
