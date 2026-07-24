# SSH status bar indicator

## Goal

Add an Orca-style **Remote Hosts** segment to the workspace bottom status bar:
closed pill (`N hosts` + overall status dot), popover host list with per-host
Connect / Disconnect, and a footer jump to SSH profile management.

One global connection truth source feeds both the status bar and the SSH
profiles config page.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Parity | Align Orca `SshStatusSegment` UX (pill + host rows + Connect/Disconnect + Manage) |
| Connection semantics | Durable keep-alive of the **storage-pool** SSH client per profile |
| Connect transport | `SshClientFactory.clientForStorage(profile)` (+ coordinator monitor tracking) |
| Disconnect transport | Cancel coordinator reconnect for that id + `SshClientFactory.disconnectProfile(id)` |
| Pill count | **Connected** host count only (Orca: `"N hosts"` / `"1 host"`) |
| Overall aggregate | Orca priority: all-connected → any-connecting → any-connected(partial) → disconnected |
| Empty state | Hide the entire pill when there are zero SSH profiles |
| Architecture | New `SshConnectionCubit` as UI truth over factory + `SshProfileConnectionCoordinator` |
| Config page | Connect / Disconnect share the same Cubit (remove ephemeral per-card status maps) |
| Test button | Remains a separate one-shot probe (`SshProfileConnectionTester`); never updates durable status as connected |
| Placement | New `SshHostsStatusItem` on `WorkspaceStatusBar`, rightmost (Orca hosts-at-edge) |
| Manage link | Navigate to `/config/ssh-profiles` and close the popover |
| Startup | Do not auto-connect all hosts; seed Cubit from profiles already present in the storage pool |
| Profile edit while connected | Keep existing connection; next Connect uses new config |
| Android + Connect | Same durable pool Connect as desktop; **also** `SshProfileCubit.selectProfile(id)` so the active storage backend follows |
| Android + Disconnect | Tear down pool only; **do not** clear / change `selectedProfile` |
| User-disconnect latch | Suppresses **coordinator auto-reconnect** only; does not quarantine `clientForStorage` |
| Status observation | Cubit always tracks live pool presence + coordinator/monitor streams (truthful) |
| Desktop + Connect | Pool only; does **not** change selected / active storage backend |
| Platform | Same status-bar UI on desktop and Android; still hide when no profiles |

## Non-goals (v1)

- Orca Remote Orca Server / runtime-host rows
- Status-bar appearance toggle (`statusBarItems`)
- Add-host form inside the popover (use Manage)
- Force-kill sessions on Disconnect (reuse existing coordinator session-plane signals)
- Auto-connect-all on app launch
- Destructive overall-dot color on the closed pill (errors live in the open panel)

## Product UX

### Closed pill (`ssh-hosts`)

- Right cluster of the workspace status bar; **rightmost** relative to Resource
  Manager (Orca hosts-at-edge).
- Hidden when `SshProfileCubit` has no profiles.
- Content: host icon + label + overall status dot.
  - Label: **connected count** as `N hosts` / `1 host` (l10n). While
    `overallStatus == connecting`, show connecting copy instead (Orca
    `Connecting…`).
  - Icon: `overallStatus == connecting` → spinner; all disconnected →
    server-off; else server.
  - Overall status (Orca `overallStatus` order — first match wins):
    1. every host connected → `connected`
    2. any host connecting **or** reconnecting → `connecting`
    3. any host connected → `partial`
    4. else → `disconnected`
  - Overall dot (no destructive on closed pill):
    - emerald — `connected` or `partial`
    - yellow — `connecting`
    - muted — `disconnected`
- Compact mode (`WorkspaceStatusBar` &lt; 720): icon + dot only (same pattern as
  Resource Manager).

### Open panel

Popover anchored above the pill via existing status-bar popover pattern
(`TpPopover` / Resource Manager style):

1. **Header:** “Remote Hosts” (l10n → 远程主机).
2. **Host rows:** `connected` first; everything else (including
   `connecting` / `reconnecting` / `error` / `auth-failed` / `disconnected`)
   below — Orca “inactive” bucket.
   - Left: per-host status dot.
   - Middle: primary label (profile name, fallback host) + subtitle
     `SSH Host · {status}` (l10n); include short error detail when
     `error` / `auth-failed`.
   - Right: **Connect** when reconnectable (`disconnected`, `error`,
     `auth-failed`); **Disconnect** when `connected`; no action while
     `connecting` / `reconnecting`.
3. **Footer:** separator + “Manage Remote Hosts…” → `/config/ssh-profiles`.

### Status vocabulary

UI statuses:

`disconnected | connecting | connected | reconnecting | error | auth-failed`

#### Mapping

| Source | UI status |
|--------|-----------|
| Never opened / pool absent / after Disconnect | `disconnected` |
| User Connect in flight | `connecting` |
| Pool client authenticated + healthy | `connected` |
| `RemoteConnectionMonitor` `reconnecting` | `reconnecting` |
| `RemoteConnectionMonitor` `degraded` | still `connected` (pill stays green; detail optional later) |
| `RemoteConnectionMonitor` `down` (pool gone / given up) | `disconnected` |
| Coordinator has scheduled or in-flight reconnect | `reconnecting` (wins over bare `down`) |
| Auth / host-key failures on Connect | `auth-failed` |
| Other Connect / transport failures | `error` |

**Important:** `RemoteConnectionMonitor.initial` is `connected`, but that must
**not** imply a host was opened. Cubit treats a profile as connected only when
the storage pool holds a live client for that id (or Connect just succeeded),
not merely because a monitor exists with default state.

## Architecture

```
GlobalResourceManagerHost / status-bar host
 └─ WorkspaceStatusBar(
      items: [ResourceUsageStatusItem, SshHostsStatusItem],
    )

SshProfileCubit          // profile CRUD / list / selectedProfile
SshConnectionCubit       // Map<profileId, SshHostConnectionVm> + aggregates
  ├─ SshClientFactory              // clientForStorage / disconnectProfile
  └─ SshProfileConnectionCoordinator  // coalesce, reconnect, monitors
       └─ RemoteConnectionMonitor per profile
```

### Connect / Disconnect (transport contract)

`SshConnectionCubit.connect(profileId)`:

1. Resolve profile; set UI `connecting`.
2. `await factory.clientForStorage(profile)` — opens or reuses the pooled
   storage client (durable keep-alive).
3. Ensure coordinator `monitorFor(profileId)` is tracking this pool client
   (extend coordinator with an explicit user-connect hook if needed; today it
   only reconnects after drops).
4. On success → UI `connected`. On Android only → also
   `SshProfileCubit.selectProfile(profileId)`.
5. On failure → UI `auth-failed` or `error` + short reason; do not leave a
   half-open pool entry.

`SshConnectionCubit.disconnect(profileId)`:

1. Set **user-disconnect latch** for `profileId` (blocks coordinator
   auto-reconnect until the next successful user Connect or external pool open).
2. Cancel in-flight / scheduled reconnect for that id on the coordinator.
3. `factory.disconnectProfile(profileId)` — closes pooled client + SFTP.
4. UI → `disconnected`.
5. Do **not** clear `selectedProfile` (Android or desktop).

**Reopen rule (Android especially):** Disconnect closes the current pool client;
it does **not** quarantine the profile. If Android (or any caller) later opens
storage via `clientForStorage` / `sftpFor` while that profile remains selected,
the pool becomes live again. Cubit **must observe** that and flip back to
`connected` (and clear the latch). Disconnect is “close now + stop auto-reconnect”,
not “forbid all future I/O”.

Coordinator today has `reconnectStorage` / monitors but **no** user-facing
connect API — planning must add a thin user-connect / user-disconnect surface
(or put those steps in the Cubit calling factory + coordinator cancel APIs).
Do not invent a second connection channel beside the storage pool.

### `SshConnectionCubit`

- Subscribes to profile list; drops VMs for deleted ids; hides pill when empty.
- On start: for each profile, if factory pool already has a live client → seed
  `connected`; else `disconnected`.
- **Live observation (required):** subscribe to coordinator /
  `RemoteConnectionMonitor.changes` and/or factory pool presence so
  drop → `disconnected` / `reconnecting`, successful auto-reconnect or external
  `clientForStorage` → `connected`, without requiring another UI Connect.
- `connect` / `disconnect` are the only **user** entry points for intentional
  durable connect/disconnect (status bar + config cards). Other code may still
  open the pool; Cubit stays truthful via observation.
- Exposes aggregates: `connectedCount`, `overallStatus`, `isEmpty`.
- Rebuild performance: closed pill `buildWhen` on aggregates only; open panel
  rebuilds host rows.

### Config page sync

- `ssh_profiles_section` removes `_statusById` for Connect / Disconnect.
- Cards read status from `SshConnectionCubit` and call the same methods.
- **Test** stays on `SshProfileConnectionTester` and must not mark the durable
  Cubit status `connected`.
- Desktop config Connect stops being a one-shot Test alias; Android config
  Connect stops being select-only — both call durable `SshConnectionCubit.connect`
  (Android still selects as a side effect, per locked decisions).

### Wiring

- Provide `SshConnectionCubit` at app shell / bootstrap next to
  `SshProfileCubit`, injected with factory + coordinator.
- Register `SshHostsStatusItem` beside `ResourceUsageStatusItem` (rightmost).

## Error handling

- Connect failure → row `error` or `auth-failed` with short subtitle reason; at
  most one soft snackbar.
- Disconnect while sessions use the profile → allowed; existing coordinator
  session-plane / disconnect handlers own fallout.
- Last profile deleted → disconnect if needed, map clears, pill unmounts.
- Auth / host-key failures map to `auth-failed` when detectable
  (`SSHAuthAbortError`, `SSHHostkeyError`, etc.); otherwise `error`.

## Testing

- Cubit: connect opens pool path; disconnect calls disconnectProfile + sets
  reconnect latch + cancel reconnect; aggregate count / overall priority
  (connecting beats partial); delete last profile → empty; seed from existing
  pool; Android connect also selects profile; desktop connect does not.
- Observation: external / later `clientForStorage` after Disconnect flips status
  back to `connected` and clears latch; coordinator reconnect updates UI without
  another Connect.
- Widget: no profiles → no segment; with profiles → pill shows **connected**
  count; row actions invoke Cubit; Manage navigates to `/config/ssh-profiles`.
- Config cards: Connect status matches status-bar Cubit fixture; Test does not
  flip durable connected.

## Reference (Orca)

- `src/renderer/src/components/status-bar/SshStatusSegment.tsx`
- `src/renderer/src/components/status-bar/SshTargetStatusRow.tsx`
- `src/renderer/src/store/slices/ssh.ts`

## Related TeamPilot

- `docs/superpowers/specs/2026-07-23-workspace-status-bar-resource-manager-design.md`
  — that doc listed SSH status segments as a v1 non-goal; **this spec
  supersedes that non-goal** for the `ssh-hosts` item only.
- `client/lib/widgets/workspace_status_bar/`
- `client/lib/services/ssh/ssh_client_factory.dart`
- `client/lib/services/ssh/ssh_profile_connection_coordinator.dart`
- `client/lib/services/remote/remote_connection_monitor.dart`
- `client/lib/pages/ssh_profiles/`
