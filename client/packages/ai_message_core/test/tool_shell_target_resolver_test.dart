import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultAiShellToolTargetResolver();

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

  test('no description → truncated command as summary', () {
    final long = 'x' * 120;
    final t = resolver.resolve(
      AiToolCallPart(
        toolCallId: '1',
        toolName: 'Shell',
        args: {'command': long},
      ),
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

  test('missing command → null', () {
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

  test('non-shell tool → null', () {
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
