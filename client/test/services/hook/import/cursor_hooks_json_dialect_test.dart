import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/cursor_hooks_json_dialect.dart';

void main() {
  const dialect = CursorHooksJsonDialect();

  test('flat entries with matcher/timeout/loop_limit/failClosed', () {
    const json = '''
{"version": 1, "hooks": {
  "preToolUse": [
    {"command": "bash /x/guard.sh", "matcher": "Shell|Read", "timeout": 30,
     "loop_limit": null, "failClosed": true}
  ],
  "stop": [
    {"command": "bash /x/stop.sh", "loop_limit": null}
  ]
}}''';
    final warnings = <String>[];
    final entries = dialect.parseJson(json, warnings);
    expect(warnings, isEmpty);
    expect(entries, hasLength(2));
    final pre = entries[0];
    expect(pre.nativeEvent, 'preToolUse');
    expect(pre.matcher, 'Shell|Read');
    expect(pre.type, 'command');
    expect(pre.timeoutSec, 30);
    expect(pre.native, {'loop_limit': null, 'failClosed': true});
    expect(pre.unsupportedFields, containsAll(['loop_limit', 'failClosed']));
    final stop = entries[1];
    expect(stop.nativeEvent, 'stop');
    expect(stop.matcher, isNull);
    expect(stop.native, {'loop_limit': null});
  });

  test('prompt type warns and is skipped', () {
    const json = '''
{"version": 1, "hooks": {
  "beforeShellExecution": [
    {"type": "prompt", "prompt": "safe?", "timeout": 10},
    {"command": "bash /x/a.sh"}
  ]
}}''';
    final warnings = <String>[];
    final entries = dialect.parseJson(json, warnings);
    expect(entries, hasLength(1));
    expect(entries.single.command, 'bash /x/a.sh');
    expect(warnings, contains('hook_import_type_unsupported_prompt'));
  });

  test('missing hooks warns', () {
    final warnings = <String>[];
    expect(dialect.parseJson('{"version": 1}', warnings), isEmpty);
    expect(warnings, contains('hook_import_no_hooks'));
  });
}
