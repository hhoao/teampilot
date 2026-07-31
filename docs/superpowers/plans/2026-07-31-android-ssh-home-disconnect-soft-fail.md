# Android SSH Home Disconnect Soft-Fail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Android’s persisted home is remote SSH and the host is down, cold-start still enters the main shell (path-cache soft-fail + reconnect banner); if soft-fail is impossible, the bootstrap error page offers Retry and Choose work environment.

**Architecture:** Mirror Termux disconnect: persist `lastHome` / `lastAppDataRoot` on device-local `SshProfile`; `_resolveSsh` soft-fails with cached paths into a lazy-SFTP `RuntimeContext` (`pathsFromCache`); show `SshHomeDisconnectedBanner` driven by `SshConnectionCubit`; bootstrap hard-fail safety net clears home to `local` so StartupGate reopens the chooser. Never auto-unbind on connect failure.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `dartssh2` / `SshClientFactory` pool, device-local `SshProfileRepository`, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-31-android-ssh-home-disconnect-soft-fail-design.md`

**Locked plan choices (from spec review advisories):**

| Topic | Choice |
|-------|--------|
| Path cache storage | Direct fields on `SshProfile` (`lastHome`, `lastAppDataRoot`) |
| Cache flag | Rename `termuxPathsFromCache` → `pathsFromCache` (single bool) |
| Cold-start reconnect | **v1 includes** one `SshConnectionCubit.connect(homeProfileId)` after shell provide (Termux parity) |
| Bootstrap safety net | Android-only: Retry + Choose work environment on any `TeamPilotBootstrap` hard fail; WSL native button unchanged |
| Soft-fail scope | Remote `RuntimeKind.ssh` (+ keep Termux soft-fail via existing cachedHome params) |
| Cache available at `ensureHome` | **Preload** home SSH profile from `sshProfileRepo` before `ensureHome` (Termux already loads `termuxConfigStore` first) — do not wait for `sshProfileCubit.load()` |
| Path-cache write sites | **Primary:** after `sshProfileCubit.load()` when home is SSH and `!pathsFromCache`. **Also:** after live `reinstallStorageContext` / home rebind success |
| Cold-start reconnect | After profiles loaded: **explicit** `await sshConnectionCubit.syncProfiles(...)` then `unawaited(connect(homePid))` — **not** from `bootstrapHomeIndex` before shell mount / binder sync |

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/ssh_profile.dart` | Optional `lastHome` / `lastAppDataRoot`; JSON round-trip; **exclude from `==` / `hashCode`** (cache churn must not look like identity change) |
| `client/lib/services/storage/runtime_context.dart` | Rename `termuxPathsFromCache` → `pathsFromCache` |
| `client/lib/services/storage/runtime_context_resolver.dart` | Soft-fail SSH with profile cache; set `pathsFromCache` |
| `client/lib/services/storage/runtime_context_registry.dart` | Pass profile `lastHome`/`lastAppDataRoot` as cached paths for SSH targets |
| `client/lib/cubits/ssh_profile_cubit.dart` | `updatePathCache(id, home, appDataRoot)` — save without `invalidateProfileConnection` |
| `client/lib/app/app_shell.dart` | Preload home SSH profile before `ensureHome`; persist cache; cold-start reconnect after syncProfiles; bootstrap Android safety net |
| `client/lib/widgets/ssh/ssh_home_disconnected_banner.dart` | In-shell banner peer of Termux |
| `client/lib/pages/home_workspace/home_workspace_shell.dart` | Mount SSH banner next to Termux banner |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Banner + bootstrap safety-net strings |
| Tests under `client/test/…` | Resolver soft-fail, profile JSON, cubit path cache, banner widget, bootstrap actions |

**Do not** put path cache under remote `AppStorage`. **Do not** auto `select(local)` on reconnect failure.

---

### Task 1: `SshProfile` path-cache fields

**Files:**
- Modify: `client/lib/models/ssh_profile.dart`
- Modify: `client/test/models/ssh_profile_test.dart`
- Modify: `client/test/services/storage/home_ssh_profile_impact_test.dart` (if fingerprint / impact tests need a profile with cache fields)

- [ ] **Step 1: Write the failing tests**

In `ssh_profile_test.dart` add:

```dart
test('json round-trip preserves lastHome and lastAppDataRoot', () {
  final p = SshProfile(
    id: 'a',
    name: 'Box',
    host: 'h',
    username: 'u',
    lastHome: '/home/u',
    lastAppDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
  );
  final r = SshProfile.fromJson(p.toJson());
  expect(r.lastHome, '/home/u');
  expect(r.lastAppDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
});

test('equality ignores path cache fields', () {
  final a = SshProfile(
    id: 'a', name: 'Box', host: 'h', username: 'u',
    lastHome: '/home/u',
  );
  final b = SshProfile(
    id: 'a', name: 'Box', host: 'h', username: 'u',
    lastHome: '/other',
  );
  expect(a, equals(b));
});
```

Also assert `sshHomeConnectionFingerprint` is unchanged when only cache fields differ (reuse existing helper test file or add one line there).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/ssh_profile_test.dart`

Expected: FAIL (no `lastHome` constructor / fields)

- [ ] **Step 3: Minimal implementation**

Add optional `lastHome` / `lastAppDataRoot` to constructor, `fromJson`, `toJson`, `copyWith`. Keep `==` / `hashCode` on connection + display fields only (same set as today — **do not** include cache). Leave `sshHomeConnectionFingerprint` as-is (already excludes cache).

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/models/ssh_profile_test.dart test/services/storage/home_ssh_profile_impact_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/ssh_profile.dart client/test/models/ssh_profile_test.dart
git commit -m "feat(ssh): persist lastHome path cache on SshProfile"
```

---

### Task 2: Rename `pathsFromCache` + SSH soft-fail in resolver

**Files:**
- Modify: `client/lib/services/storage/runtime_context.dart`
- Modify: `client/lib/services/storage/runtime_context_resolver.dart`
- Modify: `client/lib/services/storage/runtime_context_registry.dart`
- Modify: `client/lib/app/app_shell.dart` (rename `termuxPathsFromCache` call sites)
- Modify: `client/lib/cubits/termux_cubit.dart` if it reads the flag
- Modify: `client/test/services/storage/runtime_context_resolver_test.dart`
- Grep and update any other `termuxPathsFromCache` references

- [ ] **Step 1: Write the failing tests**

Extend `runtime_context_resolver_test.dart`:

```dart
test('ssh SFTP failure with profile path cache soft-fails', () async {
  final factory = _MockSshClientFactory();
  when(() => factory.sftpFor(any())).thenThrow(StateError('host down'));
  final profile = SshProfile(
    id: 'p1',
    name: 'Remote',
    host: 'example.com',
    username: 'u',
    lastHome: '/home/u',
    lastAppDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
  );
  final resolver = RuntimeContextResolver(
    sshClientFactory: factory,
    nativeAppDataPath: tmp.path,
    remotePathResolver: _FakePathResolver(
      clientFactory: factory,
      onResolve: (_) => Future.error(StateError('resolve failed')),
    ),
  );
  final ctx = await resolver.resolve(
    RuntimeTarget.ssh('p1'),
    sshProfile: profile,
    cachedHome: profile.lastHome,
    cachedAppDataRoot: profile.lastAppDataRoot,
  );
  expect(ctx.target.kind, RuntimeKind.ssh);
  expect(ctx.pathsFromCache, isTrue);
  expect(ctx.home, '/home/u');
  expect(ctx.appDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
});

test('ssh failure without cache rethrows', () async {
  final factory = _MockSshClientFactory();
  when(() => factory.sftpFor(any())).thenThrow(StateError('host down'));
  final profile = const SshProfile(
    id: 'p1',
    name: 'Remote',
    host: 'example.com',
    username: 'u',
  );
  final resolver = RuntimeContextResolver(
    sshClientFactory: factory,
    nativeAppDataPath: tmp.path,
    remotePathResolver: _FakePathResolver(
      clientFactory: factory,
      onResolve: (_) => Future.error(StateError('resolve failed')),
    ),
  );
  await expectLater(
    () => resolver.resolve(
      RuntimeTarget.ssh('p1'),
      sshProfile: profile,
    ),
    throwsA(isA<StateError>()),
  );
});
```

Update existing termux soft-fail test to expect `pathsFromCache` (rename).

- [ ] **Step 2: Run tests to verify fail**

Run: `cd client && flutter test test/services/storage/runtime_context_resolver_test.dart`

Expected: FAIL on new SSH soft-fail / rename

- [ ] **Step 3: Implement resolver + registry soft-fail**

1. Rename `RuntimeContext.termuxPathsFromCache` → `pathsFromCache` (update comment for SSH + Termux).
2. In `_resolveSsh` catch: soft-fail whenever `_hasPathCache(cachedHome, cachedAppDataRoot)` — **remove the `target.kind == RuntimeKind.termux` guard** so SSH uses the same path. Rename `_resolveTermuxFromCache` → `_resolveSshFromCache` (set `pathsFromCache: true`).
3. Registry: when resolving a target with `sshProfile`, pass:

```dart
cachedHome: termuxCache?.home ?? sshProfile?.lastHome,
cachedAppDataRoot: termuxCache?.appDataRoot ?? sshProfile?.lastAppDataRoot,
```

(Termux still wins via explicit termux cache callback when kind is termux.)

4. Fix all rename call sites in `app_shell` / Termux cubit.

- [ ] **Step 4: Preload home SSH profile before `ensureHome` (critical)**

In `app_shell.dart`, **before** `runtimeContextRegistry.ensureHome()` (mirror Termux `termuxConfigStore.load()` ~L522):

```dart
// Seed cubit/repo lookup so sshProfileById can return lastHome on cold start.
if (homeTarget.kind == RuntimeKind.ssh) {
  final pid = homeTarget.sshProfileId;
  if (pid != null && pid.isNotEmpty) {
    await sshProfileCubit.load(); // or repo.findById + local cache for sshProfileById
  }
}
```

**Ordering constraint:** today `sshProfileCubit` is constructed **before** `ensureHome`, but `load()` only runs later in `bootstrapHomeIndex`. Move an early `await sshProfileCubit.load()` (or a narrow `loadHomeProfile(pid)` from `sshProfileRepo`) to **before** `ensureHome` when home kind is `ssh`. Without this, `sshProfileById` returns null / profile without being loaded → soft-fail never sees `lastHome` → cold start still hard-fails (spec success criterion 1 broken).

If full `load()` is too heavy before home install, minimum viable:

```dart
SshProfile? homeSshProfileCache;
if (homeTarget.kind == RuntimeKind.ssh) {
  final pid = homeTarget.sshProfileId;
  if (pid != null) {
    homeSshProfileCache = await sshProfileRepo.findById(pid);
  }
}
// sshProfileById: return homeSshProfileCache if id matches, else cubit state
```

Add a **required** registry or shell-ordering test: persisted profile with `lastHome`, failing SFTP → `ensureHome` / `forTarget` succeeds with `pathsFromCache == true` when `sshProfileById` returns that profile (locks preload wiring).

- [ ] **Step 5: Run tests**

Run: `cd client && flutter test test/services/storage/runtime_context_resolver_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/storage/runtime_context.dart \
  client/lib/services/storage/runtime_context_resolver.dart \
  client/lib/services/storage/runtime_context_registry.dart \
  client/lib/app/app_shell.dart \
  client/test/services/storage/runtime_context_resolver_test.dart
# plus any other rename touch points / preload tests
git commit -m "feat(storage): soft-fail SSH home resolve with path cache"
```

---

### Task 3: Persist path cache after live resolve + cubit API

**Files:**
- Modify: `client/lib/cubits/ssh_profile_cubit.dart`
- Modify: `client/test/cubits/ssh_profile_cubit_test.dart`
- Modify: `client/lib/app/app_shell.dart` (after `ensureHome` / successful SSH home rebind)

- [ ] **Step 1: Write the failing cubit test**

```dart
test('updatePathCache saves without invalidateProfileConnection', () async {
  // arrange repo + cubit with invalidate spy
  await cubit.load();
  await cubit.updatePathCache(
    profileId,
    home: '/home/u',
    appDataRoot: '/home/u/.teampilot',
  );
  expect(invalidateCalls, isEmpty);
  final saved = await repo.loadAll();
  expect(saved.single.lastHome, '/home/u');
  expect(cubit.state.profiles.single.lastHome, '/home/u');
});
```

- [ ] **Step 2: Run — FAIL**

Run: `cd client && flutter test test/cubits/ssh_profile_cubit_test.dart --name updatePathCache`

- [ ] **Step 3: Implement `updatePathCache`**

```dart
Future<void> updatePathCache(
  String profileId, {
  required String home,
  required String appDataRoot,
}) async {
  final existing = state.profiles.where((p) => p.id == profileId).firstOrNull;
  if (existing == null) return;
  final next = existing.copyWith(
    lastHome: home,
    lastAppDataRoot: appDataRoot,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  // Do NOT call _invalidateProfileConnection
  await _profileRepository.save(next);
  emit(state.copyWith(
    profiles: [
      for (final p in state.profiles) p.id == profileId ? next : p,
    ],
  ));
}
```

Ensure `copyWith` can set nullable cache fields (use sentinel or explicit nullable params if clearing is needed — v1 only writes non-empty).

- [ ] **Step 4: Wire persistence in `app_shell` (locked write sites)**

**Primary write site:** after `sshProfileCubit.load()` when home is SSH and live context (`!AppStorage.context.pathsFromCache` / registry home):

```dart
Future<void> persistSshHomePathCacheIfLive() async {
  final home = defaultTargetResolver();
  if (home.kind != RuntimeKind.ssh) return;
  final pid = home.sshProfileId;
  if (pid == null || pid.isEmpty) return;
  final ctx = runtimeContextRegistry.home();
  if (ctx.pathsFromCache) return;
  await sshProfileCubit.updatePathCache(
    pid,
    home: ctx.home,
    appDataRoot: ctx.appDataRoot,
  );
}
```

Call from `bootstrapHomeIndex` SSH branch after profiles load + any reinstall, and after successful `reinstallStorageContext` / `setHomeTarget` when the new home is SSH and live.

Do **not** write from the early pre-`ensureHome` path when soft-fail already set `pathsFromCache`.

- [ ] **Step 5: Tests PASS + commit**

```bash
git add client/lib/cubits/ssh_profile_cubit.dart \
  client/test/cubits/ssh_profile_cubit_test.dart \
  client/lib/app/app_shell.dart
git commit -m "feat(ssh): write path cache after live SSH home resolve"
```

---

### Task 4: `SshHomeDisconnectedBanner` + shell mount + cold-start reconnect

**Files:**
- Create: `client/lib/widgets/ssh/ssh_home_disconnected_banner.dart`
- Create: `client/test/widgets/ssh/ssh_home_disconnected_banner_test.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/app/app_shell.dart` (one reconnect after provide when home is ssh)

- [ ] **Step 1: Add l10n keys**

`app_en.arb`:

```json
"sshHomeDisconnectedBannerMessage": "Remote SSH work home is disconnected. Shell, Git, and agent sessions are paused until you reconnect.",
"sshHomeDisconnectedReconnect": "Reconnect",
"bootstrapRetry": "Retry",
"bootstrapChooseWorkEnvironment": "Choose work environment"
```

`app_zh.arb`:

```json
"sshHomeDisconnectedBannerMessage": "远程 SSH 工作环境已断开。请重新连接后再使用 Shell、Git 和 Agent 会话。",
"sshHomeDisconnectedReconnect": "重新连接",
"bootstrapRetry": "重试",
"bootstrapChooseWorkEnvironment": "选择工作环境"
```

(Bootstrap strings used in Task 5; add now to avoid a second ARB pass.)

Run codegen if the project requires it (`flutter gen-l10n` via normal build — follow repo convention; if generated files are committed, update `app_localizations*.dart` accordingly).

- [ ] **Step 2: Failing widget test**

Mirror `termux_disconnected_banner` tests if any; else:

```dart
testWidgets('shows when SSH home and host not connected', (tester) async {
  // Provide ConnectionModeService isSshMode=true,
  // HomeTargetController current ssh:p1,
  // SshConnectionCubit state with p1 disconnected
  await tester.pumpWidget(/* … */);
  expect(find.textContaining('disconnected'), findsOneWidget);
});

testWidgets('Reconnect calls SshConnectionCubit.connect', (tester) async {
  // tap Reconnect → verify connect('p1') called
});

testWidgets('hidden when connected', (tester) async { … });
testWidgets('hidden when not SSH home', (tester) async { … });
```

- [ ] **Step 3: Implement banner**

Peer of `TermuxDisconnectedBanner`:

- Watch `ConnectionModeService.isSshMode`
- Resolve home profile id from `HomeTargetController.current.sshProfileId`
- Watch `SshConnectionCubit` host status for that id
- Hide when connected; show connecting state on button when `connecting` / `reconnecting`
- Reconnect → `context.read<SshConnectionCubit>().connect(profileId)`

- [ ] **Step 4: Mount in `home_workspace_shell.dart`**

Next to `TermuxDisconnectedBanner()`:

```dart
const TermuxDisconnectedBanner(),
const SshHomeDisconnectedBanner(),
```

- [ ] **Step 5: Cold-start reconnect (locked placement)**

`SshConnectionCubit.connect` returns early if `_profilesById` is empty. `SshConnectionBinder.syncProfiles` runs only after the shell mounts (post-frame). **Do not** call `connect` from `bootstrapHomeIndex` (that runs before `setState(_shell)` → binder has not synced yet → silent no-op).

**Locked approach:** in `bootstrapAppData`, immediately after the SSH `bootstrapHomeIndex` / profile-load path completes, call:

```dart
Future<void> reconnectHomeSshIfNeeded() async {
  final home = defaultTargetResolver();
  final pid = home.sshProfileId;
  if (home.kind != RuntimeKind.ssh || pid == null || pid.isEmpty) return;
  await sshConnectionCubit.syncProfiles(sshProfileCubit.state.profiles);
  unawaited(sshConnectionCubit.connect(pid));
}
```

Failure leaves banner visible; do not unbind home. Do not rely on binder post-frame alone.
- [ ] **Step 6: Tests + commit**

```bash
git add client/lib/widgets/ssh/ssh_home_disconnected_banner.dart \
  client/test/widgets/ssh/ssh_home_disconnected_banner_test.dart \
  client/lib/pages/home_workspace/home_workspace_shell.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/app/app_shell.dart
git commit -m "feat(android): SSH home disconnected banner and cold reconnect"
```

---

### Task 5: Bootstrap safety net (Retry + Choose work environment)

**Files:**
- Modify: `client/lib/app/app_shell.dart` (`TeamPilotBootstrap` error UI)
- Prefer extract: `client/lib/pages/system/bootstrap_startup_error_page.dart` (keeps `app_shell` smaller)
- Create: `client/test/pages/system/bootstrap_startup_error_page_test.dart` (or test extracted actions)

- [ ] **Step 1: Failing widget test**

```dart
testWidgets('Android error page shows Retry and Choose work environment', (
  tester,
) async {
  var retried = false;
  var choseEnv = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BootstrapStartupErrorPage(
        error: StateError('ssh down'),
        showChooseWorkEnvironment: true,
        showNativeStorageFallback: false,
        retrying: false,
        onRetry: () => retried = true,
        onChooseWorkEnvironment: () => choseEnv = true,
      ),
    ),
  );
  await tester.tap(find.text('Retry')); // or zh locale — use keys if added
  expect(retried, isTrue);
  await tester.tap(find.text('Choose work environment'));
  expect(choseEnv, isTrue);
});
```

Prefer `Key`s: `AppKeys.bootstrapRetryButton`, `AppKeys.bootstrapChooseWorkEnvironmentButton` if the project has `AppKeys`.

- [ ] **Step 2: Implement page + wire bootstrap**

`TeamPilotBootstrap`:

```dart
Future<void> _retryBootstrap() async {
  if (_retrying) return;
  setState(() => _retrying = true);
  await _start();
}

Future<void> _chooseWorkEnvironmentAndRetry() async {
  if (_retrying) return;
  setState(() => _retrying = true);
  await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
  await _start();
}
```

Error UI:

- Always: error text
- Always (or Android): **Retry** → `_retryBootstrap`
- When `Platform.isAndroid`: **Choose work environment** → `_chooseWorkEnvironmentAndRetry`
- When `_canFallbackToNativeStorage`: existing WSL button

Do not auto-clear home except via Choose work environment.

- [ ] **Step 3: Tests PASS + commit**

```bash
git add client/lib/pages/system/bootstrap_startup_error_page.dart \
  client/test/pages/system/bootstrap_startup_error_page_test.dart \
  client/lib/app/app_shell.dart
git commit -m "fix(android): bootstrap escape hatch when SSH home cannot soft-fail"
```

---

### Task 6: Verification + regression lock

**Files:** none new required beyond fixes from failures

- [ ] **Step 1: Run focused suites**

```bash
cd client && flutter test \
  test/models/ssh_profile_test.dart \
  test/services/storage/runtime_context_resolver_test.dart \
  test/cubits/ssh_profile_cubit_test.dart \
  test/widgets/ssh/ssh_home_disconnected_banner_test.dart \
  test/pages/system/bootstrap_startup_error_page_test.dart \
  test/pages/startup_gate_test.dart \
  test/widgets/termux/ \
  test/services/termux/
```

Expected: PASS

If Task 2 added an `ensureHome`+preload ordering test, include that file in the list.

- [ ] **Step 2: Analyze touched code**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/models/ssh_profile.dart \
  lib/services/storage/runtime_context.dart \
  lib/services/storage/runtime_context_resolver.dart \
  lib/services/storage/runtime_context_registry.dart \
  lib/cubits/ssh_profile_cubit.dart \
  lib/widgets/ssh/ssh_home_disconnected_banner.dart \
  lib/pages/system/bootstrap_startup_error_page.dart \
  lib/app/app_shell.dart \
  lib/pages/home_workspace/home_workspace_shell.dart
```

Expected: no new errors

- [ ] **Step 3: Manual checklist (device)**

1. Connect SSH once (cache written) → kill host / airplane mode → force-stop app → relaunch → main shell + banner, not dead error page  
2. Banner Reconnect restores when host is back  
3. Work-environment selector switches to Termux while SSH down  
4. Clear profile path cache / wipe app data mid-bind scenario: no-cache hard fail → Choose work environment → chooser  

- [ ] **Step 4: Final commit only if cleanup remained**

```bash
git status
# commit any leftover test fixes
```

---

## Done when

1. Soft-fail with cache enters shell; banner reconnect works  
2. No-cache hard fail offers Choose work environment  
3. Termux soft-fail / banner / StartupGate regressions green  
4. Spec success criteria 1–5 satisfied
