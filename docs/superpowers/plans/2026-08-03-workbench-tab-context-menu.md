# Workbench Tab Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compose workbench tab context menus from ordered sources (file actions above, built-in close last, dividers between groups) on center + floating strips, sharing path actions with the file tree.

**Architecture:** `WorkbenchTabMenuSource` + `WorkbenchTabMenuComposer` merge non-empty groups into `TpActionMenuSpec`s with `onAction`. `FilePathActions` owns copy/reveal/terminal/external. `WorkbenchStripTabChip` builds context at show-time and uses `defaultWorkbenchTabMenuSources()`.

**Tech Stack:** Flutter / Dart, `shared_ui` `TpActionMenuSpec`, existing folder/terminal openers, `flutter_test`, app l10n arb files.

**Spec:** `docs/superpowers/specs/2026-08-03-workbench-tab-context-menu-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/io/file_path_actions.dart` | Pure-ish helpers: relative path resolve, copy absolute/relative, reveal, open terminal, open external |
| `client/test/services/io/file_path_actions_test.dart` | Relative path + resolve-containing-root tests |
| `client/lib/services/workbench/tab_menu/workbench_tab_menu_context.dart` | Context DTO |
| `client/lib/services/workbench/tab_menu/workbench_tab_menu_source.dart` | `WorkbenchTabMenuSource` + `WorkbenchTabMenuItem` |
| `client/lib/services/workbench/tab_menu/workbench_tab_menu_composer.dart` | Merge groups + dividers → specs |
| `client/test/services/workbench/tab_menu/workbench_tab_menu_composer_test.dart` | Composer unit tests |
| `client/lib/services/workbench/tab_menu/sources/builtin_close_tab_menu_source.dart` | Pin + close trio |
| `client/lib/services/workbench/tab_menu/sources/file_path_tab_menu_source.dart` | Five file actions |
| `client/lib/services/workbench/tab_menu/sources/session_tab_menu_source.dart` | Empty v1 stub |
| `client/lib/services/workbench/tab_menu/sources/run_tab_menu_source.dart` | Empty v1 stub |
| `client/lib/services/workbench/tab_menu/default_workbench_tab_menu_sources.dart` | Ordered default list |
| `client/test/services/workbench/tab_menu/sources/file_path_tab_menu_source_test.dart` | Capability gating |
| `client/test/services/workbench/tab_menu/sources/builtin_close_tab_menu_source_test.dart` | Pin gating |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | `fileTreeCopyRelativePath` |
| `client/lib/widgets/file_tree/file_tree_context_menu.dart` | Call `FilePathActions`; add relative path item |
| `client/lib/pages/workspace_shell/workspace_shell_models.dart` | `TabInfo.kind` + `filePath` (+ optional workspaceRoot fields passed at strip) |
| `client/lib/services/workbench/workbench_tab_projection.dart` | Fill kind / filePath on `TabInfo` |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Chip show-time compose; strip passes context fields |
| `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart` | Same compose path; map surface → path |
| `client/lib/widgets/run/run_panel.dart` | Pass kind=run (builtin-only menu) |
| `client/lib/pages/chat/chat_page_shell.dart` (or strip host) | Supply workspaceRoot / capability flags into tab row |
| `client/test/pages/workspace_shell/workspace_shell_tab_chip_pin_test.dart` | Update for composer-backed menu |
| `client/test/pages/workspace_shell/workspace_shell_tab_chip_file_menu_test.dart` | File tab menu shows Copy path |

**Out of scope:** Home title-bar workspace tabs; global contribution registry; `FileEditorTab` deletion unless trivial.

---

### Task 1: `FilePathActions` + containing-root helper

**Files:**
- Create: `client/lib/services/io/file_path_actions.dart`
- Create: `client/test/services/io/file_path_actions_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/file_path_actions.dart';

void main() {
  group('resolveContainingWorkspaceRoot', () {
    test('picks longest matching folder prefix', () {
      expect(
        resolveContainingWorkspaceRoot(
          '/a/b/c/file.dart',
          ['/a', '/a/b'],
        ),
        '/a/b',
      );
    });

    test('returns null when no folder contains path', () {
      expect(
        resolveContainingWorkspaceRoot('/other/x', ['/a/b']),
        isNull,
      );
    });
  });

  group('tryRelativeWorkspacePath', () {
    test('returns relative path when inside root', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/ws/src/a.dart',
          workspaceRoot: '/ws',
        ),
        'src/a.dart',
      );
    });

    test('returns null when root null', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/ws/a.dart',
          workspaceRoot: null,
        ),
        isNull,
      );
    });

    test('returns null when outside root', () {
      expect(
        tryRelativeWorkspacePath(
          absolutePath: '/other/a.dart',
          workspaceRoot: '/ws',
        ),
        isNull,
      );
    });
  });
}
```

Use POSIX-style joins via `package:path` with a fixed context in tests if needed (`p.Context(style: p.Style.posix)`), or document that helpers take an optional `p.Context`. Production callers pass `workContext?.fs.pathContext` (same as file tree) so WSL/SSH relative paths are correct.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/io/file_path_actions_test.dart
```

Expected: compilation failure / missing library.

- [ ] **Step 3: Implement helpers**

```dart
import 'package:path/path.dart' as p;

String? resolveContainingWorkspaceRoot(
  String absolutePath,
  Iterable<String> folderPaths, {
  p.Context? pathContext,
}) {
  final ctx = pathContext ?? p.context;
  final normalized = ctx.normalize(absolutePath);
  String? best;
  var bestLen = -1;
  for (final raw in folderPaths) {
    final root = ctx.normalize(raw);
    final prefix = root.endsWith(ctx.separator) ? root : '$root${ctx.separator}';
    if (normalized == root || normalized.startsWith(prefix)) {
      if (root.length > bestLen) {
        best = root;
        bestLen = root.length;
      }
    }
  }
  return best;
}

String? tryRelativeWorkspacePath({
  required String absolutePath,
  required String? workspaceRoot,
  p.Context? pathContext,
}) {
  if (workspaceRoot == null || workspaceRoot.isEmpty) return null;
  final ctx = pathContext ?? p.context;
  final root = ctx.normalize(workspaceRoot);
  final file = ctx.normalize(absolutePath);
  if (!ctx.isWithin(root, file) && file != root) return null;
  return ctx.relative(file, from: root);
}
```

Also add action methods that wrap clipboard / openers (can be thin static methods calling existing `SystemFolderOpener`, `RuntimeFolderOpener`, `SystemTerminalOpener`, and the same external `Process.run` logic currently private in `FileTreeContextMenu`). Keep signatures injectable where tests need it; for openers, prefer calling production classes and leave opener behavior covered by existing code / tree menu.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/io/file_path_actions_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/io/file_path_actions.dart \
  client/test/services/io/file_path_actions_test.dart
git commit -m "feat(io): add FilePathActions relative path helpers"
```

---

### Task 2: Menu source types + composer

**Files:**
- Create: `client/lib/services/workbench/tab_menu/workbench_tab_menu_context.dart`
- Create: `client/lib/services/workbench/tab_menu/workbench_tab_menu_source.dart`
- Create: `client/lib/services/workbench/tab_menu/workbench_tab_menu_composer.dart`
- Create: `client/test/services/workbench/tab_menu/workbench_tab_menu_composer_test.dart`

- [ ] **Step 1: Write failing composer tests**

```dart
test('single non-empty group has no divider', () {
  final specs = WorkbenchTabMenuComposer.compose(
    [_FixedSource([_item('a.one')])],
    _fakeCtx(),
  );
  expect(specs.where((s) => s.isDivider), isEmpty);
  expect(specs.single.value, 'a.one');
});

test('skips empty groups and inserts one divider between kept groups', () {
  final specs = WorkbenchTabMenuComposer.compose(
    [
      _FixedSource([_item('a.one'), _item('a.two')]),
      _FixedSource(const []),
      _FixedSource([_item('b.one')]),
    ],
    _fakeCtx(),
  );
  expect(specs.map((s) => s.isDivider ? '|' : s.value).toList(), [
    'a.one',
    'a.two',
    '|',
    'b.one',
  ]);
});

test('all empty yields empty specs', () {
  expect(
    WorkbenchTabMenuComposer.compose([_FixedSource(const [])], _fakeCtx()),
    isEmpty,
  );
});
```

Use minimal fakes for `WorkbenchTabMenuContext` (nullable BuildContext only needed if sources touch it — composer tests can use sources that ignore ctx).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/workbench/tab_menu/workbench_tab_menu_composer_test.dart
```

- [ ] **Step 3: Implement context, item, source, composer**

`WorkbenchTabMenuContext` fields per spec (include `RuntimeContext? workContext` for remote reveal).

`WorkbenchTabMenuComposer.compose`:

```dart
static List<TpActionMenuSpec> compose(
  List<WorkbenchTabMenuSource> sources,
  WorkbenchTabMenuContext ctx,
) {
  final groups = <List<WorkbenchTabMenuItem>>[];
  for (final source in sources) {
    final items = source.buildItems(ctx);
    if (items.isNotEmpty) groups.add(items);
  }
  final specs = <TpActionMenuSpec>[];
  for (var i = 0; i < groups.length; i++) {
    if (i > 0) specs.add(const TpActionMenuSpec.divider());
    for (final item in groups[i]) {
      specs.add(
        TpActionMenuSpec.item(
          value: item.id,
          icon: item.icon,
          label: item.label,
          enabled: item.enabled,
          destructive: item.destructive,
          onAction: item.onAction,
        ),
      );
    }
  }
  return specs;
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(workbench): add tab menu source composer"
```

---

### Task 3: BuiltinClose + FilePath sources (+ empty stubs)

**Files:**
- Create: `client/lib/services/workbench/tab_menu/sources/builtin_close_tab_menu_source.dart`
- Create: `client/lib/services/workbench/tab_menu/sources/file_path_tab_menu_source.dart`
- Create: `client/lib/services/workbench/tab_menu/sources/session_tab_menu_source.dart`
- Create: `client/lib/services/workbench/tab_menu/sources/run_tab_menu_source.dart`
- Create: `client/lib/services/workbench/tab_menu/default_workbench_tab_menu_sources.dart`
- Create: `client/test/services/workbench/tab_menu/sources/builtin_close_tab_menu_source_test.dart`
- Create: `client/test/services/workbench/tab_menu/sources/file_path_tab_menu_source_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (then codegen if project requires `flutter gen-l10n`)

- [ ] **Step 1: Add l10n key**

`app_en.arb`: `"fileTreeCopyRelativePath": "Copy relative path"`  
`app_zh.arb`: `"fileTreeCopyRelativePath": "复制相对路径"`

Run project’s usual l10n generation (see `docs/DEVELOPMENT.md` if needed).

- [ ] **Step 2: Write failing source tests**

Builtin:

- pinnable + onPin → includes `builtin.pin`
- not pinnable → no pin
- always includes `builtin.close` when `onClose` present
- `onCloseOthers` / `onCloseRight` null → omit those items (align with pin gating)

FilePath:

- `filePath == null` → `[]`
- path + desktopShellActions + remote false → ids: `file.copy_path`, `file.copy_relative_path`, `file.reveal`, `file.open_terminal`, `file.open_external`
- desktopShellActions false + remoteFileManagerActions true → has reveal, omits terminal/external
- desktopShellActions false + remote false → copy paths + no reveal? **Match file tree:** tree still shows copy_path always; reveal if desktop OR remote; terminal/external only desktop. Mirror exactly.
- relative disabled when `tryRelativeWorkspacePath` null (`enabled: false`), still present

**l10n strategy (fixed):** `WorkbenchTabMenuContext` has `required AppLocalizations l10n` (plus `BuildContext? buildContext` for toast/mounted). Source unit tests load l10n once:

```dart
late AppLocalizations l10n;
setUpAll(() async {
  l10n = await AppLocalizations.delegate.load(const Locale('en'));
});
```

Chip/show-time wiring sets `l10n: context.l10n` and `buildContext: context`.

- [ ] **Step 3: Implement sources + `defaultWorkbenchTabMenuSources()`**

Order: FilePath, Session (empty), Run (empty), BuiltinClose.

FilePath `onAction` closures call `FilePathActions` with `ctx.workContext` / flags.

- [ ] **Step 4: Run source tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(workbench): add default tab menu sources"
```

---

### Task 4: Refactor file tree to use `FilePathActions` + relative path

**Files:**
- Modify: `client/lib/widgets/file_tree/file_tree_context_menu.dart`
- Modify: call site that invokes `FileTreeContextMenu.show` if it must pass `workspaceRoot` / folder list

- [ ] **Step 1: Locate show() callers and workspace folder list**

Find where `FileTreeContextMenu.show` is called; pass `workspaceRoot: resolveContainingWorkspaceRoot(targetPath, folderPaths)` (or the active tree root if single-root).

- [ ] **Step 2: Replace copy/reveal/terminal/external switch arms**

In specs list, after `copy_path`, add:

```dart
TpActionMenuSpec.item(
  value: 'copy_relative_path',
  icon: Icons.copy_outlined, // or link icon; match design taste in existing tree
  label: l10n.fileTreeCopyRelativePath,
  enabled: tryRelativeWorkspacePath(
        absolutePath: targetPath,
        workspaceRoot: workspaceRoot,
        pathContext: cubit.fs.pathContext,
      ) !=
      null,
),
```

Delegate handlers to `FilePathActions.copyAbsolute` / `copyRelative` / `reveal` / `openTerminal` / `openExternal`.

- [ ] **Step 3: Manual sanity or small unit test if easy** — optional; at least `flutter analyze` on touched files.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(file-tree): reuse FilePathActions and add copy relative"
```

---

### Task 5: Wire `TabInfo` + projection + chip compose

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_models.dart`
- Modify: `client/lib/services/workbench/workbench_tab_projection.dart`
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (and/or `workspace_shell.dart`) to pass folder roots / flags into strip
- Modify: `client/test/pages/workspace_shell/workspace_shell_tab_chip_pin_test.dart`
- Create: `client/test/pages/workspace_shell/workspace_shell_tab_chip_file_menu_test.dart`

- [ ] **Step 1: Extend `TabInfo`**

Add:

```dart
final WorkbenchTabKind? kind;
final String? filePath; // absolute; for file/diff
```

Projection:

- session → `kind: session`
- file → `kind: file`, `filePath: tab.id`
- diff → `kind: diff`, `filePath: tab.diffAbsolutePath`
- run → `kind: run`

- [ ] **Step 2: Change `WorkbenchStripTabChip`**

Remove hard-coded `_tabMenuSpecs` / `_handleTabMenuSelection` domain switch.

Add parameters needed to build context at show-time, e.g.:

```dart
final WorkbenchTabKind kind;
final String tabId;
final String? filePath;
final String? workspaceRoot;
final bool desktopShellActions;
final bool remoteFileManagerActions;
final RuntimeContext? workContext;
final List<WorkbenchTabMenuSource>? menuSources; // default = defaultWorkbenchTabMenuSources()
```

On secondary tap / long-press:

```dart
final ctx = WorkbenchTabMenuContext(
  buildContext: context,
  kind: widget.kind,
  tabId: widget.tabId,
  filePath: widget.filePath,
  workspaceRoot: widget.workspaceRoot,
  pinnable: widget.pinnable,
  pinned: widget.pinned,
  desktopShellActions: widget.desktopShellActions,
  remoteFileManagerActions: widget.remoteFileManagerActions,
  workContext: widget.workContext,
  onClose: widget.onClose,
  onCloseOthers: widget.onCloseOthers,
  onCloseRight: widget.onCloseRight,
  onPin: widget.onPin,
);
final specs = WorkbenchTabMenuComposer.compose(
  widget.menuSources ?? defaultWorkbenchTabMenuSources(),
  ctx,
);
await showTpActionMenuFromSpecsAtTap<Object>(...);
// onAction already runs; ignore returned value
```

Defaults for backward compat: `kind: WorkbenchTabKind.run` (or session), empty filePath, desktop flags false unless passed.

- [ ] **Step 3: Update `WorkspaceShellTabRow` to pass fields from `TabInfo` + strip-level workspaceRoot/flags**

Folder roots: `WorkspaceToolsScope.maybeOf(context)?.effectiveFolders` (or equivalent already used by the file tree). Resolve `workspaceRoot` per tab: `resolveContainingWorkspaceRoot(filePath, folderPaths)` when path known.

- [ ] **Step 4: Update pin widget tests** — still expect Pin/Close labels.

- [ ] **Step 5: Add file menu widget test**

```dart
testWidgets('file tab menu shows copy path above close', (tester) async {
  await tester.pumpWidget(_wrap(
    WorkbenchStripTabChip(
      title: 'a.dart',
      active: true,
      kind: WorkbenchTabKind.file,
      tabId: '/ws/a.dart',
      filePath: '/ws/a.dart',
      workspaceRoot: '/ws',
      desktopShellActions: true,
      onTap: () {},
      onClose: () {},
      onCloseOthers: () {},
      onCloseRight: () {},
    ),
  ));
  await _openContextMenu(tester);
  expect(find.text('Copy path'), findsOneWidget);
  expect(find.text('Copy relative path'), findsOneWidget);
  expect(find.text('Close'), findsOneWidget);
});
```

- [ ] **Step 6: Run tests**

```bash
cd client && flutter test \
  test/pages/workspace_shell/workspace_shell_tab_chip_pin_test.dart \
  test/pages/workspace_shell/workspace_shell_tab_chip_file_menu_test.dart
```

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(workbench): compose tab chip menus from sources"
```

---

### Task 6: Floating strip + run panel

**Files:**
- Modify: `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`
- Modify: `client/lib/widgets/run/run_panel.dart`

- [ ] **Step 1: Floating mapping helper**

```dart
(WorkbenchTabKind kind, String? filePath) floatingTabMenuIdentity(FloatingTab tab) {
  return switch (tab.surfaceId) {
    'filePreview' => (
      WorkbenchTabKind.file,
      tab.payload is String ? tab.payload as String : null,
    ),
    'diffPreview' => () {
      final key = tab.payload is String ? tab.payload as String : null;
      final parsed = key == null ? null : WorkbenchTabId.parseDiffKey(key);
      return (WorkbenchTabKind.diff, parsed?.$1);
    }(),
    'terminal' => (WorkbenchTabKind.shell, null),
    _ => (WorkbenchTabKind.run, null),
  };
}
```

Pass desktop/remote flags + `workContext` from floating host the same way file tree does (read from existing cubit/providers available in that subtree — mirror center strip). If floating lacks remote context, start with desktop flags from `!kIsWeb && (Platform.is…)` pattern used elsewhere; search `desktopShellActions` / `remoteFileManagerActions` call sites for the canonical check.

Also resolve and pass `workspaceRoot` on floating (same `resolveContainingWorkspaceRoot` + folder list via `FloatingWorkspaceToolsScopeBridge` / `WorkspaceToolsScope` as center strip) so Copy Relative Path works on floating file/diff tabs.

- [ ] **Step 2: Run panel**

```dart
WorkbenchStripTabChip(
  kind: WorkbenchTabKind.run,
  tabId: session.id,
  // filePath null → FilePath source empty
  ...
)
```

- [ ] **Step 3: Analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/services/workbench/tab_menu/ test/services/io/file_path_actions_test.dart test/pages/workspace_shell/
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(workbench): wire floating and run tab menus"
```

---

### Task 7: Verification sweep

- [ ] **Step 1: Full unit suite (exclude integration)**

```bash
cd client && flutter test --exclude-tags integration
```

Fix any fallout from `TabInfo` / chip constructor changes.

- [ ] **Step 2: Commit any test fixes**

```bash
git commit -m "test: fix fallout from tab menu wiring"
```

---

## Manual check (human / agent with UI)

1. Open a file tab → right-click → file actions, divider, close group.
2. Session tab → pin + close only (no file group).
3. Floating file preview tab → same file actions when path present.
4. File tree → Copy relative path works inside workspace folder; disabled/outside as specified.

---

## Execution note

Prefer **subagent-driven-development** per task with TDD. Do not skip failing-test steps.
