# SSH Status Bar Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Orca-style Remote Hosts status-bar pill with durable Connect/Disconnect, backed by one global `SshConnectionCubit` shared with the SSH config page.

**Architecture:** Thin user-connect/disconnect API on `SshProfileConnectionCoordinator` (latch + cancel reconnect) over existing `SshClientFactory` storage pool; `SshConnectionCubit` observes pool + monitors and owns UI status; `SshHostsStatusItem` is a new `WorkspaceStatusBarItem` (rightmost).

**Tech Stack:** Flutter, flutter_bloc, existing SSH factory/coordinator, `TpPopover` / `TpActionMenuAnchor`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-24-ssh-status-bar-indicator-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/ssh/ssh_client_factory.dart` | Add `hasLiveStorageClient` + `storagePoolChanges` stream for observation |
| `client/lib/services/ssh/ssh_profile_connection_coordinator.dart` | Add `userConnect` / `userDisconnect` + reconnect latch |
| `client/lib/cubits/ssh_connection_cubit.dart` | UI truth: host VMs, aggregates, connect/disconnect |
| `client/lib/pages/ssh_profiles/ssh_profile_connection_status.dart` | Expand UI status enum (or replace with shared type used by Cubit) |
| `client/lib/widgets/workspace_status_bar/ssh_hosts_status_item.dart` | Closed pill + popover |
| `client/lib/widgets/workspace_status_bar/ssh_hosts_panel.dart` | Host list + Manage footer |
| `client/lib/pages/home_workspace/global_resource_manager_host.dart` | Register `SshHostsStatusItem` rightmost |
| `client/lib/app/app_shell.dart` + `client/lib/main.dart` | Construct + provide `SshConnectionCubit` |
| `client/lib/pages/ssh_profiles/ssh_profiles_section.dart` | Drop ephemeral status map; use Cubit |
| `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart` | Richer status labels (reconnecting / auth-failed) |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Pill / panel strings |
| Tests | Coordinator latch, Cubit aggregates/observation, widget pill/panel, config sync |

---

### Task 1: Factory pool observation API

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart`
- Modify: `client/test/services/ssh/ssh_client_factory_pool_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('hasLiveStorageClient is false until clientForStorage succeeds', () async {
  // ...
  expect(factory.hasLiveStorageClient(profile.id), isFalse);
  await factory.clientForStorage(profile);
  expect(factory.hasLiveStorageClient(profile.id), isTrue);
});

test('storagePoolChanges emits on open and disconnectProfile', () async {
  final events = <String>[];
  final sub = factory.storagePoolChanges.listen(events.add);
  await factory.clientForStorage(profile);
  factory.disconnectProfile(profile.id);
  await Future<void>.delayed(Duration.zero);
  expect(events, [profile.id, profile.id]); // open then close
  await sub.cancel();
});
```

- [ ] **Step 2: Run tests — expect FAIL** (API missing)

Run: `cd client && flutter test test/services/ssh/ssh_client_factory_pool_test.dart`

- [ ] **Step 3: Implement**

Add to `SshClientFactory`:

```dart
bool hasLiveStorageClient(String profileId) {
  final cached = _pool[profileId];
  // Only "live" after authenticated ready — not merely map presence.
  return cached != null && !cached.client.isClosed && cached.readyCompleted;
}

final _poolChanges = StreamController<String>.broadcast();
Stream<String> get storagePoolChanges => _poolChanges.stream;

void _notifyPoolChange(String profileId) {
  if (!_poolChanges.isClosed) _poolChanges.add(profileId);
}
```

**Auth gating (required):** Today `clientForStorage` inserts into `_pool` before
`await ready`. Implement so observation stays truthful:

1. Track `readyCompleted` (or equivalent) on `_PooledConnection`; set only after
   `await ready` succeeds.
2. On auth / connect failure after insert: `_evictProfile` (no half-open entry),
   then notify close if an open was already signaled — or **only**
   `_notifyPoolChange` after successful `await ready` (preferred: notify open
   only post-auth).
3. Notify close from `_evictProfile` / `disconnectProfile` when a previously
   live client is removed.

Do **not** treat “key in `_pool`” alone as connected.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ssh/ssh_client_factory.dart \
  client/test/services/ssh/ssh_client_factory_pool_test.dart
git commit -m "feat(ssh): expose storage pool presence for status observation"
```

---

### Task 2: Coordinator userConnect / userDisconnect + latch

**Files:**
- Modify: `client/lib/services/ssh/ssh_profile_connection_coordinator.dart`
- Modify: `client/test/services/ssh/ssh_profile_connection_coordinator_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('userDisconnect sets latch and skips auto-reconnect after transport close', () async {
  // policy with maxAttempts > 0; userDisconnect; simulate transport close
  // expect no reconnectStorage / monitor stays down / latch held
});

test('userConnect clears latch and opens storage pool', () async {
  await coordinator.userConnect(profile);
  expect(factory.hasLiveStorageClient(profile.id), isTrue);
});

test('external clientForStorage after userDisconnect clears latch via pool observation', () async {
  await coordinator.userConnect(profile);
  await coordinator.userDisconnect(profile.id);
  expect(coordinator.isUserDisconnectLatched(profile.id), isTrue);
  await factory.clientForStorage(profile); // external reopen
  await Future<void>.delayed(Duration.zero);
  expect(coordinator.isUserDisconnectLatched(profile.id), isFalse);
});
```

Lock placement per spec advisory: **latch lives on coordinator**.

API:

```dart
Future<void> userConnect(SshProfile profile, {Duration timeout = ...});
Future<void> userDisconnect(String profileId);
bool isUserDisconnectLatched(String profileId);
```

`userConnect`: clear latch → `factory.clientForStorage` → ensure `monitorFor` exists (do not treat monitor.initial alone as connected).

`userDisconnect`: set latch → cancel coalesce/reconnect timers for id → `factory.disconnectProfile(id)`.

`_scheduleReconnect`: if latched, return early.

**Latch clear:** coordinator **subscribes to `factory.storagePoolChanges`** and
clears the latch when `hasLiveStorageClient(id)` becomes true (external or user
open). No Cubit-owned latch API.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement API + latch in `_scheduleReconnect`**

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(ssh): add user connect/disconnect with reconnect latch"
```

---

### Task 3: Status enum + `SshConnectionCubit`

**Files:**
- Create: `client/lib/cubits/ssh_connection_cubit.dart`
- Create: `client/test/cubits/ssh_connection_cubit_test.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_connection_status.dart` (expand or re-export Cubit status)

- [ ] **Step 1: Define status + VM**

```dart
enum SshHostUiStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
  authFailed,
}

class SshHostConnectionVm {
  const SshHostConnectionVm({
    required this.profileId,
    required this.label,
    required this.host,
    required this.status,
    this.errorDetail,
  });
  final String profileId;
  final String label;
  final String host;
  final SshHostUiStatus status;
  final String? errorDetail;
}

enum SshHostsOverallStatus { connected, partial, connecting, disconnected }

class SshConnectionState {
  const SshConnectionState({
    this.hostsById = const {},
    this.profileOrder = const [],
  });
  final Map<String, SshHostConnectionVm> hostsById;
  final List<String> profileOrder; // stable order from SshProfileCubit

  bool get isEmpty => profileOrder.isEmpty;
  int get connectedCount => hostsById.values
      .where((h) => h.status == SshHostUiStatus.connected)
      .length;
  SshHostsOverallStatus get overallStatus { /* Orca priority */ }
  List<SshHostConnectionVm> get connectedHosts => ...;
  List<SshHostConnectionVm> get inactiveHosts => ...; // sort by label
}
```

Map auth failures via `sshConnectionFailureCause` → `SSHAuthFailError` / `SSHHostkeyError` → `authFailed`.

- [ ] **Step 2: Failing Cubit tests** (fake factory + coordinator)

Cover:
1. Empty profiles → `isEmpty`
2. Seed: pool already live → `connected`
3. `connect` → connecting then connected; Android path: inject `onAndroidSelectProfile` callback invoked only when `selectOnConnect: true` (pass from wiring with `Platform.isAndroid`)
4. `disconnect` → disconnected + coordinator.userDisconnect called
5. Overall: connecting beats partial; `reconnecting` host also yields overall `connecting`
6. Observation: emit pool change after disconnect → connected again
7. Monitor reconnecting → UI reconnecting
8. Profile deleted → pruned; last deleted → empty
9. Connect failure → error / authFailed; optional one soft snackbar signal (callback/stream) — not toast spam

- [ ] **Step 3: Implement Cubit**

Dependencies:
- `SshClientFactory`
- `SshProfileConnectionCoordinator`
- `Stream<List<SshProfile>>` or sync from `SshProfileCubit` via `syncProfiles(List<SshProfile>)` called by a thin binder / Cubit listening pattern

Preferred wiring: Cubit constructor takes factory + coordinator + optional `Future<void> Function(String id)? selectProfileOnConnect`. Parent listens to `SshProfileCubit` and calls `sshConnectionCubit.syncProfiles(state.profiles)`.

Subscriptions in Cubit:
- `factory.storagePoolChanges`
- per-profile `coordinator.changesFor(id)` (subscribe/unsubscribe as profile set changes)

`connect` / `disconnect` call coordinator `userConnect` / `userDisconnect`.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(ssh): add SshConnectionCubit as global connection UI truth"
```

---

### Task 4: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Run codegen if project uses `flutter gen-l10n` (usually on build)

Add keys (names illustrative — match existing `sshProfile*` style):

| Key | EN | ZH |
|-----|----|----|
| `sshHostsPillCount` | `{count} {count, plural, =1{host} other{hosts}}` or two keys | `{count} 台主机` |
| `sshHostsPillConnecting` | `Connecting…` | `连接中…` |
| `sshHostsPanelTitle` | `Remote Hosts` | `远程主机` |
| `sshHostsRowKind` | `SSH Host` | `SSH 主机` |
| `sshHostsManage` | `Manage Remote Hosts…` | `管理远程主机` |
| `sshProfileStatusReconnecting` | `Reconnecting…` | `重连中…` |
| `sshProfileStatusAuthFailed` | `Authentication failed` | `认证失败` |

Reuse existing Connect / Disconnect / status Connected / Disconnected / Connecting / Error where possible.

- [ ] **Step 1: Add ARB entries both locales**
- [ ] **Step 2: Ensure `AppLocalizations` regenerates** (`flutter gen-l10n` or next analyze)
- [ ] **Step 3: Run `dart run tool/gen_warmup_glyphs.dart`** (repo convention after ARB edits)
- [ ] **Step 4: Commit**

```bash
git commit -m "l10n: add SSH status bar remote hosts strings"
```

---

### Task 5: Status bar UI (pill + panel)

**Files:**
- Create: `client/lib/widgets/workspace_status_bar/ssh_hosts_status_item.dart`
- Create: `client/lib/widgets/workspace_status_bar/ssh_hosts_panel.dart`
- Create: `client/test/widgets/workspace_status_bar/ssh_hosts_status_item_test.dart`
- Modify: `client/lib/pages/home_workspace/global_resource_manager_host.dart`

- [ ] **Step 1: Failing widget tests** (pump with mock Cubit)

1. `isEmpty` → no pill (`findsNothing` for key `ssh-hosts-pill`)
2. With hosts → shows connected count label
3. Tap Connect on inactive row → Cubit.connect called
4. Tap Manage → `go` / callback to `/config/ssh-profiles` (inject `VoidCallback onManage` for testability)

- [ ] **Step 2: Implement panel** (~Orca layout)

`SshHostsPanel`: header, connected rows, inactive rows (name sort), divider, Manage item.

Row: status dot, title, subtitle `SSH Host · {status}`, Connect/Disconnect text button.

- [ ] **Step 3: Implement `SshHostsStatusItem`**

Mirror `ResourceUsageStatusItem`:
- `TpActionMenuAnchor` upward, 8px gap, panel width ~320 (`min(20rem,…)`)
- Pill: icon + label + overall dot; compact → icon+dot
  - `overallStatus == connecting` → small spinner (spec)
  - all disconnected → server-off icon; else server
- `buildWhen` on `connectedCount`, `overallStatus`, `isEmpty`, `isOpen` if tracked

Hide segment when `state.isEmpty` (return `SizedBox.shrink()`).

Do **not** register on `GlobalResourceManagerHost` in this task — Cubit is not
provided until Task 6. Widget tests supply a local `BlocProvider`.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(ui): add SSH hosts status bar pill and panel"
```

---

### Task 6: App wiring (`SshConnectionCubit` + status-bar registration)

**Files:**
- Modify: `client/lib/app/app_shell.dart` (construct Cubit near SSH stack)
- Modify: `client/lib/main.dart` (provide Cubit in `MultiBlocProvider`)
- Modify: `client/lib/pages/home_workspace/global_resource_manager_host.dart`
- Possibly small binder widget under shell that syncs profiles

- [ ] **Step 1: Construct + provide Cubit first**

```dart
sshConnectionCubit = SshConnectionCubit(
  factory: sshClientFactory,
  coordinator: sshProfileConnectionCoordinator,
  selectProfileOnConnect: Platform.isAndroid
      ? (id) => sshProfileCubit.selectProfile(id)
      : null,
);
// MultiBlocProvider must include SshConnectionCubit before status bar mounts
```

- [ ] **Step 2: Sync profiles**

Either:
- `BlocListener<SshProfileCubit>` in a tiny `SshConnectionBinder` wrapping MaterialApp child, or
- subscribe inside Cubit if given `SshProfileCubit` reference

Call `syncProfiles` on every profile list change; on delete of connected profile, Cubit disconnects then prunes.

- [ ] **Step 3: Register status-bar item (only after Cubit is provided)**

```dart
WorkspaceStatusBar(
  items: [
    ResourceUsageStatusItem(),
    SshHostsStatusItem(
      onManage: () => GoRouter.of(context).go('/config/ssh-profiles'),
    ),
  ],
)
```

Path confirmed: `/config/ssh-profiles` in `app_router.dart`.

- [ ] **Step 4: Dispose Cubit with shell**

- [ ] **Step 5: Smoke `flutter analyze` on touched files**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(app): provide SshConnectionCubit and register SSH status item"
```

---

### Task 7: Config page uses shared Cubit

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profiles_section.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart`
- Create/Modify: `client/test/pages/ssh_profiles/ssh_profiles_section_test.dart` (or extend existing)

- [ ] **Step 1: Failing test**

Config Connect calls `SshConnectionCubit.connect`; Test does not set Cubit to connected; status on card comes from Cubit.

- [ ] **Step 2: Remove `_statusById` Connect/Disconnect path**

Keep `_runTest` / testing busy flags local. Map Cubit status → card (extend card for `reconnecting` / `authFailed`).

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ssh): drive config Connect/Disconnect from SshConnectionCubit"
```

---

### Task 8: Verification + docs touch

**Files:**
- Optionally note in `docs/superpowers/specs/2026-07-23-workspace-status-bar-resource-manager-design.md` that SSH segment non-goal is superseded (one-line pointer)

- [ ] **Step 1: Run focused tests**

```bash
cd client && flutter test \
  test/services/ssh/ssh_client_factory_pool_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_test.dart \
  test/cubits/ssh_connection_cubit_test.dart \
  test/widgets/workspace_status_bar/ssh_hosts_status_item_test.dart
```

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Manual checklist** (for human)

1. Add SSH profile → pill appears with `0 hosts`
2. Connect from pill → count `1 host`, green dot
3. Disconnect → `0 hosts`; Android storage I/O may reconnect (pill truthful)
4. Manage → `/config/ssh-profiles`
5. Config Connect/Disconnect matches pill
6. Test button does not leave durable connected without Connect

- [ ] **Step 4: Final commit if docs pointer added**

```bash
git commit -m "docs: point status-bar resource manager spec at SSH hosts segment"
```

---

## Execution notes

- Follow TDD per task; do not skip red→green.
- Do not auto-connect all hosts on startup.
- Do not add Remote Orca Server rows or appearance toggles.
- Prefer coordinator latch over Cubit-owned latch.
- Keep Resource Manager item left of SSH hosts (SSH rightmost).
