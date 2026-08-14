import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/claude_family_hooks_json_dialect.dart';
import 'package:teampilot/services/hook/import/codex_hooks_json_dialect.dart';
import 'package:teampilot/services/hook/import/hook_grouped_json_parser.dart';

void main() {
  const claude = ClaudeFamilyHooksJsonDialect();
  const codex = CodexHooksJsonDialect();

  test('claude: settings.json hooks map with matcher group and command/http',
      () {
    const json = '''
{
  "apiKeyHelper": {"enabled": true},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash /x/guard.sh", "timeout": 5,
         "if": "Bash(rm *)", "async": true},
        {"type": "http", "url": "http://127.0.0.1:1/h", "headers": {"X-A": "b"}}
      ]}
    ]
  }
}''';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(warnings, isEmpty);
    expect(entries, hasLength(2));
    final cmd = entries[0];
    expect(cmd.nativeEvent, 'PreToolUse');
    expect(cmd.matcher, 'Bash');
    expect(cmd.type, 'command');
    expect(cmd.command, 'bash /x/guard.sh');
    expect(cmd.timeoutSec, 5);
    expect(cmd.native, {'if': 'Bash(rm *)', 'async': true});
    expect(cmd.unsupportedFields, containsAll(['if', 'async']));
    final http = entries[1];
    expect(http.type, 'http');
    expect(http.url, 'http://127.0.0.1:1/h');
    expect(http.headers, {'X-A': 'b'});
  });

  test('claude: pasted hooks-only fragment works (no top-level hooks key)', () {
    const json = '{"Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]}';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(entries.single.nativeEvent, 'Stop');
    expect(entries.single.command, 'echo done');
  });

  test('claude: mcp_tool/prompt/agent handlers warn and are skipped', () {
    const json = '''
{"hooks": {"Stop": [
  {"hooks": [
    {"type": "command", "command": "echo a"},
    {"type": "prompt", "prompt": "is it ok?"},
    {"type": "mcp_tool", "server": "x", "tool": "y"},
    {"type": "agent", "prompt": "check"}
  ]}
]}}''';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(entries, hasLength(1));
    expect(warnings, containsAll([
      'hook_import_type_unsupported_prompt',
      'hook_import_type_unsupported_mcp_tool',
      'hook_import_type_unsupported_agent',
    ]));
  });

  test('codex: description top-level ignored, statusMessage into native', () {
    const json = '''
{
  "description": "team hooks",
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [
        {"type": "command", "command": "python3 ~/.codex/hooks/s.py",
         "statusMessage": "Loading", "additionalContextLimit": 5000,
         "timeout": 30}
      ]}
    ]
  }
}''';
    final warnings = <String>[];
    final entries = codex.parseJson(json, warnings);
    expect(entries.single.nativeEvent, 'SessionStart');
    expect(entries.single.matcher, 'startup');
    expect(entries.single.timeoutSec, 30);
    expect(entries.single.native, {
      'statusMessage': 'Loading',
      'additionalContextLimit': 5000,
    });
  });

  test('missing hooks and bad json produce warnings not throws', () {
    final w1 = <String>[];
    expect(HookGroupedJsonParser.parse('{"version": 1}', w1), isEmpty);
    expect(w1, contains('hook_import_no_hooks'));
    final w2 = <String>[];
    expect(HookGroupedJsonParser.parse('not json', w2), isEmpty);
    expect(w2, contains('hook_import_invalid_json_shape'));
  });

  test('hooks envelope: non-map hooks key and empty hooks map warn', () {
    final w1 = <String>[];
    expect(HookGroupedJsonParser.parse('{"hooks": []}', w1), isEmpty);
    expect(w1, contains('hook_import_bad_hooks_envelope'));
    final w2 = <String>[];
    expect(HookGroupedJsonParser.parse('{"hooks": {}}', w2), isEmpty);
    expect(w2, contains('hook_import_no_hooks'));
  });
}
