import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/hook_json_dialect.dart';

void main() {
  test('RawHookEntry value equality', () {
    const a = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      timeoutSec: 5,
      native: {'async': true},
      unsupportedFields: ['async'],
    );
    const b = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      timeoutSec: 5,
      native: {'async': true},
      unsupportedFields: ['async'],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('native with nested list hashes deep-equal', () {
    final a = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      native: <String, Object?>{'args': <Object?>['-f', 'x']},
    );
    final b = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      native: <String, Object?>{'args': <Object?>['-f', 'x']},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('json helpers parse strings, ints, maps', () {
    const map = <String, Object?>{
      'a': 'x',
      't': 5.0,
      'headers': {'X-M': 'm1'},
      'n': null,
    };
    expect(hookJsonString(map, 'a'), 'x');
    expect(hookJsonString(map, 'n'), null);
    expect(hookJsonInt(map, 't'), 5);
    expect(hookJsonInt(map, 'n'), null);
    expect(hookJsonStringMap(map, 'headers'), {'X-M': 'm1'});
    expect(hookJsonStringMap(map, 'n'), const {});
  });

  test('path and quote helpers', () {
    expect(isPathLike('/abs/x.sh'), isTrue);
    expect(isPathLike('~/x.sh'), isTrue);
    expect(isPathLike('./x.sh'), isTrue);
    expect(isPathLike('scripts/x.py'), isTrue);
    expect(isPathLike('echo'), isFalse);
    expect(isPathLike('-f'), isFalse);
    expect(stripQuotes('"/a b/x.sh"'), '/a b/x.sh');
    expect(stripQuotes("'/a/x.sh'"), '/a/x.sh');
    expect(stripQuotes('/a/x.sh'), '/a/x.sh');
  });

  test('looksLikeGroups accepts a hooks-map-shaped root', () {
    expect(
      looksLikeGroups(<String, Object?>{
        'PreToolUse': [
          {'matcher': 'Bash'},
        ],
      }),
      isTrue,
    );
    expect(
      looksLikeGroups(<String, Object?>{'version': 1, 'hooks': {}}),
      isFalse,
    );
  });
}
