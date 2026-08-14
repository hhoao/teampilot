# File Tree Blank-Area Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Right-clicking the blank area of the file-tree panel (below the last row, or on `(empty)`) opens a VSCode-style context menu targeting the root folder under the pointer.

**Architecture:** Two additions on top of existing infra. (1) A new `FileTreeContextMenu.showForBlankArea` entry point in `file_tree_context_menu.dart` builds a trimmed `TpActionMenuSpec` list and reuses the existing private helpers (`_promptCreate`, `_runOp`). (2) `file_tree_panel.dart` wraps the list area with a `GestureDetector(onSecondaryTapDown:)`; rows win the gesture arena so the blank handler only fires on empty space; the target root is resolved by reusing `resolveFileTreePanelDropHit` (band math already used by drag & drop).

**Tech Stack:** Flutter, flutter_bloc (`FileTreeCubit`), shared_ui `TpActionMenuSpec` / `showTpActionMenuFromSpecsAtTap` / `TpTextPromptDialog` / `AppToast`.

## Global Constraints

- All work in `client/`. Verify with `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test --exclude-tags integration`.
- No new dependencies. No changes to row context-menu behavior or drag & drop.
- l10n: use existing keys only — `fileTreeNewFile`, `fileTreeNewFolder`, `fileTreePaste`, `fileTreePasteDone`, `fileTreeRefresh`, `treeCollapseAllFolders`, `fileTreeOpenInTerminal`, `fileTreeOpenInTerminalFailed`, `create`, `cancel`. Hidden-files label follows the existing header convention: hardcoded `'Show hidden files'` / `'Hide hidden files'` (file_tree_panel.dart:390) — do not add arb keys.
- No comments unless the codebase pattern requires them; follow existing style (doc comments on public members).
- Tests: widget tests use `MaterialApp` + `AppLocalizations.localizationsDelegates` + `TpTheme`, mouse right-click via `tester.startGesture(buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse)`, and `debugDefaultTargetPlatformOverride = TargetPlatform.linux` (see `test/widgets/git/git_change_tile_test.dart`).

---

### Task 1: Blank-area context menu entry point

**Files:**
- Modify: `client/lib/widgets/file_tree/file_tree_context_menu.dart`
- Create (test): `client/test/widgets/file_tree/file_tree_blank_area_context_menu_test.dart`

**Interfaces:**
- Produces: `static Future<void> FileTreeContextMenu.showForBlankArea({required BuildContext context, required TapDownDetails tapDetails, required FileTreeCubit cubit, required String targetRootDir, required String workspaceId, required bool desktopShellActions})` — used by Task 2.

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/file_tree/file_tree_blank_area_context_menu_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/widgets/file_tree/file_tree_context_menu.dart';

class _FakeFilesystem implements Filesystem {
  _FakeFilesystem(Map<String, List<FsDirEntry>> dirs) : _dirs = dirs;

  final Map<String, List<FsDirEntry>> _dirs;
  final Set<String> _files = {};

  @override
  final p.Context pathContext = p.Context();

  @override
  Future<FsStat> stat(String path) async {
    if (_dirs.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    if (_files.contains(path)) {
      return const FsStat(kind: FsEntityKind.file, size: 0);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<void> ensureDir(String path) async {
    _dirs[path] ??= [];
  }

  @override
  Future<void> writeString(String path, String content) async {
    _files.add(path);
  }

  @override
  Future<void> removeRecursive(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<String?> readString(String path) async => '';

  @override
  Future<List<int>?> readBytes(String path) async => [];

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async =>
      [];

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {}

  @override
  Future<void> atomicWrite(String path, String content) async {}

  @override
  Future<List<FsDirEntry>> listDir(String path) async =>
      _dirs[path] ?? const [];

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async => false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<String?> resolveSymlink(String path) async => null;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {}

  @override
  Future<void> copyFile(String source, String destination) async {}

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async =>
      listDir(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async =>
      '/tmp';

  @override
  Future<void> appendString(String path, String content) async {}
}

Widget _host(FileTreeCubit cubit, {required bool desktopShellActions}) {
  return TpTheme(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => GestureDetector(
            onSecondaryTapDown: (details) {
              unawaited(
                FileTreeContextMenu.showForBlankArea(
                  context: context,
                  tapDetails: details,
                  cubit: cubit,
                  targetRootDir: p.normalize('/proj'),
                  workspaceId: 'ws1',
                  desktopShellActions: desktopShellActions,
                ),
              );
            },
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    const Offset(200, 200),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _runOnDesktop(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<FileTreeCubit> _cubitWithRoot() async {
  final cubit = FileTreeCubit(
    fs: _FakeFilesystem({
      p.normalize('/proj'): [const FsDirEntry(name: 'a.txt', isDirectory: false)],
    }),
  );
  await cubit.setRoot(p.normalize('/proj'));
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return cubit;
}

void main() {
  testWidgets('blank-area menu shows trimmed items; Paste disabled', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot();
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);

      expect(find.text('New File'), findsOneWidget);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Collapse all folders'), findsOneWidget);
      expect(find.text('Show hidden files'), findsOneWidget);
      expect(find.text('Open in Terminal'), findsOneWidget);
      // Row-menu-only items must be absent.
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      // No clipboard yet → Paste is disabled.
      final pasteItem = tester.widget<TpActionMenuItem>(
        find.widgetWithText(TpActionMenuItem, 'Paste'),
      );
      expect(pasteItem.enabled, isFalse);

      await cubit.close();
    });
  });

  testWidgets('Paste enabled after copyItem; terminal item hidden on ssh', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot();
      cubit.copyItem(p.normalize('/proj/a.txt'));
      await tester.pumpWidget(_host(cubit, desktopShellActions: false));

      await _openMenu(tester);

      expect(find.text('Open in Terminal'), findsNothing);
      final pasteItem = tester.widget<TpActionMenuItem>(
        find.widgetWithText(TpActionMenuItem, 'Paste'),
      );
      expect(pasteItem.enabled, isTrue);

      await cubit.close();
    });
  });

  testWidgets('Show hidden files toggles cubit state', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot();
      expect(cubit.state.showHiddenFiles, isFalse);
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);
      await tester.tap(find.text('Show hidden files'));
      await tester.pump();

      expect(cubit.state.showHiddenFiles, isTrue);

      await cubit.close();
    });
  });

  testWidgets('New Folder creates inside the target root', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = await _cubitWithRoot();
      await tester.pumpWidget(_host(cubit, desktopShellActions: true));

      await _openMenu(tester);
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();
      expect(find.text('New Folder'), findsOneWidget); // dialog title

      await tester.enterText(find.byType(TextField), 'sub');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        cubit.entriesFor(p.normalize('/proj')).map((e) => e.name),
        contains('sub'),
      );

      await cubit.close();
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/file_tree/file_tree_blank_area_context_menu_test.dart`
Expected: FAIL — `No static member 'showForBlankArea' declared in class 'FileTreeContextMenu'` (compile error).

- [ ] **Step 3: Implement `showForBlankArea`**

In `client/lib/widgets/file_tree/file_tree_context_menu.dart`, after the existing `show(...)` method (it ends at line ~196), add:

```dart
  /// Right-click menu for the file-tree blank area (VSCode style). Actions
  /// target [targetRootDir] — the root folder under the pointer.
  static Future<void> showForBlankArea({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required FileTreeCubit cubit,
    required String targetRootDir,
    required String workspaceId,
    required bool desktopShellActions,
  }) async {
    final l10n = context.l10n;
    final canPaste = cubit.state.clipboard != null;
    final showHiddenFiles = cubit.state.showHiddenFiles;
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: 'new_file',
        icon: Icons.note_add_outlined,
        label: l10n.fileTreeNewFile,
      ),
      TpActionMenuSpec.item(
        value: 'new_folder',
        icon: Icons.create_new_folder_outlined,
        label: l10n.fileTreeNewFolder,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'paste',
        icon: Icons.content_paste,
        label: l10n.fileTreePaste,
        enabled: canPaste,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'refresh',
        icon: Icons.refresh,
        label: l10n.fileTreeRefresh,
      ),
      TpActionMenuSpec.item(
        value: 'collapse_all',
        icon: Icons.unfold_less,
        label: l10n.treeCollapseAllFolders,
      ),
      TpActionMenuSpec.item(
        value: 'toggle_hidden',
        icon: showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        label: showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
      ),
      if (desktopShellActions) ...[
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: 'terminal',
          icon: Icons.terminal,
          label: l10n.fileTreeOpenInTerminal,
        ),
      ],
    ];

    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;

    switch (value) {
      case 'new_file':
        await _promptCreate(
          context,
          cubit: cubit,
          parentDir: targetRootDir,
          isFolder: false,
          workspaceId: workspaceId,
        );
      case 'new_folder':
        await _promptCreate(
          context,
          cubit: cubit,
          parentDir: targetRootDir,
          isFolder: true,
          workspaceId: workspaceId,
        );
      case 'paste':
        await _runOp(
          context,
          () => cubit.pasteInto(targetRootDir),
          success: l10n.fileTreePasteDone,
        );
      case 'refresh':
        unawaited(cubit.refresh());
      case 'collapse_all':
        cubit.collapseAllFolders();
      case 'toggle_hidden':
        cubit.toggleShowHidden();
      case 'terminal':
        final ok = await FilePathActions.openInTerminal(
          targetPath: targetRootDir,
          isDirectory: true,
        );
        if (!context.mounted) return;
        if (!ok) {
          AppToast.show(
            context,
            message: l10n.fileTreeOpenInTerminalFailed,
            variant: TpToastVariant.error,
          );
        }
    }
  }
```

Imports already present in the file: `dart:async` (line 1), `material.dart`, `shared_ui.dart` (`TpActionMenuSpec`, `TpActionMenuSpec`, `showTpActionMenuFromSpecsAtTap`, `AppToast`, `TpToastVariant`), `l10n_extensions.dart`, `file_path_actions.dart`. No new imports needed.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/file_tree/file_tree_blank_area_context_menu_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/file_tree/file_tree_context_menu.dart client/test/widgets/file_tree/file_tree_blank_area_context_menu_test.dart
git commit -m "feat(file-tree): blank-area context menu entry point"
```

---

### Task 2: Panel wiring — right-click on blank area

**Files:**
- Modify: `client/lib/widgets/right_tools/file_tree_panel.dart`
- Create (test): `client/test/widgets/file_tree/file_tree_panel_blank_area_menu_test.dart`

**Interfaces:**
- Consumes: `FileTreeContextMenu.showForBlankArea({context, tapDetails, cubit, targetRootDir, workspaceId, desktopShellActions})` from Task 1; `resolveFileTreePanelDropHit`, `FileTreeDropHit.destDir` from `client/lib/services/file_tree_import/file_tree_drop_hit_test.dart` (already imported in `file_tree_panel.dart`); `fileTreeDropContentY` from `file_tree_drop_region.dart` (already imported via `file_tree_drop_region.dart`).
- Produces: `void _FileTreePanelState._showBlankAreaMenu(TapDownDetails details)` — private.

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/file_tree/file_tree_panel_blank_area_menu_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/right_tools/file_tree_panel.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';
import 'package:teampilot/test/support/test_runtime_context.dart';

// Same enhanced fake as Task 1 (stat honors notFound; ensureDir/writeString
// mutate state so create flows are observable).
class _FakeFilesystem implements Filesystem {
  _FakeFilesystem(Map<String, List<FsDirEntry>> dirs) : _dirs = dirs;

  final Map<String, List<FsDirEntry>> _dirs;
  final Set<String> _files = {};

  @override
  final p.Context pathContext = p.Context();

  @override
  Future<FsStat> stat(String path) async {
    if (_dirs.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    if (_files.contains(path)) {
      return const FsStat(kind: FsEntityKind.file, size: 0);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<void> ensureDir(String path) async {
    _dirs[path] ??= [];
    final parent = pathContext.dirname(path);
    if (parent != path &&
        !_dirs[parent]!.any((e) => e.name == pathContext.basename(path))) {
      _dirs[parent]!.add(
        FsDirEntry(name: pathContext.basename(path), isDirectory: true),
      );
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    _files.add(path);
  }

  @override
  Future<void> removeRecursive(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<String?> readString(String path) async => '';

  @override
  Future<List<int>?> readBytes(String path) async => [];

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async =>
      [];

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {}

  @override
  Future<void> atomicWrite(String path, String content) async {}

  @override
  Future<List<FsDirEntry>> listDir(String path) async =>
      _dirs[path] ?? const [];

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async => false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<String?> resolveSymlink(String path) async => null;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {}

  @override
  Future<void> copyFile(String source, String destination) async {}

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async =>
      listDir(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async =>
      '/tmp';

  @override
  Future<void> appendString(String path, String content) async {}
}

Widget _panel({
  required FileTreeCubit cubit,
  required RuntimeContext workContext,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: Scaffold(
        body: BlocProvider.value(
          value: WorkbenchCubit(),
          child: BlocProvider.value(
            value: FloatingWorkspaceCubit(),
            child: RightToolsLifecycle(
              data: RightToolsLifecycleData(
                scope: const WorkspaceToolsScopeState(resolving: true),
                fileTreeCubit: cubit,
                pokeOnTurnEnd: () {},
                ensureFileTreeReady: () {},
              ),
              child: SizedBox(
                width: 320,
                height: 420,
                child: FileTreePanel(
                  cubit: cubit,
                  workContext: workContext,
                  workspaceId: 'ws1',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _rightClickAt(WidgetTester tester, Offset point) async {
  final gesture = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _runOnDesktop(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('blank-area right-click shows blank menu (single root)', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): [
            const FsDirEntry(name: 'a.txt', isDirectory: false),
          ],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Blank area: below the only row, near the panel bottom.
      final rect = tester.getRect(find.byKey(AppKeys.fileTreePanel));
      await _rightClickAt(tester, Offset(rect.center.dx, rect.bottom - 24));

      // Blank menu markers: Refresh present, row-only Cut absent.
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Collapse all folders'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('right-click on (empty) opens the blank menu', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): <FsDirEntry>[],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(
        _panel(cubit: cubit, workContext: testRuntimeContext('/home')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClickAt(tester, tester.getCenter(find.text('(empty)')));

      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('row right-click keeps the row menu', (tester) async {
    await _runOnDesktop(tester, () async {
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          p.normalize('/proj'): [
            const FsDirEntry(name: 'a.txt', isDirectory: false),
          ],
        }),
      );
      await cubit.setRoot(p.normalize('/proj'));
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _rightClickAt(tester, tester.getCenter(find.text('a.txt')));

      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);

      await cubit.close();
    });
  });

  testWidgets('multi-root: blank right-click targets the pointer root band', (
    tester,
  ) async {
    await _runOnDesktop(tester, () async {
      final a = p.normalize('/projA');
      final b = p.normalize('/projB');
      final cubit = FileTreeCubit(
        fs: _FakeFilesystem({
          a: [const FsDirEntry(name: 'x.dart', isDirectory: false)],
          b: [const FsDirEntry(name: 'y.dart', isDirectory: false)],
        }),
      );
      await cubit.setRoots([a, b]);
      await tester.pumpWidget(_panel(cubit: cubit, workContext: testRuntimeContext('/home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Blank below all rows resolves to the nearest band → root B.
      final rect = tester.getRect(find.byKey(AppKeys.fileTreePanel));
      await _rightClickAt(tester, Offset(rect.center.dx, rect.bottom - 24));

      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'z');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        cubit.entriesFor(b).map((e) => e.name),
        contains('z'),
      );

      // Drain the success-toast timer before the test ends.
      await tester.pump(const Duration(seconds: 2));

      await cubit.close();
    });
  });
}
```

Note: the plan's Task 2 test harness carries the five environment fixes learned during Task 1 (TpTheme requires `data:` — use `TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0)`; the fake FS `ensureDir` registers the new folder in its parent's listing; drain the success-toast timer with `tester.pump(Duration(seconds: 2))` before the test ends; no bare `Future.delayed` before a pump in FakeAsync — use `tester.pump`; add `behavior: HitTestBehavior.opaque` on bare `GestureDetector` hosts that have no hit-testable child). `import 'package:teampilot/test/support/test_runtime_context.dart';` — the `test/` dir is importable from other test files (see `test/services/io/runtime_folder_opener_test.dart` which imports it).

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/file_tree/file_tree_panel_blank_area_menu_test.dart`
Expected: FAIL — right-click on the blank area shows nothing: `Expected: exactly one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets...>` for `find.text('Refresh')`.

- [ ] **Step 3: Implement the panel wiring**

In `client/lib/widgets/right_tools/file_tree_panel.dart`:

1. Add import for the menu entry point. Current imports include `'../file_tree/file_tree_drop_region.dart'` (line 27). Add after it:

```dart
import '../file_tree/file_tree_context_menu.dart';
```

2. Add the handler to `_FileTreePanelState` (after `_scheduleRevealScroll`, before `@override void dispose()`):

```dart
  void _showBlankAreaMenu(TapDownDetails details) {
    final cubit = _cubit;
    if (!cubit.state.anyRootExists) return;
    final contentY =
        details.localPosition.dy +
        (_listScrollController.hasClients ? _listScrollController.offset : 0);
    final hit = resolveFileTreePanelDropHit(
      contentY: contentY,
      visibleRows: cubit.state.visibleRows,
      rootPaths: cubit.state.rootPaths,
      pathContextFor: (path) => cubit.fsFor(path).pathContext,
    );
    final destDir = hit.destDir;
    if (destDir == null) return;
    unawaited(
      FileTreeContextMenu.showForBlankArea(
        context: context,
        tapDetails: details,
        cubit: cubit,
        targetRootDir: destDir,
        workspaceId: widget.workspaceId,
        desktopShellActions: _desktopShellActionsFor(_workContext),
      ),
    );
  }
```

3. Wrap the list widget in `build`. Current code (file_tree_panel.dart:305-327) returns `_FloatingPreviewHighlight(...)` inside the `BlocSelector` builder. Change:

```dart
                                return _FloatingPreviewHighlight(
                                  workspaceId: widget.workspaceId,
                                  builder: (context, path) => _FileTreeList(
```

to:

```dart
                                return GestureDetector(
                                  onSecondaryTapDown: _showBlankAreaMenu,
                                  child: _FloatingPreviewHighlight(
                                    workspaceId: widget.workspaceId,
                                    builder: (context, path) => _FileTreeList(
```

and close the extra paren at the end of that expression. The current tail of that builder is:

```dart
                                      ),
                                    ),
                                  ),
                                );
```

(three closing parens — `_FileTreeList`, `_FloatingPreviewHighlight`, `_FloatingPreviewHighlight` builder call). It becomes four closing parens plus the new `child:`-wrapper structure:

```dart
                                      ),
                                    ),
                                  ),
                                ),
                              );
```

Structure after edit:

```dart
                              builder: (context, rows) {
                                if (!context
                                    .read<FileTreeCubit>()
                                    .state
                                    .anyRootExists) {
                                  return const SizedBox.shrink();
                                }
                                return GestureDetector(
                                  onSecondaryTapDown: _showBlankAreaMenu,
                                  child: _FloatingPreviewHighlight(
                                    workspaceId: widget.workspaceId,
                                    builder: (context, path) => _FileTreeList(
                                      rows: rows,
                                      cubit: _cubit,
                                      textColor: cs.onSurface,
                                      listScrollController:
                                          _listScrollController,
                                      horizontalScrollController:
                                          _horizontalScrollController,
                                      desktopShellActions:
                                          _desktopShellActionsFor(
                                            _workContext,
                                          ),
                                      remoteFileManagerActions:
                                          _remoteFileManagerActionsFor(
                                            _workContext,
                                          ),
                                      workContext: _workContext,
                                      workspaceId: widget.workspaceId,
                                      activeFloatingFilePath: path,
                                    ),
                                  ),
                                );
                              },
```

`dart:async` (`unawaited`) is already imported (line 1). `resolveFileTreePanelDropHit` is already imported via `file_tree_drop_hit_test.dart` (line 21).

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/file_tree/file_tree_panel_blank_area_menu_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run both new test files plus existing file-tree tests**

Run:
```bash
flutter test test/widgets/file_tree/ test/cubits/file_tree_cubit_test.dart
```
Expected: all pass (no regressions in drop region / import dialogs / cubit tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/right_tools/file_tree_panel.dart client/test/widgets/file_tree/file_tree_panel_blank_area_menu_test.dart
git commit -m "feat(file-tree): blank-area right-click context menu"
```

---

### Task 3: Full verification

- [ ] **Step 1: Run analyzer**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings` from `client/`
Expected: no new issues (the two modified files must be clean; `discarded_futures`/`unawaited_futures` lints must not fire — all futures are awaited or `unawaited`).

- [ ] **Step 2: Run full test suite**

Run: `flutter test --exclude-tags integration` from `client/`
Expected: all tests pass.

- [ ] **Step 3: Manual smoke check (desktop)**

In the running app: open a workspace → file tree panel → right-click below the last row → the blank-area menu opens with New File / New Folder / Paste (enabled after cutting/copying) / Refresh / Collapse all folders / Show hidden files / Open in Terminal. Right-click on a row still shows the row menu. In a multi-root workspace, right-click in the second root's area and create a folder — it lands under the second root.
