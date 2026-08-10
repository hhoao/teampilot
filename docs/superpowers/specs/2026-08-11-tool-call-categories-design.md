# 工具调用类别体系设计(Tool Call Categories)

**日期:** 2026-08-11
**状态:** 待实施

## 问题

当前聊天界面对工具调用的"分类"是隐式的,散落在多个地方:

- `AiToolCallPartView`(tool_call_part_view.dart:60-73)用一条**硬编码优先级链**依次尝试 subagent → shell → edit → file → fallback,决定渲染 chrome
- 5 个 CLI 的 `*ToolCallResolvers`(claude/opencode/codex/cursor/flashskyai)各自复制了一份几乎相同的 edit/file/shell 工具名映射表(claude/opencode/codex/flashskyai 字节相同,cursor 仅多 `execute`)
- 思考过程的折叠(`groupMessageParts`)把**所有** tool call 一律折入"思考过程 (N steps)"块,无法配置哪些类别折叠、哪些保持可见
- 没有正式类别概念:统计、导出、过滤、TeamBus、未来 chrome 切换都没有可依赖的分类依据

## 目标

- 建立 12 类的正式类别体系,类别是 `AiToolCallPart` 的**一等字段**,解析管线一次性标注
- 每 CLI 的类别映射收敛到共享默认表 + 每 CLI 增量,消灭重复
- 折叠配置以类别为维度(全局偏好),reasoning 恒折叠,tool call 按类别谓词折叠
- 渲染 chrome 本轮不动(类别已在模型上,后续可无痛切换为 category 驱动分发)
- 性能:标注每解析一次,渲染 O(1) 字段直读

## 设计

### 1. 类别模型 — `ai_message_core`

`ai_message_core/lib/src/message.dart` 新增枚举与字段:

```dart
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

- `AiToolCallPart` 增加 `final AiToolCallCategory category`,默认 `other`;`copyWith` 透传
- **不纳入 `messageContentIdentity`**:category 是派生数据,标注逻辑变更不应引起重载时内容指纹抖动
- `normalizeMessage` / coalesce 基于 copyWith,自动透传

新增纯接口 `ai_message_core/lib/src/tool_category_resolver.dart`:

```dart
abstract interface class AiToolCallCategoryResolver {
  AiToolCallCategory resolve(AiToolCallPart part);
}
```

### 2. 标注管线 — `client/lib`

**单一标注通道**:`AiHistoryLoader.load()` 在 `adapter.parse` + `SubagentAttachmentInflater.inflate` **之后**执行:

```dart
messages = annotateToolCallCategories(
  messages,
  resolver: cap.categoryResolver,  // ToolCallResolversCapability
);
```

- 初始加载 / `softReload` / `invalidateAndReload` 全部经此汇聚(ai_history_seat.dart:262/335/645),live 刷新也走 loader
- inflate 产生的子代理子消息一并被标注(annotate 在 inflate 之后)
- 标注结果随 loader 的 per-token 缓存一起缓存,不重复计算
- 未来任何新的 AiToolCallPart 构造路径必须复用 `annotateToolCallCategories`(唯一共享工具,文档注释中声明)

**共享映射表** `client/lib/services/ai_history/tool_call_categories.dart`:

```dart
class ConfigurableAiToolCallCategoryResolver implements AiToolCallCategoryResolver {
  const ConfigurableAiToolCallCategoryResolver({
    required this.nameRules,      // 精确工具名(小写)→ 类别
    this.prefixRules = const {},  // 前缀 → 类别(mcp__ → mcp)
  });
  // resolve: 先 exact 匹配,再前缀匹配,未命中 → other
}
```

共享默认表(12 类别 × 工具名,见附录 A):`defaultToolCallNameRules` + `defaultToolCallPrefixRules`。

**能力层**:`ToolCallResolversCapability`(tool_call_resolver_capability.dart)增加

```dart
AiToolCallCategoryResolver get categoryResolver;
```

5 个 CLI resolver 重构为**共享基类 + 每 CLI 增量**:基类 `SharedCliToolCallResolvers`(或等价组合)持有默认的 edit/file/shell/category 配置,cursor 仅覆盖 shell 集合追加 `execute`;删除 5 份近重复代码。

### 3. 折叠 — `ai_message_ui`

**新作用域** `ai_message_ui/lib/src/tool_call_fold_scope.dart`(仿 `AiToolCallBubbleScope` 的 InheritedWidget):

```dart
typedef AiToolCallFoldPredicate = bool Function(AiToolCallPart part);

class AiToolCallFoldScope extends InheritedWidget {
  final AiToolCallFoldPredicate? shouldFold; // null = 全部折叠(其他 host 的默认)
}
```

**分组**:`groupMessageParts(parts, {AiToolCallFoldPredicate? shouldFold})`(part_grouping.dart):

- `AiReasoningPart` 恒为 chain 材料(思考过程本体)
- `AiToolCallPart` 当且仅当 `shouldFold == null || shouldFold(part)` 时折入 chain
- 不折叠的 tool call 如同文本一样成为 run 边界,单独经 `AiRenderPart` 渲染(现有 chrome 不动)
- `AiMessageParts.build` 读取 `AiToolCallFoldScope.maybeOf(context)` 并把谓词传入分组
- 折叠块计数 `formatThinkingProcessSteps(run.length)` 只统计实际折入的 parts,天然正确
- `AiChainOfThoughtView` 内部渲染、autoExpand、`cotExpandReasoningOnOpen` / `cotExpandToolsOnOpen` 行为不变

### 4. 偏好与设置 — `client/lib`

- `LayoutPreferences` 新增 `foldToolCallCategories: Set<AiToolCallCategory>`
- **默认折叠**:{read, write, edit, command, search, browser, mcp, task}
- **默认可见**:{subagent, askUser, plan, other}(交互 / 关键事件不藏)
- 谓词组装:`(part) => prefs.foldToolCallCategories.contains(part.category)`,在 `SessionChatMessageArea` 用 `AiToolCallFoldScope` 包裹消息区(读 `LayoutCubit`)
- 设置页 `layout_appearance_in_layout_section.dart`"思考过程"区下新增每类别一行 `TpPreferenceRow` + Switch
- l10n:12 个类别名 + 区块标题(en / zh 各一份)

### 5. 渲染

本轮 **chrome 不动**:`AiToolCallPartView` 的解析优先级链保持现状。类别已在 part 上,后续将分发切换为 `switch (part.category)` 是独立小迭代(设计上已就绪)。

### 6. 文件结构总览

```
ai_message_core/lib/src/
  message.dart                        # AiToolCallCategory 枚举 + AiToolCallPart.category 字段
  tool_category_resolver.dart         # AiToolCallCategoryResolver 接口(新)

client/lib/services/ai_history/
  tool_call_categories.dart           # ConfigurableAiToolCallCategoryResolver + 共享默认表(新)
  tool_call_category_annotator.dart   # annotateToolCallCategories(新)

client/lib/services/cli/registry/capabilities/
  tool_call_resolver_capability.dart  # + categoryResolver
  claude_tool_call_resolvers.dart     # 重构为共享基类 + 增量
  codex_tool_call_resolvers.dart      # 同上
  flashskyai_tool_call_resolvers.dart # 同上
  opencode_tool_call_resolvers.dart   # 同上
  cursor_tool_call_resolvers.dart     # 同上(cursor 增量:shell + 'execute')

client/lib/services/session/
  ai_history_loader.dart              # parse + inflate 后调用 annotateToolCallCategories

client/packages/ai_message_ui/lib/src/
  tool_call_fold_scope.dart           # AiToolCallFoldScope(新)
  part_grouping.dart                  # groupMessageParts 增加谓词参数
  ai_message_parts.dart               # 读取 scope,传入谓词

client/lib/
  cubits/layout_cubit.dart            # preferences + foldToolCallCategories
  pages/config/layout_appearance_in_layout_section.dart  # 每类别 Switch
  pages/chat/session_chat_message_area.dart              # 注入 AiToolCallFoldScope
  l10n/app_en.arb / app_zh.arb        # 类别名 + 区块标题
```

## 测试

| 层 | 用例 |
|---|---|
| ai_message_core | 枚举;`AiToolCallPart` category 默认值 / copyWith;`messageContentIdentity` 不含 category |
| client(映射) | 每 CLI 全表测试:已知工具名 → 类别、`mcp__` 前缀 → mcp、未知 → other、大小写不敏感 |
| client(标注) | `annotateToolCallCategories` 对嵌套消息(子代理附件)一并标注;幂等 |
| ai_message_ui | `groupMessageParts` 谓词:reasoning 恒折、折 / 不折边界、混合 run、纯工具 run、计数只含折入 parts;scope 缺省 = 全折 |
| prefs | 默认折叠集合;toggle 持久化 |
| 设置页 | widget 测试:每类别 Switch 渲染与切换 |

## 性能

- 标注:O(parts) 每解析一次,随 loader per-token 缓存
- 渲染折叠判断:`part.category` 字段直读 + Set 包含检查,O(1)
- 分组:单遍线性,不变

## 不涉及范围

- 渲染 chrome(工具卡片样式 / 优先级链)— 后续 `switch(category)` 独立迭代
- `AiToolCallBubbleScope`(cli_task_bubbles / workflow 自定义气泡)— 保持不变
- 子代理预览、导出、统计等下游消费者 — 类别就绪后各自独立接入

## 附录 A — 共享默认映射表(草案)

| 类别 | 工具名(小写) |
|---|---|
| read | read, readfile, read_file, glob, grep, list, list_files, file_search, search_files, grep_search |
| write | write, writefile, write_file, create, create_file, createfile |
| edit | strreplace, edit, editnotebook, notebookedit, multi_edit, applypatch, apply_patch |
| command | bash, shell, shell_command, exec_command, run_shell_command, run_terminal_cmd, zsh, sh |
| search | websearch, web_search, webfetch, web_fetch, fetch, url_fetch, search_web |
| browser | browser, browser_navigate, browser_click, browser_type, browser_act, playwright, computer, computer_use |
| subagent | agent, task, workflow, spawn_agent, agentdelegate, subagent |
| askUser | askuserquestion, ask_user_question, ask_user |
| plan | plan, exitplanmode, exit_plan_mode |
| task | todowrite, todo_write, taskcreate, task_create, taskupdate, task_update |
| mcp | 前缀规则:`mcp__` |
| other | 其余一切(含 custom_tool_call 等) |
