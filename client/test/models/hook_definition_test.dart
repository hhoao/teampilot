import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('round-trips a raw command definition', () {
    final definition = HookDefinition(
      id: 'h1',
      name: 'Deny git push',
      description: 'Block git push in Bash',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: const CommandHookAction.raw('exit 2'),
      policy: HookPolicy.deny,
      timeoutSec: 10,
      env: const {'DEBUG': '1'},
    );
    final json = definition.toJson();
    final restored = HookDefinition.fromJson(json);
    expect(restored, definition);
    expect(restored.policy, HookPolicy.deny);
    expect((restored.action as CommandHookAction).command, 'exit 2');
  });

  test('round-trips a script definition', () {
    const action = CommandHookAction.script(
      fileName: 'hook.sh',
      scriptContent: '#!/usr/bin/env bash\ncat >/dev/null',
    );
    final definition = HookDefinition(
      id: 'h2',
      name: 'On start',
      event: HookEvent.sessionStart,
      action: action,
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored.id, 'h2');
    expect(restored.event, HookEvent.sessionStart);
    expect((restored.action as CommandHookAction).fileName, 'hook.sh');
    // 持久化不存内容（内容在脚本文件里）。
    expect((restored.action as CommandHookAction).scriptContent, isNull);
  });

  test('round-trips http action', () {
    final definition = HookDefinition(
      id: 'h3',
      name: 'Notify',
      event: HookEvent.notification,
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/hook',
        headers: {'X-A': 'b'},
      ),
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored.action, definition.action);
  });

  test('defaults on absent fields', () {
    final definition = HookDefinition.fromJson({'id': 'h4', 'event': 'stop'});
    expect(definition.name, '');
    expect(definition.description, '');
    expect(definition.policy, HookPolicy.none);
    expect(definition.matcher, isNull);
    expect(definition.timeoutSec, isNull);
    expect(definition.env, isEmpty);
  });

  test('unknown event falls back to stop', () {
    final definition = HookDefinition.fromJson({'id': 'h5', 'event': 'nope'});
    expect(definition.event, HookEvent.stop);
  });

  test('copyWith', () {
    final base = HookDefinition(
      id: 'h6',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo a'),
    );
    final next = base.copyWith(name: 'b', policy: HookPolicy.allow);
    expect(next.id, 'h6');
    expect(next.name, 'b');
    expect(next.policy, HookPolicy.allow);
  });
}
