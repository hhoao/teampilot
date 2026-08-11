# 工具调用类别体系 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 12 类工具调用类别体系(`AiToolCallCategory` 作为 `AiToolCallPart` 一等字段),解析管线一次性标注,并以类别为维度实现可配置的思考过程折叠(全局偏好)。

**Architecture:** 类别枚举与解析器接口定义在纯模型层 `ai_message_core`;每 CLI 的类别映射收敛到 `client/lib/services/ai_history/tool_call_categories.dart` 共享默认表 + capability 层 `categoryResolver`(5 个近重复 resolver 文件重构为共享基类);`AiHistoryLoader` 在 parse/inflate 后做幂等标注,seat 在 mailbox merge 后补标;`ai_message_ui` 新增 `AiToolCallFoldScope`,`groupMessageParts` 按谓词决定哪些 tool call 折入"思考过程";偏好存 `LayoutPreferences`,设置页每类别一个 Switch。

**Tech Stack:** Dart 3, Flutter, flutter_bloc, ai_message_core / ai_message_ui(本地 packages), shared_ui(Tp 设计系统)。

**Spec:** `docs/superpowers/specs/2026-08-11-tool-call-categories-design.md`

---

## 文件结构总览

```
ai_message_core/lib/src/
  message.dart                        # + AiToolCallCategory 枚举, AiToolCallPart.category 字段
  tool_category_resolver.dart         # 新建: AiToolCallCategoryResolver 接口
  subagent_attachment.dart            # + copyWith(AiSubagentAttachment / SubagentWorkflowAgent / SubagentWorkflowInfo)
  ai_message_core.dart                # + export tool_category_resolver.dart

client/lib/services/ai_history/
  tool_call_categories.dart           # 新建: ConfigurableAiToolCallCategoryResolver + 共享默认表
  tool_call_category_annotator.dart   # 新建: annotateToolCallCategories / annotateSubagentAttachments

client/lib/services/cli/registry/capabilities/
  tool_call_resolver_capability.dart  # + categoryResolver
  shared_tool_call_resolvers.dart     # 新建: SharedToolCallResolvers(共享 edit/file/shell/category 配置)
  claude_tool_call_resolvers.dart     # 重构为 extends SharedToolCallResolvers
  opencode_tool_call_resolvers.dart   # 同上
  codex_tool_call_resolvers.dart      # 同上
  flashskyai_tool_call_resolvers.dart # 同上
  cursor_tool_call_resolvers.dart     # extends + 覆盖 shellResolver(含 'execute')

client/lib/services/session/
  ai_history_load_result.dart         # + cli 字段
  ai_history_loader.dart              # 标注 + annotate() 薄封装

client/lib/cubits/
  ai_history_seat.dart                # _lastCli + 两个 _apply* 入口补标

client/packages/ai_message_ui/lib/src/
  tool_call_fold_scope.dart           # 新建: AiToolCallFoldScope(InheritedWidget)
  part_grouping.dart                  # groupMessageParts + shouldFold 谓词
  ai_message_parts.dart               # 读取 scope 传谓词
  ai_message_ui.dart                  # + export tool_call_fold_scope.dart

client/lib/
  models/layout_preferences.dart      # + foldToolCallCategories
  cubits/layout_cubit.dart            # + setFoldToolCallCategory
  pages/config/layout_appearance_in_layout_section.dart  # 折叠类别区(12 Switch)
  pages/chat/session_chat_message_area.dart              # + AiToolCallFoldScope 包裹 Stack
  l10n/app_en.arb / app_zh.arb        # 类别名 + 区块标题
```

---

### Task 1: ai_message_core — 类别枚举 + AiToolCallPart.category + 解析器接口

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/message.dart`
- Create: `client/packages/ai_message_core/lib/src/tool_category_resolver.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Test: `client/packages/ai_message_core/test/message_content_identity_test.dart`(extend)、`client/packages/ai_message_core/test/tool_category_test.dart`(new)

- [ ] **Step 1: 写失败测试 — 新文件 `tool_category_test.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiToolCallPart.category defaults to other', () {
    const part = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    expect(part.category, AiToolCallCategory.other);
  });

  test('copyWith sets and preserves category', () {
    const part = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final edited = part.copyWith(category: AiToolCallCategory.command);
    expect(edited.category, AiToolCallCategory.command);
    expect(edited.toolName, 'bash');
    expect(part.copyWith(toolName: 'Read').category, AiToolCallCategory.other);
  });

  test('enum has all 12 categories', () {
    expect(AiToolCallCategory.values, hasLength(12));
    expect(AiToolCallCategory.values, containsAll([
      AiToolCallCategory.read,
      AiToolCallCategory.write,
      AiToolCallCategory.edit,
      AiToolCallCategory.command,
      AiToolCallCategory.search,
      AiToolCallCategory.browser,
      AiToolCallCategory.subagent,
      AiToolCallCategory.askUser,
      AiToolCallCategory.plan,
      AiToolCallCategory.task,
      AiToolCallCategory.mcp,
      AiToolCallCategory.other,
    ]));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client/packages/ai_message_core && flutter test test/tool_category_test.dart`
Expected: 编译失败 — `AiToolCallCategory` 未定义

- [ ] **Step 3: 实现 — message.dart 加枚举与字段**

在 `message.dart` 顶部(AiRole 之后)加:

```dart
/// Coarse cross-CLI tool call category. Computed once at parse/annotation time
/// and stored on [AiToolCallPart]; drives fold policy and future chrome.
enum AiToolCallCategory {
  read,     // 文件读取 / glob / grep / list
  write,    // 新建 / 覆写文件
  edit,     // 修改已有文件
  command,  // bash / exec / shell
  search,   // web 搜索 / 抓取
  browser,  // 浏览器 / computer 操作
  subagent, // agent / task / workflow / spawn_agent
  askUser,  // AskUserQuestion
  plan,     // Plan / ExitPlanMode
  task,     // todo / taskcreate / taskupdate
  mcp,      // mcp__ 前缀
  other,    // 未知 / 其他(默认兜底)
}
```

`AiToolCallPart` 构造函数加 `this.category = AiToolCallCategory.other`,加字段 `final AiToolCallCategory category;`,copyWith 加 `AiToolCallCategory? category` 参数与 `category: category ?? this.category`。

- [ ] **Step 4: 新建 `tool_category_resolver.dart`**

```dart
import 'message.dart';

/// Maps a tool call to its coarse category. Implementations are per-CLI
/// (client/lib/services/cli/registry/capabilities/) or the shared default
/// table (client/lib/services/ai_history/tool_call_categories.dart).
abstract interface class AiToolCallCategoryResolver {
  AiToolCallCategory resolve(AiToolCallPart part);
}
```

`ai_message_core.dart` 加 `export 'src/tool_category_resolver.dart';`

- [ ] **Step 5: 运行确认通过**

Run: `cd client/packages/ai_message_core && flutter test test/tool_category_test.dart`
Expected: PASS(3 个测试)

- [ ] **Step 6: extend `message_content_identity_test.dart` — 类别不参与内容指纹**

在现有 `main()` 中加:

```dart
test('category is excluded from content identity', () {
  const base = AiToolCallPart(toolCallId: '1', toolName: 'bash');
  final other = base.copyWith(category: AiToolCallCategory.command);
  const m1 = AiMessage(id: 'm', role: AiRole.assistant, parts: [base]);
  final m2 = AiMessage(id: 'm', role: AiRole.assistant, parts: [other]);
  expect(messageContentIdentity(m1), messageContentIdentity(m2));
});
```

Run: `cd client/packages/ai_message_core && flutter test test/message_content_identity_test.dart`
Expected: PASS(类别不在 `messageContentIdentity` 的解构字段里,无需改实现)

- [ ] **Step 7: 提交**

```bash
git add client/packages/ai_message_core/lib/src/message.dart \
        client/packages/ai_message_core/lib/src/tool_category_resolver.dart \
        client/packages/ai_message_core/lib/ai_message_core.dart \
        client/packages/ai_message_core/test/tool_category_test.dart \
        client/packages/ai_message_core/test/message_content_identity_test.dart
git commit -m "feat(core): add AiToolCallCategory and AiToolCallPart.category"
```

---

### Task 2: ai_message_core — 子代理模型 copyWith

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/subagent_attachment.dart`
- Test: `client/packages/ai_message_core/test/subagent_attachment_test.dart`(extend)

- [ ] **Step 1: 写失败测试 — extend `subagent_attachment_test.dart`**

实现采用与既有 `AiToolCallPart.copyWith` 一致的 `?? this.` 语义(workflow 缺省保留,set 场景不需要 clear):

```dart
test('attachment copyWith preserves workflow when not provided', () {
  final messages = [AiMessage(id: 'a', role: AiRole.assistant, parts: [])];
  final wf = const SubagentWorkflowInfo(runId: 'r1');
  final attachment = AiSubagentAttachment(
    toolCallId: 't1',
    messages: messages,
    source: AiSubagentAttachmentSource.sideTranscript,
    workflow: wf,
  );
  final edited = attachment.copyWith(messages: messages);
  expect(edited.workflow, same(wf));
  expect(edited.messages, same(messages));
});

test('workflow copyWith rebuilds agents', () {
  const messages = [AiMessage(id: 'a', role: AiRole.assistant, parts: [])];
  const agent = SubagentWorkflowAgent(
    agentId: 'ag1',
    messages: messages,
    handle: SubagentFileHandle('/side/a'),
  );
  final wf = const SubagentWorkflowInfo(runId: 'r1', agents: [agent]);
  final newMessages = [
    AiMessage(id: 'b', role: AiRole.assistant, parts: [AiTextPart(text: 'x')]),
  ];
  final wfEdited = wf.copyWith(
    agents: [agent.copyWith(messages: newMessages)],
  );
  expect(wfEdited.agents.single.messages, same(newMessages));
  expect(wfEdited.runId, 'r1');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client/packages/ai_message_core && flutter test test/subagent_attachment_test.dart`
Expected: 编译失败 — copyWith 未定义

- [ ] **Step 3: 实现 copyWith**

`subagent_attachment.dart`:

```dart
class SubagentWorkflowAgent {
  // ... 既有字段不变,加:
  SubagentWorkflowAgent copyWith({
    String? agentId,
    String? role,
    String? status,
    List<AiMessage>? messages,
    SubagentFileHandle? handle,
  }) {
    return SubagentWorkflowAgent(
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      status: status ?? this.status,
      messages: messages ?? this.messages,
      handle: handle ?? this.handle,
    );
  }
}
```

`SubagentWorkflowInfo.copyWith`(runId, workflowName, status, phases, agentCount, summary, duration, agents — 全部 `?? this.`)。

`AiSubagentAttachment.copyWith`(toolCallId, messages, source, title, handle, workflow — `?? this.`,handle 无 clear 需求)。

- [ ] **Step 4: 运行确认通过**

Run: `cd client/packages/ai_message_core && flutter test`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/packages/ai_message_core/lib/src/subagent_attachment.dart \
        client/packages/ai_message_core/test/subagent_attachment_test.dart
git commit -m "feat(core): add copyWith to subagent attachment models"
```

---

### Task 3: 共享映射表 + 可配置解析器 + 标注器

**Files:**
- Create: `client/lib/services/ai_history/tool_call_categories.dart`
- Create: `client/lib/services/ai_history/tool_call_category_annotator.dart`
- Test: `client/test/services/ai_history/tool_call_categories_test.dart`(new)、`client/test/services/ai_history/tool_call_category_annotator_test.dart`(new)

- [ ] **Step 1: 写失败测试 — `tool_call_categories_test.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';

AiToolCallPart tool(String name) =>
    AiToolCallPart(toolCallId: '1', toolName: name);

void main() {
  const resolver = defaultToolCallCategoryResolver;

  test('known names resolve to expected categories', () {
    expect(resolver.resolve(tool('Read')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('glob')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('write')), AiToolCallCategory.write);
    expect(resolver.resolve(tool('strreplace')), AiToolCallCategory.edit);
    expect(resolver.resolve(tool('bash')), AiToolCallCategory.command);
    expect(resolver.resolve(tool('web_search')), AiToolCallCategory.search);
    expect(resolver.resolve(tool('browser_act')), AiToolCallCategory.browser);
    expect(resolver.resolve(tool('task')), AiToolCallCategory.subagent);
    expect(resolver.resolve(tool('TodoWrite')), AiToolCallCategory.task);
    expect(
      resolver.resolve(tool('AskUserQuestion')),
      AiToolCallCategory.askUser,
    );
    expect(resolver.resolve(tool('ExitPlanMode')), AiToolCallCategory.plan);
  });

  test('case-insensitive matching', () {
    expect(resolver.resolve(tool('READ')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('Bash')), AiToolCallCategory.command);
  });

  test('mcp__ prefix maps to mcp', () {
    expect(
      resolver.resolve(tool('mcp__github__get_issue')),
      AiToolCallCategory.mcp,
    );
  });

  test('unknown names map to other', () {
    expect(resolver.resolve(tool('custom_tool_call')), AiToolCallCategory.other);
    expect(resolver.resolve(tool('random_thing')), AiToolCallCategory.other);
  });

  test('ConfigurableAiToolCallCategoryResolver supports custom rules', () {
    const custom = ConfigurableAiToolCallCategoryResolver(
      nameRules: {'mine': AiToolCallCategory.task},
      prefixRules: [('ext__', AiToolCallCategory.mcp)],
    );
    expect(custom.resolve(tool('mine')), AiToolCallCategory.task);
    expect(custom.resolve(tool('ext__foo')), AiToolCallCategory.mcp);
    expect(custom.resolve(tool('bash')), AiToolCallCategory.other);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/ai_history/tool_call_categories_test.dart`
Expected: 编译失败 — 文件不存在

- [ ] **Step 3: 实现 `tool_call_categories.dart`**

```dart
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
  // plan
  'plan': AiToolCallCategory.plan,
  'exitplanmode': AiToolCallCategory.plan,
  'exit_plan_mode': AiToolCallCategory.plan,
  // task
  'todowrite': AiToolCallCategory.task,
  'todo_write': AiToolCallCategory.task,
  'taskcreate': AiToolCallCategory.task,
  'task_create': AiToolCallCategory.task,
  'taskupdate': AiToolCallCategory.task,
  'task_update': AiToolCallCategory.task,
};

const List<(String, AiToolCallCategory)> defaultToolCallPrefixRules = [
  ('mcp__', AiToolCallCategory.mcp),
];

const ConfigurableAiToolCallCategoryResolver defaultToolCallCategoryResolver =
    ConfigurableAiToolCallCategoryResolver(
  nameRules: defaultToolCallNameRules,
  prefixRules: defaultToolCallPrefixRules,
);
```

- [ ] **Step 4: 写失败测试 — `tool_call_category_annotator_test.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';
import 'package:teampilot/services/ai_history/tool_call_category_annotator.dart';

const resolver = defaultToolCallCategoryResolver;

AiMessage assistantWithTool(String toolName) => AiMessage(
  id: 'a1',
  role: AiRole.assistant,
  parts: [AiToolCallPart(toolCallId: '1', toolName: toolName)],
);

void main() {
  test('annotates tool parts, skips text and reasoning', () {
    final messages = [
      assistantWithTool('Bash'),
      const AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [
          AiTextPart(text: 'hi'),
          AiReasoningPart(text: 'think'),
          AiToolCallPart(toolCallId: '2', toolName: 'Read'),
        ],
      ),
    ];
    final out = annotateToolCallCategories(messages, resolver: resolver);
    final bash = (out[0].parts.single as AiToolCallPart);
    expect(bash.category, AiToolCallCategory.command);
    final read = out[1].parts
        .whereType<AiToolCallPart>()
        .single;
    expect(read.category, AiToolCallCategory.read);
  });

  test('idempotent: repeated annotation returns same instance', () {
    final once = annotateToolCallCategories(
      [assistantWithTool('Bash')],
      resolver: resolver,
    );
    final twice = annotateToolCallCategories(once, resolver: resolver);
    expect(identical(once, twice), isTrue);
  });

  test('unknown tools stay other', () {
    final out = annotateToolCallCategories(
      [assistantWithTool('custom_tool_call')],
      resolver: resolver,
    );
    expect((out.single.parts.single as AiToolCallPart).category,
        AiToolCallCategory.other);
  });

  test('annotates attachment transcripts including workflow agents', () {
    final sideMessages = [assistantWithTool('Grep')];
    final agent = SubagentWorkflowAgent(
      agentId: 'ag1',
      messages: [assistantWithTool('bash')],
      handle: const SubagentFileHandle('/side/a'),
    );
    final attachment = AiSubagentAttachment(
      toolCallId: 't1',
      messages: sideMessages,
      source: AiSubagentAttachmentSource.sideTranscript,
      workflow: SubagentWorkflowInfo(runId: 'r1', agents: [agent]),
    );
    final out = annotateSubagentAttachments(
      {'t1': attachment},
      resolver: resolver,
    );
    final edited = out['t1']!;
    expect(
      (edited.messages.single.parts.single as AiToolCallPart).category,
      AiToolCallCategory.read,
    );
    expect(
      (edited.workflow!.agents.single.messages.single.parts.single
              as AiToolCallPart)
          .category,
      AiToolCallCategory.command,
    );
  });
}
```

- [ ] **Step 5: 实现 `tool_call_category_annotator.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';

/// 幂等标注:为每个 AiToolCallPart 填充 category。类别已匹配时跳过
/// copyWith(返回原实例),因此重复调用零分配、结果 identical。
List<AiMessage> annotateToolCallCategories(
  List<AiMessage> messages, {
  required AiToolCallCategoryResolver resolver,
}) {
  if (messages.isEmpty) return messages;
  var anyChanged = false;
  final out = <AiMessage>[];
  for (final message in messages) {
    var messageChanged = false;
    final parts = message.parts;
    final annotated = <AiMessagePart>[];
    for (final part in parts) {
      if (part is AiToolCallPart) {
        final category = resolver.resolve(part);
        if (category != part.category) {
          messageChanged = true;
          annotated.add(part.copyWith(category: category));
        } else {
          annotated.add(part);
        }
      } else {
        annotated.add(part);
      }
    }
    if (messageChanged) {
      anyChanged = true;
      out.add(message.copyWith(parts: annotated));
    } else {
      out.add(message);
    }
  }
  return anyChanged ? out : messages;
}

/// 对附件 map 的每条 transcript(含 workflow agents)做幂等标注。
Map<String, AiSubagentAttachment> annotateSubagentAttachments(
  Map<String, AiSubagentAttachment> attachments, {
  required AiToolCallCategoryResolver resolver,
}) {
  if (attachments.isEmpty) return attachments;
  final out = <String, AiSubagentAttachment>{};
  for (final entry in attachments.entries) {
    out[entry.key] = _annotateAttachment(entry.value, resolver);
  }
  return out;
}

AiSubagentAttachment _annotateAttachment(
  AiSubagentAttachment attachment,
  AiToolCallCategoryResolver resolver,
) {
  final messages = annotateToolCallCategories(
    attachment.messages,
    resolver: resolver,
  );
  final workflow = attachment.workflow;
  if (workflow == null) {
    return identical(messages, attachment.messages)
        ? attachment
        : attachment.copyWith(messages: messages);
  }
  var agentsChanged = false;
  final agents = <SubagentWorkflowAgent>[];
  for (final agent in workflow.agents) {
    final agentMessages = annotateToolCallCategories(
      agent.messages,
      resolver: resolver,
    );
    agentsChanged = agentsChanged || !identical(agentMessages, agent.messages);
    agents.add(
      identical(agentMessages, agent.messages)
          ? agent
          : agent.copyWith(messages: agentMessages),
    );
  }
  final nextWorkflow = agentsChanged
      ? workflow.copyWith(agents: agents)
      : workflow;
  return attachment.copyWith(messages: messages, workflow: nextWorkflow);
}
```

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/services/ai_history/tool_call_categories_test.dart test/services/ai_history/tool_call_category_annotator_test.dart`
Expected: PASS(全部)

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/ai_history/tool_call_categories.dart \
        client/lib/services/ai_history/tool_call_category_annotator.dart \
        client/test/services/ai_history/tool_call_categories_test.dart \
        client/test/services/ai_history/tool_call_category_annotator_test.dart
git commit -m "feat(history): shared tool call category mapping and annotator"
```

---

### Task 4: capability 层 — categoryResolver + 共享基类 + 5 CLI 重构

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/tool_call_resolver_capability.dart`
- Create: `client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`
- Modify: `claude_tool_call_resolvers.dart`、`opencode_tool_call_resolvers.dart`、`codex_tool_call_resolvers.dart`、`flashskyai_tool_call_resolvers.dart`、`cursor_tool_call_resolvers.dart`(均在同目录)
- Test: `client/test/services/cli/registry/capabilities/tool_call_category_mapping_test.dart`(new)

- [ ] **Step 1: 写失败测试 — `tool_call_category_mapping_test.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
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
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/tool_call_category_mapping_test.dart`
Expected: 编译失败 — categoryResolver 未定义

- [ ] **Step 3: capability 接口加 categoryResolver**

`tool_call_resolver_capability.dart`:

```dart
abstract interface class ToolCallResolversCapability implements CliCapability {
  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
  AiToolCallCategoryResolver get categoryResolver;
}
```

- [ ] **Step 4: 新建 `shared_tool_call_resolvers.dart`**

把 5 个文件共有的 edit codecs / file rules / shell 集合 / category 解析集中到共享基类(内容与现有 claude 版本一致,category 用默认表):

```dart
import 'package:ai_message_core/ai_message_core.dart'
    hide
        StrReplaceEditHunkCodec,
        WriteEditHunkCodec,
        UnifiedDiffEditHunkCodec;

import '../../../ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../ai_history/tool_call_categories.dart';
import '../../../ai_history/tool_call_resolvers.dart';
import 'tool_call_resolver_capability.dart';

/// Shared edit/file/shell/category configuration for all built-in CLIs.
/// Per-CLI deltas override specific resolvers (see CursorToolCallResolvers).
class SharedToolCallResolvers implements ToolCallResolversCapability {
  const SharedToolCallResolvers();

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: {'strreplace', 'edit', 'editnotebook', 'notebookedit'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    oldStringKeys: ['old_string', 'oldString'],
    newStringKeys: ['new_string', 'newString'],
    startLineKeys: ['start_line', 'startLine'],
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: {'write', 'writefile', 'write_file', 'create', 'create_file'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    contentKeys: ['content', 'contents'],
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: {'applypatch', 'apply_patch'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    patchKeys: ['patch', 'diff', 'input'],
  );

  static const _fileRules = <AiToolFileTargetRule>[
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
      },
    ),
    AiToolFileTargetRule(
      toolNames: {
        'edit',
        'strreplace',
        'applypatch',
        'editnotebook',
        'notebookedit',
      },
    ),
  ];

  static const _shellToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
  };

  @override
  AiEditToolTargetResolver get editResolver =>
      const ConfigurableAiEditToolTargetResolver(
        codecs: [_strReplaceCodec, _writeCodec, _unifiedDiffCodec],
      );

  @override
  AiToolFileTargetResolver get fileResolver =>
      const ConfigurableAiToolFileTargetResolver(rules: _fileRules);

  @override
  AiShellToolTargetResolver get shellResolver =>
      const ConfigurableAiShellToolTargetResolver(toolNames: _shellToolNames);

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      defaultToolCallCategoryResolver;
}
```

- [ ] **Step 5: 重构 5 个 CLI 文件**

`claude_tool_call_resolvers.dart` 整体替换为:

```dart
import 'shared_tool_call_resolvers.dart';

/// Claude tool-call resolvers (shared configuration, no CLI deltas).
class ClaudeToolCallResolvers extends SharedToolCallResolvers {
  const ClaudeToolCallResolvers();
}
```

`opencode`/`codex`/`flashskyai` 同构(类名对应)。`cursor_tool_call_resolvers.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';

import '../../../ai_history/tool_call_resolvers.dart';
import 'shared_tool_call_resolvers.dart';

/// Cursor tool-call resolvers: shared configuration plus `execute` as a shell
/// / terminal tool name.
class CursorToolCallResolvers extends SharedToolCallResolvers {
  const CursorToolCallResolvers();

  @override
  AiShellToolTargetResolver get shellResolver =>
      const ConfigurableAiShellToolTargetResolver(
        toolNames: {
          'bash',
          'shell',
          'execute',
          'run_terminal_cmd',
          'shell_command',
          'exec_command',
          'run_shell_command',
        },
      );
}
```

注意:消费端类型不变——`claude_tool.dart:121`、`cursor_tool.dart:106` 等仍持有 `ClaudeToolCallResolvers` 等具体类型,extends 保持兼容。

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/tool_call_category_mapping_test.dart test/services/cli/registry/ai_history_capability_wiring_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/
git commit -m "refactor(cli): shared tool call resolvers base + category resolver capability"
```

---

### Task 5: AiHistoryLoader 标注 + AiHistoryLoadResult.cli

**Files:**
- Modify: `client/lib/services/session/ai_history_load_result.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart`(extend)

- [ ] **Step 1: 写失败测试 — extend `ai_history_loader_test.dart`**

在 `parses Claude fixture bytes via locate + adapter` 测试之后加:

```dart
test('annotates tool call categories after parse (built-in resolver)', () async {
  final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
  final sessionId = 'sess-cat';
  final toolRoot = layout.sessionRuntimeToolDir('ws-1', sessionId, 'claude');
  final projects = p.join(toolRoot, 'projects', bucket);
  await Directory(projects).create(recursive: true);
  final fixture = await File(
    'test/fixtures/session_history/claude/basic.jsonl',
  ).readAsBytes();
  await File(p.join(projects, '$sessionId.jsonl')).writeAsBytes(fixture);

  final session = simpleSession(id: sessionId);
  final result = await buildLoader().load(
    session: session,
    memberId: '',
    launchContext: launchContextFor(session),
  );
  expect(result.cli, CliTool.claude);
  final parts = [
    for (final m in result.messages) ...m.parts.whereType<AiToolCallPart>(),
  ];
  expect(parts, isNotEmpty);
  // fixture 只有 Bash(basic.jsonl 仅含一条 tool_use):
  expect(parts.single.category, AiToolCallCategory.command);
});
```

(buildLoader 默认 `CliToolRegistry.builtIn()`,含 ToolCallResolversCapability——该用例验证的是 built-in 解析路径,不是 fallback。fixture 已确认只含 Bash。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`
Expected: 编译失败 — `result.cli` 不存在

- [ ] **Step 3: 实现**

`ai_history_load_result.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';

class AiHistoryLoadResult {
  const AiHistoryLoadResult({
    required this.messages,
    required this.cli,
    this.subagentAttachments = const {},
  });

  final List<AiMessage> messages;
  final CliTool cli;
  final Map<String, AiSubagentAttachment> subagentAttachments;
}
```

`ai_history_loader.dart`:
- import 增加:`../ai_history/tool_call_categories.dart`、`../ai_history/tool_call_category_annotator.dart`、`../cli/registry/capabilities/tool_call_resolver_capability.dart`
- 增加私有辅助:

```dart
AiToolCallCategoryResolver _categoryResolverFor(CliTool cli) =>
    _registry.capability<ToolCallResolversCapability>(cli)?.categoryResolver ??
    defaultToolCallCategoryResolver;

/// Defensive annotation for post-load merged lists (mailbox). Idempotent.
List<AiMessage> annotate(List<AiMessage> messages, {required CliTool cli}) =>
    annotateToolCallCategories(
      messages,
      resolver: _categoryResolverFor(cli),
    );
```

- 两个 `AiHistoryLoadResult(` 返回点(148 缓存命中、229 新鲜)都加 `cli: cli`。
- 新鲜路径(215-250):parse 后先 `messages = annotateToolCallCategories(messages, resolver: _categoryResolverFor(cli));`(inflate 之前),inflate 之后 `attachments = annotateSubagentAttachments(attachments, resolver: _categoryResolverFor(cli));`(`final` 改 `var`)。
- 缓存命中路径(148-152)返回的是已标注的缓存实例,无需处理。

> **注意(用户未提交改动)**:主工作区 `ai_history_loader.dart` 有一条未提交的 side-refresh 重标路径(缓存命中时按 side-transcript fingerprint 重建附件),会产生未标注的新 `AiToolCallPart`。本 worktree 基于已提交 HEAD(无该路径),本次不处理;用户合并该改动时需在两个 inflate 点都补 `annotateSubagentAttachments`(与上文一致)。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/session/ai_history_load_result.dart \
        client/lib/services/session/ai_history_loader.dart \
        client/test/services/session/ai_history_loader_test.dart
git commit -m "feat(history): annotate tool call categories in loader"
```

---

### Task 6: seat 防御性补标(mailbox merge 后)

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Test: `client/test/cubits/ai_history_seat_isolation_test.dart`(extend)

- [ ] **Step 1: 写回归守卫测试 — extend `ai_history_seat_isolation_test.dart`**

mailbox 事件当前为纯用户文本,seat 补标在现有数据流下**不可达**(loader 已在 Task 5 标注,merge 复用同一批 part 实例)。因此本用例定位为**回归守卫**:保证 Task 5 之后 merged 消息仍带类别,且补标路径不破坏现有行为。该测试在 seat 补标实现**前后都应通过**;Step 2 的"失败预期"不适用——这是 Task 6 与 Task 5 的差异点,实现验证靠代码走查(两处 `_apply*` 入口有 `_loader.annotate` 调用)而非红绿循环。

```dart
test('merged messages keep tool call categories after mailbox merge', () async {
  messagesBySession['sess-a'] = [
    AiMessage(
      id: 'm-tool',
      role: AiRole.assistant,
      parts: [AiToolCallPart(toolCallId: 't1', toolName: 'Bash')],
    ),
  ];
  // 通过现有 harness 的 seat load 路径装载,再断言 state 消息里的
  // tool part.category == command(沿用本文件其他测试读取消息的方式)。
});
```

(若该文件已有可直接复用的 seat 装配 helper,照其模式;断言通过 `cubit.ensureSeat(...)` 后的 `seat.runtime.messages` 读取——`AiHistoryState` 本身不含消息列表,照本文件现有测试的读取方式。)

- [ ] **Step 2: 运行确认通过(前后都应通过)**

Run: `cd client && flutter test test/cubits/ai_history_seat_isolation_test.dart`
Expected: PASS

- [ ] **Step 3: 实现**

`ai_history_seat.dart`:
- 增加字段 `CliTool? _lastCli;`
- `load()` 内 `_loader.load` 返回后、`_cliMessages = result.messages;` 附近加 `_lastCli = result.cli;`(仅 `load()` 设置即可——seat 的 CLI 身份在会话生命周期内稳定,`softReload` / `refreshMailboxTimeline` 复用同一值,无需重复赋值)
- `_applyMessages`(732 行)与 `_applySoftReloadMessages`(753 行)两个方法开头加:

```dart
final cli = _lastCli;
if (cli != null) {
  messages = _loader.annotate(messages, cli: cli);
}
```

(两方法签名不变,参数名都是 `List<AiMessage> messages`。所有 4 条 merge 路径 —— load:279、empty-CLI:380、softReload:403、refreshMailboxTimeline:445 —— 都汇聚到这两个方法,一处补标全覆盖;`annotate` 幂等,常见路径零分配。)

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/cubits/ai_history_seat_isolation_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/cubits/ai_history_seat.dart \
        client/test/cubits/ai_history_seat_isolation_test.dart
git commit -m "feat(history): defensive category annotation after mailbox merge"
```

---

### Task 7: ai_message_ui — AiToolCallFoldScope + groupMessageParts 谓词

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/tool_call_fold_scope.dart`
- Modify: `client/packages/ai_message_ui/lib/src/part_grouping.dart`
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_parts.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`
- Test: `client/packages/ai_message_ui/test/part_grouping_test.dart`(extend)、`client/packages/ai_message_ui/test/tool_call_fold_scope_test.dart`(new)

- [ ] **Step 1: 写失败测试 — extend `part_grouping_test.dart`**

```dart
test('shouldFold predicate keeps unfolded tool calls outside the chain', () {
  final nodes = groupMessageParts(
    [
      const AiReasoningPart(text: 'r1'),
      AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      AiToolCallPart(toolCallId: '2', toolName: 'bash'),
    ],
    shouldFold: (part) => part.toolName != 'bash',
  );
  expect(nodes, hasLength(2));
  final chain = nodes[0] as AiRenderChainOfThought;
  expect(chain.parts, hasLength(2)); // reasoning + Read
  expect(nodes[1], isA<AiRenderPart>());
  expect((nodes[1] as AiRenderPart).part.toolName, 'bash');
});

test('default (null) predicate folds all tool calls', () {
  final nodes = groupMessageParts([
    AiToolCallPart(toolCallId: '1', toolName: 'bash'),
    AiToolCallPart(toolCallId: '2', toolName: 'bash'),
  ]);
  expect(nodes.single, isA<AiRenderChainOfThought>());
  expect((nodes.single as AiRenderChainOfThought).parts, hasLength(2));
});

test('reasoning always folds even when predicate rejects tools', () {
  final nodes = groupMessageParts(
    [
      const AiReasoningPart(text: 'r'),
      AiToolCallPart(toolCallId: '1', toolName: 'bash'),
    ],
    shouldFold: (_) => false,
  );
  expect(nodes, hasLength(2));
  expect((nodes[0] as AiRenderChainOfThought).parts.single,
      isA<AiReasoningPart>());
  expect(nodes[1], isA<AiRenderPart>());
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client/packages/ai_message_ui && flutter test test/part_grouping_test.dart`
Expected: 编译失败 — shouldFold 参数不存在

- [ ] **Step 3: 新建 `tool_call_fold_scope.dart`**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

typedef AiToolCallFoldPredicate = bool Function(AiToolCallPart part);

/// Host-injected fold policy for chain-of-thought grouping. Null predicate
/// (scope absent) folds every tool call — the historical default.
class AiToolCallFoldScope extends InheritedWidget {
  const AiToolCallFoldScope({
    required this.shouldFold,
    required super.child,
    super.key,
  });

  final AiToolCallFoldPredicate shouldFold;

  static AiToolCallFoldScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiToolCallFoldScope>();

  @override
  bool updateShouldNotify(AiToolCallFoldScope oldWidget) =>
      shouldFold != oldWidget.shouldFold;
}
```

`ai_message_ui.dart` 加 `export 'src/tool_call_fold_scope.dart';`

- [ ] **Step 4: 修改 `part_grouping.dart`**

`groupMessageParts` 增加可选谓词参数,reasoning 恒折:

```dart
/// Groups reasoning/tool runs into chain-of-thought nodes; text stays outside.
/// Tool calls fold only when [shouldFold] allows (null folds everything);
/// unfolded tool calls split the run like text.
List<AiRenderNode> groupMessageParts(
  List<AiMessagePart> parts, {
  AiToolCallFoldPredicate? shouldFold,
}) {
  final out = <AiRenderNode>[];
  var i = 0;
  bool isChainPart(AiMessagePart p) =>
      p is AiReasoningPart ||
      (p is AiToolCallPart && (shouldFold == null || shouldFold(p)));
  while (i < parts.length) {
    if (isChainPart(parts[i])) {
      final run = <AiMessagePart>[];
      while (i < parts.length && isChainPart(parts[i])) {
        run.add(parts[i]);
        i++;
      }
      out.add(AiRenderChainOfThought(run));
      continue;
    }
    out.add(AiRenderPart(parts[i]));
    i++;
  }
  return out;
}
```

`part_grouping.dart` 需要 import `tool_call_fold_scope.dart`(同包路径)。

- [ ] **Step 5: 修改 `ai_message_parts.dart`**

```dart
@override
Widget build(BuildContext context) {
  if (parts.isEmpty) return const SizedBox.shrink();
  final gap = AiMessageTheme.of(context).partSpacing;
  final shouldFold = AiToolCallFoldScope.maybeOf(context)?.shouldFold;
  final nodes = groupMessageParts(parts, shouldFold: shouldFold);
  ...
}
```

- [ ] **Step 6: 新 widget 测试 — `tool_call_fold_scope_test.dart`(端到端经 AiMessageView)**

关键断言:reasoning **恒**折——`(_) => false` 时仍有一个仅含 reasoning 的链头;区别在 Bash 是否可见(折叠时在链内、链默认收起 → 不可见;不折叠时独立行 → 可见)。

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AiMessage messageWith(String id, List<AiMessagePart> parts) => AiMessage(
    id: id,
    role: AiRole.assistant,
    parts: parts,
  );

  Widget harness({AiToolCallFoldPredicate? shouldFold}) {
    final message = messageWith('m1', [
      const AiReasoningPart(text: 'r1'),
      AiToolCallPart(
        toolCallId: '1',
        toolName: 'Bash',
        status: AiToolCallStatus.complete,
        argsText: '{"command":"ls"}',
      ),
    ]);
    final view = AiMessageView(message: message);
    final wrapped = shouldFold == null
        ? view
        : AiToolCallFoldScope(shouldFold: shouldFold, child: view);
    return MaterialApp(
      home: Scaffold(
        body: Theme(
          data: ThemeData(extensions: [AiMessageTheme.test()]),
          child: wrapped,
        ),
      ),
    );
  }

  testWidgets('fold scope folds the tool call into the collapsed chain', (
    tester,
  ) async {
    await tester.pumpWidget(harness(shouldFold: (_) => true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
    // Bash 在折叠的链内,不单独渲染
    expect(find.textContaining('Bash'), findsNothing);
  });

  testWidgets('fold scope keeps unfolded tool call as standalone row', (
    tester,
  ) async {
    await tester.pumpWidget(harness(shouldFold: (_) => false));
    await tester.pumpAndSettle();
    // reasoning 仍折 → 恰一个链头
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
    // Bash 独立成行
    expect(find.textContaining('Bash'), findsWidgets);
  });

  testWidgets('no scope defaults to folding', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
    expect(find.textContaining('Bash'), findsNothing);
  });
}
```

注意:`AiMessageTheme.test()` 已存在(theme.dart:42,同包测试多处使用)。

- [ ] **Step 7: 运行确认通过**

Run: `cd client/packages/ai_message_ui && flutter test`
Expected: PASS

- [ ] **Step 8: 提交**

```bash
git add client/packages/ai_message_ui/
git commit -m "feat(ui): AiToolCallFoldScope + fold predicate in chain-of-thought grouping"
```

---

### Task 8: LayoutPreferences + LayoutCubit

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/models/layout_preferences_default_test.dart`(extend)、`client/test/cubits/layout_cubit_preferences_test.dart`(extend)

- [ ] **Step 1: 写失败测试 — extend `layout_preferences_default_test.dart`**

```dart
test('foldToolCallCategories defaults to workhorse set', () {
  final prefs = const LayoutPreferences();
  expect(
    prefs.foldToolCallCategories,
    LayoutPreferences.defaultFoldToolCallCategories,
  );
  expect(
    prefs.foldToolCallCategories.contains(AiToolCallCategory.read),
    isTrue,
  );
  expect(
    prefs.foldToolCallCategories.contains(AiToolCallCategory.subagent),
    isFalse,
  );
});

test('foldToolCallCategories round-trips via JSON names', () {
  final prefs = const LayoutPreferences().copyWith(
    foldToolCallCategories: {AiToolCallCategory.command, AiToolCallCategory.mcp},
  );
  final parsed = LayoutPreferences.fromJson(prefs.toJson());
  expect(
    parsed.foldToolCallCategories,
    {AiToolCallCategory.command, AiToolCallCategory.mcp},
  );
});

test('foldToolCallCategories missing key → default; empty list → empty', () {
  expect(
    LayoutPreferences.fromJson(const {}).foldToolCallCategories,
    LayoutPreferences.defaultFoldToolCallCategories,
  );
  expect(
    LayoutPreferences.fromJson(const {'foldToolCallCategories': <String>[]})
        .foldToolCallCategories,
    isEmpty,
  );
});
```

文件头部 import 加 `package:ai_message_core/ai_message_core.dart`。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: 编译失败 — foldToolCallCategories 未定义

- [ ] **Step 3: 实现 `layout_preferences.dart`**

- import 加 `package:ai_message_core/ai_message_core.dart`
- 类常量:

```dart
/// Categories folded into the thinking-process chain by default.
static const Set<AiToolCallCategory> defaultFoldToolCallCategories = {
  AiToolCallCategory.read,
  AiToolCallCategory.write,
  AiToolCallCategory.edit,
  AiToolCallCategory.command,
  AiToolCallCategory.search,
  AiToolCallCategory.browser,
  AiToolCallCategory.mcp,
  AiToolCallCategory.task,
};
```

- 构造函数加 `this.foldToolCallCategories = defaultFoldToolCallCategories`
- 字段 `final Set<AiToolCallCategory> foldToolCallCategories;`
- fromJson:`foldToolCallCategories: _categorySet(json['foldToolCallCategories'])`
- toJson:`'foldToolCallCategories': foldToolCallCategories.map((c) => c.name).toList()`
- copyWith:`Set<AiToolCallCategory>? foldToolCallCategories` + `foldToolCallCategories: foldToolCallCategories ?? this.foldToolCallCategories`
- `withAtLeastOneToolVisible()` 的重建构造里加 `foldToolCallCategories: foldToolCallCategories`(所有显式重建处都要带上,否则丢默认值)
- 文件底部 helper:

```dart
Set<AiToolCallCategory> _categorySet(Object? raw) {
  if (raw is! List) return LayoutPreferences.defaultFoldToolCallCategories;
  final out = <AiToolCallCategory>{};
  for (final value in raw) {
    if (value is! String) continue;
    for (final category in AiToolCallCategory.values) {
      if (category.name == value) {
        out.add(category);
        break;
      }
    }
  }
  return out;
}
```

- [ ] **Step 4: 实现 `layout_cubit.dart` — setter**

```dart
Future<void> setFoldToolCallCategory(
  AiToolCallCategory category, {
  required bool fold,
}) {
  final next = {...state.preferences.foldToolCallCategories};
  if (fold) {
    next.add(category);
  } else {
    next.remove(category);
  }
  return _save(state.preferences.copyWith(foldToolCallCategories: next));
}
```

import 加 `package:ai_message_core/ai_message_core.dart`。

- [ ] **Step 5: extend `layout_cubit_preferences_test.dart` — toggle 持久化**

参照该文件现有用例模式:

```dart
test('setFoldToolCallCategory toggles and persists', () async {
  final cubit = LayoutCubit(repository: LayoutRepository(prefs));
  await cubit.load();
  await cubit.setFoldToolCallCategory(
    AiToolCallCategory.subagent,
    fold: true,
  );
  expect(
    cubit.state.preferences.foldToolCallCategories.contains(
      AiToolCallCategory.subagent,
    ),
    isTrue,
  );
  await cubit.setFoldToolCallCategory(
    AiToolCallCategory.subagent,
    fold: false,
  );
  expect(
    cubit.state.preferences.foldToolCallCategories.contains(
      AiToolCallCategory.subagent,
    ),
    isFalse,
  );
});
```

(按该文件现有 repository/prefs 装配方式调整。)

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart test/cubits/layout_cubit_preferences_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add client/lib/models/layout_preferences.dart \
        client/lib/cubits/layout_cubit.dart \
        client/test/models/layout_preferences_default_test.dart \
        client/test/cubits/layout_cubit_preferences_test.dart
git commit -m "feat(prefs): foldToolCallCategories preference"
```

---

### Task 9: 设置页 UI + l10n

**Files:**
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/config/layout_appearance_in_layout_section_test.dart`(extend)

- [ ] **Step 1: 写失败测试 — extend `layout_appearance_in_layout_section_test.dart`**

在现有测试后加:

```dart
testWidgets('thinking-process fold section shows all category toggles', (
  tester,
) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = LayoutCubit(repository: LayoutRepository(prefs));
  await cubit.load();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlocProvider.value(
            value: cubit,
            child: const LayoutAppearanceInLayoutSection(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Fold into thinking process'), findsOneWidget);
  // 12 类别 + 既有 2 个 cot 展开开关 = 14 个 Switch
  expect(find.byType(Switch), findsNWidgets(14));
  final switches = tester
      .widgetList<Switch>(find.byType(Switch))
      .toList();
  // 默认折叠 8 类为 on;两个 cot 开关默认 off
  final onCount = switches.where((s) => s.value).length;
  expect(onCount, 8);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/pages/config/layout_appearance_in_layout_section_test.dart`
Expected: 失败 — 找不到 'Fold into thinking process'

- [ ] **Step 3: 实现设置页**

`layout_appearance_in_layout_section.dart`:"思考过程"区(`TpSectionHeader(title: l10n.thinkingProcessSectionTitle)`)的两个既有 TpPreferenceRow 之后、`TpSectionHeader(title: l10n.contentDisplayModeSectionTitle)` 之前插入:

```dart
TpSectionHeader(title: l10n.thinkingProcessFoldSectionTitle),
for (final category in AiToolCallCategory.values) ...[
  TpPreferenceRow(
    title: _foldCategoryTitle(l10n, category),
    trailing: Switch(
      value: context.select<LayoutCubit, bool>(
        (c) =>
            c.state.preferences.foldToolCallCategories.contains(category),
      ),
      onChanged: (value) =>
          controller.setFoldToolCallCategory(category, fold: value),
    ),
    showDividerBelow: true,
  ),
]
```

文件顶部 import `package:ai_message_core/ai_message_core.dart`;文件内加 helper:

```dart
String _foldCategoryTitle(AppLocalizations l10n, AiToolCallCategory c) =>
    switch (c) {
      AiToolCallCategory.read => l10n.toolCategoryRead,
      AiToolCallCategory.write => l10n.toolCategoryWrite,
      AiToolCallCategory.edit => l10n.toolCategoryEdit,
      AiToolCallCategory.command => l10n.toolCategoryCommand,
      AiToolCallCategory.search => l10n.toolCategorySearch,
      AiToolCallCategory.browser => l10n.toolCategoryBrowser,
      AiToolCallCategory.subagent => l10n.toolCategorySubagent,
      AiToolCallCategory.askUser => l10n.toolCategoryAskUser,
      AiToolCallCategory.plan => l10n.toolCategoryPlan,
      AiToolCallCategory.task => l10n.toolCategoryTask,
      AiToolCallCategory.mcp => l10n.toolCategoryMcp,
      AiToolCallCategory.other => l10n.toolCategoryOther,
    };
```

(确认该文件是否已有 import `AppLocalizations` / 现有 helper 风格;controller 变量名以现有代码为准——已有 `controller.setCotExpandReasoningOnOpen`,沿用同一 controller。)

- [ ] **Step 4: l10n**

`app_en.arb` 加(在 cotExpandToolsOnOpenDescription 之后):

```json
"thinkingProcessFoldSectionTitle": "Fold into thinking process",
"toolCategoryRead": "Read file",
"toolCategoryWrite": "Write file",
"toolCategoryEdit": "Edit file",
"toolCategoryCommand": "Shell command",
"toolCategorySearch": "Web search",
"toolCategoryBrowser": "Browser",
"toolCategorySubagent": "Subagent",
"toolCategoryAskUser": "Ask user",
"toolCategoryPlan": "Plan",
"toolCategoryTask": "Tasks & todos",
"toolCategoryMcp": "MCP",
"toolCategoryOther": "Other"
```

`app_zh.arb` 对应:

```json
"thinkingProcessFoldSectionTitle": "折叠进思考过程",
"toolCategoryRead": "读取文件",
"toolCategoryWrite": "写入文件",
"toolCategoryEdit": "编辑文件",
"toolCategoryCommand": "Shell 命令",
"toolCategorySearch": "网络搜索",
"toolCategoryBrowser": "浏览器",
"toolCategorySubagent": "子代理",
"toolCategoryAskUser": "询问用户",
"toolCategoryPlan": "计划",
"toolCategoryTask": "任务与待办",
"toolCategoryMcp": "MCP",
"toolCategoryOther": "其他"
```

(若项目用 flutter gen-l10n 生成,检查 `client/l10n.yaml`;生成的 `app_localizations.dart` 由构建/分析自动产出,无需手改。)

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/pages/config/layout_appearance_in_layout_section_test.dart`
Expected: PASS(若 gen-l10n 未自动跑,先 `flutter gen-l10n` 或 `flutter analyze` 触发)

- [ ] **Step 6: 提交**

```bash
git add client/lib/pages/config/layout_appearance_in_layout_section.dart \
        client/lib/l10n/app_en.arb \
        client/lib/l10n/app_zh.arb \
        client/test/pages/config/layout_appearance_in_layout_section_test.dart
git commit -m "feat(settings): per-category thinking-process fold toggles"
```

---

### Task 10: SessionChatMessageArea — AiToolCallFoldScope 装配

**Files:**
- Modify: `client/lib/pages/chat/session_chat_message_area.dart`
- Test: `client/test/pages/chat/session_history_review_messages_test.dart`(extend)

- [ ] **Step 1: 写组合守卫测试 — extend `session_history_review_messages_test.dart`**

**测试可达性说明**:`_harness` 直接渲染 `SessionHistoryReviewMessages`,而 Step 3 的 scope 包在 `SessionChatMessageArea` 的内层 Stack 里——harness 树中**不可见**。因此本测试不验证消息区装配本身(那由代码走查确认),而是**镜像生产的装配逻辑**验证组合:`LayoutCubit 默认偏好 → AiToolCallFoldScope 谓词 → 分组结果`。该测试在 Step 3 **前后都通过**(回归守卫),防止未来有人改坏偏好→折叠的链路。

消息顺序 **`[reasoning, Read, Task]`**(不能是 `[reasoning, Task, Read]`——那会产生两个链:reasoning 单独成链 + Read 单独成链,计数不可判别)。默认偏好下:Read(read,折)并入 reasoning 链(共 1 个链头);Task(subagent,不折)独立成行可见:

```dart
testWidgets('default prefs fold read but keep subagent standalone', (
  tester,
) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = LayoutCubit(repository: LayoutRepository(prefs));
  await cubit.load();
  final foldCategories = cubit.state.preferences.foldToolCallCategories;

  final runtime = ExternalStoreAiThreadRuntime()
    ..setMessages([
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [
          const AiReasoningPart(text: 'r'),
          // 注意:测试直接构造 part,不经标注管线 —— 必须显式给 category,
          // 否则默认 other 会导致谓词判断错误(Read 也会独立渲染)。
          AiToolCallPart(
            toolCallId: '1',
            toolName: 'Read',
            category: AiToolCallCategory.read,
          ),
          AiToolCallPart(
            toolCallId: '2',
            toolName: 'Task',
            category: AiToolCallCategory.subagent,
          ),
        ],
      ),
    ]);

  // 镜像 SessionChatMessageArea 的装配:scope 谓词来自 LayoutCubit 偏好
  final child = AiToolCallFoldScope(
    shouldFold: (part) => foldCategories.contains(part.category),
    child: _harness(state: readyState, runtime: runtime),
  );
  await tester.pumpWidget(
    BlocProvider.value(value: cubit, child: child),
  );
  await tester.pumpAndSettle();

  // 链头恰 1 个(reasoning + Read 折入)
  expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
  // Task(subagent,不折)独立成行可见
  expect(find.textContaining('Task'), findsWidgets);
  // Read 在折叠链内不可见
  expect(find.textContaining('Read'), findsNothing);
});
```

(`readyState` 用本文件既有测试的 ready 状态构造方式;`SharedPreferences` / `LayoutCubit` / `LayoutRepository` / `BlocProvider` 按本文件现有 import 风格补充。)

- [ ] **Step 2: 运行确认通过(前后都应通过)**

Run: `cd client && flutter test test/pages/chat/session_history_review_messages_test.dart`
Expected: PASS(组合链路已在 Task 7-8 就绪;本测试是守卫)

- [ ] **Step 3: 实现 `session_chat_message_area.dart`**

- `build()` 中 `prefs` 之外再加:

```dart
final foldCategories = context.select<LayoutCubit, Set<AiToolCallCategory>>(
  (c) => c.state.preferences.foldToolCallCategories,
);
```

- 用 scope 包裹内层 `Stack`(第 216 行起,同时覆盖 `SessionHistoryReviewMessages` 与子代理预览 overlay):

```dart
child: AiToolCallFoldScope(
  shouldFold: (part) => foldCategories.contains(part.category),
  child: Stack(
    children: [ ... ],
  ),
),
```

注意第 216 行处已有 `child: Stack(children: [...])`,直接在该 Stack 外包一层。`AiToolCallFoldScope` 是 InheritedWidget,重建开销极小且 `updateShouldNotify` 按谓词比较。装配正确性由走查确认:scope 位于 message-area 根,覆盖消息线程与子代理预览 overlay;谓词与 Step 1 测试的构造完全一致。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/pages/chat/session_history_review_messages_test.dart`
Expected: PASS(Step 3 后再次全量跑该文件,确认无回归)

- [ ] **Step 5: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 无 error/warning;全部测试通过

- [ ] **Step 6: 提交**

```bash
git add client/lib/pages/chat/session_chat_message_area.dart \
        client/test/pages/chat/session_history_review_messages_test.dart
git commit -m "feat(chat): wire thinking-process fold scope from preferences"
```

---

## 验证清单(全部完成后)

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
cd client/packages/ai_message_core && flutter test
cd client/packages/ai_message_ui && flutter test
```

## 风险与备注

- **loader 返回点以 worktree 内已提交版本为准**(2 处:148 缓存命中、229 新鲜;主工作区有未提交的 side-refresh 重标路径,本次不涉及——见 Task 5 备注)。
- **Task 6 是回归守卫**:mailbox 纯文本使 seat 补标在现有数据流不可达,测试前后都通过;实现正确性靠代码走查(`_applyMessages`(732)/ `_applySoftReloadMessages`(753)开头有 `_loader.annotate`;`_lastCli` 只在 `load()` 设置,seat CLI 稳定)。
- **Task 10 是组合守卫**:`SessionHistoryReviewMessages` harness 树中不含 `SessionChatMessageArea` 的 Stack,测试镜像生产装配(偏好 → scope 谓词),前后都通过;消息区装配本身靠代码走查。
- **fake registry 测试**:`fakeAiHistoryRegistry` 只注册 `AiHistoryCapability`,loader 的 category 走 fallback 默认表——这是设计内行为,不是 bug;`tool_call_category_mapping_test` 用 `CliToolRegistry.builtIn()` 覆盖全量映射。
- **`withAtLeastOneToolVisible`**:新增偏好字段时必须同步所有显式重建 `LayoutPreferences` 的地方(共 2 处:fromJson 与该方法本身)。
- **gen-l10n**:若 `client/lib/l10n/app_localizations_*.dart` 由生成器产出,不要手改;跑 `flutter gen-l10n` 或分析触发。
- **链头断言用图标**:`Icons.psychology_outlined`(chain_of_thought_view.dart:76),不依赖 strings 文案。
- **缓存一致性**:loader 缓存里存的是标注后的消息;`annotate` 幂等,seat 补标不会产生内容差异,`sameMessageListContent` 不受影响(类别不进 identity)。
