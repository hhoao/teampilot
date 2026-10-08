# Workspace CLI runtime cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put CLI runtime caches under `workspace/cache/cli/{tool}/{providerKey}/`, inherit them through workspace `config/{tool}/` into the session, and stop linking Cursor `plugins/cache` to `~/.cursor`.

**Architecture:** A small `WorkspaceCliCache` owns path keys and relative-name mappings. `RuntimeLayout` inherits each mapped child from global cache → `config/{tool}` → session tool dir (same `_ensureInheritedChild` / `_ensureInheritedFile` as `agents`). Cursor/OpenCode/Codex call that instead of OS `$HOME` or `cli-defaults` cache trees.

**Tech Stack:** Dart 3.8 / Flutter `client/`, existing `Filesystem` + `RuntimeLayout`, `dart run tool/run_tests.dart` (never `flutter test` in `client/`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-16-workspace-cli-cache-design.md` (状态：已批准).
- Do not commit unless the user asks; skip commit steps.
- Do not move `plugins/installed`, marketplace flavor/git, mixed `runtime/teams`, or `cli-defaults/{tool}/agents`.
- Do not SFTP `workspace/cache` via `WorkMachineMaterializer`; keep `.tmp` exclusion on **cli-defaults** trees.
- Services ~600 lines: new types in `workspace_cli_cache.dart`, do not dump path math into `cursor_home_provisioner.dart`.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/storage/workspace_cli_cache.dart` | `providerKey`, global/workspace roots, per-CLI relative bindings |
| `client/lib/services/storage/runtime_layout.dart` | inherit cache bindings into `config/{tool}` and session |
| `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart` | seed from cache, not OS home |
| `client/lib/services/cli/cursor/capabilities/provider.dart` | stop passing `ctx.paths.home` as warm root |
| `client/lib/services/cli/cursor/capabilities/session_lifecycle.dart` | same |
| `client/lib/services/cli/opencode/provider/opencode_shared_plugin_deps.dart` | install into global cache root |
| `client/lib/services/cli/codex/...` (native plugin + `ensureSessionOwnsCodexTmpPlugins`) | write/ln cache |
| `docs/workspace-storage-layout.md` | document `workspace/cache` |
| Tests listed per task | |

---

### Task 1: WorkspaceCliCache paths

**Files:**
- Create: `client/lib/services/storage/workspace_cli_cache.dart`
- Test: `client/test/services/storage/workspace_cli_cache_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_cli_cache.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  final cache = WorkspaceCliCache(
    layout: RuntimeLayout(teampilotRoot: '/tp', fs: InMemoryFilesystem()),
  );

  test('empty provider id is _shared', () {
    expect(WorkspaceCliCache.providerKey(null), '_shared');
    expect(WorkspaceCliCache.providerKey('  '), '_shared');
    expect(WorkspaceCliCache.providerKey('acct-1'), 'acct-1');
  });

  test('global cursor plugins cache is under workspace/cache', () {
    expect(
      cache.globalEntryPath(
        tool: CliTool.cursor.value,
        providerId: 'acct-1',
        cacheRel: WorkspaceCliCache.cursorPluginsCacheRel,
      ),
      '/tp/workspace/cache/cli/cursor/acct-1/plugins/cache',
    );
  });

  test('workspace tool rel for cursor plugins is fake-home path', () {
    final binding = WorkspaceCliCache.bindingFor(CliTool.cursor)
        .singleWhere((b) => b.cacheRel == WorkspaceCliCache.cursorPluginsCacheRel);
    expect(binding.toolRel, 'home/.cursor/plugins/cache');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/workspace_cli_cache_test.dart`

Expected: compile error, `workspace_cli_cache.dart` missing.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import 'runtime_layout.dart';

final class CliCacheBinding {
  const CliCacheBinding({required this.cacheRel, required this.toolRel});
  final String cacheRel;
  final String toolRel;
}

final class WorkspaceCliCache {
  WorkspaceCliCache({required this.layout});

  final RuntimeLayout layout;

  static const sharedProviderKey = '_shared';
  static const cursorPluginsCacheRel = 'plugins/cache';
  static const cursorStatsigRel = 'statsig-cache.json';
  static const codexTmpPluginsCacheRel = 'tmp-plugins';
  static const codexPluginsCacheRel = 'plugins-cache';

  static String providerKey(String? providerId) {
    final trimmed = providerId?.trim() ?? '';
    return trimmed.isEmpty ? sharedProviderKey : trimmed;
  }

  p.Context get _ctx => layout.pathContext;

  String globalRoot({required String tool, required String providerId}) =>
      _ctx.join(
        layout.teampilotRoot,
        'workspace',
        'cache',
        'cli',
        tool.trim(),
        providerKey(providerId),
      );

  String globalEntryPath({
    required String tool,
    required String providerId,
    required String cacheRel,
  }) => _ctx.join(globalRoot(tool: tool, providerId: providerId), cacheRel);

  String workspaceToolRelPath({
    required String workspaceId,
    required String tool,
    required String toolRel,
  }) => _ctx.join(layout.workspaceConfigToolDir(workspaceId, tool), toolRel);

  static List<CliCacheBinding> bindingFor(CliTool tool) => switch (tool) {
    CliTool.cursor => const [
      CliCacheBinding(
        cacheRel: cursorPluginsCacheRel,
        toolRel: 'home/.cursor/plugins/cache',
      ),
      CliCacheBinding(
        cacheRel: cursorStatsigRel,
        toolRel: 'home/.cursor/statsig-cache.json',
      ),
    ],
    CliTool.opencode => const [
      CliCacheBinding(cacheRel: 'package.json', toolRel: 'package.json'),
      CliCacheBinding(
        cacheRel: 'package-lock.json',
        toolRel: 'package-lock.json',
      ),
      CliCacheBinding(cacheRel: 'node_modules', toolRel: 'node_modules'),
    ],
    CliTool.codex => const [
      CliCacheBinding(
        cacheRel: codexTmpPluginsCacheRel,
        toolRel: '.tmp/plugins',
      ),
      CliCacheBinding(
        cacheRel: codexPluginsCacheRel,
        toolRel: 'plugins/cache',
      ),
    ],
    _ => const [],
  };
}
```

Confirm `CursorHomeLayout` statsig relative path is `statsig-cache.json` under the cursor dir (`home/.cursor/statsig-cache.json` from tool root). If the layout helper differs, match `CursorHomeLayout` exactly.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/workspace_cli_cache_test.dart`

Expected: PASS.

---

### Task 2: Inherit cache bindings into config and session

**Files:**
- Modify: `client/lib/services/storage/runtime_layout.dart`
- Test: `client/test/services/storage/runtime_layout_test.dart` (add tests at end of file)

- [x] **Step 1: Write the failing test**

```dart
test('session cursor plugins cache inherits global workspace cache', () async {
  final fs = InMemoryFilesystem();
  final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
  final cache = WorkspaceCliCache(layout: layout);
  final global = cache.globalEntryPath(
    tool: 'cursor',
    providerId: 'acct-1',
    cacheRel: WorkspaceCliCache.cursorPluginsCacheRel,
  );
  await fs.writeString('$global/keep.txt', 'ok');

  await layout.ensureSessionInheritsCliCache(
    workspaceId: 'proj-1',
    sessionId: 's1',
    tool: CliTool.cursor,
    providerId: 'acct-1',
  );

  final session = layout.pathContext.join(
    layout.sessionRuntimeToolDir('proj-1', 's1', 'cursor'),
    'home/.cursor/plugins/cache',
  );
  expect(await fs.readSymlinkTarget(session), global);
});
```

If `InMemoryFilesystem` stores symlink targets as given, assert that target. Also assert workspace `config/cursor/home/.cursor/plugins/cache` is a symlink to `global` (mid layer).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/runtime_layout_test.dart --plain-name 'session cursor plugins cache inherits global workspace cache'`

Expected: FAIL, method missing.

- [ ] **Step 3: Implement inherit**

Add `ensureSessionInheritsCliCache` on `RuntimeLayout`:

1. Resolve `WorkspaceCliCache` with `this`.
2. For each `WorkspaceCliCache.bindingFor` of the tool (map `tool` string → `CliTool` via `CliTool.values`).
3. `ensureDir` the global parent of `cacheRel`; for directory bindings, `ensureDir` the global entry if missing.
4. Inherit global entry → `workspaceConfigToolDir/toolRel` using existing `_ensureInheritedChild` when the entry is a directory, `_ensureInheritedFile` when it is a file (`statsig-cache.json`, `package.json`, `package-lock.json`).
5. Inherit workspace toolRel → `sessionRuntimeToolDir/toolRel` the same way.

Skip bindings whose `CliTool` is unknown. Need `CliTool` import in `runtime_layout.dart` (already imports `team_config.dart`).

For nested `toolRel` (`home/.cursor/plugins/cache`), `_ensureInheritedChild` only joins one `childName`. Either:

- inherit using the full relative path: extend helpers to accept `relativePath` with multiple segments, or
- walk: `ensureDir` parent of dest, then symlink the leaf.

Prefer a private `_ensureInheritedPath({source, dest})` that `ensureDir(dirname(dest))` then link-or-copy `source` → `dest`, preserving a real dest directory (workspace override).

Override rule (match spec): if dest `lstat` is a directory and not a symlink, return (keep override). If dest is a symlink already pointing at source, return.

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/runtime_layout_test.dart test/services/storage/workspace_cli_cache_test.dart`

Expected: PASS.

---

### Task 3: Cursor seeds from WorkspaceCliCache

**Files:**
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/provider.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/session_lifecycle.dart`
- Test: `client/test/services/provider/cursor/cursor_home_provisioner_test.dart`
- Test: `client/test/services/provider/cursor/cursor_home_provisioner_overlay_test.dart`

- [ ] **Step 1: Change failing assertion**

In `provision symlinks plugins/cache from the warm home`, the target must **not** be `/home/user/.cursor/plugins/cache`. It must be under `…/workspace/cache/cli/cursor/…/plugins/cache`.

Update the test to construct `RuntimeLayout` + `WorkspaceCliCache`, pass `teampilotRoot` / layout into provisioner (constructor inject `RuntimeLayout?` or `WorkspaceCliCache?` + `workspaceId` + `providerId`).

Minimal API: provisioner already has `warmCacheHomeRoot`. **Replace** that string with structured args:

```dart
String? teampilotRoot,
String? workspaceId,
String? providerId,
```

Call `ensureSessionInheritsCliCache` then link memberHome `.cursor/plugins/cache` from the **session tool dir** inherit result, or directly from resolved cache if provisioner writes memberHome itself.

Cursor provision writes `memberHome` which **is** the session fake HOME (`…/runtime/cursor/home`). So after inherit, `memberHome/.cursor/plugins/cache` should already be the session leaf if inherit ran on the session tool dir (`memberHome` = `toolDir/home`).

Check: `sessionRuntimeToolDir/home` == `memberHome`. Inherit `toolRel` `home/.cursor/plugins/cache` is `memberHome/.cursor/plugins/cache`. Then `_seedWarmCaches` can be replaced by `layout.ensureSessionInheritsCliCache(...)` using the session ids.

If provisioner does not have sessionId, keep linking:

```dart
final source = cache.globalEntryPath(
  tool: CliTool.cursor.value,
  providerId: providerId,
  cacheRel: WorkspaceCliCache.cursorPluginsCacheRel,
);
await _linkDirectoryIfSourceExists(source: source, dest: _layout.pluginsCache(memberHome));
```

and still run workspace inherit so `config/cursor/...` is populated.

Delete `warmCacheHomeRoot` entirely. Never pass `ctx.paths.home`. `ensureDir` the global `plugins/cache` (empty is fine), inherit/ln, let `cursor-agent` fill it. Do **not** copy statsig or cli-config cache fields from OS `$HOME`. First launch may be slow.

- [ ] **Step 2: Run tests RED**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/cursor/cursor_home_provisioner_test.dart --plain-name 'provision symlinks plugins/cache'`

Expected: FAIL (still points at real home) until implementation.

- [ ] **Step 3: Implement**

Remove `_seedWarmCaches`'s OS-home reads (`statsig`, `plugins/cache` link from `$HOME`, `serverConfigCache` / `authInfo` from warm home). Empty `ensureDir` + ln only.

- [ ] **Step 4: Run Cursor provisioner tests**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/cursor/cursor_home_provisioner_test.dart test/services/provider/cursor/cursor_home_provisioner_overlay_test.dart`

Expected: PASS. Overlay test `seeds plugins/cache from the warm home` must use cache path.

---

### Task 4: OpenCode shared deps live in workspace/cache

**Files:**
- Modify: `client/lib/services/cli/opencode/provider/opencode_shared_plugin_deps.dart`
- Modify: `client/lib/services/storage/runtime_layout.dart` (`ensureSessionInheritsOpencodePluginDeps`)
- Test: `client/test/services/provider/opencode/opencode_shared_plugin_deps_test.dart`
- Test: `client/test/services/storage/runtime_layout_test.dart` (`ensureSessionInheritsOpencodePluginDeps links node_modules...`)

- [ ] **Step 1: Point tests at cache root**

`sharedRoot` must be `/tp/workspace/cache/cli/opencode/_shared`, not `layout.appToolRoot('opencode')`.

Update `ensureSessionInheritsOpencodePluginDeps` tests: after inherit, session `node_modules` symlink target is the cache root's `node_modules`.

- [ ] **Step 2: Run RED**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/opencode/opencode_shared_plugin_deps_test.dart`

Expected: FAIL on path.

- [ ] **Step 3: Implement**

```dart
String get sharedRoot => WorkspaceCliCache(layout: layout).globalRoot(
  tool: CliTool.opencode.value,
  providerId: null,
);
```

Change `ensureSessionInheritsOpencodePluginDeps` to `ensureSessionInheritsCliCache(..., tool: opencode, providerId: null)` **or** keep the method as a wrapper that calls inherit (so OpenCode provider.dart call site stays).

One-shot migration: if `appToolRoot('opencode')/node_modules` exists and cache `node_modules` does not, `rename` or copyTree then remove old. Implement behind the same `ensureSharedInstalled` lock.

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/opencode/opencode_shared_plugin_deps_test.dart test/services/storage/runtime_layout_test.dart`

Expected: PASS.

---

### Task 5: Codex cache inherit

**Files:**
- Modify: `client/lib/services/storage/runtime_layout.dart` (`ensureSessionOwnsCodexTmpPlugins`)
- Modify: Codex native plugin writer so it writes into global `tmp-plugins` when populating the pool (find the call that copies into session `.tmp/plugins`)
- Test: `client/test/services/storage/runtime_layout_test.dart` (existing Codex `.tmp/plugins` tests around line 212)

- [ ] **Step 1: Rewrite the session-owns test**

Current: session dir is a real empty directory, not a link to `cli-defaults/codex/.tmp/plugins`.

New:

- `ensureSessionOwnsCodexTmpPlugins` (rename in a follow step if needed to `ensureSessionInheritsCodexCliCache`) creates session `.tmp/plugins` as symlink to `workspace/cache/cli/codex/_shared/tmp-plugins`.
- Does **not** `removeRecursive` a populated global cache.
- Session `plugins/cache` symlink to `…/plugins-cache`.

Keep materializer test: `cli-defaults/codex/.tmp/plugins` still excluded from work copy.

- [ ] **Step 2: Run RED**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/runtime_layout_test.dart --plain-name 'Codex'`

Expected: FAIL.

- [ ] **Step 3: Implement**

Replace body of `ensureSessionOwnsCodexTmpPlugins` with `ensureSessionInheritsCliCache(..., tool: codex, providerId: null)`.

Update native Codex plugin provision to write files under `WorkspaceCliCache.globalEntryPath(..., codexTmpPluginsCacheRel)` (and/or `plugins-cache` as today under session — prefer global tmp-plugins for the install tree). If the writer currently takes a session plugins dir, pass the global cache path.

Grep `ensureSessionOwnsCodexTmpPlugins` and `.tmp/plugins` under `client/lib/services/cli/codex/` and update call sites.

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/runtime_layout_test.dart test/services/remote/work_machine_materializer_test.dart`

Expected: PASS; `.tmp` still not copied from cli-defaults.

---

### Task 6: Storage layout doc

**Files:**
- Modify: `docs/workspace-storage-layout.md`

- [ ] **Step 1: Document**

Under top-level / workspace section add:

```text
workspace/cache/cli/{tool}/{providerKey}/   # CLI runtime cache (global)
workspace/workspaces/{id}/config/{tool}/    # workspace CLI tree (trust + inherit cache)
```

Note: Cursor `plugins/cache` is not `~/.cursor`. `cli-defaults` is templates (`agents`), not cache. OpenCode node_modules and Codex tmp-plugins live under `workspace/cache`.

No test. Read the spec “What does not move” and do not claim mixed team warm tier moved.

---

## Spec coverage

| Spec | Task |
|------|------|
| Path keys + `_shared` | 1 |
| Inherit config → session | 2 |
| Cursor leave OS home | 3 |
| OpenCode move | 4 |
| Codex move + no cli-defaults .tmp ship | 5 |
| Layout doc | 6 |
| Projector / ApplyPlan | already works if paths stay under teampilotRoot; Task 3 tests cover target prefix |

## Notes for implementers

- `cd client && dart run tool/run_tests.dart <files>` only.
- Cursor `toolRel` must match `CursorHomeLayout.pluginsCache(memberHome)` relative to `sessionRuntimeToolDir`.
- Do not add `workspace/workspaces/{id}/cache/`.
