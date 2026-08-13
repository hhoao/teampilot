# 工作区内容搜索 UI（面板 + 搜索框档位）— 设计

Date: 2026-08-13
Status: Draft (brainstorming, rev 1)

## 背景与前置

- `teampilot_search` 包（Rust FFI 引擎 + 纯 Dart fallback）已在 `feat/teampilot-search-rust-engine` 分支实现：`WorkspaceContentSearchService`（本地/WSL → Rust，SSH → fallback）、`FilesystemSearchReader`（app `Filesystem` → `SearchFileReader` 适配）、`TpSearchMatch{ path, relativePath, lineNumber, lineText, matchStart, matchEnd }`（char 偏移）。
- 现有 UI：`workspace_search_dialog.dart`（Ctrl+P 风格 quick-open：`_SearchFilter{ all, conversations, files }`，搜会话标题/内容 + 文件名）；右侧工具面板区（文件树 / Git 等）由 `WorkspacePanePolicy` 管理 dock/overlay（窄屏 <840px 变 overlay）。
- 内容搜索（VS Code Ctrl+Shift+F 式）目前**无任何 UI 挂载**。

## 目标

1. 右侧工具面板新增「搜索」tab：完整功能（结果树、流式渲染、区间高亮跳转、glob 输入、**替换**）。
2. 现有搜索 dialog 的 `_SearchFilter` 新增独立档位 `content`：轻量内容搜索（输入 + 结果列表 + 跳转）。
3. **「全部」(all) 档不包含内容搜索结果**——内容搜索保持独立档位，不进 all/conversations/files 的聚合（内容搜索是重扫描 + 异步流，不应污染 quick-open 结果）。
4. 快捷键 Ctrl+Shift+F 打开/聚焦搜索面板。

## 架构

```
client/lib/
├── cubits/content_search/
│   └── content_search_cubit.dart              # 面板状态机
├── services/search/
│   ├── content_search_runner.dart             # 后端选择 + 流式收集
│   └── content_replacer.dart                  # 替换执行
└── pages/home_workspace/workspace/
    ├── workspace_search_panel.dart            # 面板根：输入区 + 选项行 + 结果树
    └── workspace_search_panel_sections.dart   # 文件分组 / 行 tile（区间高亮）
```

### ContentSearchCubit（flutter_bloc，放 cubits/content_search/）

状态：`idle / loading / results / error`，携带：

```dart
class ContentSearchState {
  final String query;
  final bool isRegex, caseSensitive, useGitignore;
  final List<String> filesToInclude, filesToExclude;
  final String replaceQuery;                    // 替换输入
  final List<ContentSearchFileGroup> files;     // 聚合结果：文件 → 行匹配
  final bool truncated;
  final bool searching;
  final Object? error;
  final String? replacedFile;                   // 最近替换提示
}
```

事件：`queryChanged`（debounce 后触发搜索）、`toggleRegex/Case/Gitignore`、`globsChanged`、`cancel`、`clear`、`replaceSingle(file, lineIndex, replacement)`、`replaceAll(replacement)`。

聚合语义：**文件先行**——stream 里首个命中某文件的匹配到达时立即创建 `ContentSearchFileGroup`（文件头先显示），后续匹配追加行；`truncated` 从引擎截断标记透出。

### ContentSearchRunner（services/search/content_search_runner.dart）

```dart
class ContentSearchRunner {
  ContentSearchRunner({required this.fs, required this.root});
  Stream<TpSearchMatch> run(TpSearchOptions options);
  String? get backendLabel;   // 'rust' | 'dart-fallback'（调试/展示用）
}
```

- 后端选择：`fs` 是 `SftpFilesystem`（或路径探针不支持）→ `fallbackSearch(FilesystemSearchReader(fs), ...)`；否则 `TpSearchEngine().search(root, ...)`（**每次搜索新建引擎实例**，规避单 handle 槽并发问题）。
- root：活动工作区项目文件夹（`Workspace.projectFolderPath`）；SSH 场景同样传入远端 root。
- 搜索由 Cubit 驱动，Stream 增量进 state；cancel → `engine.cancel()` / Stream 取消。

### ContentReplacer（services/search/content_replacer.dart）

```dart
class ContentReplacer {
  ContentReplacer({required this.fs});
  Future<int> replaceAllInFile({
    required String path,
    required List<TpSearchMatch> matches,      // 同一文件、行升序
    required String replacement,
  });  // 返回替换次数
}
```

- 流程：`readString(path)` → 按行还原偏移（`LineSplitter` + 逐行累计行长，保留行终止符语义）→ 对每个匹配在原文的 [start,end) 做替换，**从后往前应用**避免偏移漂移 → `writeString(path, newContent)`。
- `TpSearchMatch.matchStart/End` 即 **UTF-16 code unit 偏移**（两引擎均如此），可直接作为 Dart `String` 索引用于 `substring`/`replaceRange`。
- 替换字符串支持捕获组引用 `$1`（Dart `RegExp.replaceAll` 语义；对字面量匹配无组则原样替换）。
- SSH 后端同样可用（`SftpFilesystem.writeString` 已存在）。
- **不做 undo**：Replace All 前弹确认对话框（显示将替换条数）；单条 Replace 即时生效。
- 替换后：该文件所有已替换行从结果中移除或标记"已替换"（面板展示层处理），文件内容不重新扫描。

### 面板（workspace_search_panel.dart + sections）

- 顶部：pattern 输入（自动聚焦）+ 选项行（正则 / 大小写 / gitignore 三个 toggle + include/exclude 两个 glob 输入框）+ 替换输入框 + Replace All 按钮（替换输入非空时显示）+ 取消/清空按钮。
- 结果区：`ListView`（文件分组 header：路径 + 命中数 + 单文件 Replace；行 tile：行号 + 行文本 + 匹配区间高亮 → 点击 `EditorCubit.openFile(workspaceId, path, fs:)` + 行选择高亮，复用现有 `codeLineSelectionForLines` 工具）。
- 底部：`truncated` 提示（"结果过多，已显示前 N 条"）+ backend label。
- 空态 / 错误态（非法正则 → l10n 文案，不弹 snackbar）。

### 搜索 dialog 档位（workspace_search_dialog.dart 修改）

- `_SearchFilter` 增 `content`；**all/conversations/files 行为不变**（all 不含内容搜索）。
- 选中 `content`：输入框语义切换为内容搜索（debounce 300ms → runner），结果列表 tile：`文件名:行号` + 行文本预览（单行截断），点击跳转（同面板）；仅提供正则/大小写两个 toggle；无 glob/replace。
- 与现有文件/会话结果共用 dialog 外壳与键盘导航。

### 快捷键

- Ctrl+Shift+F：`workspace_split_pane.dart`（或 workspace_page 快捷键层）捕获 → 打开右工具面板并聚焦「搜索」tab；若面板已开则聚焦输入框。dialog 已有入口（侧边栏按钮 + 现有快捷键）不动。

## 数据流

```
输入 → debounce → ContentSearchCubit.search()
  → ContentSearchRunner.run()（选引擎）
  → Stream<TpSearchMatch> 增量 → state.files 聚合 → 面板渲染
点击行 → EditorCubit.openFile + 行选择高亮
替换 → ContentReplacer.replaceAllInFile() → 面板标记已替换
```

## 错误处理

| 情形 | 行为 |
|------|------|
| 非法正则 | 面板/对话框内联错误文案（l10n），不触发搜索 |
| root 不可读 / 引擎错误 | 错误态 UI + l10n 文案 |
| 单文件不可读（SSH） | 跳过（引擎既有语义），不报错 |
| 替换写回失败 | 错误态 + 该文件不标记已替换 |
| 搜索中取消 | 立即停流，state 回 idle |

## 测试

- `content_search_runner_test`：fake `Filesystem`（Local → 真 Rust 引擎 + 临时目录；SSH → 假 reader 验证走 fallback）。
- `content_search_cubit_test`：debounce、聚合顺序（文件先出）、truncated、cancel、替换状态。
- `content_replacer_test`：多行、CRLF、多匹配同行、捕获组 `$1`、区间相邻替换。
- 面板 widget 测试：输入 → 结果渲染 → 点击回调；替换确认对话框出现条件。
- dialog 档位测试：content 档结果渲染 + all 档不含内容结果。

## 不在 v1 范围

- 替换的 undo / 只替换选中文件（Replace All 为全局，单条可逐条替换）
- 搜索历史、跨工作区搜索、按语言过滤
- 面板内差异高亮 / 导出结果
