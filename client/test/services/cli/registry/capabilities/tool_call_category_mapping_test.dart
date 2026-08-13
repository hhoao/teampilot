import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();
  final clis = CliTool.values.where((c) => registry.tryGet(c) != null);

  AiToolCallPart tool(String name) =>
      AiToolCallPart(toolCallId: '1', toolName: name);

  test('every launch-supported CLI exposes a categoryResolver', () {
    for (final cli in clis) {
      final resolvers = registry.toolCallResolvers(cli);
      expect(resolvers, isNotNull, reason: '$cli');
      expect(resolvers!.categoryResolver, isNotNull, reason: '$cli');
    }
  });

  test('core tools map identically across CLIs', () {
    for (final cli in clis) {
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      expect(resolver.resolve(tool('bash')), AiToolCallCategory.command,
          reason: '$cli');
      expect(resolver.resolve(tool('read')), AiToolCallCategory.read,
          reason: '$cli');
      expect(resolver.resolve(tool('write')), AiToolCallCategory.write,
          reason: '$cli');
      expect(resolver.resolve(tool('strreplace')), AiToolCallCategory.edit,
          reason: '$cli');
      expect(resolver.resolve(tool('mcp__foo')), AiToolCallCategory.mcp,
          reason: '$cli');
      expect(resolver.resolve(tool('unknown_x')), AiToolCallCategory.other,
          reason: '$cli');
    }
  });

  test('cursor maps execute to command', () {
    final resolver = registry.toolCallResolvers(CliTool.cursor)!
        .categoryResolver;
    expect(resolver.resolve(tool('execute')), AiToolCallCategory.command);
  });

  test('opencode-origin tools question resolves to askUser (Task 6 决策统一)，'
      'skill 显式 other（矩阵 G-3）', () {
    for (final cli in clis) {
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      expect(resolver.resolve(tool('question')), AiToolCallCategory.askUser,
          reason: '$cli');
      expect(resolver.resolve(tool('skill')), AiToolCallCategory.other,
          reason: '$cli');
    }
  });

  test('subagentToolNames consistency: every name resolves to subagent', () {
    for (final cli in clis) {
      final history = registry.capability<AiHistoryCapability>(cli)!;
      final resolver = registry.toolCallResolvers(cli)!.categoryResolver;
      for (final name in history.subagentToolNames) {
        expect(resolver.resolve(tool(name)), AiToolCallCategory.subagent,
            reason: '$cli/$name');
      }
    }
  });

  test('类别表 union 集精确钉死（等价 golden 快照，Task 2 审计补齐）', () {
    // defaultToolCallNameRules = 五 CLI 工具名 union（附录 A）；全表深比较：
    // 键集与类别映射同时钉死，任何改名/改类须同步此处。
    const expected = <String, AiToolCallCategory>{
      // read
      'read': AiToolCallCategory.read,
      'readfile': AiToolCallCategory.read,
      'read_file': AiToolCallCategory.read,
      'glob': AiToolCallCategory.read,
      'grep': AiToolCallCategory.read,
      'list': AiToolCallCategory.read,
      'list_files': AiToolCallCategory.read,
      'file_search': AiToolCallCategory.read,
      'search_files': AiToolCallCategory.read,
      'grep_search': AiToolCallCategory.read,
      // write
      'write': AiToolCallCategory.write,
      'writefile': AiToolCallCategory.write,
      'write_file': AiToolCallCategory.write,
      'create': AiToolCallCategory.write,
      'create_file': AiToolCallCategory.write,
      'createfile': AiToolCallCategory.write,
      // edit
      'strreplace': AiToolCallCategory.edit,
      'edit': AiToolCallCategory.edit,
      'editnotebook': AiToolCallCategory.edit,
      'notebookedit': AiToolCallCategory.edit,
      'multi_edit': AiToolCallCategory.edit,
      'applypatch': AiToolCallCategory.edit,
      'apply_patch': AiToolCallCategory.edit,
      // command
      'bash': AiToolCallCategory.command,
      'shell': AiToolCallCategory.command,
      'shell_command': AiToolCallCategory.command,
      'exec_command': AiToolCallCategory.command,
      'run_shell_command': AiToolCallCategory.command,
      'run_terminal_cmd': AiToolCallCategory.command,
      'zsh': AiToolCallCategory.command,
      'sh': AiToolCallCategory.command,
      'execute': AiToolCallCategory.command,
      // search
      'websearch': AiToolCallCategory.search,
      'web_search': AiToolCallCategory.search,
      'webfetch': AiToolCallCategory.search,
      'web_fetch': AiToolCallCategory.search,
      'fetch': AiToolCallCategory.search,
      'url_fetch': AiToolCallCategory.search,
      'search_web': AiToolCallCategory.search,
      // browser
      'browser': AiToolCallCategory.browser,
      'browser_navigate': AiToolCallCategory.browser,
      'browser_click': AiToolCallCategory.browser,
      'browser_type': AiToolCallCategory.browser,
      'browser_act': AiToolCallCategory.browser,
      'playwright': AiToolCallCategory.browser,
      'computer': AiToolCallCategory.browser,
      'computer_use': AiToolCallCategory.browser,
      // subagent（union of subagentToolNames + 前瞻）
      'agent': AiToolCallCategory.subagent,
      'task': AiToolCallCategory.subagent,
      'workflow': AiToolCallCategory.subagent,
      'spawn_agent': AiToolCallCategory.subagent,
      'agentdelegate': AiToolCallCategory.subagent,
      'subagent': AiToolCallCategory.subagent,
      // askUser
      'askuserquestion': AiToolCallCategory.askUser,
      'ask_user_question': AiToolCallCategory.askUser,
      'ask_user': AiToolCallCategory.askUser,
      'askquestion': AiToolCallCategory.askUser,
      'question': AiToolCallCategory.askUser,
      // plan
      'plan': AiToolCallCategory.plan,
      'enterplanmode': AiToolCallCategory.plan,
      'exitplanmode': AiToolCallCategory.plan,
      'exit_plan_mode': AiToolCallCategory.plan,
      // task
      'todowrite': AiToolCallCategory.task,
      'todo_write': AiToolCallCategory.task,
      'taskcreate': AiToolCallCategory.task,
      'task_create': AiToolCallCategory.task,
      'taskupdate': AiToolCallCategory.task,
      'task_update': AiToolCallCategory.task,
      'taskget': AiToolCallCategory.task,
      'tasklist': AiToolCallCategory.task,
      'taskoutput': AiToolCallCategory.task,
      'taskstop': AiToolCallCategory.task,
      // other（显式化：真实工具无细分类别，落 other）
      'skill': AiToolCallCategory.other,
    };
    expect(defaultToolCallNameRules, expected);
    expect(defaultToolCallPrefixRules, hasLength(1));
    expect(defaultToolCallPrefixRules.single,
        ('mcp__', AiToolCallCategory.mcp));
  });
}
