import 'package:ai_message_core/ai_message_core.dart';

import 'edit_codecs/tool_args.dart';

final Expando<AiEditToolTarget> _editTargetCache = Expando();

/// Chains [codecs], tries each in order, and returns the first [AiEditHunk]
/// any codec produces for [part].
///
/// Each codec is asked `matches()` first; when it matches, `encode()` is
/// called.  The first non-null hunk wins.
///
/// Successful results are cached on [part] identity so History `build()`
/// does not re-split Write/Edit payloads every frame.
class ConfigurableAiEditToolTargetResolver
    implements AiEditToolTargetResolver {
  const ConfigurableAiEditToolTargetResolver({required this.codecs});

  /// Codecs tried in order for each tool call.
  final List<AiEditHunkCodec> codecs;

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    final cached = _editTargetCache[part];
    if (cached != null) return cached;
    for (final codec in codecs) {
      if (!codec.matches(part.toolName)) continue;
      final hunk = codec.encode(part);
      if (hunk != null) {
        final target = AiEditToolTarget(hunk: hunk);
        _editTargetCache[part] = target;
        return target;
      }
    }
    return null;
  }
}

/// Matches [rules] by [AiToolFileTargetRule.toolNames] (case-insensitive),
/// extracts a file path and optional line range from the tool-call arguments
/// using the shared [tool_args] utilities.
class ConfigurableAiToolFileTargetResolver
    implements AiToolFileTargetResolver {
  const ConfigurableAiToolFileTargetResolver({required this.rules});

  /// Rules tried in order; the first whose [AiToolFileTargetRule.toolNames]
  /// contains the lower-cased tool name is used.
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

    final args = toolCallArgsMap(part);
    final path = firstNonEmptyString(args, rule.pathKeys);
    if (path == null) return null;

    final lines = _extractLines(args, part.argsText, rule);
    return AiToolFileTarget(
      path: path,
      startLine: lines.$1,
      endLine: lines.$2,
    );
  }

  static (int?, int?) _extractLines(
    Map<String, Object?>? args,
    String? argsText,
    AiToolFileTargetRule rule,
  ) {
    if (args != null) {
      if (rule.useOffsetLimit) {
        final offset = parsePositiveInt(args['offset']);
        final limit = parsePositiveInt(args['limit']);
        if (offset != null && limit != null) {
          return (offset, offset + limit - 1);
        }
      }

      final start = firstPositiveInt(args, rule.startLineKeys);
      final end = firstPositiveInt(args, rule.endLineKeys);
      if (start != null || end != null) {
        if (start == null && end != null) return (end, end);
        return (start, end);
      }
    }

    return _parseLineRangeFromArgsText(argsText);
  }

  static final _lineRangePattern = RegExp(r'L(\d+)(?:-(\d+))?');

  static (int?, int?) _parseLineRangeFromArgsText(String? argsText) {
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
}

/// Matches [toolNames] (case-insensitive), extracts the shell command and an
/// optional description from the tool-call arguments using the shared
/// [tool_args] utilities.
class ConfigurableAiShellToolTargetResolver
    implements AiShellToolTargetResolver {
  const ConfigurableAiShellToolTargetResolver({
    required this.toolNames,
    this.commandKeys = const ['command', 'cmd', 'CommandLine'],
  });

  /// Tool names to match, compared case-insensitively.
  final Set<String> toolNames;

  /// Argument keys searched in order for the shell command.
  final List<String> commandKeys;

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;

    final args = toolCallArgsMap(part);
    final command = firstNonEmptyString(args, commandKeys);
    if (command == null) return null;

    final description = firstNonEmptyString(args, const ['description']);
    return AiShellToolTarget(command: command, description: description);
  }
}
