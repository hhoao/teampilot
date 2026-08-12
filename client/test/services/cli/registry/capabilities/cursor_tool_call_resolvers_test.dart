import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/tool_call_resolvers.dart';

AiToolCallPart part(String name, {String? argsText, Map<String, Object?>? args}) {
  return AiToolCallPart(
    toolCallId: 'call_1',
    toolName: name,
    args: args,
    argsText: argsText,
  );
}

void main() {
  const cursor = CursorToolCallResolvers();

  group('shell（既有覆写不回归）', () {
    // 夹具实测：chat-aaaa-bbbb-cccc-dddd.jsonl Shell{command:"pwd"}、
    // chat-shell-missing-result.jsonl Shell{command,description}——description
    // 是 CursorTerminalToolResultEnricher tier1 匹配（description==title）的前提。
    test('Shell{command, description} 解析出命令与描述', () {
      final target = cursor.shellResolver.resolve(part(
        'Shell',
        args: {
          'command': 'pwd',
          'description': 'pwd',
        },
      ));
      expect(target, isNotNull);
      expect(target!.command, 'pwd');
      expect(target.description, 'pwd');
    });

    test('execute 别名解析出命令（cursor 专属覆写，spl@93c9991 快照未见，前瞻条目）',
        () {
      final target =
          cursor.shellResolver.resolve(part('execute', args: {'command': 'ls'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls');
    });

    test('共享 shell 别名集合全部可解析（追加语义，未替换共享名集）', () {
      for (final name in [
        'bash',
        'shell',
        'run_terminal_cmd',
        'shell_command',
        'exec_command',
        'run_shell_command',
      ]) {
        final target =
            cursor.shellResolver.resolve(part(name, args: {'command': 'pwd'}));
        expect(target, isNotNull, reason: '$name 应可解析');
        expect(target!.command, 'pwd');
      }
    });

    test('非 shell 工具不误命中 shell 解析器', () {
      expect(cursor.shellResolver.resolve(part('Read', args: {'path': 'a.txt'})),
          isNull);
    });
  });

  group('file / edit（G-4 证据固化）', () {
    // 矩阵 G-4：StrReplace/Write/EditNotebook 参数 key 仅 spl 散文级证据
    // （spl:cursor.md:244-254），夹具无工具行——共享 codec 键集已覆盖时按
    // 「证据不足非缺口」用断言固化可解析性（夹具增补留待 Task 6 回填）。
    test('StrReplace{file_path, old_string, new_string} 解析出 hunk', () {
      final target = cursor.editResolver.resolve(part(
        'StrReplace',
        args: {
          'file_path': 'a.txt',
          'old_string': 'foo',
          'new_string': 'bar',
        },
      ));
      expect(target, isNotNull, reason: 'StrReplace 应经共享 str-replace codec 解析');
      expect(target!.hunk.path, 'a.txt');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.remove).text, 'foo');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.add).text, 'bar');
    });

    test('StrReplace 带 replace_all 参数仍可解析（spl:cursor.md:244-245 散文 key）', () {
      final target = cursor.editResolver.resolve(part(
        'StrReplace',
        args: {
          'file_path': 'a.txt',
          'old_string': 'foo',
          'new_string': 'bar',
          'replace_all': true,
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.addedCount, 1);
      expect(target.hunk.removedCount, 1);
    });

    test('EditNotebook{notebook_path, new_source} 解析出 hunk（Task 2 共享键集）', () {
      final target = cursor.editResolver.resolve(part(
        'EditNotebook',
        args: {
          'notebook_path': '/tmp/demo.ipynb',
          'new_source': 'print(1)',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/tmp/demo.ipynb');
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.removedCount, 0);
    });

    test('Write{file_path, content} 解析出 hunk', () {
      final target = cursor.editResolver.resolve(part(
        'Write',
        args: {
          'file_path': 'new.txt',
          'content': 'line1\nline2',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'new.txt');
      expect(target.hunk.addedCount, 2);
    });

    test('Read{path} 解析出文件目标（夹具实测 key，agent_transcript_no_tool_id.jsonl）',
        () {
      final target = cursor.fileResolver.resolve(part(
        'Read',
        args: {'path': '/tmp/demo/SKILL.md'},
      ));
      expect(target, isNotNull);
      expect(target!.path, '/tmp/demo/SKILL.md');
    });
  });

  group('category（G-3）', () {
    test('AskQuestion 归类为 askUser（矩阵 G-3：askquestion→askUser）', () {
      expect(
        cursor.categoryResolver.resolve(part('AskQuestion', args: {})),
        AiToolCallCategory.askUser,
      );
    });

    test('已覆盖工具不回归：TodoWrite→task、WebSearch/WebFetch→search、Glob/Grep→read',
        () {
      expect(
        cursor.categoryResolver.resolve(part('TodoWrite', args: {})),
        AiToolCallCategory.task,
      );
      expect(
        cursor.categoryResolver.resolve(part('WebSearch', args: {})),
        AiToolCallCategory.search,
      );
      expect(
        cursor.categoryResolver.resolve(part('WebFetch', args: {})),
        AiToolCallCategory.search,
      );
      expect(
        cursor.categoryResolver.resolve(part('Glob', args: {})),
        AiToolCallCategory.read,
      );
      expect(
        cursor.categoryResolver.resolve(part('Grep', args: {})),
        AiToolCallCategory.read,
      );
    });

    test('mcp__ 前缀规则生效', () {
      expect(
        cursor.categoryResolver.resolve(part('mcp__filesystem_read', args: {})),
        AiToolCallCategory.mcp,
      );
    });

    test('SwitchMode/SemanticSearch/Delete/GenerateImage 落 other（矩阵接受差异固化）',
        () {
      // 矩阵 cursor Category 格：这些工具无自然类别，落 other 可显示但不细分
      // （同 codex update_plan 先例「→other（可接受）」）；如需归类属有意变更。
      for (final name in ['SwitchMode', 'SemanticSearch', 'Delete', 'GenerateImage']) {
        expect(
          cursor.categoryResolver.resolve(part(name, args: {})),
          AiToolCallCategory.other,
          reason: '$name 应落 other（接受差异）',
        );
      }
    });
  });

  group('subagent', () {
    test('agent/task 归类为 subagent', () {
      expect(
        cursor.categoryResolver.resolve(part('agent', args: {})),
        AiToolCallCategory.subagent,
      );
      expect(
        cursor.categoryResolver.resolve(part('task', args: {})),
        AiToolCallCategory.subagent,
      );
    });

    test('subagentToolNames 含 agent/task', () {
      expect(
        CursorAiHistoryCapability(shellResolver: cursor.shellResolver)
            .subagentToolNames,
        containsAll(['agent', 'task']),
      );
    });
  });
}
