import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/provider/codex_toml_parser.dart';
import 'package:toml/toml.dart';

void main() {
  group('CodexTomlParser.invalidHookTypes', () {
    test('accepts command/prompt/agent hook types', () {
      const toml = '''
[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "command"
command = "bash '/s/hooks/a.sh'"

[[hooks.PreToolUse]]
matcher = "*"

[[hooks.PreToolUse.hooks]]
type = "prompt"
prompt = "decide"

[[hooks.PostToolUse]]

[[hooks.PostToolUse.hooks]]
type = "agent"
agent = "review"
''';
      expect(CodexTomlParser.invalidHookTypes(toml), isEmpty);
    });

    test('rejects unsupported type values in document order', () {
      const toml = '''
[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "http"
url = "http://127.0.0.1:1/idle"

[[hooks.PreToolUse]]

[[hooks.PreToolUse.hooks]]
type = "command"
command = "echo ok"

[[hooks.PreToolUse.hooks]]
type = "webhook"
url = "http://127.0.0.1:2/x"
''';
      expect(CodexTomlParser.invalidHookTypes(toml), ['http', 'webhook']);
    });

    test('returns empty when config has no hooks table', () {
      const toml = '''
model = "m1"
base_url = "https://upstream.example.com"
[model_providers.custom]
base_url = "https://upstream.example.com"

[mcp_servers.time]
command = "npx"
''';
      expect(CodexTomlParser.invalidHookTypes(toml), isEmpty);
    });

    test('matches the writer output for managed agent-status + bus hooks', () {
      // Rendered by CodexHookWriter today — regression guard: any future
      // change that reintroduces a native `http` row must fail here.
      const toml = '''
# TeamPilot user hooks — do not edit.

[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "command"
command = "bash '/s/hooks/teampilot-http-teampilot-agent-status-stop-stop.sh'"
timeout = 5

[[hooks.PreToolUse]]
matcher = "*"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "bash '/s/hooks/teampilot-http-teampilot-agent-status-preToolUse-preToolUse.sh'"
timeout = 86400
''';
      expect(CodexTomlParser.invalidHookTypes(toml), isEmpty);
    });
  });

  group('CodexTomlParser.removeInvalidHooks', () {
    test('drops http handlers and empty event groups, keeps command', () {
      const toml = '''
[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "http"
url = "http://127.0.0.1:1/idle"

[[hooks.Stop.hooks]]
type = "command"
command = "/s/hooks/a.sh"

[[hooks.PreToolUse]]

[[hooks.PreToolUse.hooks]]
type = "webhook"
url = "http://127.0.0.1:2/x"
''';
      final root = Map<String, dynamic>.from(
        TomlDocument.parse(toml).toMap(),
      );
      CodexTomlParser.removeInvalidHooks(root);
      expect(
        CodexTomlParser.invalidHookTypes('${TomlDocument.fromMap(root)}\n'),
        isEmpty,
      );
      final stop = (root['hooks'] as Map)['Stop'] as List;
      expect(stop, hasLength(1));
      expect(((stop.first as Map)['hooks'] as List).single['type'], 'command');
      expect((root['hooks'] as Map).containsKey('PreToolUse'), isFalse);
    });
  });
}
