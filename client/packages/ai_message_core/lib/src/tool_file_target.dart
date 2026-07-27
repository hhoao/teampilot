import 'message.dart';

class AiToolFileTarget {
  const AiToolFileTarget({
    required this.path,
    this.startLine,
    this.endLine,
  });

  final String path;
  final int? startLine;
  final int? endLine;
}

abstract class AiToolFileTargetResolver {
  AiToolFileTarget? resolve(AiToolCallPart part);
}

class AiToolFileTargetRule {
  const AiToolFileTargetRule({
    required this.toolNames,
    this.pathKeys = const ['file_path', 'path', 'file', 'target_file'],
    this.startLineKeys = const ['start_line', 'startLine'],
    this.endLineKeys = const ['end_line', 'endLine'],
    this.useOffsetLimit = false,
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> startLineKeys;
  final List<String> endLineKeys;
  final bool useOffsetLimit;
}

class DefaultAiToolFileTargetResolver implements AiToolFileTargetResolver {
  const DefaultAiToolFileTargetResolver({this.rules = defaultRules});

  final List<AiToolFileTargetRule> rules;

  static const defaultRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: {'read', 'readfile', 'read_file'},
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: {
        'write',
        'writefile',
        'write_file',
        'create',
        'create_file',
      },
    ),
    AiToolFileTargetRule(
      toolNames: {
        'edit',
        'strreplace',
        'applypatch',
        'editnotebook',
        'notebookedit',
      },
    ),
  ];

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

    final path = _firstNonEmptyString(part.args, rule.pathKeys);
    if (path == null) return null;

    final lines = _extractLines(part, rule);
    return AiToolFileTarget(
      path: path,
      startLine: lines.$1,
      endLine: lines.$2,
    );
  }
}

class CompositeAiToolFileTargetResolver implements AiToolFileTargetResolver {
  const CompositeAiToolFileTargetResolver(this.resolvers);

  final List<AiToolFileTargetResolver> resolvers;

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    for (final resolver in resolvers) {
      final target = resolver.resolve(part);
      if (target != null) return target;
    }
    return null;
  }
}

String? _firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

(int?, int?) _extractLines(AiToolCallPart part, AiToolFileTargetRule rule) {
  final args = part.args;
  if (args != null) {
    if (rule.useOffsetLimit) {
      final offset = _parsePositiveInt(args['offset']);
      final limit = _parsePositiveInt(args['limit']);
      if (offset != null && limit != null) {
        return (offset, offset + limit - 1);
      }
    }

    final start = _firstPositiveInt(args, rule.startLineKeys);
    final end = _firstPositiveInt(args, rule.endLineKeys);
    if (start != null || end != null) {
      if (start == null && end != null) return (end, end);
      return (start, end);
    }
  }

  return _parseLineRangeFromArgsText(part.argsText);
}

int? _firstPositiveInt(Map<String, Object?> args, List<String> keys) {
  for (final key in keys) {
    final parsed = _parsePositiveInt(args[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

int? _parsePositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value >= 1) return value.toInt();
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
