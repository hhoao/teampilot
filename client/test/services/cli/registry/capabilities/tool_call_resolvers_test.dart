import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/codex/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/tool_call_resolvers.dart';

AiToolCallPart part(String name, {String? argsText, Map<String, Object?>? args}) {
  return AiToolCallPart(
    toolCallId: 'call_1',
    toolName: name,
    args: args,
    argsText: argsText,
  );
}

void main() {
  const claude = ClaudeToolCallResolvers();
  const codex = CodexToolCallResolvers();
  const flashskyai = FlashskyaiToolCallResolvers();

  group('claude', () {
    // spl@93c9991: Edit{file_path,old_string,new_string,replace_all}
    // (claude-code-sonnet-5.md:1282-1312), Write{file_path,content}
    // (:2868-2888), Read{file_path,offset,limit,pages} (:1829-1860),
    // Bash{command,timeout,description} (:882-912), NotebookEdit
    // {notebook_path,new_source} (:1725).
    test('Edit 工具解析出 hunk（file_path/old_string/new_string）', () {
      final target = claude.editResolver.resolve(part(
        'Edit',
        args: {
          'file_path': 'a.txt',
          'old_string': 'foo',
          'new_string': 'bar',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'a.txt');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.remove).text, 'foo');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.add).text, 'bar');
    });

    test('NotebookEdit 工具解析出 hunk（notebook_path/new_source）', () {
      final target = claude.editResolver.resolve(part(
        'NotebookEdit',
        args: {
          'notebook_path': '/tmp/demo.ipynb',
          'cell_id': 'abc123',
          'new_source': 'print(1)',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/tmp/demo.ipynb');
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.removedCount, 0);
    });

    test('Write 工具解析出 hunk（file_path/content）', () {
      final target = claude.editResolver.resolve(part(
        'Write',
        args: {
          'file_path': 'new.txt',
          'content': 'line1\nline2',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'new.txt');
      expect(target.hunk.addedCount, 2);
      expect(target.hunk.removedCount, 0);
    });

    test('Read 工具解析出文件目标（file_path/offset/limit → 行区间）', () {
      final target = claude.fileResolver.resolve(part(
        'Read',
        args: {
          'file_path': 'a.dart',
          'offset': 10,
          'limit': 5,
        },
      ));
      expect(target, isNotNull);
      expect(target!.path, 'a.dart');
      expect(target.startLine, 10);
      expect(target.endLine, 14);
    });

    test('Bash 工具解析出命令', () {
      final target =
          claude.shellResolver.resolve(part('Bash', args: {'command': 'ls -la'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls -la');
    });

    test('Agent/Workflow 工具归类为 subagent', () {
      expect(
        claude.categoryResolver.resolve(part('Agent', args: {})),
        AiToolCallCategory.subagent,
      );
      expect(
        claude.categoryResolver.resolve(part('Workflow', args: {})),
        AiToolCallCategory.subagent,
      );
    });

    test('EnterPlanMode 归类为 plan；TaskGet/TaskList/TaskOutput/TaskStop 归类为 task',
        () {
      expect(
        claude.categoryResolver.resolve(part('EnterPlanMode', args: {})),
        AiToolCallCategory.plan,
      );
      for (final name in ['TaskGet', 'TaskList', 'TaskOutput', 'TaskStop']) {
        expect(
          claude.categoryResolver.resolve(part(name, args: {})),
          AiToolCallCategory.task,
          reason: '$name 应归类为 task',
        );
      }
    });

    test('Glob/Grep 归类为 read（npm/Windows 构建工具面，G-6 观察项）', () {
      expect(
        claude.categoryResolver.resolve(part('Glob', args: {})),
        AiToolCallCategory.read,
      );
      expect(
        claude.categoryResolver.resolve(part('Grep', args: {})),
        AiToolCallCategory.read,
      );
    });

    test('subagentToolNames 含 agent/task/workflow', () {
      expect(
        const ClaudeAiHistoryCapability().subagentToolNames,
        containsAll(['agent', 'task', 'workflow']),
      );
    });
  });

  group('codex', () {
    // spl@93c9991 codex-full.md: apply_patch 为 FREEFORM（:547），
    // grammar（:550-572）：`*** Begin Patch` / `*** Update File: <path>` /
    // `*** Add File: <path>` / `@@` context 标记 / `+`/`-`/` ` 行前缀；
    // codex adapter 把非 JSON arguments 放 argsText（ai_transcript.dart:426-432）。
    test('apply_patch FREEFORM（argsText 直接是 patch 文本）解析出 hunk', () {
      final target = codex.editResolver.resolve(part(
        'apply_patch',
        argsText: '''*** Begin Patch
*** Update File: lib/foo.dart
@@ -1,2 +1,3 @@
-removed
+added
*** End Patch''',
      ));
      expect(target, isNotNull, reason: 'FREEFORM argsText 应能提取 hunk');
      expect(target!.hunk.path, 'lib/foo.dart');
      expect(target.hunk.removedCount, 1);
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.remove).text, 'removed');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.add).text, 'added');
    });

    test('apply_patch FREEFORM 的 Add File hunk 提取路径', () {
      final target = codex.editResolver.resolve(part(
        'apply_patch',
        argsText: '''*** Begin Patch
*** Add File: README.md
+hello
*** End Patch''',
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'README.md');
      expect(target.hunk.addedCount, 1);
    });

    test('exec_command{cmd} 解析出命令', () {
      final target =
          codex.shellResolver.resolve(part('exec_command', args: {'cmd': 'ls'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls');
    });

    test('shell_command{command} 解析出命令', () {
      final target = codex.shellResolver.resolve(
        part('shell_command', args: {'command': 'pwd'}),
      );
      expect(target, isNotNull);
      expect(target!.command, 'pwd');
    });

    test('spawn_agent 归类为 subagent；apply_patch 归类为 edit', () {
      expect(
        codex.categoryResolver.resolve(part('spawn_agent', args: {})),
        AiToolCallCategory.subagent,
      );
      expect(
        codex.categoryResolver.resolve(part('apply_patch', args: {})),
        AiToolCallCategory.edit,
      );
    });
  });

  group('flashskyai', () {
    // G-5：夹具（streamed_tools.jsonl）只有 Read{file_path}/Bash{command,
    // description} 实测；Edit/Write 无夹具证据，但解析器复用共享 codec——
    // 用断言固化共享配置对这些工具的可解析性（矩阵：证据不足非缺口）。
    test('Edit 工具通过共享 codec 解析出 hunk（file_path/old_string/new_string）',
        () {
      final target = flashskyai.editResolver.resolve(part(
        'Edit',
        args: {
          'file_path': 'a.txt',
          'old_string': 'foo',
          'new_string': 'bar',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'a.txt');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.remove).text, 'foo');
      expect(target.hunk.lines.firstWhere((l) => l.kind == AiEditLineKind.add).text, 'bar');
    });

    test('Write 工具通过共享 codec 解析出 hunk（file_path/content）', () {
      final target = flashskyai.editResolver.resolve(part(
        'Write',
        args: {
          'file_path': 'b.txt',
          'content': 'line1\nline2',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'b.txt');
      expect(target.hunk.addedCount, 2);
    });

    test('Read{file_path} 解析出文件目标（夹具实测 key）', () {
      final target = flashskyai.fileResolver.resolve(part(
        'Read',
        args: {'file_path': '/tmp/demo/SKILL.md'},
      ));
      expect(target, isNotNull);
      expect(target!.path, '/tmp/demo/SKILL.md');
    });

    test('Bash{command, description} 解析出命令（夹具实测 key）', () {
      final target = flashskyai.shellResolver.resolve(part(
        'Bash',
        args: {
          'command': 'pwd',
          'description': 'List working directory contents',
        },
      ));
      expect(target, isNotNull);
      expect(target!.command, 'pwd');
      expect(target.description, 'List working directory contents');
    });

    test('agent/task 归类为 subagent（G-2 固化：run 侧无 workflow 解析，类别侧仍可解析）',
        () {
      expect(
        flashskyai.categoryResolver.resolve(part('agent', args: {})),
        AiToolCallCategory.subagent,
      );
      expect(
        flashskyai.categoryResolver.resolve(part('task', args: {})),
        AiToolCallCategory.subagent,
      );
      expect(
        flashskyai.categoryResolver.resolve(part('workflow', args: {})),
        AiToolCallCategory.subagent,
      );
    });

    test('G-2 接受差异固化：subagentToolNames 仅 agent/task（无 workflow run 侧解析）',
        () {
      expect(
        const FlashskyaiAiHistoryCapability().subagentToolNames,
        {'agent', 'task'},
      );
    });
  });
}
