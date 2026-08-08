# Git 变更列表：右侧对齐操作按钮 + 打开文件功能 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让源代码管理面板的变更行把悬停操作按钮右侧对齐（VS Code 风格），并新增「打开文件」按钮。

**Architecture:** 改动集中在 `client/lib/widgets/git/` 的四个文件与 `git_changes_visible_rows.dart` 宽度常量。文件行/文件夹行把 `OverflowBox` 换成有界 `SizedBox(width: double.infinity)` + `Row(Expanded 名称 + 右侧 trailing)`，从而支持右侧对齐。新增 `onOpenFile` 回调从面板经列表透传到行，面板用它调用 `WorkbenchEditorOpener.openFile`。`deleted` 类型的行不传打开文件回调。

**Tech Stack:** Flutter / Material Icons（`Icons.file_open_outlined`）/ flutter_bloc / shared_ui `TpIconButton` / `TpHover`。

## Global Constraints

- **悬停交互不变：** 非悬停显示状态字母（M/A/D…，右侧对齐），悬停时替换为按钮组。
- **deleted 行不显示打开文件按钮**（`GitChangeKind.deleted`，磁盘无文件）。
- **行点击仍打开 diff**（`onOpenDiff` 行为不变）。
- **保留横向滚动机制**：`contentWidth` 仍按最长行计算；`Expanded` 文件名带 `overflow: ellipsis`，普通状态不省略。
- **打开文件路径**：`WorkbenchEditorOpener.openFile(workspaceId, p.join(repoRoot, change.path))`。
- **l10n**：只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，然后 `flutter gen-l10n`（生成文件 `lib/l10n/app_localizations*.dart` 已提交，需一并提交）。
- **TDD**：每个任务先写失败测试 → 运行确认失败 → 实现 → 运行确认通过 → 提交。
- 复用 `TpIconButton` / `TpHover` / shared_ui；不在 `client/lib/widgets/` 下加新通用控件。
- `TpIconButton.kCompactSize` = 28，因此 3 按钮 = 84，2 按钮 = 56。

---

### Task 1: l10n key `gitOpenFile`

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated (commit): `client/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`, `l10n_extensions.dart`（`context.l10n` 的 getter 由生成类提供，无需手改）

**Interfaces:**
- Produces: `AppLocalizations.gitOpenFile` — 供 `GitChangeTile` 的 tooltip 使用（`context.l10n.gitOpenFile`）。

- [ ] **Step 1: 在 en arb 添加 key**

在 `client/lib/l10n/app_en.arb` 的 `"gitDiscard": "Discard changes",` 一行后加：

```json
  "gitOpenFile": "Open File",
```

- [ ] **Step 2: 在 zh arb 添加 key**

在 `client/lib/l10n/app_zh.arb` 的 `"gitDiscard": "放弃更改",` 一行后加：

```json
  "gitOpenFile": "打开文件",
```

- [ ] **Step 3: 重新生成 l10n**

Run: `cd client && flutter gen-l10n`
Expected: 成功生成 `lib/l10n/app_localizations*.dart`。

- [ ] **Step 4: 验证生成结果**

Run: `grep -n "gitOpenFile" lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart`
Expected: 三处都有 `gitOpenFile` getter/字段。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/l10n/l10n_extensions.dart
git commit -m "chore(l10n): add gitOpenFile string"
```

---

### Task 2: 变更行 trailing 宽度常量

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart:70-76, 117-134, 140-150`
- Test: `client/test/services/git/git_changes_visible_rows_test.dart`（新建）

**Interfaces:**
- Produces:
  - `const double kGitChangesTrailingActionsWidth = 84;`（未暂存行悬停：打开+放弃+暂存 3 按钮）
  - `const double kGitChangesTrailingTwoActionsWidth = 56;`（暂存行悬停 / 文件夹行：2 按钮）
  - `gitChangesMinContentWidth(...)` 现在为未暂存文件行、暂存文件行、文件夹行分别预留 84 / 56 / 56。
  - `kGitChangesTrailingBadgeWidth = 22` 保留（Task 3 的 `_badge` 使用）。

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/git/git_changes_visible_rows_test.dart`：

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_changes_visible_rows.dart';

void main() {
  GitChangesVisibleRow fileRow({required bool staged}) => GitChangesVisibleRow.file(
    change: GitFileChange(
      path: 'a.txt',
      kind: GitChangeKind.modified,
      staged: staged,
    ),
    depth: 0,
  );

  test('unstaged rows reserve wider trailing than staged/folder rows', () {
    const style = TextStyle(fontSize: 12);
    final unstaged = fileRow(staged: false);
    final staged = fileRow(staged: true);
    final folder = GitChangesVisibleRow.folder(
      folderPath: 'src',
      name: 'src',
      depth: 0,
    );

    final wUnstaged = gitChangesMinContentWidth(
      rows: [unstaged],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    final wStaged = gitChangesMinContentWidth(
      rows: [staged],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    final wFolder = gitChangesMinContentWidth(
      rows: [folder],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );

    expect(
      wUnstaged - wStaged,
      closeTo(
        kGitChangesTrailingActionsWidth - kGitChangesTrailingTwoActionsWidth,
        1,
      ),
    );
    expect(wFolder, closeTo(wStaged, 1));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: FAIL。当前 `kGitChangesTrailingActionsWidth=60`，暂存行 trailing 用 `kGitChangesTrailingBadgeWidth=22`，`wUnstaged - wStaged` 为 38 而非 28，`wFolder != wStaged`。

- [ ] **Step 3: 实现**

编辑 `client/lib/services/git/git_changes_visible_rows.dart`：

把常量（约 70-71 行）：

```dart
/// Trailing stage/unstage actions (two compact buttons).
const double kGitChangesTrailingActionsWidth = 60;
```

改为：

```dart
/// Trailing open/discard/stage actions on an unstaged row (three compact
/// buttons, `TpIconButton.kCompactSize` = 28).
const double kGitChangesTrailingActionsWidth = 84;

/// Trailing actions on a staged row or a folder row (two compact buttons).
const double kGitChangesTrailingTwoActionsWidth = 56;
```

在 `gitChangesMinContentWidth` 中，把文件夹行的 trailing（约 116 行）：

```dart
          kGitChangesRowHorizontalPadding * 2 +
          painter.width +
          kGitChangesTrailingActionsWidth;
```

改为 `+ kGitChangesTrailingTwoActionsWidth;`。

把文件行的 trailing 选择（约 124-126 行）：

```dart
    final trailing = row.change!.staged
        ? kGitChangesTrailingBadgeWidth
        : kGitChangesTrailingActionsWidth;
```

改为：

```dart
    final trailing = row.change!.staged
        ? kGitChangesTrailingTwoActionsWidth
        : kGitChangesTrailingActionsWidth;
```

把 `_rowWidthEstimate` 的 trailing 选择（约 146-148 行）：

```dart
  final trailing = row.isFolder || !row.change!.staged
      ? kGitChangesTrailingActionsWidth
      : kGitChangesTrailingBadgeWidth;
```

改为：

```dart
  final trailing = row.isFolder || row.change!.staged
      ? kGitChangesTrailingTwoActionsWidth
      : kGitChangesTrailingActionsWidth;
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/git/git_changes_visible_rows.dart client/test/services/git/git_changes_visible_rows_test.dart
git commit -m "refactor(git): widen changes tree trailing action widths"
```

---

### Task 3: 文件行右侧对齐 + 打开文件按钮（`GitChangeTile`）

**Files:**
- Modify: `client/lib/widgets/git/git_change_tile.dart:59-152`
- Test: `client/test/widgets/git/git_change_tile_test.dart`（新建）

**Interfaces:**
- Consumes: `AppLocalizations.gitOpenFile`（Task 1）、`kGitChangesTrailingBadgeWidth` / `kGitChangesNodeHeight` / `kGitChangesNodePaddingLeft` / `kGitChangesNodePaddingRight` / `kGitChangesRowHorizontalPadding`（已存在）、`TpIconButton`、`Icons.file_open_outlined`。
- Produces: `GitChangeTile.onOpenFile`（`VoidCallback?`，可空，默认 null）— Task 5 的 `GitChangesTreeList` 传入。

- [ ] **Step 1: 写失败测试**

新建 `client/test/widgets/git/git_change_tile_test.dart`：

```dart
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, height: 36, child: child),
    ),
  );

  GitChangeTile tile({
    required GitFileChange change,
    VoidCallback? onOpenFile,
  }) =>
      GitChangeTile(
        change: change,
        depth: 0,
        onOpenDiff: () {},
        onStage: () {},
        onUnstage: () {},
        onDiscard: () {},
        onOpenFile: onOpenFile,
      );

  Future<void> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
  }

  testWidgets('hover on unstaged row shows open/discard/stage right-aligned', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onOpenFile: () {},
        ),
      ),
    );
    await hover(tester, find.byType(GitChangeTile));

    expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    final rowRect = tester.getRect(find.byType(GitChangeTile).first);
    final btnRect = tester.getRect(find.byIcon(Icons.file_open_outlined));
    expect(rowRect.right - btnRect.right, lessThan(16));
  });

  testWidgets('hover on staged row shows open + unstage, no stage', (tester) async {
    await tester.pumpWidget(
      wrap(
        tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: true,
          ),
          onOpenFile: () {},
        ),
      ),
    );
    await hover(tester, find.byType(GitChangeTile));

    expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('badge shown when not hovered, no buttons', (tester) async {
    await tester.pumpWidget(
      wrap(
        tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        ),
      ),
    );

    expect(find.text('M'), findsOneWidget);
    expect(find.byIcon(Icons.file_open_outlined), findsNothing);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_change_tile_test.dart`
Expected: FAIL — `GitChangeTile` 尚无 `onOpenFile` 参数（编译错误），且悬停后无 `Icons.file_open_outlined`。

- [ ] **Step 3: 实现**

编辑 `client/lib/widgets/git/git_change_tile.dart`：

构造函数加参数（约 15-33 行，`onDiscard` 后）：

```dart
    required this.onDiscard,
    this.onOpenFile,
    this.hoverEnabled = true,
    super.key,
  });
```

字段加声明：

```dart
  final VoidCallback? onOpenFile;
```

`build` 中把 `OverflowBox(...)`（84-107 行）整体替换为：

```dart
        child: SizedBox(
          width: double.infinity,
          height: kGitChangesNodeHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 16),
              FileIconWidget(fileName: name),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
              const SizedBox(width: 8),
              if (_hovered) ..._actions(context) else _badge(cs),
            ],
          ),
        ),
```

把 `_badge`（111-120 行）的 `SizedBox(width: 22,` 改为 `SizedBox(width: kGitChangesTrailingBadgeWidth,`。

把 `_actions`（122-151 行）整体替换为：

```dart
  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final actions = <Widget>[
      if (widget.onOpenFile != null)
        TpIconButton(
          icon: Icons.file_open_outlined,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitOpenFile,
          onTap: widget.onOpenFile,
        ),
    ];
    if (widget.change.staged) {
      actions.add(
        TpIconButton(
          icon: Icons.remove,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitUnstage,
          onTap: widget.onUnstage,
        ),
      );
      return actions;
    }
    return [
      ...actions,
      TpIconButton(
        icon: Icons.undo,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.gitDiscard,
        onTap: widget.onDiscard,
      ),
      TpIconButton(
        icon: Icons.add,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.gitStage,
        onTap: widget.onStage,
      ),
    ];
  }
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_change_tile_test.dart`
Expected: PASS（3 个用例）。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/git/git_change_tile.dart client/test/widgets/git/git_change_tile_test.dart
git commit -m "feat(git): right-align change row actions and add open-file button"
```

---

### Task 4: 文件夹行右侧对齐（`GitChangeFolderTile`）

**Files:**
- Modify: `client/lib/widgets/git/git_change_folder_tile.dart:82-142`
- Test: `client/test/widgets/git/git_change_folder_tile_test.dart`（新建）

**Interfaces:**
- Consumes: `GitCubit`（构造 `GitCubit(service: stub)..setRepoRoot('/repo')`，不需要真实 git 调用）、`GitService`（可子类化，见面板测试模式）。

- [ ] **Step 1: 写失败测试**

新建 `client/test/widgets/git/git_change_folder_tile_test.dart`：

```dart
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_change_folder_tile.dart';

class _FolderGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('folder hover shows right-aligned stage button', (tester) async {
    final cubit = GitCubit(service: _FolderGitStub())..setRepoRoot('/repo');
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 36,
              child: GitChangeFolderTile(
                folderPath: 'src',
                name: 'src',
                depth: 0,
                cubit: cubit,
                onStage: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(GitChangeFolderTile)));
    await tester.pump();

    expect(find.byIcon(Icons.add), findsOneWidget);
    final rowRect = tester.getRect(find.byType(GitChangeFolderTile).first);
    final btnRect = tester.getRect(find.byIcon(Icons.add));
    expect(rowRect.right - btnRect.right, lessThan(16));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_change_folder_tile_test.dart`
Expected: FAIL — `rowRect.right - btnRect.right` 约为 400 − (按钮紧跟名称后的位置)，≥ 16；当前按钮紧跟文件夹名，不在右缘。

- [ ] **Step 3: 实现**

编辑 `client/lib/widgets/git/git_change_folder_tile.dart`，把 `build` 中 `OverflowBox(...)`（约 101-141 行）整体替换为：

```dart
        child: SizedBox(
          width: double.infinity,
          height: kGitChangesNodeHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                isExpanded ? Icons.folder_open : Icons.folder_outlined,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
              if (showActions) ...[
                const SizedBox(width: 8),
                ..._actions(context),
              ],
            ],
          ),
        ),
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_change_folder_tile_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/git/git_change_folder_tile.dart client/test/widgets/git/git_change_folder_tile_test.dart
git commit -m "feat(git): right-align folder row actions"
```

---

### Task 5: 面板与列表接线 `onOpenFile` + 打开文件集成测试

**Files:**
- Modify: `client/lib/widgets/git/git_changes_tree_list.dart:18-34, 192-202`
- Modify: `client/lib/widgets/git/git_source_control_panel.dart:282-303, 515-524`
- Test: `client/test/widgets/git/git_source_control_panel_open_file_test.dart`（新建）

**Interfaces:**
- Consumes: `GitChangeTile.onOpenFile`（Task 3）、`WorkbenchEditorOpener.openFile(String workspaceId, String path, {Filesystem? fs, bool preview})`、`GitCubit.state.repoRoot`、`GitChangeKind.deleted`。
- Produces: `GitChangesTreeList.onOpenFile`（`ValueChanged<GitFileChange>?`）— 面板传入 `_openFile`。

- [ ] **Step 1: 写失败测试**

新建 `client/test/widgets/git/git_source_control_panel_open_file_test.dart`：

```dart
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

class _UnstagedGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: [],
    unstaged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: false),
      GitFileChange(path: 'gone.txt', kind: GitChangeKind.deleted, staged: false),
    ],
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

class _RecordingOpener extends WorkbenchEditorOpener {
  _RecordingOpener({
    required super.editor,
    required super.workbench,
    required super.floating,
  }) : super(
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );

  final openedPaths = <String>[];

  @override
  Future<void> openFile(
    String workspaceId,
    String path, {
    Filesystem? fs,
    bool preview = true,
  }) async {
    openedPaths.add(path);
  }
}

void main() {
  late RuntimeContext workContext;
  late GitRepoStore store;
  _RecordingOpener? opener;

  setUp(() {
    setUpTestAppStorage();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    workContext = testRuntimeContext('/home');
    GitService.debugOverrideFactory = _UnstagedGitStub.new;
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    store.dispose();
    tearDownTestAppStorage();
  });

  Widget wrap(AiFeatureSettingsCubit aiSettingsCubit, Widget child) {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws-test');
    opener = _RecordingOpener(editor: editor, workbench: workbench, floating: floating);
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<GitRepoStore>.value(value: store),
          RepositoryProvider<WorkbenchEditorOpener>.value(value: opener!),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: aiSettingsCubit),
            BlocProvider.value(value: editor),
            BlocProvider.value(value: workbench),
          ],
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
    return gesture;
  }

  testWidgets('open-file button opens the changed file', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    addTearDown(aiSettingsCubit.close);

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/repo'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final rowA = find.ancestor(
      of: find.text('a.txt'),
      matching: find.byType(GitChangeTile),
    );
    expect(rowA, findsOneWidget);

    final gesture = await hover(tester, rowA);
    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pump();

    expect(opener!.openedPaths, ['/repo/a.txt']);
    await gesture.removePointer();
  });

  testWidgets('deleted rows do not show the open-file button', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    addTearDown(aiSettingsCubit.close);

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/repo'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final rowGone = find.ancestor(
      of: find.text('gone.txt'),
      matching: find.byType(GitChangeTile),
    );
    expect(rowGone, findsOneWidget);

    final gesture = await hover(tester, rowGone);

    expect(find.byIcon(Icons.file_open_outlined), findsNothing);
    await gesture.removePointer();
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_open_file_test.dart`
Expected: FAIL — `GitChangesTreeList` 尚无 `onOpenFile`，`GitChangeTile` 未收到打开文件回调 → 第一个用例点不到按钮、`openedPaths` 为空；第二个用例因打开文件按钮已出现在 deleted 行而失败（无 `onOpenFile` 过滤）。

- [ ] **Step 3: 实现 — 列表透传**

编辑 `client/lib/widgets/git/git_changes_tree_list.dart`：

构造函数加参数（`onConfirmDiscard` 后）：

```dart
    required this.onConfirmDiscard,
    this.onOpenFile,
    super.key,
  });
```

字段加声明：

```dart
  final ValueChanged<GitFileChange>? onOpenFile;
```

`_buildTreeRow` 中（约 192-202 行）把返回的 `GitChangeTile` 改为：

```dart
    final change = row.change!;
    final canOpenFile =
        widget.onOpenFile != null && change.kind != GitChangeKind.deleted;
    return GitChangeTile(
      key: ValueKey('${staged ? 'staged' : 'unstaged'}:${change.path}'),
      change: change,
      depth: row.depth,
      hoverEnabled: _hoverEnabled,
      onOpenDiff: () => widget.onOpenDiff(change),
      onStage: staged ? () {} : () => unawaited(widget.cubit.stage(change)),
      onUnstage: staged ? () => unawaited(widget.cubit.unstage(change)) : () {},
      onDiscard: staged ? () {} : () => widget.onConfirmDiscard(change),
      onOpenFile: canOpenFile ? () => widget.onOpenFile!(change) : null,
    );
```

- [ ] **Step 4: 实现 — 面板处理**

编辑 `client/lib/widgets/git/git_source_control_panel.dart`：

在 `_openDiff`（约 282-303 行）之后加：

```dart
  void _openFile(GitFileChange change) {
    final absolutePath = p.join(_cubit.state.repoRoot, change.path);
    unawaited(
      context
          .read<WorkbenchEditorOpener>()
          .openFile(workspaceId: widget.workspaceId, path: absolutePath),
    );
  }
```

在 `GitChangesTreeList(...)` 调用处（约 515-524 行）加：

```dart
                      onConfirmDiscard: (change) =>
                          unawaited(_confirmDiscard(change)),
                      onOpenFile: _openFile,
```

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_open_file_test.dart`
Expected: PASS（2 个用例）。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/git/git_changes_tree_list.dart client/lib/widgets/git/git_source_control_panel.dart client/test/widgets/git/git_source_control_panel_open_file_test.dart
git commit -m "feat(git): open changed file from source control panel"
```

---

### Task 6: 全量验证

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error / warning（`--no-fatal-infos` 允许 info）。

- [ ] **Step 2: 全量测试（排除集成）**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全部通过。重点确认新增 4 个测试文件与既有 `git_source_control_panel_generate_test.dart` 均 PASS。

- [ ] **Step 3: 如有遗留，修复并重跑**

若 analyze 或测试失败：修复后回到对应 Task 的 Step 4/5 重跑，直到全绿。

---

## 自检记录

- **Spec 覆盖：** 目标 1（文件行右对齐）→ Task 3；目标 2（打开文件按钮）→ Task 3 按钮 + Task 5 接线；目标 3（文件夹行右对齐）→ Task 4；宽度常量 → Task 2；l10n → Task 1；测试 4 条 → Task 3（悬停显示、点击打开、deleted 隐藏、右对齐结构断言）+ Task 4/5。
- **无占位符：** 每个任务含完整可运行代码与命令。
- **类型一致性：** `onOpenFile` 在 Task 3 定义为 `VoidCallback?`（行级，无参）；Task 5 定义为 `ValueChanged<GitFileChange>?`（列表级，带 change 参数）——行级用闭包 `() => widget.onOpenFile!(change)` 适配；`kGitChangesTrailingActionsWidth` / `kGitChangesTrailingTwoActionsWidth` 在 Task 2 与测试中命名一致。
