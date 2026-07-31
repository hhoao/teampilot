# Android Termux Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, add Termux as a first-class work home peer to remote SSH so users can cold-start without a remote host and run file tree / Git / shell / CLI sessions on-device via loopback SSH.

**Architecture:** Introduce `RuntimeKind.termux` / id `termux:default`. Device-local `TermuxConfig` + reserved credential id feed a synthetic `SshProfile` into the existing `SshClientFactory` / `SftpFilesystem` / `SshPtyTransport` path. StartupGate becomes a work-environment chooser (Termux | remote SSH); gate checks **bound home**, not live sshd. Shared-storage folder migration is **out of this plan** (follow-up; not required for success criteria).

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `dartssh2` SSH stack, device-local control plane (`AppPaths` + `LocalFilesystem`), l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-31-android-termux-home-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/runtime_target.dart` | `RuntimeKind.termux`, `termux:` id helpers, factory; set `sshProfileId: 'termux'` on termux targets for transport lookup without catalog entries |
| `client/lib/services/termux/termux_connection_gate.dart` | Pure allow/deny for work ops when termux home disconnected |
| `client/lib/services/storage/work_target_canonicalizer.dart` | Canonicalize termux home / fromId |
| `client/lib/services/termux/termux_config.dart` | Immutable config (username, host, port, optional lastHome/lastAppDataRoot) |
| `client/lib/services/termux/termux_config_store.dart` | Device-local JSON persist under native app data |
| `client/lib/services/termux/termux_key_material.dart` | Generate/read ed25519; pubkey text for setup copy |
| `client/lib/services/termux/termux_transport_profile.dart` | Build synthetic `SshProfile` id=`termux` (not in SSH catalog) |
| `client/lib/services/termux/apply_termux_connect_home.dart` | Pure helper: Connect OK → `select('termux:default')` |
| `client/lib/cubits/termux_cubit.dart` | Config + connected flag; connect/disconnect/clear |
| `client/lib/services/app/connection_mode_service.dart` | `isTermuxMode`, `hasBoundAndroidWorkHome`, narrow SSH-only setup |
| `client/lib/services/storage/runtime_context_resolver.dart` | Resolve termux → same SSH SFTP path via synthetic profile |
| `client/lib/services/storage/runtime_target_registry.dart` | List `termux:default` on Android when configured |
| `client/lib/services/team/default_workspace_service.dart` | Treat termux like ssh/wsl for `$HOME/TeamPilot` (likely already via non-local branch) |
| `client/lib/pages/startup_gate.dart` | Work-environment chooser when unbound |
| `client/lib/pages/termux/work_environment_chooser_page.dart` | Two peers: Termux / Remote SSH |
| `client/lib/pages/termux/termux_setup_page.dart` | Guided setup + Connect |
| `client/lib/widgets/android_work_environment_selector.dart` | Replace/extend SSH-only top-bar selector |
| `client/lib/widgets/termux/termux_disconnected_banner.dart` | In-shell reconnect UX |
| Call-site audit | Anywhere `isSshMode` means “remote work plane” → include termux |

**Reserved ids:** Runtime home `termux:default`; transport profile / credential id `termux` (never written to `SshProfileRepository`).

---

### Task 1: `RuntimeKind.termux` + id helpers

**Files:**
- Modify: `client/lib/models/runtime_target.dart`
- Modify: `client/test/models/runtime_target_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('termux factory and id helpers', () {
  expect(RuntimeTarget.termux().id, 'termux:default');
  expect(runtimeKindOfId('termux:default'), RuntimeKind.termux);
  expect(runtimeKindOfId('termux:other'), RuntimeKind.termux);
});

test('termux json round-trip', () {
  final t = RuntimeTarget.termux(label: 'Termux');
  final r = RuntimeTarget.fromJson(t.toJson());
  expect(r.kind, RuntimeKind.termux);
  expect(r.id, 'termux:default');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/runtime_target_test.dart`

Expected: FAIL (no `termux` / factory)

- [ ] **Step 3: Minimal implementation**

In `runtime_target.dart`:

- Add `termux` to `RuntimeKind`
- `runtimeKindOfId`: if `id.startsWith('termux:')` → `RuntimeKind.termux`
- `static const termuxDefaultId = 'termux:default';`
- `factory RuntimeTarget.termux({String label = 'Termux'}) => RuntimeTarget(id: termuxDefaultId, label: label, kind: RuntimeKind.termux, sshProfileId: 'termux');`
- Ensure `fromJson` / `copyWith` / equality still work (kind from json or id)
- Test asserts `RuntimeTarget.termux().sshProfileId == 'termux'`

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/runtime_target.dart client/test/models/runtime_target_test.dart
git commit -m "feat(runtime): add RuntimeKind.termux and termux:default id"
```

---

### Task 2: WorkTargetCanonicalizer for termux

**Files:**
- Modify: `client/lib/services/storage/work_target_canonicalizer.dart`
- Modify: `client/test/services/storage/work_target_canonicalizer_test.dart`

- [ ] **Step 1: Failing tests**

```dart
final termuxHome = RuntimeTarget.termux();

test('defaultFolderTargetId for termux home', () {
  expect(
    WorkTargetCanonicalizer.defaultFolderTargetId(termuxHome),
    'termux:default',
  );
});

test('bare local resolves to termux home', () {
  expect(
    WorkTargetCanonicalizer.resolve('local', home: termuxHome),
    termuxHome,
  );
});

test('fromId parses termux', () {
  expect(
    WorkTargetCanonicalizer.fromId('termux:default').kind,
    RuntimeKind.termux,
  );
});
```

- [ ] **Step 2: Run — expect FAIL** (`fromId` switch exhaustiveness / wrong kind)

- [ ] **Step 3: Implement**

Update `fromId` switch to include:

```dart
RuntimeKind.termux => RuntimeTarget.termux(),
```

`defaultFolderTargetId` / `resolve` already return `home.id` / `home` for non-local — verify termux is non-local (it is). Fix any exhaustiveness errors elsewhere in the repo (`dart analyze` on touched packages).

- [ ] **Step 4: Run canonicalizer tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/work_target_canonicalizer.dart \
  client/test/services/storage/work_target_canonicalizer_test.dart
git commit -m "feat(storage): canonicalize work targets for termux home"
```

---

### Task 3: TermuxConfig store + key material + transport profile

**Files:**
- Create: `client/lib/services/termux/termux_config.dart`
- Create: `client/lib/services/termux/termux_config_store.dart`
- Create: `client/lib/services/termux/termux_key_material.dart`
- Create: `client/lib/services/termux/termux_transport_profile.dart`
- Create: `client/test/services/termux/termux_config_store_test.dart`
- Create: `client/test/services/termux/termux_transport_profile_test.dart`

- [ ] **Step 1: Failing store test**

Use a temp dir + `LocalFilesystem` (same pattern as `device_local_control_plane_test.dart`):

```dart
test('round-trips username and marks configured', () async {
  final store = TermuxConfigStore(rootDir: temp, fs: fs);
  expect(await store.load(), isNull);
  await store.save(const TermuxConfig(
    username: 'u0_a399',
    host: '127.0.0.1',
    port: 8022,
  ));
  final loaded = await store.load();
  expect(loaded!.username, 'u0_a399');
  expect(loaded.port, 8022);
});
```

Transport profile test:

```dart
test('synthetic profile uses reserved id and loopback', () {
  final p = termuxTransportProfile(
    const TermuxConfig(username: 'u0_a1', host: '127.0.0.1', port: 8022),
  );
  expect(p.id, 'termux');
  expect(p.host, '127.0.0.1');
  expect(p.port, 8022);
  expect(p.authType, SshAuthType.privateKey);
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

`TermuxConfig`: `username`, `host` (default `127.0.0.1`), `port` (default `8022`), optional `lastHome` / `lastAppDataRoot` (filled after successful connect; used by Task 5 cold-start fallback), json round-trip.

`TermuxConfigStore`: path **`{nativeAppData}/.termux/config.json`** (fixed). Use injected `Filesystem` + root; **never** `AppStorage` home.

`TermuxKeyMaterial`:

- `ensureKeyPair({required String nativeAppDataPath})` → write `id_ed25519` / `id_ed25519.pub` under `{nativeAppData}/.termux/ssh/` if missing; also `SshCredentialStore.savePrivateKey('termux', pem)` so `SshClientFactory` can auth
- `publicKeyOpenSsh()` for setup copy block
- Prefer existing crypto used by SSH key upload if present; otherwise use a small ed25519 PEM generator already in deps (check `pointycastle` / existing helpers). If no shared helper exists, add a focused `TermuxEd25519` in the same folder — do not invent a second credential store.

`termuxTransportProfile(TermuxConfig)` → `SshProfile(id: 'termux', name: 'Termux', …)`.

- [ ] **Step 4: Tests PASS** — also assert store still loads after a fake `AppStorage` home rebind to a remote path (control plane stays on native root; mirror `device_local_control_plane_test.dart` spirit).

- [ ] **Step 5: Commit**
---

### Task 4: ConnectionModeService — bound Android work home

**Files:**
- Modify: `client/lib/services/app/connection_mode_service.dart`
- Create or modify: `client/test/services/app/connection_mode_service_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('hasBoundAndroidWorkHome for ssh and termux only', () {
  expect(
    ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.termux(),
      hasSshProfiles: () => false,
    ).hasBoundAndroidWorkHome,
    isTrue,
  );
  expect(
    ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.local(),
      hasSshProfiles: () => true,
    ).hasBoundAndroidWorkHome,
    isFalse,
  );
});

test('requiresSshProfileSetup only when ssh home lacks profiles', () {
  final svc = ConnectionModeService(
    defaultTargetResolver: () => RuntimeTarget.termux(),
    hasSshProfiles: () => false,
  );
  expect(svc.requiresSshProfileSetup, isFalse);
  expect(svc.isTermuxMode, isTrue);
  expect(svc.isSshMode, isFalse);
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```dart
bool get isTermuxMode =>
    _defaultTargetResolver().kind == RuntimeKind.termux;

bool get hasBoundAndroidWorkHome => isSshMode || isTermuxMode;

/// Prefer this when code means "SFTP / remote CLI plane" not "SSH profile UI".
bool get isRemoteWorkPlane => isSshMode || isTermuxMode;
```

Keep `isSshMode` as **ssh-only**. Keep `requiresSshProfileSetup => isSshMode && !hasProfiles`.

Note: existing `isLocalMode => !isSshMode` will be **true** for termux until callers migrate — Task 11 must replace “remote work plane” checks that incorrectly use `isLocalMode` / `!isSshMode` with `isRemoteWorkPlane` / `isTermuxMode` as appropriate. Optionally redefine `isLocalMode => kind == local` in this task if analyze/tests allow (preferred if low churn).

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/app/connection_mode_service.dart \
  client/test/services/app/connection_mode_service_test.dart
git commit -m "feat(app): treat termux as bound Android work home"
```

---

### Task 5: RuntimeContextResolver + registry for termux

**Files:**
- Modify: `client/lib/services/storage/runtime_context_resolver.dart`
- Modify: `client/lib/services/storage/runtime_target_registry.dart`
- Modify: `client/lib/app/app_shell.dart` (wire TermuxConfig → synthetic profile into resolve/switch)
- Test: `client/test/services/storage/runtime_context_resolver_test.dart` (create if missing; else extend)

- [ ] **Step 1: Failing test**

Mock `SshClientFactory` / path resolver like existing SSH resolver tests (search repo for `_resolveSsh` tests). Assert `resolve(RuntimeTarget.termux(), sshProfile: synthetic)` returns context with `target.kind == termux` and `filesystem is SftpFilesystem`.

If full SFTP mock is heavy: unit-test that `resolve` takes the SSH branch when `kind == termux && sshProfile != null` by extracting the condition:

```dart
final useSshTransport =
    (target.kind == RuntimeKind.ssh || target.kind == RuntimeKind.termux) &&
    sshProfile != null &&
    sshClientFactory != null;
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

- Update `useSsh` / rename to `useSshTransport` as above; keep returning `RuntimeContext(target: target, …)` so kind stays `termux`.
- Registry: on Android, if Termux config exists (callback/injected), include `RuntimeTarget.termux()` in `listTargets`.
- App shell home switch: when id is `termux:default`, load config, build transport profile, ensure credential, pass synthetic profile into `RuntimeContextResolver` / `SshClientFactory` pool under reserved id `termux` (same pool machinery as SSH profiles, **without** `SshProfileCubit.selectProfile`). If the factory keys sessions by profile id, `termux` is enough isolation from catalog profiles.
- Bootstrap alignment: when home is termux, use the **same remote home-index path** as SSH (`isRemoteWorkPlane`), not `hydrateNativeHomeIndex`.

**Cold start when sshd is down (spec §3 — must not crash bootstrap):**

`ensureHome()` / `RuntimeContextResolver` currently `await clientFactory.sftpFor(profile)` inside `_resolveSsh`. For Termux that would throw before UI/banner exists. Downstream `bootstrapAppData` also reads workspace index via `AppStorage.fs` (SFTP) and today branches on `isSshMode` only.

**Chosen disconnected strategy (do not leave alternatives open):**

1. Persist optional `lastHome` + `lastAppDataRoot` on `TermuxConfig` after every **successful** Connect/resolve (fields added in Task 3).
2. On Termux resolve: try SFTP with short timeout.
3. On failure with cache present: **keep** home id `termux:default`; build `RuntimeContext` using cached paths + `SftpFilesystem`/`RemoteFileStore` **without** calling `pathResolver.resolve` or eager `sftpFor` at construct time (lazy connect on first I/O is OK; I/O may fail until reconnect).
4. `bootstrapAppData` for termux uses `isRemoteWorkPlane` (same branch as SSH). Wrap workspace index load / default seed **and** any early `homeIndexPrefetch` / `loadWorkspacesIndex` in `app_shell` so SFTP read failures **soft-fail** to an empty index (log via `AppLogger`) instead of crashing the app — user sees main shell + Task 10 banner/gate.
5. Never fall home back to `local` on sshd failure.
6. Unit test: mock SFTP failure on resolve → no throw out of `ensureHome`/`switchTo`; home id remains `termux:default`. Separate test or assertion: bootstrap soft-fail path does not rethrow.

**Transport pool eviction:**

- `homeTargetFromId` / switch helpers must handle `RuntimeKind.termux` (and `termux:default`).
- `onEvict(targetId)` receives a string only: resolve with `homeTargetFromId(targetId).sshProfileId ?? sshProfileIdOfId(targetId)` so termux disconnects reserved id `termux` (Task 1 sets `sshProfileId: 'termux'` on the factory).

**Task ordering note:** Implement `profileById` resolution for reserved id `termux` → `termuxTransportProfile(config)` in Task 5 (needed for ensureHome tests). Task 11 widens remaining CLI call sites.

Mark disconnected for UI in Task 7/10 via `TermuxCubit` after provide — resolver/registry stays free of cubit imports; bootstrap only soft-fails FS.

- [ ] **Step 4: Tests PASS; `dart analyze` on touched files clean**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_context_resolver.dart \
  client/lib/services/storage/runtime_target_registry.dart \
  client/lib/app/app_shell.dart \
  client/test/services/storage/
git commit -m "feat(storage): resolve termux home via loopback SSH transport"
```

---

### Task 6: Default workspace path for termux home

**Files:**
- Modify: `client/test/services/team/default_workspace_service_test.dart`
- Modify: `client/lib/services/team/default_workspace_service.dart` only if needed

- [ ] **Step 1: Failing test**

Mirror existing SSH home seed test with `home: RuntimeTarget.termux()`:

- path ends with `/TeamPilot` under bound `AppStorage.home`
- folder `targetId == 'termux:default'`

- [ ] **Step 2: Run**

If non-local branch already covers termux, test may PASS immediately — keep the test as regression lock.

- [ ] **Step 3: Only if FAIL — widen comment / branch; do not special-case Documents path**

- [ ] **Step 4: Commit**

```bash
git add client/test/services/team/default_workspace_service_test.dart \
  client/lib/services/team/default_workspace_service.dart
git commit -m "test(workspace): lock Default path under termux home"
```

---

### Task 7: Apply Termux Connect home helper + TermuxCubit

**Files:**
- Create: `client/lib/services/termux/apply_termux_connect_home.dart`
- Create: `client/test/services/termux/apply_termux_connect_home_test.dart`
- Create: `client/lib/cubits/termux_cubit.dart`
- Create: `client/test/cubits/termux_cubit_test.dart`
- Wire: `client/lib/app/app_shell.dart` / `main.dart` providers

- [ ] **Step 1: Helper failing test** (same style as `android_ssh_connect_home_test.dart`)

```dart
test('selects termux home only after success callback order', () async {
  final calls = <String>[];
  await applyTermuxConnectHome(
    selectHome: (id) async => calls.add('home:$id'),
  );
  expect(calls, ['home:termux:default']);
});
```

Cubit tests with fake tester / fake `SshProfileConnectionTester`:

- `connect` success → state.connected == true and invokes home select once
- `connect` failure → not connected; home select not called
- `disconnect` → connected false; config retained; home stays `termux:default`
- `clearSetup` → deletes config+keys; **and** invokes injected `onClearedHome` that selects an unbound home (`local`) so StartupGate shows the chooser on Android

Pure helper for clear (optional, same style as connect):

```dart
Future<void> applyTermuxClearSetupHome({
  required Future<void> Function(String homeId) selectHome,
}) => selectHome(RuntimeTarget.localId);
```

Test: clear calls `home:local` (or whatever unbound id Android gate treats as “needs work home”).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```dart
Future<void> applyTermuxConnectHome({
  required Future<void> Function(String homeId) selectHome,
}) => selectHome(RuntimeTarget.termuxDefaultId);
```

`TermuxCubit`: load/save via store; `connect` uses `SshProfileConnectionTester` + transport profile + credential; on success call `applyTermuxConnectHome`; expose `isConnected` for banner/gates. Persist **config** device-local; do not persist “connected” across process — cold start attempts reconnect.

`clearSetup`: wipe store + credential id `termux` + key files; then `applyTermuxClearSetupHome` so gate re-opens. Wire a **Clear setup** action on `TermuxSetupPage` (and/or work-environment selector overflow) in Task 9 — do not leave clear as cubit-only.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/termux/apply_termux_connect_home.dart \
  client/lib/cubits/termux_cubit.dart \
  client/test/services/termux/ client/test/cubits/termux_cubit_test.dart \
  client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(termux): add connect home helper and TermuxCubit"
```

---

### Task 8: StartupGate work-environment chooser

**Files:**
- Create: `client/lib/pages/termux/work_environment_chooser_page.dart`
- Modify: `client/lib/pages/startup_gate.dart`
- Modify: `client/test/pages/startup_gate_test.dart` (or create)

- [ ] **Step 1: Failing widget tests**

| Scenario | Expected |
|----------|----------|
| Android + home local + no termux bind | Shows chooser (not bare SSH list as only option) |
| Android + home `termux:default` | Shows `child` even if TermuxCubit disconnected |
| Android + home `ssh:p1` + profiles | Shows `child` (existing) |
| Android + user navigates Remote SSH with zero profiles | SSH list / setup (existing remote path) |

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

Replace `androidNeedsSshHome = android && !mode.isSshMode` with:

```dart
final androidNeedsWorkHome = android && !mode.hasBoundAndroidWorkHome;
```

When `androidNeedsWorkHome` → `WorkEnvironmentChooserPage`.

Chooser:

- Tile **Termux** → push `TermuxSetupPage` (Task 9)
- Tile **Remote SSH** → push/show `SshProfilesPage`

Do **not** use `requiresSshProfileSetup` alone to block Termux chooser.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/startup_gate.dart \
  client/lib/pages/termux/work_environment_chooser_page.dart \
  client/test/pages/
git commit -m "feat(android): StartupGate offers Termux or remote SSH"
```

---

### Task 9: Termux setup page (guided UX)

**Files:**
- Create: `client/lib/pages/termux/termux_setup_page.dart`
- Create: `client/test/pages/termux/termux_setup_page_test.dart` (smoke: shows copy steps / validates username)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (then codegen if project requires)

- [ ] **Step 1: Widget smoke test** — page shows install/openssh/authorized_keys/storage/sshd/whoami sections and username field; invalid username shows error; Save+Connect taps cubit (mock).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement UI**

Follow Roxum step order; use `Tp*` controls from `shared_ui`. Username validator: non-empty and starts with `u` (same spirit as Roxum). On Connect success: `applyTermuxConnectHome` already bound home → gate clears on next build. Show snackbar errors from cubit failure strings (l10n).

Include **Clear setup** (destructive confirm): calls `TermuxCubit.clearSetup` → home → `local` → StartupGate chooser. Cover with a widget/cubit test that clear triggers `selectHome(local)`.

Links: Play / F-Droid / GitHub Termux — open via `url_launcher` if already used; else copy URL.

- [ ] **Step 4: Tests PASS; run `dart run tool/gen_warmup_glyphs.dart` if ARB changed per AGENTS.md**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/termux/ client/lib/l10n/ client/test/pages/termux/
git commit -m "feat(termux): add guided Termux setup and Connect page"
```

---

### Task 10: Work environment selector + disconnected banner + blocked launch

**Files:**
- Create: `client/lib/widgets/android_work_environment_selector.dart` (or evolve `android_ssh_profile_selector.dart`)
- Create: `client/lib/widgets/termux/termux_disconnected_banner.dart`
- Create: `client/lib/services/termux/termux_connection_gate.dart` (pure: `bool allowTermuxWorkOps(bool isTermuxHome, bool connected)`)
- Modify: session launch / workspace shell entry points to consult the gate when home/launch target is termux
- Modify: `client/lib/router/app_router.dart` (AppBar actions)
- Modify: home shell body to show banner when `isTermuxMode && !connected`
- Test: gate unit tests + one launch/shell path test that disconnected termux refuses with a clear error

- [ ] **Step 1: Tests**

- Selector lists Termux (if configured) + SSH profiles; choosing Termux calls `HomeTargetController.select('termux:default')` **and** triggers `TermuxCubit.connect` (not only cold start)
- Banner visible when disconnected; Reconnect invokes cubit.connect
- `allowTermuxWorkOps(true, false) == false`; `allowTermuxWorkOps(true, true) == true`
- Attempting session launch (or workspace shell connect) while termux home disconnected → does not open PTY; surfaces reconnect messaging (l10n)

Blocked surfaces (minimum for spec §3): **session launch**, **workspace shell**, and any immediate **Git/SFTP** user action that would otherwise throw a cryptic socket error — prefer one shared gate check at the connector / launch service boundary rather than scattering SnackBars.

- [ ] **Step 2–4: Implement + PASS**

Cold start: if home is termux, bootstrap (Task 5) must already tolerate dead sshd; then `TermuxCubit` attempts reconnect once after provide; failure leaves banner + gate closed for work ops. Manual: kill app with sshd down → relaunch still enters main shell (not chooser).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/android_work_environment_selector.dart \
  client/lib/widgets/termux/ client/lib/services/termux/termux_connection_gate.dart \
  client/lib/router/app_router.dart client/lib/services/launch/ \
  client/test/widgets/ client/test/services/termux/
git commit -m "feat(android): Termux selector, banner, and blocked launch when disconnected"
```

---

### Task 11: Remote work-plane call-site audit + Termux synthetic profile for CLI

**Files:** audit + patch call sites such as:

- `client/lib/app/app_data_bootstrap.dart`
- `client/lib/app/app_shell.dart` (`RemoteCliReadinessService` / `sshProfileById`)
- `client/lib/services/launch/session_shell_connector.dart`
- `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- `client/lib/pages/onboarding/steps/cli_step.dart`
- `client/lib/pages/config/cli_executable_path_settings_row.dart`
- `client/lib/services/terminal/workspace_shell_connector.dart`
- `client/lib/services/` target liveness / any exhaustive `RuntimeKind` switches (`target_liveness.dart` if present)
- Member connect gates / any `kind != RuntimeKind.ssh` early returns that should accept termux

- [ ] **Step 1: Grep (no truncation)**

```bash
cd client && rg -n "isSshMode|RuntimeKind\.ssh|RemoteCliReadiness" lib/ --glob '*.dart'
cd client && rg -n "kind != RuntimeKind\.ssh|kind == RuntimeKind\.ssh" lib/ --glob '*.dart'
```

Classify each hit: **SSH-catalog UI** (leave) vs **remote work plane / transport** (include termux).

- [ ] **Step 2: Failing tests for CLI readiness with termux**

Critical gap: `RemoteCliReadinessService` and session shell today resolve profiles via `profileById` from the **SSH catalog**. Termux’s synthetic `SshProfile(id: 'termux')` is **not** in that catalog.

Required wiring:

```dart
SshProfile? profileByIdIncludingTermux(String id) {
  if (id == 'termux') {
    final cfg = termuxConfigStore.loadSyncOrCached();
    return cfg == null ? null : termuxTransportProfile(cfg);
  }
  return sshProfileRepository.getById(id);
}
```

- Extend `RuntimeTarget.termux()` to carry or resolve transport id `termux` (e.g. document that shell code uses reserved id when `kind == termux`, **or** add optional `sshProfileId: 'termux'` on the termux `RuntimeTarget` factory so existing `profileById(target.sshProfileId)` keeps working without catalog pollution).
- Prefer **`RuntimeTarget.termux()` sets `sshProfileId: 'termux'`** for least churn in `session_shell_connector` / readiness — still never write that profile into `SshProfileRepository`.
- Update `RemoteCliReadiness` / panel guards from `kind != ssh` to `kind != ssh && kind != termux` (or helper `usesSshTransport(kind)`).

Tests:

- `profileByIdIncludingTermux('termux')` returns synthetic profile when config exists
- readiness probe with termux target does not throw “not ssh” / missing catalog profile
- at least one path proves no device-native `File.existsSync` for Termux binaries

- [ ] **Step 3: Patch all classified call sites**

- [ ] **Step 4: `cd client && flutter test` on touched tests; `flutter analyze --no-fatal-infos --no-fatal-warnings` on changed libs**

- [ ] **Step 5: Commit**

```bash
git add client/lib/ client/test/
git commit -m "fix(android): termux synthetic profile for remote CLI and shell"
```

---

### Task 12: Verification + docs touch-up

- [x] **Step 1: Run focused suites**

```bash
cd client && flutter test \
  test/models/runtime_target_test.dart \
  test/services/storage/work_target_canonicalizer_test.dart \
  test/services/termux/ \
  test/services/app/connection_mode_service_test.dart \
  test/pages/startup_gate_test.dart \
  test/services/team/default_workspace_service_test.dart \
  test/cubits/termux_cubit_test.dart
```

- [ ] **Step 2: Broader non-integration**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 3: Manual device checklist** (record in PR / commit message if done)

1. Fresh Android install → chooser → Termux setup → Connect → Default at `$HOME/TeamPilot`
2. Kill sshd → still in app, banner, reconnect works
3. Clear Termux setup → returns to chooser
4. Remote SSH path still Connect → home `ssh:…`

- [ ] **Step 4: Optional one-line pointer in `docs/workspace-storage-layout.md` or AGENTS.md Android row — only if accurate and short**

- [ ] **Step 5: Final commit if docs changed**

---

## Out of this plan (follow-up)

- Settings UI to migrate Default folder to `~/storage/shared/TeamPilot`
- Cross-home mix (pin folder/member to Termux while home is remote)
- Silent multi-CLI install on Connect
- Embedding Termux / iOS

---

## Execution note

Prefer **subagent-driven-development**: one fresh subagent per task, TDD order, commit per task. Do not start Task 8 UI until Tasks 1–7 (model + connect) are green.
