# 工作区搜索面板 VSCode 化重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将右侧工具栏内容搜索面板重构为 VSCode 搜索视图风格（chevron 替换行、内嵌选项切换、`⋯` 详情区、统计行、可折叠文件组、hover 每文件替换）。

**Architecture:** 纯 UI 层重构。`ContentSearchCubit` / `ContentSearchRunner` / `ContentReplacer` 零改动；面板本地 UI 状态（替换行/详情区展开、折叠集合）留在 widget state；复用 `widgets/find/` 的 VSCode 原语（`FindField` / `FindToggleButton` / `FindActionButton` / `FindBarPalette` / `FindBarIcons`）。

**Tech Stack:** Flutter + flutter_bloc + shared_ui（TpTextStyles / TpHover / TpDialog）+ flutter_svg（现有 SVG 资产）。

**Spec:** `docs/superpowers/specs/2026-08-25-workspace-search-panel-vscode-redesign-design.md`

## Global Constraints

- **零后端改动**：不修改 `ContentSearchCubit`、`ContentSearchRunner`、`ContentReplacer`、`teampilot_search` 包任何文件。
- **公开 API 不变**：`WorkspaceSearchPanel` 构造参数（`workspaceId` / `root` / `fs` / `focusRequest` / `onOpenResult`）保持不变。
- **不做 ab（全字匹配）与 AB（保留大小写）切换**：`TpSearchOptions` 无对应字段（只有 `pattern/isRegex/caseSensitive/smartCase/useGitignore/filesToInclude/filesToExclude/maxFileSize/maxResults`），spec 非目标禁止改引擎。搜索字段切换只有 **Aa（大小写）+ .*（正则）** 两个。
- **复用 find_bar 原语**：`FindField`（`width` 省略 = 全宽，用于拉伸 Column）、`FindToggleButton`、`FindActionButton`、`FindBarIcons`、`FindBarPalette`。不新建 SVG 资产，不改 `find_bar_widgets.dart` / `find_bar_palette.dart`。
- **行为不变项**：防抖 key/时长（`'workspace_search_panel'` 300ms、`'workspace_search_panel_globs'` 400ms）、`_maxPanelResults = 2000`、默认值（`_isRegex = true`、`_caseSensitive = false`、`_useGitignore = true`）、全局与每文件替换的确认对话框、错误内联红字、截断提示。
- **`⋯` 高亮条件**：include/exclude 非空 **或 gitignore 被关闭**（非默认过滤状态；spec 原文"gitignore 开启"有误——默认即开启，会导致常亮，按此修正执行）。
- **l10n**：只改 `client/lib/l10n/app_en.arb`（含 `@` 元数据）与 `app_zh.arb`（仅键值）；不硬编码文案。
- **验证命令**：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 且 `flutter test --exclude-tags integration` 全绿（每个任务至少跑受影响的测试文件）。
- 遵循 `docs/CODE_QUALITY.md`：无 `print`、诊断走 `AppLogger`（本任务无新增日志）、widget 文件保持聚焦。

---

### Task 1: 结果统计行 + 引擎标签上移

**Files:**
- Modify: `client/lib/l10n/app_en.arb`（workspaceSearch 区块末尾）
- Modify: `client/lib/l10n/app_zh.arb`（同位置）
- Modify: `client/lib/widgets/right_tools/search_panel.dart`
- Modify: `client/lib/widgets/right_tools/search_panel_results.dart`
- Test: `client/test/widgets/right_tools/search_panel_test.dart`

**Interfaces:**
- Consumes: `ContentSearchState.files`（`List<ContentSearchFileGroup>`，`group.lines.length` 为匹配数）、`state.searching`、`l10n.workspaceSearchSearching`（已存在）。
- Produces: `l10n.workspaceSearchResultSummary(int matches, int files)`；`SearchPanelResults` **移除** `backendLabel` 参数（Task 2/3 在此基础上改）。

- [ ] **Step 1: 写失败测试**

在 `client/test/widgets/right_tools/search_panel_test.dart` 的 `main()` 末尾追加：

```dart
  testWidgets('summary row shows match and file counts after a search', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.workspaceSearchResultSummary(1, 1)), findsOneWidget);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: FAIL（`workspaceSearchResultSummary` 未定义，编译错误即视为失败）

- [ ] **Step 3: 加 l10n 键**

`app_en.arb` 在 `workspaceSearchBackend` 的 `@` 元数据块之后追加：

```json
"workspaceSearchResultSummary": "{matches} results in {files} files",
"@workspaceSearchResultSummary": {
  "placeholders": {
    "matches": {
      "type": "int"
    },
    "files": {
      "type": "int"
    }
  }
},
```

`app_zh.arb` 在 `workspaceSearchBackend` 之后追加（zh 无 `@` 元数据）：

```json
"workspaceSearchResultSummary": "{matches} 个结果 · {files} 个文件",
```

- [ ] **Step 4: 面板加统计行、结果组件移除 backendLabel**

`search_panel.dart` 的 `build` 中，`BlocBuilder` builder 内、表单 `Padding` 之后 / `state.error` 区块之前插入：

```dart
            if (_queryController.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.searching
                            ? l10n.workspaceSearchSearching
                            : state.files.isEmpty
                            ? ''
                            : l10n.workspaceSearchResultSummary(
                                state.files.fold<int>(
                                  0,
                                  (sum, f) => sum + f.lines.length,
                                ),
                                state.files.length,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mutedSm,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_backendLabel(), style: styles.mutedSm),
                  ],
                ),
              ),
```

`search_panel_results.dart`：删除 `backendLabel` 字段与构造参数；`build` 改为：

```dart
    final itemCount = files.length + (truncated ? 1 : 0);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == files.length) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.workspaceSearchTruncated,
              style: styles.mutedSm,
            ),
          );
        }
        final group = files[index];
        return _FileGroupTile(
          group: group,
          replacement: replacement,
          onOpenResult: onOpenResult,
          onReplaceSingle: onReplaceSingle,
        );
      },
    );
```

`search_panel.dart` 中 `SearchPanelResults(...)` 调用删除 `backendLabel: _backendLabel(),` 一行。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: 全部 PASS（含原有 6 个测试）

- [ ] **Step 6: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/widgets/right_tools/search_panel.dart client/lib/widgets/right_tools/search_panel_results.dart client/test/widgets/right_tools/search_panel_test.dart
git commit -m "feat(search-panel): results summary row with engine label"
```

---

### Task 2: 文件组折叠 + hover 每文件替换

**Files:**
- Modify: `client/lib/widgets/right_tools/search_panel_results.dart`（整文件重写）
- Modify: `client/lib/widgets/right_tools/search_panel.dart`
- Test: `client/test/widgets/right_tools/search_panel_test.dart`

**Interfaces:**
- Consumes: `FindBarIcons.replaceAll`、`FindActionButton`（`assetPath` / `enabled` / `width` / `height` / `tooltip` / `onTap`）、Task 1 后的 `SearchPanelResults` 签名。
- Produces: `SearchPanelResults` 新签名 —— 新增必填 `collapsedPaths`（`Set<String>`）与 `onToggleGroup`（`void Function(String path)`）；`_FileGroupTile` 以 `ValueKey('search-group-<path>')` 稳定标识；每文件替换按钮 key 为 `ValueKey('search-file-replace-all')`。Task 3 依赖这两个 props。

- [ ] **Step 1: 写失败测试**

在 `search_panel_test.dart` 追加：

```dart
  testWidgets('tapping a file group header collapses and expands its lines', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    expect(find.textContaining('hello world'), findsWidgets);
    await tester.tap(find.textContaining('a.dart').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('hello world'), findsNothing);
    await tester.tap(find.textContaining('a.dart').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('hello world'), findsWidgets);
  });

  testWidgets('hover replace button replaces one file after confirm', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    await tester.enterText(find.byType(TextField).at(3), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-file-replace-all')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.workspaceSearchReplaceAllTitle), findsOneWidget);
    await tester.tap(find.text(l10n.workspaceSearchReplace).last);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(File('${fixture.path}/a.dart').readAsStringSync(), 'hi world\n');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: 新增 2 个测试 FAIL（无 `search-file-replace-all` key / 折叠不生效）

- [ ] **Step 3: 重写 `search_panel_results.dart`**

整文件替换为：

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/content_search/content_search_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../find/find_bar_widgets.dart';

/// Renders aggregated search results: collapsible file groups with matching
/// lines, a hover replace action per file, and the truncation footer.
class SearchPanelResults extends StatelessWidget {
  const SearchPanelResults({
    required this.files,
    required this.query,
    required this.truncated,
    required this.replacement,
    required this.collapsedPaths,
    required this.onToggleGroup,
    required this.onOpenResult,
    required this.onReplaceSingle,
    super.key,
  });

  final List<ContentSearchFileGroup> files;
  final String query;
  final bool truncated;
  final String replacement;
  final Set<String> collapsedPaths;
  final void Function(String path) onToggleGroup;
  final void Function(String path, int lineNumber) onOpenResult;
  final Future<void> Function(String path, String replacement) onReplaceSingle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    if (files.isEmpty) {
      return Center(
        child: Text(
          query.trim().isEmpty
              ? l10n.workspaceSearchEmptyHint
              : l10n.workspaceSearchNoResults,
          style: styles.mutedSm,
        ),
      );
    }
    final itemCount = files.length + (truncated ? 1 : 0);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == files.length) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.workspaceSearchTruncated,
              style: styles.mutedSm,
            ),
          );
        }
        final group = files[index];
        return _FileGroupTile(
          key: ValueKey('search-group-${group.path}'),
          group: group,
          collapsed: collapsedPaths.contains(group.path),
          replacement: replacement,
          onToggleGroup: () => onToggleGroup(group.path),
          onOpenResult: onOpenResult,
          onReplaceSingle: onReplaceSingle,
        );
      },
    );
  }
}

class _FileGroupTile extends StatelessWidget {
  const _FileGroupTile({
    required this.group,
    required this.collapsed,
    required this.replacement,
    required this.onToggleGroup,
    required this.onOpenResult,
    required this.onReplaceSingle,
    super.key,
  });

  final ContentSearchFileGroup group;
  final bool collapsed;
  final String replacement;
  final VoidCallback onToggleGroup;
  final void Function(String path, int lineNumber) onOpenResult;
  final Future<void> Function(String path, String replacement) onReplaceSingle;

  int get _pendingCount => group.lines.where((l) => !l.replaced).length;

  Future<void> _confirmReplace(BuildContext context) async {
    final l10n = context.l10n;
    final count = _pendingCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.workspaceSearchReplaceAllTitle),
            const SizedBox(height: 16),
            Text(l10n.workspaceSearchReplaceAllMessage(count)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                TpButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.workspaceSearchReplace),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await onReplaceSingle(group.path, replacement);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(
          group: group,
          collapsed: collapsed,
          pendingCount: _pendingCount,
          replaceEnabled: replacement.isNotEmpty && _pendingCount > 0,
          onToggle: onToggleGroup,
          onReplace: () => _confirmReplace(context),
        ),
        if (!collapsed)
          for (final line in group.lines)
            _LineTile(
              line: line,
              onTap: () => onOpenResult(group.path, line.lineNumber),
            ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
      ],
    );
  }
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.pendingCount,
    required this.replaceEnabled,
    required this.onToggle,
    required this.onReplace,
  });

  final ContentSearchFileGroup group;
  final bool collapsed;
  final int pendingCount;
  final bool replaceEnabled;
  final VoidCallback onToggle;
  final VoidCallback onReplace;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              AnimatedRotation(
                turns: widget.collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 120),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.group.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smSemibold,
                ),
              ),
              Text(
                '${widget.pendingCount}',
                style: styles.smColored(cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              // Hover-only per-file replace action, like the VS Code search
              // view. AnimatedOpacity keeps it hit-testable so tests can tap
              // it without synthesizing a hover.
              AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: FindActionButton(
                  key: const ValueKey('search-file-replace-all'),
                  assetPath: FindBarIcons.replaceAll,
                  tooltip: context.l10n.workspaceSearchReplaceAll,
                  enabled: widget.replaceEnabled,
                  width: 22,
                  height: 22,
                  onTap: widget.onReplace,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap});

  final ContentSearchLineMatch line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final base = styles.sm;
    final text = line.lineText;
    final start = line.matchStart.clamp(0, text.length);
    final end = line.matchEnd.clamp(start, text.length);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${line.lineNumber}',
                textAlign: TextAlign.right,
                style: styles.smColored(cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    if (start > 0) TextSpan(text: text.substring(0, start)),
                    TextSpan(
                      text: text.substring(start, end),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                      ),
                    ),
                    if (end < text.length) TextSpan(text: text.substring(end)),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 面板接入折叠状态**

`search_panel.dart` 的 `_WorkspaceSearchPanelState` 增加字段：

```dart
  final Set<String> _collapsedPaths = {};
```

`build` 中 `SearchPanelResults(...)` 调用改为：

```dart
              child: SearchPanelResults(
                files: state.files,
                query: _queryController.text.trim(),
                truncated: state.truncated,
                replacement: _replaceController.text,
                collapsedPaths: _collapsedPaths,
                onToggleGroup: (path) => setState(() {
                  if (!_collapsedPaths.add(path)) _collapsedPaths.remove(path);
                }),
                onOpenResult: (path, line) => _openResult(context, path, line),
                onReplaceSingle: (path, replacement) =>
                    _cubit.replaceSingle(path, replacement),
              ),
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: 全部 PASS（原 replace-all 测试的 `find.text(l10n.workspaceSearchReplaceAll).first` 现在唯一匹配全局 `TpButton` 文本，不受 hover 图标影响）

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/right_tools/search_panel.dart client/lib/widgets/right_tools/search_panel_results.dart client/test/widgets/right_tools/search_panel_test.dart
git commit -m "feat(search-panel): collapsible file groups with hover replace"
```

---

### Task 3: VSCode 表单区（搜索行 / 替换行 / ⋯ 详情区）

**Files:**
- Create: `client/lib/widgets/right_tools/search_panel_form.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Modify: `client/lib/widgets/right_tools/search_panel.dart`（表单区重写）
- Test: `client/test/widgets/right_tools/search_panel_test.dart`

**Interfaces:**
- Consumes: `FindField`（`controller` / `focusNode` / `hint` / `toggles` / `onChanged`）、`FindToggleButton`（`iconAsset` / `tooltip` / `checked` / `onTap`）、`FindActionButton`、`FindBarIcons.{caseSensitive,regexp,replaceAll}`、`FindBarPalette.of(context)`、`SearchPanelResults` 的 Task 2 签名。
- Produces: `SearchPanelChevron`（`{required bool expanded, required VoidCallback onTap}`）、`SearchPanelDetailsToggle`（`{required bool expanded, required bool highlighted, required VoidCallback onTap}`）、`SearchPanelDetailsSection`（`{required TextEditingController includeController, required FocusNode includeFocusNode, required TextEditingController excludeController, required FocusNode excludeFocusNode, required bool useGitignore, required ValueChanged<String> onGlobChanged, required ValueChanged<bool> onGitignoreChanged}`）—— 均放 `search_panel_form.dart`。
- l10n 新键：`workspaceSearchFilesToInclude` / `workspaceSearchFilesToExclude` / `workspaceSearchUseGitignore` / `workspaceSearchToggleDetails`。

- [ ] **Step 1: 写失败测试**

在 `search_panel_test.dart` 追加（并按下文 Step 5 更新旧测试）：

```dart
  testWidgets('chevron toggles the replace row', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.pumpWidget(wrap(cubit));
    expect(find.byKey(const ValueKey('search-replace-all')), findsNothing);
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-replace-all')), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-replace-all')), findsNothing);
  });

  testWidgets('details toggle reveals include/exclude and gitignore', (
    tester,
  ) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.pumpWidget(wrap(cubit));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.workspaceSearchFilesToInclude), findsNothing);
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text(l10n.workspaceSearchFilesToInclude), findsOneWidget);
    expect(find.text(l10n.workspaceSearchFilesToExclude), findsOneWidget);
    expect(find.text(l10n.workspaceSearchUseGitignore), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('option toggles flow into the searched options', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.pumpWidget(wrap(cubit));
    await tester.tap(find.byTooltip(l10n.workspaceSearchToggleDetails));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.editorFindMatchCase));
    await tester.tap(find.byTooltip(l10n.editorFindUseRegex));
    await tester.pump();
    await runSearch(tester, 'hello');
    expect(cubit.state.useGitignore, isFalse);
    expect(cubit.state.caseSensitive, isFalse);
    expect(cubit.state.isRegex, isFalse);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: 新增 3 个测试 FAIL（`workspaceSearchToggleDetails` 等未定义 / 无该交互）

- [ ] **Step 3: 加 l10n 键**

`app_en.arb`（紧跟 Task 1 的 `workspaceSearchResultSummary` 元数据后）：

```json
"workspaceSearchFilesToInclude": "Files to include:",
"workspaceSearchFilesToExclude": "Files to exclude:",
"workspaceSearchUseGitignore": "Use .gitignore settings",
"workspaceSearchToggleDetails": "Toggle search details",
```

`app_zh.arb`（同位置）：

```json
"workspaceSearchFilesToInclude": "包含的文件：",
"workspaceSearchFilesToExclude": "排除的文件：",
"workspaceSearchUseGitignore": "使用 .gitignore 设置",
"workspaceSearchToggleDetails": "展开搜索选项",
```

- [ ] **Step 4: 新建 `search_panel_form.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../find/find_bar_palette.dart';
import '../find/find_bar_widgets.dart';

/// Chevron that expands/collapses the replace row, like the VS Code search
/// view's left-edge toggle.
class SearchPanelChevron extends StatelessWidget {
  const SearchPanelChevron({
    required this.expanded,
    required this.onTap,
    super.key,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return Tooltip(
      message: context.l10n.editorFindToggleReplace,
      child: TpHover(
        width: 16,
        height: FindField.kHeight,
        borderRadius: BorderRadius.circular(3),
        hoverColor: palette.hoverBg,
        onTap: onTap,
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          child: Icon(Icons.chevron_right, size: 14, color: palette.icon),
        ),
      ),
    );
  }
}

/// `...` toggle for the search details section; stays highlighted while
/// non-default filters (include/exclude globs, gitignore off) are active.
class SearchPanelDetailsToggle extends StatelessWidget {
  const SearchPanelDetailsToggle({
    required this.expanded,
    required this.highlighted,
    required this.onTap,
    super.key,
  });

  final bool expanded;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FindActionButton(
      icon: Icons.more_horiz,
      tooltip: context.l10n.workspaceSearchToggleDetails,
      checked: expanded || highlighted,
      onTap: onTap,
    );
  }
}

/// Include/exclude glob fields + gitignore switch shown under the `...`
/// toggle (the VS Code search details body).
class SearchPanelDetailsSection extends StatelessWidget {
  const SearchPanelDetailsSection({
    required this.includeController,
    required this.includeFocusNode,
    required this.excludeController,
    required this.excludeFocusNode,
    required this.useGitignore,
    required this.onGlobChanged,
    required this.onGitignoreChanged,
    super.key,
  });

  final TextEditingController includeController;
  final FocusNode includeFocusNode;
  final TextEditingController excludeController;
  final FocusNode excludeFocusNode;
  final bool useGitignore;
  final ValueChanged<String> onGlobChanged;
  final ValueChanged<bool> onGitignoreChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = FindBarPalette.of(context);
    final styles = TpTextStyles.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: styles.xsColored(palette.mutedText)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(l10n.workspaceSearchFilesToInclude),
        FindField(
          controller: includeController,
          focusNode: includeFocusNode,
          hint: l10n.workspaceSearchIncludeHint,
          onChanged: onGlobChanged,
        ),
        const SizedBox(height: 8),
        label(l10n.workspaceSearchFilesToExclude),
        FindField(
          controller: excludeController,
          focusNode: excludeFocusNode,
          hint: l10n.workspaceSearchExcludeHint,
          onChanged: onGlobChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: useGitignore,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onGitignoreChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            Text(l10n.workspaceSearchUseGitignore, style: styles.sm),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: 重写 `search_panel.dart` 表单区**

整文件替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot_search/teampilot_search.dart' show TpSearchOptions;

import '../../cubits/content_search/content_search_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/io/filesystem.dart';
import '../../services/search/content_search_runner.dart';
import '../../utils/debounce/debounce.dart';
import '../find/find_bar_widgets.dart';
import 'search_panel_form.dart';
import 'search_panel_results.dart';

/// Right-tools search tool styled like the VS Code search view: a search row
/// with inline option toggles, an expandable replace row, a `...` details
/// section (globs + gitignore), and collapsible file-group results over the
/// workspace content search engines (Rust / Dart fallback).
class WorkspaceSearchPanel extends StatefulWidget {
  const WorkspaceSearchPanel({
    required this.workspaceId,
    required this.root,
    required this.fs,
    required this.focusRequest,
    this.onOpenResult,
    super.key,
  });

  final String workspaceId;
  final String root;
  final Filesystem fs;

  /// Bump to focus the query field (Ctrl+Shift+F).
  final ValueNotifier<int> focusRequest;

  /// Injectable open handler for tests; defaults to editor open + select line.
  final void Function(String path, int lineNumber)? onOpenResult;

  @override
  State<WorkspaceSearchPanel> createState() => _WorkspaceSearchPanelState();
}

class _WorkspaceSearchPanelState extends State<WorkspaceSearchPanel> {
  /// Result cap for the panel. The Rust engine stops at this cap (the
  /// truncation footer is derived by the cubit from the cap); the lazy
  /// [SearchPanelResults] list stays bounded.
  static const _maxPanelResults = 2000;

  final _queryController = TextEditingController();
  final _replaceController = TextEditingController();
  final _includeController = TextEditingController();
  final _excludeController = TextEditingController();
  final _focusNode = FocusNode();
  final _replaceFocusNode = FocusNode();
  final _includeFocusNode = FocusNode();
  final _excludeFocusNode = FocusNode();
  bool _isRegex = true;
  bool _caseSensitive = false;
  bool _useGitignore = true;
  bool _showReplace = false;
  bool _showDetails = false;
  final Set<String> _collapsedPaths = {};

  ContentSearchCubit get _cubit => context.read<ContentSearchCubit>();

  /// Captured in [didChangeDependencies] so [dispose] can cancel the search
  /// without an unsafe ancestor lookup on a deactivated element.
  ContentSearchCubit? _cubitRef;

  @override
  void initState() {
    super.initState();
    widget.focusRequest.addListener(_onFocusRequest);
    _queryController.addListener(_onQueryChanged);
    _replaceController.addListener(_onReplaceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubitRef = context.read<ContentSearchCubit>();
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onFocusRequest);
    _queryController.removeListener(_onQueryChanged);
    _replaceController.removeListener(_onReplaceChanged);
    _queryController.dispose();
    _replaceController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    _focusNode.dispose();
    _replaceFocusNode.dispose();
    _includeFocusNode.dispose();
    _excludeFocusNode.dispose();
    // Bump the search sequence so an in-flight stream bails out instead of
    // emitting after the provider closes this cubit on unmount.
    final cubit = _cubitRef;
    if (cubit != null && !cubit.isClosed) {
      cubit.cancel();
    }
    super.dispose();
  }

  void _onFocusRequest() => _focusNode.requestFocus();

  void _onQueryChanged() {
    Debounces.debounce(
      'workspace_search_panel',
      const Duration(milliseconds: 300),
      () {
        if (!mounted) return;
        _runSearch();
      },
    );
  }

  void _onReplaceChanged() {
    if (mounted) setState(() {});
  }

  TpSearchOptions get _options => TpSearchOptions(
    pattern: _queryController.text.trim(),
    isRegex: _isRegex,
    caseSensitive: _caseSensitive,
    useGitignore: _useGitignore,
    maxResults: _maxPanelResults,
    filesToInclude: _includeController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    filesToExclude: _excludeController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
  );

  void _runSearch() {
    if (_queryController.text.trim().isEmpty) {
      _cubit.clear();
      return;
    }
    _cubit.search(_options);
  }

  void _cancelSearch() => _cubit.cancel();

  /// Non-default filters keep the `...` toggle highlighted, like VS Code.
  bool get _hasActiveFilters =>
      _includeController.text.trim().isNotEmpty ||
      _excludeController.text.trim().isNotEmpty ||
      !_useGitignore;

  Future<void> _confirmReplaceAll(String replacement) async {
    final l10n = context.l10n;
    final count = _cubit.state.files.fold<int>(
      0,
      (sum, f) => sum + f.lines.where((l) => !l.replaced).length,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.workspaceSearchReplaceAllTitle),
            const SizedBox(height: 16),
            Text(l10n.workspaceSearchReplaceAllMessage(count)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                TpButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.workspaceSearchReplace),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _cubit.replaceAll(replacement);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return BlocBuilder<ContentSearchCubit, ContentSearchState>(
      builder: (context, state) {
        final query = _queryController.text.trim();
        final pendingCount = state.files.fold<int>(
          0,
          (sum, f) => sum + f.lines.where((l) => !l.replaced).length,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SearchPanelChevron(
                        expanded: _showReplace,
                        onTap: () =>
                            setState(() => _showReplace = !_showReplace),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FindField(
                                    controller: _queryController,
                                    focusNode: _focusNode,
                                    hint: l10n.workspaceSearchQueryHint,
                                    toggles: [
                                      FindToggleButton(
                                        iconAsset: FindBarIcons.caseSensitive,
                                        tooltip: l10n.editorFindMatchCase,
                                        checked: _caseSensitive,
                                        onTap: () => setState(() {
                                          _caseSensitive = !_caseSensitive;
                                          _runSearch();
                                        }),
                                      ),
                                      FindToggleButton(
                                        iconAsset: FindBarIcons.regexp,
                                        tooltip: l10n.editorFindUseRegex,
                                        checked: _isRegex,
                                        onTap: () => setState(() {
                                          _isRegex = !_isRegex;
                                          _runSearch();
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                                if (state.searching) ...[
                                  const SizedBox(width: 4),
                                  FindActionButton(
                                    icon: Icons.close,
                                    tooltip: l10n.workspaceSearchCancel,
                                    onTap: _cancelSearch,
                                  ),
                                ],
                              ],
                            ),
                            if (_showReplace) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: FindField(
                                      controller: _replaceController,
                                      focusNode: _replaceFocusNode,
                                      hint: l10n.workspaceSearchReplaceHint,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  FindActionButton(
                                    key: const ValueKey('search-replace-all'),
                                    assetPath: FindBarIcons.replaceAll,
                                    tooltip: l10n.editorFindReplaceAll,
                                    enabled:
                                        _replaceController.text.isNotEmpty &&
                                        pendingCount > 0,
                                    onTap: () => _confirmReplaceAll(
                                      _replaceController.text,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SearchPanelDetailsToggle(
                      expanded: _showDetails,
                      highlighted: _hasActiveFilters,
                      onTap: () =>
                          setState(() => _showDetails = !_showDetails),
                    ),
                  ),
                  if (_showDetails) ...[
                    const SizedBox(height: 4),
                    SearchPanelDetailsSection(
                      includeController: _includeController,
                      includeFocusNode: _includeFocusNode,
                      excludeController: _excludeController,
                      excludeFocusNode: _excludeFocusNode,
                      useGitignore: _useGitignore,
                      onGlobChanged: (_) => Debounces.debounce(
                        'workspace_search_panel_globs',
                        const Duration(milliseconds: 400),
                        () {
                          if (!mounted) return;
                          _runSearch();
                        },
                      ),
                      onGitignoreChanged: (v) => setState(() {
                        _useGitignore = v;
                        _runSearch();
                      }),
                    ),
                  ],
                  if (state.replacedCount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.workspaceSearchReplacedCount(state.replacedCount!),
                        style: styles.smColored(cs.primary),
                      ),
                    ),
                ],
              ),
            ),
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.searching
                            ? l10n.workspaceSearchSearching
                            : state.files.isEmpty
                            ? ''
                            : l10n.workspaceSearchResultSummary(
                                state.files.fold<int>(
                                  0,
                                  (sum, f) => sum + f.lines.length,
                                ),
                                state.files.length,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.mutedSm,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_backendLabel(), style: styles.mutedSm),
                  ],
                ),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  l10n.workspaceSearchError,
                  style: styles.smColored(cs.error),
                ),
              ),
            Expanded(
              child: SearchPanelResults(
                files: state.files,
                query: query,
                truncated: state.truncated,
                replacement: _replaceController.text,
                collapsedPaths: _collapsedPaths,
                onToggleGroup: (path) => setState(() {
                  if (!_collapsedPaths.add(path)) _collapsedPaths.remove(path);
                }),
                onOpenResult: (path, line) => _openResult(context, path, line),
                onReplaceSingle: (path, replacement) =>
                    _cubit.replaceSingle(path, replacement),
              ),
            ),
          ],
        );
      },
    );
  }

  String _backendLabel() =>
      ContentSearchRunner(fs: widget.fs, root: widget.root).backendLabel;

  void _openResult(BuildContext context, String path, int lineNumber) {
    final handler = widget.onOpenResult;
    if (handler != null) {
      handler(path, lineNumber);
      return;
    }
    final editor = context.read<EditorCubit>();
    editor.openFile(widget.workspaceId, path, fs: widget.fs);
    editor.selectLines(widget.workspaceId, path, startLine: lineNumber);
  }
}
```

- [ ] **Step 6: 更新受影响的旧测试**

`search_panel_test.dart` 中原 `replace all applies through the confirm dialog` 测试改为（替换行默认收起 + 按钮变图标）：

```dart
  testWidgets('replace all applies through the confirm dialog', (tester) async {
    final cubit = buildCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(wrap(cubit));
    await runSearch(tester, 'hello');
    expect(find.textContaining('hello world'), findsWidgets);

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-replace-all')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.workspaceSearchReplaceAllTitle), findsOneWidget);
    await tester.tap(find.text(l10n.workspaceSearchReplace).last);
    // The replace runs real file IO; interleave frames with real event-loop
    // turns so the fake-async zone can complete the read/write.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text(l10n.workspaceSearchReplacedCount(1)), findsOneWidget);
    expect(File('${fixture.path}/a.dart').readAsStringSync(), 'hi world\n');
  });
```

同时 Task 2 的 hover 替换测试里，`await tester.enterText(find.byType(TextField).at(3), 'hi');` 之前插入两行（表单重构后替换行默认收起，且字段顺序变为 query(0)、[replace(1) 展开时]、include、exclude）：

```dart
    await tester.tap(find.byTooltip(l10n.editorFindToggleReplace));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'hi');
```

（即原 `at(3)` 整行替换为上面三行；该测试内 `l10n` 变量在 tap 之前已可用，若定义顺序冲突则把 `final l10n = ...` 上移到 `pumpWidget` 之后。）

- [ ] **Step 7: 跑测试确认通过**

Run: `cd client && flutter test test/widgets/right_tools/search_panel_test.dart`
Expected: 全部 PASS（原 6 + 新增 5）

- [ ] **Step 8: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/widgets/right_tools/search_panel_form.dart client/lib/widgets/right_tools/search_panel.dart client/test/widgets/right_tools/search_panel_test.dart
git commit -m "feat(search-panel): vscode-style form with details section"
```

---

### Task 4: 全量验证

**Files:**
- 无新改动（如验证暴露问题则修复后一并提交）

**Interfaces:**
- Consumes: 前 3 个任务的全部产物。

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found

- [ ] **Step 2: 全量测试**

Run: `cd client && flutter test --exclude-tags integration`
Expected: All tests passed（如其它测试文件引用了被改面板的细节导致失败，修复测试或按 Global Constraints 修实现，修复后重跑）

- [ ] **Step 3: 收尾提交（如有修复）**

```bash
git add -A client/
git commit -m "fix(search-panel): address verification fallout"
```

（无修复则跳过本步）
