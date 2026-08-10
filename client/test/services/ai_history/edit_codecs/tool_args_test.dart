import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/edit_codecs/tool_args.dart';

void main() {
  // ---------------------------------------------------------------------------
  // toolCallArgsMap
  // ---------------------------------------------------------------------------
  group('toolCallArgsMap', () {
    test('returns args map when populated', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        args: {'file_path': '/a/b.txt'},
      );
      expect(toolCallArgsMap(part), equals({'file_path': '/a/b.txt'}));
    });

    test('returns null when args is empty and argsText is null', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        args: const {},
        argsText: null,
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('returns null when args is null and argsText is null', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('decodes valid argsText JSON when args is null', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        argsText: '{"file_path": "/x/y.txt"}',
      );
      expect(toolCallArgsMap(part), equals({'file_path': '/x/y.txt'}));
    });

    test('decodes valid argsText JSON when args is empty', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        args: const {},
        argsText: '{"key": "val"}',
      );
      expect(toolCallArgsMap(part), equals({'key': 'val'}));
    });

    test('returns null for whitespace-only argsText', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        argsText: '   ',
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('returns null for empty argsText string', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        argsText: '',
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('returns null when argsText decodes to a non-Map (e.g. list)', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        argsText: '[1, 2, 3]',
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('returns null for invalid JSON argsText', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        argsText: 'not json',
      );
      expect(toolCallArgsMap(part), isNull);
    });

    test('prefers non-empty args over argsText', () {
      final part = AiToolCallPart(
        toolCallId: 't1',
        toolName: 'edit',
        args: {'file_path': '/fromArgs.txt'},
        argsText: '{"file_path": "/fromText.txt"}',
      );
      expect(
        toolCallArgsMap(part),
        equals({'file_path': '/fromArgs.txt'}),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // firstNonEmptyString
  // ---------------------------------------------------------------------------
  group('firstNonEmptyString', () {
    test('returns first matching non-empty string', () {
      final args = <String, Object?>{'b': 'hello', 'a': ''};
      expect(firstNonEmptyString(args, ['a', 'b']), equals('hello'));
    });

    test('skips empty strings', () {
      final args = <String, Object?>{'x': '', 'y': ''};
      expect(firstNonEmptyString(args, ['x', 'y']), isNull);
    });

    test('skips whitespace-only strings', () {
      final args = <String, Object?>{'x': '   ', 'y': '\t\n'};
      expect(firstNonEmptyString(args, ['x', 'y']), isNull);
    });

    test('trims whitespace from returned string', () {
      final args = <String, Object?>{'x': '  hello  '};
      expect(firstNonEmptyString(args, ['x']), equals('hello'));
    });

    test('skips non-string values', () {
      final args = <String, Object?>{'num': 42, 'str': 'valid'};
      expect(firstNonEmptyString(args, ['num', 'str']), equals('valid'));
    });

    test('respects key precedence order', () {
      final args = <String, Object?>{'first': 'uno', 'second': 'dos'};
      expect(firstNonEmptyString(args, ['second', 'first']), equals('dos'));
    });

    test('returns null when args is null', () {
      expect(firstNonEmptyString(null, ['any']), isNull);
    });

    test('returns null when no key matches', () {
      final args = <String, Object?>{'x': 'val'};
      expect(firstNonEmptyString(args, ['unknown']), isNull);
    });

    test('returns null when args is empty map', () {
      expect(firstNonEmptyString(<String, Object?>{}, ['a']), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // optionalString
  // ---------------------------------------------------------------------------
  group('optionalString', () {
    test('returns string value for first present key', () {
      final args = <String, Object?>{'b': 'world'};
      expect(optionalString(args, ['a', 'b']), equals('world'));
    });

    test('returns empty string when present key has empty value', () {
      final args = <String, Object?>{'desc': ''};
      expect(optionalString(args, ['desc']), equals(''));
    });

    test('returns null when key is present but value is not a String', () {
      final args = <String, Object?>{'num': 123, 'str': 'text'};
      expect(optionalString(args, ['num', 'str']), isNull);
    });

    test('returns null when args is null', () {
      expect(optionalString(null, ['k']), isNull);
    });

    test('returns null when no key is present', () {
      final args = <String, Object?>{'x': 'v'};
      expect(optionalString(args, ['unknown']), isNull);
    });

    test('respects key precedence', () {
      final args = <String, Object?>{'a': 'first', 'b': 'second'};
      expect(optionalString(args, ['b', 'a']), equals('second'));
    });
  });

  // ---------------------------------------------------------------------------
  // firstPositiveInt
  // ---------------------------------------------------------------------------
  group('firstPositiveInt', () {
    test('returns first positive integer by key list', () {
      final args = <String, Object?>{'y': 10, 'x': 5};
      final result = firstPositiveInt(args, ['x', 'y']);
      expect(result, equals(5));
    });

    test('skips non-positive values (0)', () {
      final args = <String, Object?>{'a': 0, 'b': 3};
      expect(firstPositiveInt(args, ['a', 'b']), equals(3));
    });

    test('skips negative values', () {
      final args = <String, Object?>{'a': -1, 'b': 1};
      expect(firstPositiveInt(args, ['a', 'b']), equals(1));
    });

    test('parses numeric string args', () {
      final args = <String, Object?>{'line': '42'};
      expect(firstPositiveInt(args, ['line']), equals(42));
    });

    test('skips non-numeric strings', () {
      final args = <String, Object?>{'a': 'abc', 'b': 3};
      expect(firstPositiveInt(args, ['a', 'b']), equals(3));
    });

    test('returns null when args is null', () {
      expect(firstPositiveInt(null, ['k']), isNull);
    });

    test('returns null for empty args', () {
      expect(firstPositiveInt(<String, Object?>{}, ['k']), isNull);
    });

    test('returns null when no key matches', () {
      final args = <String, Object?>{'z': 99};
      expect(firstPositiveInt(args, ['unknown']), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // parsePositiveInt
  // ---------------------------------------------------------------------------
  group('parsePositiveInt', () {
    test('returns int value when >= 1', () {
      expect(parsePositiveInt(5), equals(5));
    });

    test('returns int value for boundary 1', () {
      expect(parsePositiveInt(1), equals(1));
    });

    test('returns null for 0', () {
      expect(parsePositiveInt(0), isNull);
    });

    test('returns null for negative int', () {
      expect(parsePositiveInt(-1), isNull);
    });

    test('returns int from positive double (truncated)', () {
      expect(parsePositiveInt(3.7), equals(3));
    });

    test('returns null for double < 1', () {
      expect(parsePositiveInt(0.5), isNull);
    });

    test('returns null for double.infinity', () {
      expect(parsePositiveInt(double.infinity), isNull);
    });

    test('returns null for double.nan', () {
      expect(parsePositiveInt(double.nan), isNull);
    });

    test('parses positive numeric string', () {
      expect(parsePositiveInt('10'), equals(10));
    });

    test('returns null for non-numeric string', () {
      expect(parsePositiveInt('hello'), isNull);
    });

    test('returns null for string "0"', () {
      expect(parsePositiveInt('0'), isNull);
    });

    test('returns null for string "-5"', () {
      expect(parsePositiveInt('-5'), isNull);
    });

    test('trims whitespace around numeric string', () {
      expect(parsePositiveInt('  7  '), equals(7));
    });

    test('returns null for null input', () {
      expect(parsePositiveInt(null), isNull);
    });

    test('returns null for bool input', () {
      expect(parsePositiveInt(true), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // splitLines
  // ---------------------------------------------------------------------------
  group('splitLines', () {
    test('splits multi-line text', () {
      expect(splitLines('a\nb\nc'), equals(['a', 'b', 'c']));
    });

    test('returns single element for single line', () {
      expect(splitLines('hello'), equals(['hello']));
    });

    test('returns empty list for empty string', () {
      expect(splitLines(''), isEmpty);
    });

    test('preserves empty trailing segment', () {
      expect(splitLines('a\n'), equals(['a', '']));
    });

    test('handles Windows-style line endings correctly', () {
      // \r\n splits to ['a\r', 'b']
      final result = splitLines('a\r\nb');
      expect(result, equals(['a\r', 'b']));
    });

    test('handles multiple consecutive newlines', () {
      expect(splitLines('a\n\nb'), equals(['a', '', 'b']));
    });
  });
}
