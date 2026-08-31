import 'package:ai_message_core/ai_message_core.dart';

/// Package-level default [AiToolFileTargetResolver] used when the host does
/// not mount an [AiToolFileActionsScope].
///
/// Covers the cross-CLI tool-name union (read / write / create families) so
/// file summary chrome renders out of the box; per-CLI arg-key deltas stay in
/// the host's `ConfigurableAiToolFileTargetResolver` (client
/// `services/cli/registry/capabilities/shared_tool_call_resolvers.dart`).
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
        'createfile',
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

  static (int?, int?) _extractLines(
    AiToolCallPart part,
    AiToolFileTargetRule rule,
  ) {
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
        return (start, end);
      }
    }
    return (null, null);
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

/// Package-level default [AiEditToolTargetResolver]: null — the edit hunk
/// codecs are host-owned (client `services/ai_history/edit_codecs/`).
class NoopEditToolTargetResolver implements AiEditToolTargetResolver {
  const NoopEditToolTargetResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

/// Package-level default [AiShellToolTargetResolver]: extracts the shell
/// command for the cross-CLI bash/shell union. Per-CLI arg-key deltas stay
/// host-owned (client `ConfigurableAiShellToolTargetResolver`).
class DefaultAiShellToolTargetResolver implements AiShellToolTargetResolver {
  const DefaultAiShellToolTargetResolver({
    this.toolNames = defaultToolNames,
  });

  final Set<String> toolNames;

  static const defaultToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
    'execute',
  };

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;
    final command = _firstNonEmptyString(
      part.args,
      const ['command', 'cmd', 'CommandLine'],
    );
    if (command == null) return null;
    final description = _firstNonEmptyString(
      part.args,
      const ['description'],
    );
    return AiShellToolTarget(command: command, description: description);
  }
}
