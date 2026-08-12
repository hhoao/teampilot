import 'package:ai_message_core/ai_message_core.dart';

/// Exact-name → category table (lowercase keys) plus ordered prefix rules.
class ConfigurableAiToolCallCategoryResolver
    implements AiToolCallCategoryResolver {
  const ConfigurableAiToolCallCategoryResolver({
    this.nameRules = const {},
    this.prefixRules = const [],
  });

  /// Lowercase exact tool names; first match wins.
  final Map<String, AiToolCallCategory> nameRules;

  /// Ordered (prefix, category); first match wins.
  final List<(String, AiToolCallCategory)> prefixRules;

  @override
  AiToolCallCategory resolve(AiToolCallPart part) {
    final name = part.toolName.toLowerCase();
    final exact = nameRules[name];
    if (exact != null) return exact;
    for (final (prefix, category) in prefixRules) {
      if (name.startsWith(prefix)) return category;
    }
    return AiToolCallCategory.other;
  }
}

/// 共享默认表(附录 A):union of all 5 CLIs' tool names. subagent 集合为各
/// CLI AiHistoryCapability.subagentToolNames 的并集 + 前瞻条目。
const Map<String, AiToolCallCategory> defaultToolCallNameRules = {
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
  // subagent(union of subagentToolNames + 前瞻)
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
};

const List<(String, AiToolCallCategory)> defaultToolCallPrefixRules = [
  ('mcp__', AiToolCallCategory.mcp),
];

const ConfigurableAiToolCallCategoryResolver defaultToolCallCategoryResolver =
    ConfigurableAiToolCallCategoryResolver(
  nameRules: defaultToolCallNameRules,
  prefixRules: defaultToolCallPrefixRules,
);
