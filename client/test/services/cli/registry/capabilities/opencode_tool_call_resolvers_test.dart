import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/tool_call_resolvers.dart';

void main() {
  const resolvers = OpencodeToolCallResolvers();

  AiToolCallPart toolCall(String name, Map<String, Object?> args) {
    return AiToolCallPart(
      toolCallId: 'call-1',
      toolName: name,
      args: args,
    );
  }

  group('editResolver', () {
    test('edit with camelCase filePath/oldString/newString resolves to hunk',
        () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'filePath': '/src/main.dart',
        'oldString': 'hello',
        'newString': 'goodbye',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/src/main.dart');
      expect(target.hunk.removedCount, 1);
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.lines[0].kind, AiEditLineKind.remove);
      expect(target.hunk.lines[1].kind, AiEditLineKind.add);
    });

    test('write with camelCase filePath/content resolves to hunk', () {
      final target = resolvers.editResolver.resolve(toolCall('write', {
        'filePath': '/lib/app.dart',
        'content': 'line1\nline2',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/lib/app.dart');
      expect(target.hunk.addedCount, 2);
      expect(target.hunk.removedCount, 0);
    });

    test('legacy snake_case file_path still resolves', () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'file_path': '/old.dart',
        'old_string': 'a',
        'new_string': 'b',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/old.dart');
    });

    test('write with snake_case file_path/content still resolves', () {
      final target = resolvers.editResolver.resolve(toolCall('write', {
        'file_path': '/snake_write.dart',
        'content': 'a\nb',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/snake_write.dart');
      expect(target.hunk.addedCount, 2);
    });

    test('bash tool does not resolve as edit', () {
      final target =
          resolvers.editResolver.resolve(toolCall('bash', {'command': 'ls'}));
      expect(target, isNull);
    });
  });

  group('fileResolver', () {
    test('read with filePath + offset/limit resolves with line range', () {
      final target = resolvers.fileResolver.resolve(toolCall('read', {
        'filePath': '/a.dart',
        'offset': 10,
        'limit': 5,
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
      expect(target.startLine, 10);
      expect(target.endLine, 14);
    });

    test('read with snake_case file_path + offset/limit still resolves', () {
      final target = resolvers.fileResolver.resolve(toolCall('read', {
        'file_path': '/snake_read.dart',
        'offset': 3,
        'limit': 2,
      }));
      expect(target, isNotNull);
      expect(target!.path, '/snake_read.dart');
      expect(target.startLine, 3);
      expect(target.endLine, 4);
    });

    test('read with only filePath resolves without line range', () {
      final target =
          resolvers.fileResolver.resolve(toolCall('read', {'filePath': '/plain.dart'}));
      expect(target, isNotNull);
      expect(target!.path, '/plain.dart');
      expect(target.startLine, isNull);
      expect(target.endLine, isNull);
    });

    test('edit with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('edit', {
        'filePath': '/a.dart',
        'oldString': 'x',
        'newString': 'y',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
    });

    test('write with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('write', {
        'filePath': '/b.dart',
        'content': 'c',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/b.dart');
    });
  });

  group('shellResolver', () {
    test('bash with command resolves', () {
      final target =
          resolvers.shellResolver.resolve(toolCall('bash', {'command': 'ls -la'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls -la');
    });

    test('bash with timeout/workdir (本机实测 key 集) resolves command', () {
      final target = resolvers.shellResolver.resolve(toolCall('bash', {
        'command': 'flutter test',
        'timeout': 1000,
        'workdir': '/home/user/repo',
      }));
      expect(target, isNotNull);
      expect(target!.command, 'flutter test');
    });

    test('bash with description keeps description', () {
      final target = resolvers.shellResolver.resolve(toolCall('bash', {
        'command': 'ls',
        'description': 'List files',
      }));
      expect(target, isNotNull);
      expect(target!.description, 'List files');
    });
  });

  group('categoryResolver', () {
    AiToolCallPart named(String name) => toolCall(name, const {});

    test('question resolves to askUser（Task 6 决策：跨 CLI 统一为 askUser）', () {
      expect(resolvers.categoryResolver.resolve(named('question')),
          AiToolCallCategory.askUser);
    });

    test('skill resolves explicitly to other (矩阵 G-3)', () {
      expect(resolvers.categoryResolver.resolve(named('skill')),
          AiToolCallCategory.other);
    });

    test('matrix tool set maps to their categories', () {
      const expected = <String, AiToolCallCategory>{
        'bash': AiToolCallCategory.command,
        'read': AiToolCallCategory.read,
        'write': AiToolCallCategory.write,
        'edit': AiToolCallCategory.edit,
        'grep': AiToolCallCategory.read,
        'glob': AiToolCallCategory.read,
        'task': AiToolCallCategory.subagent,
        'todowrite': AiToolCallCategory.task,
        'webfetch': AiToolCallCategory.search,
      };
      expected.forEach((name, category) {
        expect(resolvers.categoryResolver.resolve(named(name)), category,
            reason: name);
      });
    });

    test('mcp__ prefix maps to mcp', () {
      expect(resolvers.categoryResolver.resolve(named('mcp__files')),
          AiToolCallCategory.mcp);
    });

    test('fallback tool name maps to other', () {
      expect(resolvers.categoryResolver.resolve(named('tool')),
          AiToolCallCategory.other);
    });
  });

  group('生效映射集精确钉死（Task 2 审计补齐）', () {
    // opencode 生效集 = 共享集 + camelCase 追加（filePath/oldString/
    // newString）；cursor 特有键（path/contents）不得泄漏进 opencode。
    test('edit/write/read 的 path 与 write contents 使用 cursor 特有键时不解析',
        () {
      expect(
        resolvers.editResolver.resolve(toolCall('edit', {
          'path': '/a.txt',
          'oldString': 'x',
          'newString': 'y',
        })),
        isNull,
        reason: 'path 为 cursor 特有键（G-4），opencode 生效键集无',
      );
      expect(
        resolvers.editResolver.resolve(toolCall('write', {
          'filePath': '/a.txt',
          'contents': 'c',
        })),
        isNull,
        reason: 'contents 为 cursor 特有键（G-4），opencode 生效键集无',
      );
      expect(
        resolvers.fileResolver.resolve(toolCall('read', {'path': '/a.dart'})),
        isNull,
        reason: 'read 的 path 不在 opencode 生效键集（file_path/filePath）',
      );
    });

    test('shell 生效集恰为共享集 {bash, shell_command, exec_command}，'
        'cursor 覆写名不泄漏', () {
      for (final name in ['bash', 'shell_command', 'exec_command']) {
        final target =
            resolvers.shellResolver.resolve(toolCall(name, {'command': 'pwd'}));
        expect(target, isNotNull, reason: '$name 应在 opencode 生效集');
        expect(target!.command, 'pwd');
      }
      for (final name in [
        'shell',
        'execute',
        'run_terminal_cmd',
        'run_shell_command',
        'zsh',
        'sh',
      ]) {
        expect(
          resolvers.shellResolver
              .resolve(toolCall(name, {'command': 'pwd'})),
          isNull,
          reason: '$name 不在 opencode 生效集',
        );
      }
    });
  });

  group('subagentToolNames', () {
    test('opencode subagent set is exactly {task}', () {
      expect(const OpencodeAiHistoryCapability().subagentToolNames, {'task'});
    });

    test('task resolves to subagent category', () {
      expect(resolvers.categoryResolver.resolve(toolCall('task', const {})),
          AiToolCallCategory.subagent);
    });
  });
}
