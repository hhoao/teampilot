import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

/// Inline resolver that replicates [DefaultAiToolFileTargetResolver] behavior
/// using [AiToolFileTargetRule] data types.  The real configurable resolver
/// lives in `package:teampilot/services/ai_history/tool_call_resolvers.dart`.
class _TestFileTargetResolver implements AiToolFileTargetResolver {
  const _TestFileTargetResolver({required this.rules});

  final List<AiToolFileTargetRule> rules;

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final toolLower = part.toolName.toLowerCase();
    AiToolFileTargetRule? rule;
    for (final candidate in rules) {
      if (candidate.toolNames.contains(toolLower)) {
        rule = candidate;
        break;
      }
    }
    if (rule == null) return null;

    final args = _toolCallArgsMap(part);
    final path = _firstNonEmptyString(args, rule.pathKeys);
    if (path == null) return null;

    final lines = _extractLines(args, part.argsText, rule);
    return AiToolFileTarget(path: path, startLine: lines.$1, endLine: lines.$2);
  }
}

Map<String, Object?>? _toolCallArgsMap(AiToolCallPart part) {
  if (part.args != null && part.args!.isNotEmpty) return part.args;
  final text = part.argsText?.trim();
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return {for (final e in decoded.entries) e.key.toString(): e.value};
  } catch (_) {
    return null;
  }
}

String? _firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

(int?, int?) _extractLines(
  Map<String, Object?>? args,
  String? argsText,
  AiToolFileTargetRule rule,
) {
  if (args != null) {
    if (rule.useOffsetLimit) {
      final offset = _parsePositiveInt(args['offset']);
      final limit = _parsePositiveInt(args['limit']);
      if (offset != null && limit != null) return (offset, offset + limit - 1);
    }

    final start = _firstPositiveInt(args, rule.startLineKeys);
    final end = _firstPositiveInt(args, rule.endLineKeys);
    if (start != null || end != null) {
      if (start == null && end != null) return (end, end);
      return (start, end);
    }
  }

  return _parseLineRangeFromArgsText(argsText);
}

int? _firstPositiveInt(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final parsed = _parsePositiveInt(args[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

int? _parsePositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value.isFinite && value >= 1) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

final _lineRangePattern = RegExp(r'L(\d+)(?:-(\d+))?');

(int?, int?) _parseLineRangeFromArgsText(String? argsText) {
  if (argsText == null || argsText.isEmpty) return (null, null);
  final match = _lineRangePattern.firstMatch(argsText);
  if (match == null) return (null, null);

  final start = int.tryParse(match.group(1)!);
  if (start == null || start < 1) return (null, null);

  final endGroup = match.group(2);
  if (endGroup == null) return (start, start);

  final end = int.tryParse(endGroup);
  if (end == null || end < 1) return (start, null);

  return (start, end);
}

void main() {
  final resolver = _TestFileTargetResolver(rules: [
    const AiToolFileTargetRule(
      toolNames: {'read', 'readfile', 'read_file'},
      useOffsetLimit: true,
    ),
    const AiToolFileTargetRule(
      toolNames: {'write', 'writefile', 'write_file', 'create', 'create_file'},
    ),
    const AiToolFileTargetRule(
      toolNames: {'edit', 'strreplace', 'applypatch', 'apply_patch'},
    ),
  ]);

  AiToolCallPart part({
    required String toolName,
    Map<String, Object?>? args,
    String? argsText,
  }) {
    return AiToolCallPart(
      toolCallId: 'tc1',
      toolName: toolName,
      args: args,
      argsText: argsText,
    );
  }

  group('_TestFileTargetResolver', () {
    test('Read file_path + offset/limit start 110 end 189', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'lib/foo.dart', 'offset': 110, 'limit': 80},
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/foo.dart');
      expect(target.startLine, 110);
      expect(target.endLine, 189);
    });

    test('WriteFile path; no lines', () {
      final target = resolver.resolve(
        part(toolName: 'WriteFile', args: {'path': 'lib/bar.dart'}),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/bar.dart');
      expect(target.startLine, isNull);
      expect(target.endLine, isNull);
    });

    test('StrReplace start_line/end_line', () {
      final target = resolver.resolve(
        part(
          toolName: 'StrReplace',
          args: {'file_path': 'lib/edit.dart', 'start_line': 5, 'end_line': 12},
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/edit.dart');
      expect(target.startLine, 5);
      expect(target.endLine, 12);
    });

    test('L-range from argsText', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'lib/history.dart'},
          argsText: 'Reading lib/history.dart L110-189',
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/history.dart');
      expect(target.startLine, 110);
      expect(target.endLine, 189);
    });

    test('Bash null; missing path null', () {
      expect(
        resolver.resolve(part(toolName: 'Bash', args: {'command': 'ls'})),
        isNull,
      );
      expect(
        resolver.resolve(
          part(toolName: 'Read', args: {'offset': 1, 'limit': 10}),
        ),
        isNull,
      );
    });

    test('case-insensitive tool names', () {
      final target = resolver.resolve(
        part(toolName: 'read_file', args: {'file_path': 'a.dart'}),
      );

      expect(target, isNotNull);
      expect(target!.path, 'a.dart');

      expect(
        resolver.resolve(part(toolName: 'WRITE', args: {'path': 'b.dart'}))
            ?.path,
        'b.dart',
      );
      expect(
        resolver
            .resolve(part(toolName: 'strreplace', args: {'path': 'c.dart'}))
            ?.path,
        'c.dart',
      );
    });

    test('file_path before path precedence', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'preferred.dart', 'path': 'ignored.dart'},
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'preferred.dart');
    });

    test('end_line without start_line single line at end', () {
      final target = resolver.resolve(
        part(
          toolName: 'StrReplace',
          args: {'file_path': 'lib/edit.dart', 'end_line': 12},
        ),
      );

      expect(target, isNotNull);
      expect(target!.startLine, 12);
      expect(target.endLine, 12);
    });

    test('L110 single-line from argsText', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'lib/single.dart'},
          argsText: 'Reading lib/single.dart L110',
        ),
      );

      expect(target, isNotNull);
      expect(target!.startLine, 110);
      expect(target.endLine, 110);
    });

    test('camelCase startLine/endLine args', () {
      final target = resolver.resolve(
        part(
          toolName: 'Edit',
          args: {
            'path': 'lib/camel.dart',
            'startLine': 3,
            'endLine': 7,
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/camel.dart');
      expect(target.startLine, 3);
      expect(target.endLine, 7);
    });

    test('file and target_file path keys', () {
      expect(
        resolver
            .resolve(
              part(toolName: 'Create', args: {'file': 'lib/create.dart'}),
            )
            ?.path,
        'lib/create.dart',
      );
      expect(
        resolver
            .resolve(
              part(
                toolName: 'ApplyPatch',
                args: {'target_file': 'lib/patch.dart'},
              ),
            )
            ?.path,
        'lib/patch.dart',
      );
    });
  });
}
