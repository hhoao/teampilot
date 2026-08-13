# Worktree 创建对话框重构设计

Date: 2026-08-13

## 背景

当前 worktree 创建对话框(`client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart`)用 SegmentedButton 提供"新建分支 / 已有分支"两种互斥模式,配合一个自由文本"Base (optional)"基线输入框。问题:

1. **无法同时"从下拉选源分支 + 自定义新分支名"**:新建分支模式下分支下拉隐藏,只能手动在基线框里敲源分支名;已有分支模式下分支名锁定为所选分支。
2. 基线输入框是自由文本,需要手敲 tag/commit 等任意 ref,且与分支下拉重复。
3. "创建后开始会话"选项使用率低,增加表单负担。

参照 Orca 的 worktree 创建体验(源类型 tabs + 可编辑名称 + reuse 语义),重构为无 tab 的单表单交互。

## 目标

- 一个名称输入框 + 一个可编辑分支/基线选择器 + 一个随机命名按钮,消除模式切换。
- 支持"选分支 → 自动填名 → 改名派生"的主要痛点流程。
- 删除"创建后开始会话"选项。

## 新交互

```
┌──────────────────────────────────────┐
│ 新分支名  [名称输入框        ] 🎲      │  ← 名称框 + 右侧随机按钮
│ 基线/源分支 [▼ 可编辑选择器     ]     │  ← TpSelectWithCustomInput
│ worktree 路径预览                     │
│ [创建]                                │
└──────────────────────────────────────┘
```

### 控件

1. **名称输入框**(共享,常驻):派生场景下决定新分支名;右侧 🎲 随机按钮点击填入 `wt-<6位hex>`(dart:math Random),可反复点击换一个,内容始终可手动编辑。
2. **基线/源分支选择器**:`TpSelectWithCustomInput`(shared_ui 现成组件,下拉列表 + 可输入自定义值)。
   - 下拉项 = 本地 + 远端分支(现有 `branchListLoader` 结果,沿用加载逻辑)。
   - 从下拉选中分支 → 名称框自动填入该分支名(仍可改)。
   - 直接输入文本 = 自定义基线(任意 ref:tag、commit hash、列表外分支)。

### 语义映射(纯函数 `buildWorktreeCreateResult`,可单测)

| 选择器内容 | 名称框内容 | 行为 | existingBranch | baseRef |
|-----------|-----------|------|----------------|---------|
| 空 | 任意 | 基于当前 HEAD 派生新分支 | false | null |
| 自定义文本(非下拉项) | 任意 | 从该 ref 派生新分支 | false | 自定义文本 |
| 本地分支 X(下拉选中或文本匹配) | X(未改) | 检出 X | true | null |
| 本地分支 X | ≠ X | 从 X 派生新分支 | false | X |
| 远端-only 分支 X(remoteRef=origin/X) | X | 从 origin/X 派生本地分支 X(不可检出,同现状) | false | origin/X |
| 远端-only 分支 X | ≠ X | 从 origin/X 派生新分支 | false | origin/X |

检出仅限**本地分支**:git 规定一个分支只能在一个 worktree 检出;远端-only 分支没有本地分支实体,只能派生(现状 `existingBranch: option.isLocal` 语义保留)。

### 删除项

- SegmentedButton(新建分支/已有分支模式切换)
- "Base (optional)" 自由文本基线输入框(被可编辑选择器取代)
- "创建后开始会话" 复选框 → `WorktreeCreateResult.startConversation` 字段、`showWorktreeCreateDialog` 的 `showStartConversationOption` 参数、sidebar 创建成功后的 `showWorkspaceComposeLandingWithWorktree` 调用全部移除

## 文件改动

| 文件 | 改动 |
|------|------|
| `client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart` | 重做交互;新增随机按钮;`_buildResult` 逻辑抽为纯函数 `buildWorktreeCreateResult`;删除 startConversation |
| `client/lib/services/git/worktree_branch_options.dart` | 新增 `randomWorktreeBranchName(List<String> existingPaths, {Random? random})` → `wt-<6位hex>`,与已有 worktree 目录 basename 冲突时重新生成 |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | `_createWorktree`:删除 startConversation 相关传参与调用;从 `WorktreeCubit.state.worktrees` 传入 `existingWorktreePaths`(随机避让) |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 新增名称框 label、选择器 hint、随机按钮 tooltip;删除 worktreeModeNewBranch / worktreeModeExistingBranch / worktreeBaseRefLabel / worktreeBaseRefHint / worktreeStartConversation 文案 |

`WorktreeCreateResult` 保留字段:`worktreePath`、`branch`、`baseRef`、`existingBranch`;删除 `startConversation`。

## 错误处理

- git add 失败 → 现有 AppToast 路径不变。
- 检出本地分支 X 已被其他 worktree 检出 → git 报错,AppToast 展示(不做前端门禁,YAGNI)。
- 随机名持续冲突(极端情况)→ 重试上限 20 次后回退到 `wt-<递增数字>`。

## 测试

- `randomWorktreeBranchName`:格式 `wt-[0-9a-f]{6}`;避开已有目录名;冲突后换名;上限回退。
- `buildWorktreeCreateResult` 纯函数:上表 6 种场景映射;空选择器/自定义文本/本地/远端-only。
- 现有 `worktree_branch_options_test.dart`、`git_worktree_service_*_test.dart`、`worktree_cubit_test.dart` 回归。
- 全量 `flutter test --exclude-tags integration` + `flutter analyze`。

## 范围外

- worktree 自定义显示名/目录名与分支名解耦(需 worktree meta 存储,另行设计)。
- 检出冲突前端门禁(依赖跨 worktree 分支占用查询)。
