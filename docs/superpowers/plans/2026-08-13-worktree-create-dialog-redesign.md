# Worktree 创建对话框重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构 worktree 创建对话框为"名称框 + 随机按钮 + 可编辑基线选择器"的单表单交互,支持选分支后改名派生,删除"创建后开始会话"。

**Architecture:** 纯逻辑(`randomWorktreeBranchName`、`buildWorktreeCreateResult`)放入 `services/git/`,对话框(`worktree_create_dialog.dart`)只做 UI 组装;可编辑选择器复用 shared_ui 现成 `TpSelectWithCustomInput`;sidebar 只改传参。

**Tech Stack:** Flutter, shared_ui (TpSelectWithCustomInput), flutter_bloc (无新增依赖)。

**Spec:** `docs/superpowers/specs/2026-08-13-worktree-create-dialog-redesign-design.md`

## Global Constraints

- l10n 只编辑 `client/lib/l10n/app_en.arb` 和 `app_zh.arb`;生成的 `app_localizations*.dart` 用 `flutter gen-l10n` 重新生成,禁止手改
- 检出(existingBranch)仅限本地分支;远端-only 分支恒派生(沿用现状 `existingBranch: option.isLocal` 语义)
- 每条任务结束跑 `flutter test <相关文件>` 通过后提交,提交信息用 conventional commits
- 对话框纯逻辑函数不得引用 Flutter widget 类型(可单测)
- 现有 `GitWorktreeService.add` 签名不变,只改参数来源

---

### Task 1: 随机分支名生成器

**Files:**
- Modify: `client/lib/services/git/worktree_branch_options.dart`
- Test: `client/test/services/git/worktree_branch_options_test.dart`

**Interfaces:**
- Produces: `String randomWorktreeBranchName(List<String> existingPaths, {Random? random, int maxAttempts = 20})` — 生成 `wt-<6位小写hex>`,避开 `existingPaths` 各路径 basename 的冲突;尝试 `maxAttempts` 次仍冲突则回退到 `wt-<递增数字>`(从 2 开始)

- [ ] **Step 1: 写失败测试**

在 `worktree_branch_options_test.dart` 的 `main()` 内新增:

```dart
group('randomWorktreeBranchName', () {
  test('generates wt-<6 lowercase hex>', () {
    final name = randomWorktreeBranchName(const [], random: Random(42));
    expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(name), isTrue);
  });

  test('never collides with existing path basenames', () {
    final existing = ['/root/worktrees/repo/wt-a1b2c3', '/w/other-dir'];
    for (var seed = 0; seed < 500; seed++) {
      final name = randomWorktreeBranchName(existing, random: Random(seed));
      expect(name, isNot('wt-a1b2c3'));
      expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(name), isTrue);
    }
  });

  test('falls back to wt-<n> when attempts are exhausted', () {
    expect(
      randomWorktreeBranchName(const [], random: Random(0), maxAttempts: 0),
      'wt-2',
    );
    expect(
      randomWorktreeBranchName(
        ['/w/wt-2', '/w/wt-3'],
        random: Random(0),
        maxAttempts: 0,
      ),
      'wt-4',
    );
  });
});
```

文件顶部补 `import 'dart:math';`。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/git/worktree_branch_options_test.dart`
Expected: FAIL — `randomWorktreeBranchName` 未定义

- [ ] **Step 3: 实现**

在 `worktree_branch_options.dart` 顶部加 `import 'dart:math';`,文件末尾追加:

```dart
/// Random branch name `wt-<6 lowercase hex>` that avoids colliding with the
/// basenames of [existingPaths] (worktree directories). After [maxAttempts]
/// collisions, falls back to the first free `wt-<n>` (n from 2 upward).
String randomWorktreeBranchName(
  List<String> existingPaths, {
  Random? random,
  int maxAttempts = 20,
}) {
  final rng = random ?? Random();
  final used = <String>{
    for (final path in existingPaths) _pathBasename(path).trim().toLowerCase(),
  }..removeWhere((e) => e.isEmpty);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final candidate = 'wt-${_randomHex(rng, 6)}';
    if (!used.contains(candidate)) return candidate;
  }
  var n = 2;
  while (used.contains('wt-$n')) {
    n++;
  }
  return 'wt-$n';
}

String _randomHex(Random rng, int length) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(rng.nextInt(16).toRadixString(16));
  }
  return buf.toString();
}

String _pathBasename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final idx = normalized.lastIndexOf('/');
  return idx == -1 ? normalized : normalized.substring(idx + 1);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/git/worktree_branch_options_test.dart`
Expected: PASS(含既有 `mergeWorktreeBranchOptions`、`suggestWorktreeBranchName` 测试)

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/git/worktree_branch_options.dart client/test/services/git/worktree_branch_options_test.dart
git commit -m "feat(worktree): random branch name generator"
```

---

### Task 2: 对话框语义映射纯函数

**Files:**
- Create: `client/lib/services/git/worktree_create_result.dart`
- Test: `client/test/services/git/worktree_create_result_test.dart`

**Interfaces:**
- Consumes: `WorktreeBranchOption`(`.local(name)` / `.fromRemote(name:, remoteRef:)`, `displayLabel`、`name`、`isLocal`、`remoteRef` 来自 Task 1 所在文件)
- Produces:
  - `class WorktreeCreateResult { final String worktreePath; final String branch; final String? baseRef; final bool existingBranch; }`(含 `const` 构造,4 个 required 参数;无 `startConversation`)
  - `WorktreeCreateResult buildWorktreeCreateResult({required String branch, required String selectorText, required List<WorktreeBranchOption> options, required String worktreePath})`
  - `WorktreeBranchOption? worktreeOptionForLabel(List<WorktreeBranchOption> options, String label)` — 按 `displayLabel` 精确匹配(供 Task 3 自动填名复用)

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/git/worktree_create_result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/worktree_branch_options.dart';
import 'package:teampilot/services/git/worktree_create_result.dart';

void main() {
  const options = [
    WorktreeBranchOption.local('main'),
    WorktreeBranchOption.local('feat/x'),
    WorktreeBranchOption.fromRemote(
      name: 'feature/expert-hub',
      remoteRef: 'origin/feature/expert-hub',
    ),
  ];

  WorktreeCreateResult build({
    String branch = 'feat/x-wt',
    String selectorText = '',
  }) => buildWorktreeCreateResult(
    branch: branch,
    selectorText: selectorText,
    options: options,
    worktreePath: '/root/worktrees/repo/feat/x-wt',
  );

  group('buildWorktreeCreateResult', () {
    test('empty selector derives from current HEAD', () {
      final r = build(selectorText: '');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, isNull);
      expect(r.branch, 'feat/x-wt');
    });

    test('custom selector text is used as the base ref', () {
      final r = build(branch: 'hotfix', selectorText: 'v1.2.0');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'v1.2.0');
      expect(r.branch, 'hotfix');
    });

    test('local branch X with name X checks out X', () {
      final r = build(branch: 'feat/x', selectorText: 'feat/x');
      expect(r.existingBranch, isTrue);
      expect(r.baseRef, isNull);
      expect(r.branch, 'feat/x');
    });

    test('local branch X with a different name derives from X', () {
      final r = build(branch: 'feat/x-wt', selectorText: 'feat/x');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'feat/x');
      expect(r.branch, 'feat/x-wt');
    });

    test('remote-only branch derives from its remote ref', () {
      final r = build(
        branch: 'feature/expert-hub',
        selectorText: 'origin/feature/expert-hub',
      );
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'origin/feature/expert-hub');
      expect(r.branch, 'feature/expert-hub');
    });

    test('remote-only branch with a different name derives', () {
      final r = build(
        branch: 'hub-work',
        selectorText: 'origin/feature/expert-hub',
      );
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'origin/feature/expert-hub');
      expect(r.branch, 'hub-work');
    });

    test('empty branch name throws ArgumentError', () {
      expect(
        () => build(branch: '  '),
        throwsArgumentError,
      );
    });
  });

  group('worktreeOptionForLabel', () {
    test('matches local and remote-only by display label', () {
      expect(
        worktreeOptionForLabel(options, 'feat/x')?.name,
        'feat/x',
      );
      expect(
        worktreeOptionForLabel(options, 'origin/feature/expert-hub')?.remoteRef,
        'origin/feature/expert-hub',
      );
    });

    test('returns null for unknown or empty labels', () {
      expect(worktreeOptionForLabel(options, 'main/other'), isNull);
      expect(worktreeOptionForLabel(options, ''), isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/git/worktree_create_result_test.dart`
Expected: FAIL — 无法解析 import `worktree_create_result.dart`

- [ ] **Step 3: 实现**

创建 `client/lib/services/git/worktree_create_result.dart`:

```dart
import 'worktree_branch_options.dart';

/// Result of [buildWorktreeCreateResult]; the dialog pops it on create.
class WorktreeCreateResult {
  const WorktreeCreateResult({
    required this.worktreePath,
    required this.branch,
    required this.baseRef,
    required this.existingBranch,
  });

  /// Absolute path where the worktree will be created.
  final String worktreePath;

  /// Branch name: checked out when [existingBranch], else created new.
  final String branch;

  /// Base ref for a new branch; null/empty means current HEAD.
  final String? baseRef;

  /// True → check out [branch]; false → create a new branch from [baseRef].
  final bool existingBranch;
}

/// Maps the dialog's free-form inputs to `git worktree add` semantics:
/// - Empty selector → derive [branch] from current HEAD.
/// - Selector text matching a local branch X → check out X when
///   [branch] == X, otherwise derive [branch] from X.
/// - Selector text matching a remote-only branch (displayed as `origin/x`) →
///   derive [branch] from `origin/x`.
/// - Any other selector text → treat as a custom ref and derive from it.
WorktreeCreateResult buildWorktreeCreateResult({
  required String branch,
  required String selectorText,
  required List<WorktreeBranchOption> options,
  required String worktreePath,
}) {
  final trimmedBranch = branch.trim();
  if (trimmedBranch.isEmpty) {
    throw ArgumentError.value(branch, 'branch', 'must not be empty');
  }
  final trimmedSelector = selectorText.trim();
  final option = worktreeOptionForLabel(options, trimmedSelector);
  if (option != null) {
    if (option.isLocal && trimmedBranch == option.name) {
      return WorktreeCreateResult(
        worktreePath: worktreePath,
        branch: option.name,
        baseRef: null,
        existingBranch: true,
      );
    }
    return WorktreeCreateResult(
      worktreePath: worktreePath,
      branch: trimmedBranch,
      baseRef: option.remoteRef ?? option.name,
      existingBranch: false,
    );
  }
  return WorktreeCreateResult(
    worktreePath: worktreePath,
    branch: trimmedBranch,
    baseRef: trimmedSelector.isEmpty ? null : trimmedSelector,
    existingBranch: false,
  );
}

/// Option whose [WorktreeBranchOption.displayLabel] equals [label], else null.
WorktreeBranchOption? worktreeOptionForLabel(
  List<WorktreeBranchOption> options,
  String label,
) {
  if (label.isEmpty) return null;
  for (final option in options) {
    if (option.displayLabel == label) return option;
  }
  return null;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/git/worktree_create_result_test.dart`
Expected: PASS(7 + 2 个测试)

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/git/worktree_create_result.dart client/test/services/git/worktree_create_result_test.dart
git commit -m "feat(worktree): worktree create result semantics mapper"
```

---

### Task 3: 对话框重做

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart`
- Test: `client/test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`

**Interfaces:**
- Consumes: `randomWorktreeBranchName`(Task 1)、`WorktreeCreateResult` / `buildWorktreeCreateResult` / `worktreeOptionForLabel`(Task 2)、`TpSelectWithCustomInput`(shared_ui 已导出)
- Produces: `Future<WorktreeCreateResult?> showWorktreeCreateDialog(BuildContext context, {required String repoName, required String repoPath, required WorktreeLayoutPathResolver layout, required BranchListLoader branchLoader, List<String> existingWorktreePaths = const []})` — 注意:删除 `showStartConversationOption` 参数;新增 `existingWorktreePaths`

- [ ] **Step 1: 写失败测试**

创建 `client/test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`(模型参照 `client/test/widgets/compose/simple_custom_launch_dialog_test.dart` 的 MaterialApp + localizations 宿主):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/workspace/worktree_create_dialog.dart';

const _localBranches = ['main', 'feat/x'];

Future<List<WorktreeBranchOption>> _loader(String repoPath) async =>
    mergeWorktreeBranchOptions(local: _localBranches, remote: const []);

Widget _host({
  required Widget home,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

void main() {
  testWidgets('create derives from HEAD when no branch is selected', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New worktree'), findsOneWidget);

    // Default name suggestion filled in.
    expect(
      find.widgetWithText(TextField, 'main-wt'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.existingBranch, isFalse);
    expect(result!.baseRef, isNull);
    expect(result!.branch, 'main-wt');
    expect(result!.worktreePath, '/root/worktrees/repo/main-wt');
  });

  testWidgets('random button fills the name with wt-<hex>', (tester) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                  existingWorktreePaths: const [
                    '/root/worktrees/repo/main-wt',
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Random name'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(field.controller!.text), isTrue);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result!.existingBranch, isFalse);
    expect(result!.baseRef, isNull);
  });

  testWidgets('no start-conversation checkbox exists anymore', (tester) async {
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWorktreeCreateDialog(
                context,
                repoName: 'repo',
                repoPath: '/repo',
                layout: ({required repoName, required branch}) =>
                    '/root/worktrees/$repoName/$branch',
                branchLoader: _loader,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Start a conversation here after creating'),
      findsNothing,
    );
  });
}
```

注意:测试文件顶部还需要 `import 'package:teampilot/services/git/worktree_branch_options.dart';`。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
Expected: FAIL — `showWorktreeCreateDialog` 仍有 `showStartConversationOption` 依赖或测试无法编译

- [ ] **Step 3: 实现对话框**

重写 `client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart`:

1. 头部 import 增删:
   - 加 `import '../../../services/git/worktree_create_result.dart';`
   - `worktree_branch_options.dart` 的 import 与 `export ... show suggestWorktreeBranchName;` 原样保留(文件内继续使用 `mergeWorktreeBranchOptions` 与 `suggestWorktreeBranchName`)
2. 删除整个 `WorktreeCreateResult` 类定义(移到 Task 2 文件),文件不再定义它
3. `showWorktreeCreateDialog` 签名改为:

```dart
Future<WorktreeCreateResult?> showWorktreeCreateDialog(
  BuildContext context, {
  required String repoName,
  required String repoPath,
  required WorktreeLayoutPathResolver layout,
  required BranchListLoader branchLoader,
  List<String> existingWorktreePaths = const [],
}) {
  return showDialog<WorktreeCreateResult>(
    context: context,
    builder: (_) => _WorktreeCreateDialog(
      repoName: repoName,
      repoPath: repoPath,
      layout: layout,
      branchLoader: branchLoader,
      existingWorktreePaths: existingWorktreePaths,
    ),
  );
}
```

4. `_WorktreeCreateDialog` 增加 `final List<String> existingWorktreePaths;`
5. `_WorktreeCreateDialogState` 重做:

```dart
class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  final _branch = TextEditingController();
  String _selectorValue = '';
  List<WorktreeBranchOption> _branchOptions = const [];
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await widget.branchLoader(widget.repoPath);
      if (!mounted) return;
      setState(() {
        _branchOptions = list;
        _loadingBranches = false;
        if (_branch.text.trim().isEmpty && list.isNotEmpty) {
          _branch.text = suggestWorktreeBranchName(list.first.name);
        }
      });
    } on Object {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  void _applyRandomName() {
    setState(() {
      _branch.text = randomWorktreeBranchName(widget.existingWorktreePaths);
    });
  }

  void _onSelectorChanged(String value) {
    setState(() {
      _selectorValue = value;
      final option = worktreeOptionForLabel(_branchOptions, value);
      if (option != null) {
        _branch.text = option.name;
      }
    });
  }

  List<String> get _selectorItems =>
      [for (final option in _branchOptions) option.displayLabel];

  String get _previewPath => _branch.text.trim().isEmpty
      ? ''
      : widget.layout(
          repoName: widget.repoName,
          branch: _branch.text.trim(),
        );

  WorktreeCreateResult _buildResult() => buildWorktreeCreateResult(
    branch: _branch.text,
    selectorText: _selectorValue,
    options: _branchOptions,
    worktreePath: _previewPath,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.worktreeCreateTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _branch,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.worktreeBranchLabel,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingBranches)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    TpIconButton(
                      icon: Icons.casino_outlined,
                      size: TpIconButton.kCompactSize,
                      tooltip: l10n.worktreeRandomNameTooltip,
                      onTap: _applyRandomName,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TpSelectWithCustomInput(
              value: _selectorValue,
              items: _selectorItems,
              onChanged: _onSelectorChanged,
              hintText: l10n.worktreeBaseSelectorHint,
              decoration: TpSelectDecorations.themed(context),
              customInputTooltip: l10n.worktreeBaseSelectorHint,
            ),
            const SizedBox(height: 12),
            if (_previewPath.isNotEmpty) ...[
              Text(l10n.worktreePathLabel, style: TpTextStyles(theme).xs),
              const SizedBox(height: 2),
              Text(
                _previewPath,
                style: TpTextStyles(theme).sm,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _branch.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_buildResult()),
          child: Text(l10n.worktreeCreateAction),
        ),
      ],
    );
  }
}
```

保留文件内 `branchListLoaderFor` 与 `WorktreeLayoutPathResolver` 原样;`_buildResult` 现在只做一行委托。若 `theme` 变量未在 build 中使用则删除对应局部变量(路径预览处用 `TpTextStyles(theme)` 需要 `final theme = Theme.of(context);`)。

6. l10n 新增(`app_en.arb` + `app_zh.arb`,放在 `worktreeCreateFailed` 之后):

```json
"worktreeBaseSelectorHint": "Branch or ref",
"worktreeRandomNameTooltip": "Random name",
```

zh:
```json
"worktreeBaseSelectorHint": "分支或基线",
"worktreeRandomNameTooltip": "随机名称",
```

7. 重新生成 l10n:

Run: `flutter gen-l10n`(生成的 `client/lib/l10n/app_localizations*.dart` 一并纳入提交)

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
Expected: PASS(3 个 widget 测试)

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error/warning(其余文件会因 Task 4 未完成而报 sidebar 的编译错误,以 `worktree_create_dialog.dart` 相关为参考;若 sidebar 报错,属预期,Task 4 修复)

- [ ] **Step 5: 提交**

```bash
git add client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart client/test/pages/home_workspace/workspace/worktree_create_dialog_test.dart client/lib/l10n/
git commit -m "feat(worktree): redesign create dialog with branch selector and random name"
```

---

### Task 4: Sidebar 集成

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart:233-278`(`_createWorktree`)

**Interfaces:**
- Consumes: 新签名 `showWorktreeCreateDialog(... existingWorktreePaths:)`(Task 3);`WorktreeCubit.state.worktrees` 的 `GitWorktree.path`
- Produces: 无(行为变化:创建后不再自动打开会话)

- [ ] **Step 1: 先改调用点(带行为验证)**

`_createWorktree` 中:

```dart
    final result = await showWorktreeCreateDialog(
      context,
      repoName: _basename(repoPath),
      repoPath: repoPath,
      layout: layout.worktreePathFor,
      branchLoader: branchListLoaderFor(tools.context),
      existingWorktreePaths: [
        for (final wt in cubit.state.worktrees) wt.path,
      ],
    );
    if (result == null) return;
    try {
      await GitWorktreeService.forContext(tools.context).add(
        repoPath,
        result.worktreePath,
        branch: result.branch,
        baseRef: result.baseRef,
        existingBranch: result.existingBranch,
      );
      await cubit.load(repoPath, force: true);
      cubit.setCurrentWorktree(result.worktreePath);
    } on Object catch (error) {
```

即:删除 `showStartConversationOption: true` 传参;删除创建成功后整个 `if (result.startConversation && context.mounted) { ... showWorkspaceComposeLandingWithWorktree(...) }` 块。

- [ ] **Step 2: 验证编译与静态检查**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error/warning。注意:若 `home_workspace_route.dart` import 因 `showWorkspaceComposeLandingWithWorktree` 不再使用而出现 unused import 提示,而 `showWorkspaceComposeLanding`(`_startNewConversation` 用)也来自同一 import,则保留该 import 并确认无警告。

- [ ] **Step 3: 回归测试**

Run: `flutter test test/cubits/worktree_cubit_test.dart test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_sidebar.dart
git commit -m "feat(worktree): wire sidebar to redesigned create dialog"
```

---

### Task 5: l10n 清理与全量验证

**Files:**
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`

- [ ] **Step 1: 删除不再使用的文案键**

从 `app_en.arb` 与 `app_zh.arb` 删除以下 5 个键(连带 `app_en.arb` 中的元数据,若有):

- `worktreeModeNewBranch`
- `worktreeModeExistingBranch`
- `worktreeBaseRefLabel`
- `worktreeBaseRefHint`
- `worktreeStartConversation`

删除前确认代码库中已无引用:

Run: `rg -n "worktreeModeNewBranch|worktreeModeExistingBranch|worktreeBaseRefLabel|worktreeBaseRefHint|worktreeStartConversation" client/lib --glob '!l10n/app_localizations*'`
Expected: 无输出

Run: `flutter gen-l10n`

- [ ] **Step 2: 全量测试**

Run: `flutter test --exclude-tags integration`
Expected: ALL PASS

- [ ] **Step 3: 全量静态检查**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error/warning(既有 302 个 info/warning 基线不变)

- [ ] **Step 4: 提交**

```bash
git add client/lib/l10n/
git commit -m "chore(worktree): drop obsolete create-dialog l10n keys"
```

---

## Self-Review 记录

- **Spec 覆盖**:随机名(Task 1)、6 场景语义映射(Task 2)、无 tab 交互 + 随机按钮 + 可编辑选择器(Task 3)、删除 startConversation(Task 3+4)、l10n 增删(Task 3+5)、错误处理走现有 AppToast(无需代码改动,sidebar 原样保留 try/catch)、冲突回退(Task 1)。检出冲突前端门禁明确列为范围外,未实现。
- **占位符扫描**:无 TBD/TODO。
- **类型一致性**:`randomWorktreeBranchName`(Task 1)→ Task 3 调用;`buildWorktreeCreateResult` / `WorktreeCreateResult` / `worktreeOptionForLabel`(Task 2)→ Task 3 调用;`existingWorktreePaths`(Task 3 签名)→ Task 4 传参;`worktreeBaseSelectorHint` / `worktreeRandomNameTooltip`(Task 3)→ Task 3 使用;Task 5 删除的 5 个键在 Task 3 重写后均无引用。
