# OpenCode Shared `node_modules` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed one shared `@opencode-ai/plugin` install under `cli-defaults/opencode/` and symlink each session’s `node_modules` + `package.json` to it so sessions stop duplicating ~58MB trees.

**Architecture:** A small seeder writes `package.json` and runs local `npm install` when `node_modules/@opencode-ai/plugin` is missing. `RuntimeLayout` links those two names from `appToolRoot('opencode')` into the session opencode dir (replace-on-link, no preserve). `OpencodeConfigProfileCapability.contributeLaunch` calls seed+link before writing plugins / env.

**Tech Stack:** Dart/Flutter, existing `Filesystem` / `RuntimeLayout._ensureInheritedChild`, injectable `Process.run` for `opencode --version` and `npm install`.

**Spec:** `docs/superpowers/specs/2026-07-22-opencode-shared-node-modules-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/provider/opencode/opencode_shared_plugin_deps.dart` | Completeness check, version resolve, write `package.json`, `npm install` in **home** shared root, cleanup on failure |
| `client/lib/services/storage/runtime_layout.dart` | `ensureSessionInheritsOpencodePluginDeps` — link `node_modules` + `package.json` from app → session (work plane) |
| `client/lib/services/remote/remote_app_data_materializer.dart` | Seed home opencode plugin deps **before** `WorkMachineMaterializer.reconcile` |
| `client/lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart` | Seed `ctx.catalog` (home) + inherit on `ctx.paths` (work) in `contributeLaunch` |
| `client/test/services/provider/opencode/opencode_shared_plugin_deps_test.dart` | Seed / skip / failure cleanup / version missing |
| `client/test/services/storage/runtime_layout_test.dart` | Link + replace fat session `node_modules` |
| `docs/workspace-storage-layout.md` | Document opencode shared plugin deps inherit |

---

### Task 1: Seeder (TDD)

**Files:**
- Create: `client/lib/services/provider/opencode/opencode_shared_plugin_deps.dart`
- Create: `client/test/services/provider/opencode/opencode_shared_plugin_deps_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/opencode/opencode_shared_plugin_deps.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory base;
  late RuntimeLayout layout;
  late LocalFilesystem fs;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_shared_deps_');
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    await layout.ensureAppToolLayout('opencode');
  });

  tearDown(() async {
    await base.delete(recursive: true);
  });

  test('seed writes package.json and installs when plugin dir missing', () async {
    var installCalls = 0;
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (cwd) async {
        installCalls++;
        expect(cwd, layout.appToolRoot('opencode'));
        await Directory(
          p.join(cwd, 'node_modules', '@opencode-ai', 'plugin'),
        ).create(recursive: true);
        return 0;
      },
    );

    await seeder.ensureSharedInstalled();

    expect(installCalls, 1);
    final pkg = await File(
      p.join(layout.appToolRoot('opencode'), 'package.json'),
    ).readAsString();
    expect(pkg, contains('"@opencode-ai/plugin": "1.18.4"'));
    expect(
      await Directory(
        p.join(
          layout.appToolRoot('opencode'),
          'node_modules',
          '@opencode-ai',
          'plugin',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('second ensure skips npm install when complete', () async {
    await Directory(
      p.join(
        layout.appToolRoot('opencode'),
        'node_modules',
        '@opencode-ai',
        'plugin',
      ),
    ).create(recursive: true);
    var installCalls = 0;
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (_) async {
        installCalls++;
        return 0;
      },
    );

    await seeder.ensureSharedInstalled();
    expect(installCalls, 0);
  });

  test('failed install removes incomplete node_modules', () async {
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => '1.18.4',
      npmInstall: (cwd) async {
        await Directory(p.join(cwd, 'node_modules', 'partial')).create(
          recursive: true,
        );
        return 1;
      },
    );

    await expectLater(seeder.ensureSharedInstalled(), throwsA(isA<Object>()));
    expect(
      await Directory(
        p.join(layout.appToolRoot('opencode'), 'node_modules'),
      ).exists(),
      isFalse,
    );
  });

  test('missing version fails without inventing a pin', () async {
    final seeder = OpencodeSharedPluginDeps(
      layout: layout,
      fs: fs,
      resolvePluginVersion: () async => null,
      npmInstall: (_) async => 0,
    );
    await expectLater(seeder.ensureSharedInstalled(), throwsA(isA<Object>()));
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/provider/opencode/opencode_shared_plugin_deps_test.dart
```

Expected: compilation failure / missing library.

- [ ] **Step 3: Implement seeder**

Create `opencode_shared_plugin_deps.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../io/filesystem.dart';
import '../../storage/runtime_layout.dart';
import '../../cli/cli_tool_locator.dart';

typedef OpencodePluginVersionResolver = Future<String?> Function();
typedef OpencodeNpmInstall = Future<int> Function(String cwd);

/// Seeds `<teampilotRoot>/cli-defaults/opencode/{package.json,node_modules}`
/// for OpenCode local plugins (`@opencode-ai/plugin`).
final class OpencodeSharedPluginDeps {
  OpencodeSharedPluginDeps({
    required this.layout,
    OpencodePluginVersionResolver? resolvePluginVersion,
    OpencodeNpmInstall? npmInstall,
    ProcessRunner? processRunner,
  })  : _resolvePluginVersion =
            resolvePluginVersion ?? _defaultResolvePluginVersion,
        _npmInstall = npmInstall ?? _defaultNpmInstall,
        _runner = processRunner ?? cliToolDefaultProcessRun;

  final RuntimeLayout layout;
  final OpencodePluginVersionResolver _resolvePluginVersion;
  final OpencodeNpmInstall _npmInstall;
  final ProcessRunner _runner;

  static final _lock = Object(); // use LockPool keyed 'opencode-plugin-deps' if preferred

  Filesystem get _fs => /* expose via layout or pass fs */;

  String get sharedRoot => layout.appToolRoot('opencode');

  String get _pluginPackageDir =>
      p.join(sharedRoot, 'node_modules', '@opencode-ai', 'plugin');

  Future<bool> get isComplete async =>
      (await _fs.stat(_pluginPackageDir)).isDirectory;

  /// Idempotent. Incomplete/failed trees are removed so the next call retries.
  Future<void> ensureSharedInstalled() async {
    // synchronize with LockPool('opencode|plugin-deps')
    if (await isComplete) return;

    final version = (await _resolvePluginVersion())?.trim() ?? '';
    if (version.isEmpty) {
      throw StateError(
        'Cannot seed opencode plugin deps: opencode version unavailable',
      );
    }

    final nodeModules = p.join(sharedRoot, 'node_modules');
    if ((await _fs.stat(nodeModules)).exists) {
      await _fs.removeRecursive(nodeModules);
    }

    await _fs.ensureDir(sharedRoot);
    await _fs.atomicWrite(
      p.join(sharedRoot, 'package.json'),
      const JsonEncoder.withIndent('  ').convert({
        'dependencies': {'@opencode-ai/plugin': version},
      }),
    );

    final code = await _npmInstall(sharedRoot);
    if (code != 0 || !(await isComplete)) {
      if ((await _fs.stat(nodeModules)).exists) {
        await _fs.removeRecursive(nodeModules);
      }
      throw StateError(
        'npm install @opencode-ai/plugin@$version failed (exit $code)',
      );
    }
  }

  static Future<String?> _defaultResolvePluginVersion([
    ProcessRunner runner = cliToolDefaultProcessRun,
  ]) async {
    final located = await const CliToolLocator('opencode').locate(runner: runner);
    final exe = located ?? 'opencode';
    final result = await runner(exe, ['--version']);
    if (result.exitCode != 0) return null;
    final text = '${result.stdout}'.trim();
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(text);
    return match?.group(1);
  }

  static Future<int> _defaultNpmInstall(String cwd) async {
    // Prefer `npm` on PATH; workingDirectory = cwd; args: ['install', '--omit=dev']
    final result = await Process.run(
      'npm',
      ['install', '--omit=dev'],
      workingDirectory: cwd,
      runInShell: Platform.isWindows,
    );
    return result.exitCode;
  }
}
```

Wire `layout`’s filesystem: add a package-visible getter on `RuntimeLayout` **or** pass `Filesystem fs` into the seeder constructor (prefer **pass `fs`** from caller — do not expand RuntimeLayout public surface beyond the inherit method in Task 2).

Adjust the stub above to take `required Filesystem fs` instead of reading it from layout.

Default version resolver / npm install must accept the injected `ProcessRunner` where practical; keep npm as a separate injectable for unit tests (as in Step 1).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/provider/opencode/opencode_shared_plugin_deps_test.dart
```

- [ ] **Step 5: Commit** (only if the user asked for commits in this session)

```bash
git add client/lib/services/provider/opencode/opencode_shared_plugin_deps.dart \
  client/test/services/provider/opencode/opencode_shared_plugin_deps_test.dart
git commit -m "feat(opencode): seed shared @opencode-ai/plugin under cli-defaults"
```

---

### Task 2: Session inherit links (TDD)

**Files:**
- Modify: `client/lib/services/storage/runtime_layout.dart`
- Modify: `client/test/services/storage/runtime_layout_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `runtime_layout_test.dart`:

```dart
test('ensureSessionInheritsOpencodePluginDeps links node_modules and package.json',
    () async {
  final layout = RuntimeLayout(teampilotRoot: base.path, fs: LocalFilesystem());
  await layout.ensureAppToolLayout('opencode');
  final app = layout.appToolRoot('opencode');
  await File(p.join(app, 'package.json')).writeAsString(
    '{"dependencies":{"@opencode-ai/plugin":"1.0.0"}}',
  );
  await Directory(
    p.join(app, 'node_modules', '@opencode-ai', 'plugin'),
  ).create(recursive: true);

  final sessionDir = layout.sessionRuntimeToolDir(workspaceId, 'sess-oc', 'opencode');
  await Directory(sessionDir).create(recursive: true);
  // Fat leftover from an old launch:
  await Directory(p.join(sessionDir, 'node_modules', 'old')).create(recursive: true);

  await layout.ensureSessionInheritsOpencodePluginDeps(
    workspaceId,
    'sess-oc',
  );

  final linkedNm = p.join(sessionDir, 'node_modules');
  final linkedPkg = p.join(sessionDir, 'package.json');
  expect(Link(linkedNm).existsSync() || Directory(linkedNm).existsSync(), isTrue);
  expect(
    await File(p.join(linkedNm, '@opencode-ai', 'plugin')).exists() ||
        await Directory(p.join(linkedNm, '@opencode-ai', 'plugin')).exists(),
    isTrue,
  );
  expect(await File(linkedPkg).readAsString(), contains('@opencode-ai/plugin'));
  expect(Directory(p.join(linkedNm, 'old')).existsSync(), isFalse);
});
```

Use the same path helpers / `_inheritedPathExists` the file already uses for `agents`. Cover memberId overload if the method takes `memberId` (mixed mode session dir).

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/storage/runtime_layout_test.dart --name ensureSessionInheritsOpencodePluginDeps
```

- [ ] **Step 3: Implement inherit**

In `runtime_layout.dart`:

```dart
Future<void> ensureSessionInheritsOpencodePluginDeps(
  String workspaceId,
  String sessionId, {
  String? memberId,
}) async {
  final trimmedWorkspace = workspaceId.trim();
  final trimmedSession = sessionId.trim();
  if (trimmedWorkspace.isEmpty || trimmedSession.isEmpty) return;

  await ensureAppToolLayout('opencode');
  final sessionRoot = sessionRuntimeToolDir(
    trimmedWorkspace,
    trimmedSession,
    'opencode',
    memberId: memberId,
  );
  await _fs.ensureDir(sessionRoot);
  final appRoot = appToolRoot('opencode');

  // node_modules: directory inherit (replace fat dirs)
  await _ensureInheritedChild(
    childName: 'node_modules',
    parentToolRoot: appRoot,
    ownToolRoot: sessionRoot,
  );

  // package.json: file — do NOT use ensureDir-on-missing branch for a missing source.
  // Source must already exist (seeder). Link or copy.
  final pkgSource = _pathContext.join(appRoot, 'package.json');
  final pkgTarget = _pathContext.join(sessionRoot, 'package.json');
  if (!(await _fs.stat(pkgSource)).exists) return;
  if (await _inheritLinkCurrent(source: pkgSource, target: pkgTarget)) {
    return; // already correct symlink/junction
  }
  if ((await _fs.stat(pkgTarget)).exists) {
    await _fs.removeRecursive(pkgTarget);
  }
  final linked = await _fs.createSymlink(target: pkgSource, linkPath: pkgTarget);
  if (!linked) {
    await _fs.copyFile(pkgSource, pkgTarget);
  }
}
```

Check `Filesystem` for `copyFile` / write helpers and match existing APIs. Do **not** set `preservePopulatedDirectory`.

If `_ensureInheritedChild` calls `ensureDir` when `node_modules` source is missing, the seeder must run **before** inherit so the source exists.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit** (if user requested commits)

```bash
git add client/lib/services/storage/runtime_layout.dart \
  client/test/services/storage/runtime_layout_test.dart
git commit -m "feat(opencode): inherit shared node_modules into session runtime"
```

---

### Task 3: Wire seed (home) + inherit (work) + docs

**Files:**
- Modify: `client/lib/services/remote/remote_app_data_materializer.dart`
- Modify: `client/lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart`
- Modify: `docs/workspace-storage-layout.md`
- Test: `client/test/services/remote/…` if an existing RemoteAppDataMaterializer test is easy to extend; otherwise unit-cover seeder/inherit only and add a focused materializer test that `cli == opencode` calls seed before `reconcile`

**Ordering (locked — remote-safe):**

1. **Seed only on the control-plane / home tree** with local `npm` (`catalog` / `homeFs` + `homeRoot`). Never `npm install` into an SFTP work root.
2. **`RemoteAppDataMaterializer.materialize`**: when `cli == CliTool.opencode`, call `ensureSharedInstalled` on home **before** `WorkMachineMaterializer.reconcile` so the copy includes `package.json` + `node_modules` files.
3. **`contributeLaunch`**: seed home via `ctx.catalog` (idempotent; covers native where materializer does not run), then **inherit only** on `ctx.paths.layout` (work). Do not npm-install on `ctx.paths.fs`.

`ConfigProfileLaunchContext` already splits planes: `catalog` = control/home, `paths` = work.

- [ ] **Step 1: Seed before reconcile in `RemoteAppDataMaterializer`**

In `materialize`, before constructing/`reconcile` of `WorkMachineMaterializer`:

```dart
if (cli == CliTool.opencode) {
  final homeLayout = RuntimeLayout(teampilotRoot: homeRoot, fs: homeFs);
  await OpencodeSharedPluginDeps(
    layout: homeLayout,
    fs: homeFs,
  ).ensureSharedInstalled();
}
```

Inject seeder in tests if you need to assert call order without real npm.

- [ ] **Step 2: Wire `contributeLaunch`**

Right after `ensureDir(opencodeDir)`:

```dart
try {
  await OpencodeSharedPluginDeps(
    layout: ctx.catalog.layout,
    fs: ctx.catalog.fs,
  ).ensureSharedInstalled();
} on Object catch (e) {
  // Same path as other contributeLaunch failures: ConfigProfileService
  // catches and turns into TeamLaunchOutcome.warnings with empty env.
  // Re-throw so that path runs; do not inherit onto a broken shared root.
  rethrow;
}

await ctx.paths.layout.ensureSessionInheritsOpencodePluginDeps(
  ctx.scope.workspaceId,
  ctx.scope.sessionId,
  memberId: ctx.scope.memberId,
);
```

If `OpencodeConfigProfileCapability` is `const`, keep seeder construction local (no stored fields).

- [ ] **Step 3: Docs**

In `docs/workspace-storage-layout.md`, under CLI config inheritance / `cli-defaults/{tool}/`, add:

> For `opencode`, `cli-defaults/opencode/{package.json,node_modules}` holds a shared `@opencode-ai/plugin` install (seeded on the home/control plane). Session `runtime/…/opencode/` inherits those two names (symlink preferred). Remote work machines receive the tree via `WorkMachineMaterializer`’s `cli-defaults` copy, then inherit in-root.

- [ ] **Step 4: Analyze + focused tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/provider/opencode/opencode_shared_plugin_deps.dart \
  lib/services/storage/runtime_layout.dart \
  lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart \
  lib/services/remote/remote_app_data_materializer.dart

cd client && flutter test \
  test/services/provider/opencode/opencode_shared_plugin_deps_test.dart \
  test/services/storage/runtime_layout_test.dart
```

- [ ] **Step 5: Commit** (if user requested commits)

```bash
git add client/lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart \
  client/lib/services/remote/remote_app_data_materializer.dart \
  docs/workspace-storage-layout.md
git commit -m "feat(opencode): share plugin node_modules across sessions"
```

---

## Manual check (optional)

1. Delete or move aside one fat session `runtime/opencode/node_modules`.
2. Launch an opencode session.
3. Confirm `cli-defaults/opencode/node_modules` exists once (~58MB) and session `node_modules` is a symlink to it.
4. Launch a second session → no second install; second symlink only.

---

## Notes for implementers

- **Home seed, work inherit.** Local npm never runs against SFTP. Materializer copies real files from home `node_modules` onto the work machine once; sessions on that machine symlink to the work copy.
- Do **not** inherit `node_modules` through identity/workspace layers; session → app only.
- For `package.json` file links, do not use `_inheritedPathIsAccessible`’s `listDir` check; use symlink-target / file-stat checks.
- Prefer resolving local `npm` via existing `TeampilotNodeInstall` / installer helpers when easy; raw `Process.run('npm', …)` is acceptable for v1 if injected for tests.
- YAGNI: no version upgrade, no multi-version cache, no batch cleanup of idle sessions.
