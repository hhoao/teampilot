import 'dart:convert';

import 'message.dart';

class AiShellToolTarget {
  const AiShellToolTarget({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;

  static const summaryMaxChars = 80;

  /// Header label: non-empty description, else truncated command.
  String get summary {
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return truncateCommand(command);
  }

  static String truncateCommand(String command) {
    final oneLine = command.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= summaryMaxChars) return oneLine;
    return '${oneLine.substring(0, summaryMaxChars)}…';
  }
}

abstract class AiShellToolTargetResolver {
  AiShellToolTarget? resolve(AiToolCallPart part);
}

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

  static const _commandKeys = ['command', 'cmd', 'CommandLine'];

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;

    final map = _argsMap(part);
    final command = _firstNonEmptyString(map, _commandKeys);
    if (command == null) return null;

    final description = _firstNonEmptyString(map, const ['description']);
    return AiShellToolTarget(command: command, description: description);
  }
}

Map<String, Object?>? _argsMap(AiToolCallPart part) {
  if (part.args != null && part.args!.isNotEmpty) return part.args;
  final text = part.argsText?.trim();
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return {
      for (final e in decoded.entries) e.key.toString(): e.value,
    };
  } catch (_) {
    return null;
  }
}

String? _firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
