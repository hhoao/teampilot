# Session 引用并继续完成设计

## 目标

在 Session 项目的右键菜单和悬浮“更多”菜单中增加“引用会话”。点击后进入新建对话页面，并将以下内容填入输入框：

```text
审查并继续完成该会话: <完整 Session 目录路径>
```

新建对话继续使用 Landing 页面当前的 CLI、团队、模型、权限和工作目录配置，从而支持使用其他 CLI 继续完成原 Session。原 Session 不被修改，也不复制其配置或运行状态。

## 已确认的范围

- 两个 Session 菜单入口都提供该操作：右键菜单、悬浮“更多”菜单。
- Session 路径是完整目录路径：

  `<teampilotRoot>/workspace/workspaces/{workspaceId}/sessions/{sessionId}`

- 路径使用当前存储后端的路径上下文；WSL/SSH 场景不转换为本机路径。
- “引用会话”只负责导航和填充文本，不自动提交新对话。
- 原 Session 保持不变。

## 架构

新建对话的预填文本属于 Workbench Landing 状态，而不是 Session 数据或 Landing 配置。

1. `TabStrip` 增加可选的 Landing 预填文本。
2. `WorkbenchCubit.enterLanding` 接受可选 `initialText`。
3. Session 菜单动作解析 Session 目录路径后，调用 Landing 入口并传入预填文本。
4. `WorkspaceSplitPane` 从 Workbench 状态读取文本，并传递给 `WorkspaceChatPane`。
5. `WorkspaceChatPane`、`WorkspaceChatLanding` 和 `UnboundComposeBody` 贯通该参数。
6. `UnboundComposeBody` 在预填参数变化时更新输入框，使 Landing 已打开时引用另一个 Session 也能生效。

普通进入 Landing 时不传预填文本：如果 Landing 已经打开，保留用户当前草稿；如果从 Session 切换到 Landing，则清除上一次引用操作留下的 Workbench 导航预填参数。输入框内容是否恢复由现有 Landing 草稿缓存机制决定，用户输入仍按现有机制持久化。

## 数据流

1. 用户从任一 Session 菜单点击“引用会话”。
2. 通过 `SessionRepository.fs()` 获取当前存储后端的 `WorkspaceLayout`。
3. 使用 `sessionDir(workspaceId, sessionId)` 生成完整 Session 目录路径。
4. 组合预填文本 `审查并继续完成该会话: <完整路径>`。
5. 进入对应 Workspace 的 Landing；若 Landing 已经显示，则更新当前输入框。
6. 用户提交时，沿用 Landing 当前的 `LandingLaunchContext` 创建新 Session。

## 异常处理

Session 路径解析可能受存储后端不可用或上下文初始化失败影响。发生异常时：

- 不改变当前页面或 Landing 输入内容；
- 使用 `AppLogger` 记录操作名、Workspace ID 和 Session ID；
- 显示本地化错误提示。

菜单关闭、页面卸载和异步操作期间的 `BuildContext` 生命周期遵循现有菜单操作模式，避免在 Context 已失效后继续导航或显示 Toast。

## 本地化

只修改 `client/lib/l10n/app_en.arb` 和 `client/lib/l10n/app_zh.arb`，增加菜单标签与路径解析失败提示。生成的本地化 Dart 文件按仓库现有生成流程更新，不手工维护 ARB 之外的源文件。

## 测试

增加或扩展测试覆盖：

- 右键菜单显示“引用会话”；
- 悬浮“更多”菜单显示“引用会话”；
- 点击后进入 Landing，并填充完整 Session 目录路径及准确文案；
- Landing 已打开时，引用另一个 Session 会替换输入框内容；
- 路径解析失败时保持当前页面并显示错误提示；
- 新建对话使用当前 Landing 配置，不继承原 Session 的 CLI/团队配置。

## 非目标

- 不实现跨 Session 的自动 transcript 导入或原生 CLI resume 参数映射。
- 不复制 Session 目录、Session JSON、CLI runtime 或 TeamBus 数据。
- 不修改 Session 模型、Session 持久化格式或原有会话生命周期。
