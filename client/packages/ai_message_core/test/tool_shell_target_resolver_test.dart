import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

/// Inline resolver that replicates [DefaultAiShellToolTargetResolver] behavior.
/// The real configurable resolver lives in
/// `package:teampilot/services/ai_history/tool_call_resolvers.dart`.
class _TestShellTargetResolver implements AiShellToolTargetResolver {
  const _TestShellTargetResolver({
    required this.toolNames,
    this.commandKeys = const ['command', 'cmd', 'CommandLine'],
  });

  final Set<String> toolNames;
  final List<String> commandKeys;

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;

    final map = _argsMap(part);
    final command = _firstNonEmptyString(map, commandKeys);
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
    return {for (final e in decoded.entries) e.key.toString(): e.value};
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

void main() {
  final resolver = _TestShellTargetResolver(
    toolNames: {
      'bash',
      'shell',
      'shell_command',
      'exec_command',
      'run_shell_command',
      'run_terminal_cmd',
      'execute',
    },
  );

  test('Bash command + description', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Bash',
        args: {
          'command': 'git status --short',
          'description': 'Check worktree git state',
        },
      ),
    );
    expect(t?.command, 'git status --short');
    expect(t?.description, 'Check worktree git state');
    expect(t?.summary, 'Check worktree git state');
  });

  test('no description truncated command as summary', () {
    final long = 'x' * 120;
    final t = resolver.resolve(
      AiToolCallPart(toolCallId: '1', toolName: 'Shell', args: {'command': long}),
    );
    expect(t?.command, long);
    expect(t?.description, isNull);
    expect(t!.summary.length, lessThanOrEqualTo(81)); // 80 + ellipsis
    expect(t.summary.endsWith('…'), isTrue);
  });

  test('cmd / CommandLine key aliases', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'run_terminal_cmd',
              args: {'cmd': 'ls'},
            ),
          )
          ?.command,
      'ls',
    );
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'Execute',
              args: {'CommandLine': 'pwd'},
            ),
          )
          ?.command,
      'pwd',
    );
  });

  test('command preferred over cmd', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'bash',
        args: {'command': 'echo a', 'cmd': 'echo b'},
      ),
    );
    expect(t?.command, 'echo a');
  });

  test('argsText JSON fallback', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'shell_command',
        argsText: '{"command":"uname","description":"Show kernel"}',
      ),
    );
    expect(t?.command, 'uname');
    expect(t?.description, 'Show kernel');
  });

  test('shell name set coverage', () {
    for (final name in [
      'Bash',
      'Shell',
      'bash',
      'shell_command',
      'exec_command',
      'run_shell_command',
      'run_terminal_cmd',
      'Execute',
    ]) {
      expect(
        resolver
            .resolve(
              AiToolCallPart(
                toolCallId: '1',
                toolName: name,
                args: const {'command': 'true'},
              ),
            )
            ?.command,
        'true',
        reason: name,
      );
    }
  });

  test('missing command null', () {
    expect(
      resolver.resolve(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Bash',
          args: {'description': 'noop'},
        ),
      ),
      isNull,
    );
  });

  test('non-shell tool null', () {
    expect(
      resolver.resolve(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Read',
          args: {'command': 'ls', 'file_path': 'a.dart'},
        ),
      ),
      isNull,
    );
  });
}
