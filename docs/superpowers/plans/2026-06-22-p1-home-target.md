# P1 — home target 归一 + 权威源反转 + "选 target" UI（最优终态，零兼容）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 home target 确立为唯一作用域层，权威源**直接反转**到设备本地 `homeTargetId`（桌面=local、Android=ssh:*），升级出"选 home target"UI，并**清除前序所有兼容脚手架**，达成"四旋钮/旧字段彻底消失、target 为唯一真相源"的干净终态。

**Architecture:** 新增设备本地 `HomeTargetStore`（SharedPrefs，bootstrap 前可读，解 Android home=ssh 鸡生蛋）作为 home 选择的唯一权威；`targets.json` 退为纯 target 目录（`{schemaVersion, targets}`，无 defaultTargetId/迁移）。`app_shell` bootstrap 读 `homeTargetId` → `installForTarget(homeTarget)` 一次装好。删除 P0 的 prefs 推导/镜像/迁移与预备阶段的双写/读旧脚手架。UI 用平台域定的 home target 选择器替换连接模式/后端/profile-选中三件套。

**Tech Stack:** Dart / Flutter，`flutter_bloc`，`shared_preferences`，`package:flutter_test`。

**Branch:** 建立在 `feat/p0-runtime-target` 之上——切 `feat/p1-home-target`。

## Global Constraints

- **零兼容、最优终态**：不读旧字段、不双写、不留 schemaVersion 兼容、不做"读旧迁移"。旧磁盘 manifest/prefs 失效是**用户接受的已知后果**。
- **home 身份是 bootstrap-local**：`homeTargetId` 存设备本地 SharedPrefs（唯一 home 权威）；`targets.json` 是 home 上的 target 目录。**详见设计稿 §2.1（已 flag team-lead 确认）**。
- **不在 P1**：去存储单例、控制面/工作面拆分、`resolve()` 重构、每目录 target、反向隧道、`remoteOs` 探测、桌面 home 搬 ssh。`resolve()`/`RuntimeStorageContext._current` 仍**不动**（P2）。
- 设计权威：[docs/superpowers/specs/2026-06-22-p1-home-target-design.md](../specs/2026-06-22-p1-home-target-design.md)。
- 完成判据（每任务 + 总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
- l10n 删除的字符串（连接模式/后端开关文案）从 `app_en.arb`/`app_zh.arb` 移除并 `flutter pub get` 重生成；删字符串后跑 `dart run tool/gen_warmup_glyphs.dart`。
- 频繁提交：每任务 ≥1 commit。

## 任务编排原则

清除脚手架会大面积破坏编译，故顺序为：**先建新权威（HomeTargetStore）→ 切换消费方到新权威 → 再删旧脚手架**，每个删除任务紧跟其消费方切换，确保每任务结尾编译/测试绿。

---

### Task 1: `HomeTargetStore`（设备本地 home 权威）

**Files:**
- Create: `client/lib/services/storage/home_target_store.dart`
- Test: `client/test/services/storage/home_target_store_test.dart`

**Interfaces:**
- Consumes: `SharedPreferences`, `RuntimeTarget` (existing).
- Produces: `class HomeTargetStore { HomeTargetStore(SharedPreferences prefs); String load(); Future<void> save(String id); }` (key `flashskyai.home_target.v1`).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/storage/home_target_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/services/storage/home_target_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty by default', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(HomeTargetStore(prefs).load(), '');
  });

  test('save then load round-trips', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = HomeTargetStore(prefs);
    await store.save('ssh:p1');
    expect(store.load(), 'ssh:p1');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/storage/home_target_store_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement**

```dart
// client/lib/services/storage/home_target_store.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local authority for the home target (the machine the control plane
/// runs on). Readable before any RuntimeStorageContext install — this is the
/// only place the home identity can live (the control plane is ON the home
/// machine; on Android that is the remote we cannot reach until we know it).
class HomeTargetStore {
  const HomeTargetStore(this._prefs);
  static const _key = 'flashskyai.home_target.v1';
  final SharedPreferences _prefs;

  /// '' means unset — caller applies the platform default (see app_shell).
  String load() => _prefs.getString(_key)?.trim() ?? '';

  Future<void> save(String id) async => _prefs.setString(_key, id.trim());
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/storage/home_target_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/home_target_store.dart client/test/services/storage/home_target_store_test.dart
git commit -m "feat: add device-local HomeTargetStore (home target authority)"
```

---

### Task 2: `targets.json` 终态形状（去 defaultTargetId/wslDistro/migrate）

**Files:**
- Modify: `client/lib/services/storage/targets_repository.dart`
- Modify: `client/lib/services/storage/runtime_target_registry.dart`
- Modify/replace tests: `client/test/services/storage/targets_repository_test.dart`, `client/test/services/storage/runtime_target_registry_test.dart`

**Interfaces:**
- Produces:
  - `class TargetsRegistryFile { const TargetsRegistryFile({int schemaVersion=1, List<RuntimeTarget> targets=const []}); factory fromJson(Map); Map toJson(); copyWith({List<RuntimeTarget>? targets}); }` (no `defaultTargetId`/`wslDistro`).
  - `class RuntimeTargetRegistry { ...; Future<List<RuntimeTarget>> listTargets(); }` — only `listTargets` (ssh reconcile) remains; `migrateIfNeeded`/`defaultTarget`/`setDefaultTargetId`/`wslDistro` removed.

- [ ] **Step 1: Update `TargetsRegistryFile`** — strip `defaultTargetId`/`wslDistro`:

```dart
class TargetsRegistryFile {
  const TargetsRegistryFile({this.schemaVersion = 1, this.targets = const []});
  final int schemaVersion;
  final List<RuntimeTarget> targets;

  factory TargetsRegistryFile.fromJson(Map<String, Object?> json) {
    final raw = json['targets'];
    return TargetsRegistryFile(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      targets: raw is List
          ? [for (final e in raw) if (e is Map<String, Object?>) RuntimeTarget.fromJson(e)]
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'targets': targets.map((t) => t.toJson()).toList(),
      };

  TargetsRegistryFile copyWith({List<RuntimeTarget>? targets}) =>
      TargetsRegistryFile(schemaVersion: schemaVersion, targets: targets ?? this.targets);
}
```

- [ ] **Step 2: Trim `RuntimeTargetRegistry`** — delete `migrateIfNeeded`, `defaultTarget`, `setDefaultTargetId`, `wslDistro`; keep only `listTargets` (the ssh reconcile + implicit local/wsl). Replace the implicit-wsl branch source (was `file.wslDistro`) with the injected Windows distro (passed in ctor or as a `listTargets({String wslDistro=''})` param — pass from app_shell's home distro). Keep `RuntimeTarget.local()` always first.

```dart
  Future<List<RuntimeTarget>> listTargets({String wslDistro = ''}) async {
    final file = await _repo.load();
    final profiles = await _sshProfileRepo.loadAll();
    final byId = {for (final p in profiles) p.id: p};
    final reconciled = <RuntimeTarget>[];
    var changed = false;
    for (final t in file.targets) {
      final pid = t.sshProfileId;
      if (pid != null && byId.containsKey(pid)) {
        reconciled.add(t.copyWith(label: byId[pid]!.name));
      } else { changed = true; }
    }
    final pids = reconciled.map((t) => t.sshProfileId).whereType<String>().toSet();
    for (final p in profiles) {
      if (!pids.contains(p.id)) { reconciled.add(RuntimeTarget.ssh(p.id, label: p.name)); changed = true; }
    }
    if (changed) await _repo.save(file.copyWith(targets: reconciled));
    return [
      RuntimeTarget.local(),
      if (isWindows && wslDistro.trim().isNotEmpty) RuntimeTarget.wsl(wslDistro.trim()),
      ...reconciled,
    ];
  }
```

- [ ] **Step 3: Rewrite the two test files** to the new shape: drop all `defaultTargetId`/`migrateIfNeeded`/`defaultTarget` cases; keep round-trip (`{schemaVersion, targets}`), missing-file→empty, and `listTargets` reconcile (add new profile / prune orphan / implicit local / implicit wsl when `wslDistro` passed).

- [ ] **Step 4: Run**

Run: `cd client && flutter test test/services/storage/targets_repository_test.dart test/services/storage/runtime_target_registry_test.dart`
Expected: PASS. (app_shell still references removed methods — fixed in Task 3; analyze of these two files only here.)

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/targets_repository.dart client/lib/services/storage/runtime_target_registry.dart client/test/services/storage/targets_repository_test.dart client/test/services/storage/runtime_target_registry_test.dart
git commit -m "refactor: targets.json final shape (catalog only, no default/migrate)"
```

---

### Task 3: app_shell 反转权威到 `homeTargetId` + bootstrap 次序

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: `HomeTargetStore` (Task 1), trimmed registry (Task 2), `installForTarget` (existing).
- Produces: `defaultTargetResolver()` returns the home target resolved from `homeTargetId`; `homeTargetId` default applied by platform; reinstall writes nothing legacy.

- [ ] **Step 1: Compute the home target id with platform default** — add near bootstrap (before the first install at ~232):

```dart
  final homeTargetStore = HomeTargetStore(preferences);
  String resolveHomeTargetId() {
    final stored = homeTargetStore.load();
    if (stored.isNotEmpty) return stored;
    if (Platform.isAndroid) {
      // first available ssh profile, else empty -> setup gate (Task 6)
      final first = sshProfileCubit.state.profiles.isNotEmpty
          ? sshProfileCubit.state.profiles.first.id
          : '';
      return first.isEmpty ? RuntimeTarget.localId : 'ssh:$first';
    }
    return RuntimeTarget.localId; // desktop home is always local (Windows can pick wsl in UI)
  }
```

> Note: `sshProfileCubit` must be loaded before computing the Android default; if bootstrap order needs it earlier, load ssh profiles (already local-readable) before the home install. Keep the existing two-phase only if a profile-less Android first run needs the setup gate — otherwise install home directly.

- [ ] **Step 2: Build the home target + single resolver** (replace `currentLegacyTargetId`/`synthTarget`/`defaultTargetResolver` block ~333-365):

```dart
  RuntimeTarget homeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
        RuntimeKind.ssh => RuntimeTarget.ssh(
            sshProfileIdOfId(id) ?? '',
            label: sshProfileCubit.state.profiles
                    .where((p) => p.id == sshProfileIdOfId(id))
                    .map((p) => p.name)
                    .firstOrNull ?? 'SSH'),
        RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
        RuntimeKind.local => RuntimeTarget.local(),
      };
  var _homeTarget = homeTargetFromId(resolveHomeTargetId());
  RuntimeTarget defaultTargetResolver() => _homeTarget;
  Future<void> setHomeTarget(String id) async {
    await homeTargetStore.save(id);
    _homeTarget = homeTargetFromId(id);
  }
```

- [ ] **Step 3: Replace bootstrap install** (lines ~232-245) and reinstall (~367-380):

```dart
  // bootstrap install:
  await RuntimeStorageContext.installForTarget(
    defaultTargetResolver(),
    sshProfile: sshProfileCubit.state.profiles
        .where((p) => p.id == defaultTargetResolver().sshProfileId)
        .firstOrNull,
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  // reinstallStorageContext:
  reinstallStorageContext = () => RuntimeStorageContext.installForTarget(
        defaultTargetResolver(),
        sshProfile: sshProfileCubit.state.profiles
            .where((p) => p.id == defaultTargetResolver().sshProfileId)
            .firstOrNull,
        sshClientFactory: sshClientFactory,
        nativeAppDataPath: nativeAppDataPath,
        nativeHome: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
        nativeCwd: defaultWorkspaceDirectory,
      );
```

Delete: the `migrateIfNeeded` call, `currentLegacyTargetId`, `synthTarget`, `wslDistroFromPrefs`, `windowsStorageBackend()` helper, and the `RuntimeStorageContext.install(isSshMode: Platform.isAndroid || ...connectionMode...)` legacy block. Wire `setHomeTarget` to where UI/cubit changes the home (Task 5/6). Keep `reloadRemoteBackedAppData` chain intact (triggered after `setHomeTarget` + `reinstallStorageContext`).

- [ ] **Step 4: Analyze app_shell + run storage tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app lib/services/storage && flutter test test/services/storage/`
Expected: app_shell analyze clean (UI/cubit refs to removed setters surface in Task 4/5 — if app_shell itself references `connectionMode`, remove those here). Storage tests PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "refactor: bootstrap home target from device-local homeTargetId"
```

---

### Task 4: 删除 `SessionPreferences` 旧旋钮字段 + `ConnectionModeService` 收尾

**Files:**
- Modify: `client/lib/models/session_preferences.dart`, `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/services/app/connection_mode_service.dart`
- Audit: `client/lib/models/connection_mode.dart`, `client/lib/models/windows_storage_backend.dart`, `client/lib/models/launch_target.dart`, `client/lib/services/terminal/terminal_transport_factory.dart`

**Interfaces:**
- Produces: `SessionPreferences` without `connectionMode`/`windowsStorageBackend`; `ConnectionModeService` exposes only `isSshMode`/`isLocalMode`/`requiresSshProfileSetup` (no `effectiveMode`/`preferredMode`/`ConnectionMode`).

- [ ] **Step 1: Audit ConnectionMode internal use** — run:
```bash
cd client && grep -rn "ConnectionMode\b" lib/models/launch_target.dart lib/services/terminal/terminal_transport_factory.dart lib/main.dart lib/pages/startup_gate.dart
```
Decide per result: if `ConnectionMode` is only a user knob → delete the enum + `connection_mode.dart`; if used as an internal transport descriptor (e.g. `LaunchTarget`/transport factory) → keep the enum but remove its derivation from prefs (derive from `RuntimeTarget.kind` at the call site). Record the decision in the commit message.

- [ ] **Step 2: Remove fields from `SessionPreferences`** — delete `connectionMode`, `windowsStorageBackend` from the constructor, fields, `fromJson`, `toJson`, `copyWith`. Remove now-unused imports (`connection_mode.dart`, `windows_storage_backend.dart`) if the audit deleted them.

- [ ] **Step 3: Remove cubit setters** — delete `setConnectionMode` and `setWindowsStorageBackend` from `session_preferences_cubit.dart`.

- [ ] **Step 4: Trim `ConnectionModeService`** — drop `effectiveMode`/`preferredMode`; keep:
```dart
  bool get isSshMode => _defaultTargetResolver().kind == RuntimeKind.ssh;
  bool get isLocalMode => !isSshMode;
  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
```
Update any caller of `effectiveMode`/`preferredMode` (found via grep) to `isSshMode` or the `RuntimeTarget` directly.

- [ ] **Step 5: Fix fallout** — `grep -rn "connectionMode\|windowsStorageBackend\|effectiveMode\|preferredMode" lib` and update each consumer (`session_config_section.dart` handled in Task 5; transport factory / launch_target / android selector / startup_gate / onboarding cli_step here). For transport selection, derive ssh vs local from `defaultTargetResolver().kind`.

- [ ] **Step 6: Analyze + test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS (UI picker is Task 5 — but session_config_section must at least compile; temporarily remove the backend/connection-mode UI blocks here if needed, full picker added Task 5).

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/session_preferences.dart client/lib/cubits/session_preferences_cubit.dart client/lib/services/app/connection_mode_service.dart client/lib/models/connection_mode.dart client/lib/models/windows_storage_backend.dart client/lib/services/terminal/terminal_transport_factory.dart client/lib/models/launch_target.dart
git commit -m "refactor: delete connectionMode/windowsStorageBackend knobs; isSshMode from target"
```

---

### Task 5: home target 选择器 UI（平台域定）

**Files:**
- Create: `client/lib/pages/config/runtime_target_picker.dart`
- Modify: `client/lib/pages/config/session_config_section.dart`, `client/lib/pages/config/session_config_constants.dart`
- Modify: `client/lib/widgets/android_ssh_profile_selector.dart`
- Modify: `client/lib/pages/ssh_profiles_page.dart`
- Modify l10n: `client/lib/l10n/app_en.arb`, `app_zh.arb`

**Interfaces:**
- Consumes: `RuntimeTargetRegistry.listTargets` (Task 2), `HomeTargetStore.save` via app_shell `setHomeTarget` + `reinstallStorageContext`.
- Produces: `RuntimeTargetPicker` widget showing platform-scoped home options.

- [ ] **Step 1: Build `RuntimeTargetPicker`** — a widget that:
  - Loads `registry.listTargets(wslDistro: <home distro>)`, filters by platform:
    - non-Windows desktop → only `local` (render read-only "This device").
    - Windows desktop → `local` + `wsl:<distro>` items.
    - Android → `ssh:*` items.
  - Current selection = app_shell home target id.
  - On select → `onSelect(id)` callback (wired to `setHomeTarget(id)` → `reinstallStorageContext()` → `reloadRemoteBackedAppData`, reusing the existing switch side-effect chain that `setWindowsStorageBackend`/`selectProfile` used).
  - Provide the callback via the existing DI the way `session_config_section` already obtains cubits/services.

- [ ] **Step 2: Replace controls in `session_config_section.dart`** — remove the Windows native/wsl `SegmentedButton` (lines ~279-301) and the dead connection-mode `SegmentedButton` (lines ~303-350); insert `RuntimeTargetPicker`. Delete `kShowConnectionModeSetting` from `session_config_constants.dart` and its references.

- [ ] **Step 3: Android quick-switch** — change `android_ssh_profile_selector.dart` to drive `setHomeTarget('ssh:<id>')` instead of `selectProfile` (it now picks the home target).

- [ ] **Step 4: SSH profiles page → manage-only** — remove the RadioGroup "selected" affordance from `ssh_profiles_page.dart`; keep add/edit/delete. (Selecting an ssh as home now happens in the picker / Android quick-switch.)

- [ ] **Step 5: l10n** — remove obsolete strings (connection-mode/backend toggle labels), add picker strings to `app_en.arb`/`app_zh.arb`. Then:
```bash
cd client && flutter pub get && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 6: Analyze + widget test**

Add `client/test/pages/config/runtime_target_picker_test.dart` asserting platform-scoped rendering (inject isAndroid/isWindows) and that selecting an item calls the `onSelect` with the right id.
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/config client/lib/widgets/android_ssh_profile_selector.dart client/lib/pages/ssh_profiles_page.dart client/lib/l10n client/test/pages/config/runtime_target_picker_test.dart
git commit -m "feat: platform-scoped home target picker replacing legacy knobs"
```

---

### Task 6: Android 首启门等价 + bootstrap 次序回归

**Files:**
- Modify: `client/lib/pages/startup_gate.dart` (or wherever `requiresSshProfileSetup` gates)
- Test: `client/test/app/home_target_bootstrap_test.dart`

**Interfaces:**
- Consumes: `ConnectionModeService.requiresSshProfileSetup`, `HomeTargetStore`, app_shell home resolution.

- [ ] **Step 1: Verify/keep the setup gate** — Android with no ssh profile (home would be `local` fallback but platform requires ssh): keep the existing "create a profile first" gate (`requiresSshProfileSetup`). After creating the first profile, set it as home (`setHomeTarget('ssh:<id>')`). Update the gate's check to: Android && home target kind != ssh (i.e. no usable ssh home yet).

- [ ] **Step 2: Write bootstrap-order test**

```dart
// Assert: given HomeTargetStore='ssh:p1' + profile p1, the resolved home target
// passed to installForTarget is ssh (== today's "select p1 remote"). Given
// 'local' (desktop) -> native. Given 'wsl:Ubuntu' (Windows) -> wsl.
// Use the installForTarget equivalence harness from the P0 install_for_target test.
```

- [ ] **Step 3: Run**

Run: `cd client && flutter test test/app/home_target_bootstrap_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/startup_gate.dart client/test/app/home_target_bootstrap_test.dart
git commit -m "test: home target bootstrap order + Android setup-gate equivalence"
```

---

### Task 7: 清除预备阶段兼容脚手架（folders 唯一磁盘形状）

**Files:**
- Modify: `client/lib/models/workspace_folder.dart`, `client/lib/models/workspace.dart`, `client/lib/models/app_session.dart`
- Modify tests: `client/test/models/workspace_test.dart`, `client/test/models/app_session_folders_test.dart`, `client/test/models/workspace_folder_test.dart`

**Interfaces:**
- Produces: `folders` as the ONLY disk shape; `fromJson` reads only `folders`; `toJson` writes only `folders`; no `foldersFromLegacyJson`, no `primaryPath`/`additionalPaths` dual-write or deprecated getters, no schemaVersion legacy branch.

- [ ] **Step 1: Confirm current scaffolding state** — run:
```bash
cd client && grep -n "foldersFromLegacyJson\|primaryPath\|additionalPaths\|@Deprecated" lib/models/workspace_folder.dart lib/models/workspace.dart lib/models/app_session.dart
```

- [ ] **Step 2: Simplify `workspace_folder.dart`** — replace `foldersFromLegacyJson` with a strict reader:
```dart
List<WorkspaceFolder> foldersFromJson(Object? raw) => raw is List
    ? [for (final e in raw) if (e is Map<String, Object?>) WorkspaceFolder.fromJson(e)]
    : const [];
```
Remove the legacy primaryPath/additionalPaths upgrade branch.

- [ ] **Step 3: `workspace.dart` / `app_session.dart`** —
  - `fromJson`: `folders: foldersFromJson(json['folders'])`.
  - `toJson`: write only `'folders': folders.map((f)=>f.toJson()).toList()`; **delete** the `primaryPath`/`additionalPaths` dual-write lines.
  - Remove any remaining `@Deprecated primaryPath/additionalPaths` getters and the factory/copyWith legacy `primaryPath`/`additionalPaths` params (if preparation Task 8 already removed them, confirm none remain).
  - Keep `firstFolderPath`/`extraFolderPaths`/`folderPaths`.

- [ ] **Step 4: Update model tests** — delete legacy-JSON-read tests (no longer supported); keep new-shape round-trip + getter tests. Assert `toJson()` contains NO `primaryPath`/`additionalPaths` keys.

- [ ] **Step 5: Analyze + test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/workspace_folder.dart client/lib/models/workspace.dart client/lib/models/app_session.dart client/test/models
git commit -m "refactor: folders is the only disk shape (remove preparation scaffolding)"
```

---

### Task 8: 终态清除回归 + 手验金路径

**Files:**
- Create: `client/test/app/clean_end_state_test.dart` (grep-style guard) or a CI check note
- Modify docs if a gap is found (no production code)

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Clean-state grep guard** — assert the legacy surface is gone:
```bash
cd client && for s in connectionMode windowsStorageBackend foldersFromLegacyJson currentLegacyTargetId migrateIfNeeded synthTarget; do
  echo "== $s =="; grep -rn "$s" lib --include=*.dart || echo "  (clean)";
done
echo "== model primaryPath/additionalPaths dual-write =="; grep -n "primaryPath\|additionalPaths" lib/models/workspace.dart lib/models/app_session.dart || echo "  (clean)"
```
Expected: each prints `(clean)` (except any `ConnectionMode` internal transport descriptor explicitly kept per Task 4 audit — document it).

- [ ] **Step 2: Full verification (acceptance)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS.

- [ ] **Step 3: Document manual golden paths** — append to the design spec §7.9: (1) desktop local launch; (2) Windows switch home to wsl; (3) Android select ssh home == legacy "select profile remote"; (4) Android first-run with no profile → create-profile gate → becomes home.

- [ ] **Step 4: Commit**

```bash
git add client/test/app/clean_end_state_test.dart docs/superpowers/specs/2026-06-22-p1-home-target-design.md
git commit -m "test: clean-end-state guard and manual golden-path notes"
```

---

## Self-Review

**Spec coverage:**
- §2.1 home authority = device-local homeTargetId → Task 1 (store) + Task 3 (bootstrap) ✅
- §2.2 targets.json final shape (no default/migrate) → Task 2 ✅
- §2.3 HomeTargetStore → Task 1 ✅
- §3 bootstrap order (chicken-egg) → Task 3 + Task 6 ✅
- §4 platform-scoped picker; §4.1 Windows distro default; dead toggle removal → Task 5 ✅
- §6 scaffolding removal (preparation folders + P0 prefs/migrate) → Task 7 (preparation) + Tasks 2/3/4 (P0) ✅
- §7 test strategy incl. Android equivalence + clean-state grep → Tasks 6/8 + per-task tests ✅
- §8 out-of-scope → Global Constraints ✅

**Placeholder scan:** Task 4 Step 1 (ConnectionMode audit) and Task 5 UI steps describe structure + exact mutation wiring rather than full widget code — intentional for voluminous UI, with concrete cubit/service calls named. Core model/service tasks (1,2,3,7) carry complete code. The install-equivalence harness reuse (Task 6) points at the existing P0 test — deliberate reuse, not a gap.

**Type consistency:** `HomeTargetStore.{load,save}`, `defaultTargetResolver()→RuntimeTarget`, `setHomeTarget(id)`, `homeTargetFromId(id)`, `TargetsRegistryFile{schemaVersion,targets}`, `RuntimeTargetRegistry.listTargets({wslDistro})`, `ConnectionModeService.isSshMode` used identically across tasks. `runtimeKindOfId`/`sshProfileIdOfId`/`wslDistroOfId` reused from P0.

**Zero-compat end-state guard:** Task 8 grep guard enforces the directive (no connectionMode/windowsStorageBackend/foldersFromLegacyJson/migrate/synthTarget/dual-write). Ordering (build new authority → switch consumers → delete scaffolding) keeps every task's `analyze`+`test` gate green. **Open architectural item flagged in spec §2.1 (home authority local vs targets.json-only) — surfaced to team-lead for confirm/veto; plan assumes the local-homeTargetId resolution.**
