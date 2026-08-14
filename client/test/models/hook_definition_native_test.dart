import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('native round-trips through json with equality', () {
    final definition = HookDefinition(
      id: 'h1',
      name: 'Guard',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: const CommandHookAction.raw('bash /x/guard.sh'),
      native: const {'if': 'Bash(rm *)', 'async': true, 'statusMessage': 'checking'},
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored, definition);
    expect(restored.native, {
      'if': 'Bash(rm *)',
      'async': true,
      'statusMessage': 'checking',
    });
  });

  test('native null or empty is omitted from json', () {
    const definition = HookDefinition(
      id: 'h2',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    expect(definition.toJson().containsKey('native'), isFalse);
    final withEmpty = HookDefinition(
      id: 'h2',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo done'),
      native: const {},
    );
    expect(withEmpty.toJson().containsKey('native'), isFalse);
  });

  test('copyWith replaces native', () {
    final base = HookDefinition(
      id: 'h3',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo done'),
      native: const {'async': true},
    );
    final next = base.copyWith(native: null);
    expect(next.native, isNull);
    expect(base.copyWith().native, {'async': true});
  });
}
