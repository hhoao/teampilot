import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('raw command action', () {
    const action = CommandHookAction.raw('echo hi');
    expect(action.command, 'echo hi');
    expect(action.fileName, isNull);
    expect(action.scriptContent, isNull);
  });

  test('script action carries content resolved from library', () {
    const action = CommandHookAction.script(
      fileName: 'hook.sh',
      scriptContent: '#!/usr/bin/env bash\necho hi',
    );
    expect(action.command, isNull);
    expect(action.fileName, 'hook.sh');
    expect(action.scriptContent, contains('echo hi'));
  });

  test('http action', () {
    final action = HttpHookAction(
      url: 'http://127.0.0.1:1/hook',
      headers: {'X-Member': 'm1'},
    );
    expect(action.url, 'http://127.0.0.1:1/hook');
    expect(action.headers['X-Member'], 'm1');
  });

  test('entry value equality', () {
    final a = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo hi'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    final b = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo hi'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    final c = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo bye'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    expect(a, b);
    expect(a == c, isFalse);
    expect(a.hashCode, b.hashCode);
  });

  test('entry copies and freezes env and HTTP headers', () {
    final env = <String, String>{'A': 'one'};
    final headers = <String, String>{'X-Test': 'one'};
    final entry = HookEntry(
      id: 'immutable',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://127.0.0.1/hook', headers: headers),
      env: env,
    );

    env['A'] = 'two';
    headers['X-Test'] = 'two';

    expect(entry.env, {'A': 'one'});
    expect((entry.action as HttpHookAction).headers, {'X-Test': 'one'});
    expect(() => entry.env['B'] = 'x', throwsUnsupportedError);
    expect(
      () => (entry.action as HttpHookAction).headers['X-Test'] = 'x',
      throwsUnsupportedError,
    );
  });
}
