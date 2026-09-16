# 项目树工具栏恢复刷新按钮设计

## 背景

工作区 Session 列表顶部可以在“分组”和“项目树”视图之间切换。项目树视图依赖 `WorktreeCubit` 提供项目及 Git worktree 数据；此前该标题栏右侧按钮组包含刷新工作树按钮，但在拆分两种视图后被遗漏。

## 目标

在切换到“项目树”视图时，标题栏右侧按钮组恢复刷新按钮。点击后强制重新加载当前项目的 worktree 数据，使外部新增、删除或切换的 worktree 能立即反映在项目树中。

## 方案

在 `WorkspaceSidebar` 的项目树分支中恢复一个紧邻“新建工作树”按钮的 `TpIconButton`：

- 图标使用 `Icons.refresh_rounded`。
- tooltip 使用已有的 `worktreeRefreshTooltip` 本地化文案。
- 点击行为使用已有的 `throttledTap`，调用 `WorktreeCubit.load` 并传入 `force: true`。
- 仓库路径优先取 `WorktreeCubit.state.repoPath`，为空时回退到 `workspace.firstFolderPath`。
- 仅当当前工具上下文支持工作树管理时显示，与“新建工作树”按钮保持相同能力门控。

分组视图不显示该按钮，因为它不展示 worktree 层级；不改项目树分组算法、缓存策略或右侧文件树面板中的刷新操作。

## 数据流与错误处理

按钮只负责触发已有 Cubit 加载流程。`WorktreeCubit.load(..., force: true)` 负责绕过工作树快照缓存并发布新的 `WorktreeState`，`_ConversationListHost` 通过 Cubit 状态重建项目树。此次改动不新增错误状态或 toast，沿用现有 worktree 加载行为和日志路径。

## 测试

在现有工作区侧栏 widget 测试中增加覆盖：

1. 项目树视图且工具上下文支持 worktree 管理时，右侧显示刷新图标。
2. 点击刷新按钮会触发强制 worktree reload；测试使用注入的 `WorktreeLister` 记录调用，验证调用的仓库路径及 `force` 语义对应的重新探测行为。

测试通过仓库规定的 `dart run tool/run_tests.dart` 入口执行；完成前运行 `flutter analyze --no-fatal-infos --no-fatal-warnings` 与完整测试套件。

## 非目标

- 不把刷新按钮放入分组视图。
- 不重构标题栏或抽取通用工具栏组件。
- 不改变后台 worktree 自动刷新、文件树刷新或 Session 内容刷新机制。
