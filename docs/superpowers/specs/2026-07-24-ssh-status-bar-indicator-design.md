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
| Connection semantics | Durable keep-alive per SSH profile (not one-shot probe) |
| Empty state | Hide the entire pill when there are zero SSH profiles |
| Architecture | New `SshConnectionCubit` as UI truth; transport via existing `SshProfileConnectionCoordinator` |
| Config page | Connect / Disconnect share the same Cubit (remove ephemeral per-card status maps) |
| Placement | New `SshHostsStatusItem` on `WorkspaceStatusBar`, rightmost (Orca hosts-at-edge) |
| Manage link | Navigate to `/config/ssh-profiles` and close the popover |
| Startup | Do not auto-connect all hosts; reflect already-active connections only |
| Profile edit while connected | Keep existing connection; next Connect uses new config |
| Platform | Same UI on desktop and Android; still hide when no profiles |

## Non-goals (v1)

- Orca Remote Orca Server / runtime-host rows
- Status-bar appearance toggle (`statusBarItems`)
- Add-host form inside the popover (use Manage)
- Force-kill sessions on Disconnect (reuse existing coordinator session-plane signals)
- Auto-connect-all on app launch

## Product UX

### Closed pill (`ssh-hosts`)

- Right cluster of the workspace status bar; **rightmost** relative to Resource
  Manager (Orca hosts-at-edge).
- Hidden when `SshProfileCubit` has no profiles.
- Content: host icon + label + overall status dot.
  - Label: `N hosts` / `1 host` (l10n), or connecting copy while any host is
    connecting / reconnecting.
  - Icon: disconnected-all → server-off; else server (optional small spinner
    while connecting).
  - Overall dot:
    - emerald — all or partial connected
    - yellow — connecting / reconnecting (and none yet connected, or in progress)
    - muted — all disconnected
    - destructive — error / auth-failed with no connected hosts (optional;
      errors always detailed in the open panel)
- Compact mode (`WorkspaceStatusBar` &lt; 720): icon + dot only (same pattern as
  Resource Manager).

### Open panel

Popover anchored above the pill via existing status-bar popover pattern
(`TpPopover` / Resource Manager style):

1. **Header:** “Remote Hosts” (l10n → 远程主机).
2. **Host rows:** connected first, then inactive / disconnected / error.
   - Left: per-host status dot.
   - Middle: primary label (profile name, fallback host) + subtitle
     `SSH Host · {status}` (l10n).
   - Right: **Connect** when reconnectable (`disconnected`, `error`,
     `auth-failed`); **Disconnect** when `connected`; no action while
     `connecting` / `reconnecting`.
3. **Footer:** separator + “Manage Remote Hosts…” → `/config/ssh-profiles`.

### Status vocabulary

Align Orca-ish UI statuses (richer than today’s 4-value ephemeral enum):

`disconnected | connecting | connected | reconnecting | error | auth-failed`

Map from `RemoteConnectionMonitor` / coordinator signals into this vocabulary
inside `SshConnectionCubit`.

## Architecture

```
GlobalResourceManagerHost / status-bar host
 └─ WorkspaceStatusBar(
      items: [ResourceUsageStatusItem, SshHostsStatusItem],
    )

SshProfileCubit          // profile CRUD / list
SshConnectionCubit       // Map<profileId, SshHostConnectionVm> + aggregates
  └─ SshProfileConnectionCoordinator  // keep-alive, coalesce, reconnect
       └─ RemoteConnectionMonitor per profile
```

### `SshConnectionCubit`

- Subscribes to profile list; drops VMs for deleted ids; hides pill when empty.
- `connect(profileId)` / `disconnect(profileId)` are the only UI entry points
  for durable connection (status bar + config cards).
- Exposes aggregates for the closed pill: `connectedCount`, `overallStatus`,
  `isEmpty`.
- Rebuild performance: closed pill `buildWhen` on aggregates only; open panel
  rebuilds host rows.

### Config page sync

- `ssh_profile_target_card` (and related) stop owning local
  `SshProfileConnectionStatus` maps for Connect / Disconnect.
- Cards read status from `SshConnectionCubit` and call the same methods.
- One-shot **Test** (if retained) stays separate from durable Connect.

### Wiring

- Provide `SshConnectionCubit` at app shell / bootstrap next to
  `SshProfileCubit`.
- Register `SshHostsStatusItem` beside `ResourceUsageStatusItem`.

## Error handling

- Connect failure → row becomes `error` or `auth-failed` with a short reason in
  the subtitle; at most one soft snackbar (no toast spam).
- Disconnect while sessions use the profile → allowed; existing coordinator
  session-reconnect / disconnect handlers own fallout.
- Last profile deleted → map clears, pill unmounts.
- Auth failures surface distinctly from generic transport errors when detectable.

## Testing

- Cubit: connect / disconnect transitions; aggregate count / overall; delete last
  profile → empty; map prune on profile removal.
- Widget: no profiles → no segment; with profiles → pill; row actions invoke
  Cubit; Manage navigates to `/config/ssh-profiles`.
- Config cards: Connect status matches status-bar Cubit fixture (same source).

## Reference (Orca)

- `src/renderer/src/components/status-bar/SshStatusSegment.tsx`
- `src/renderer/src/components/status-bar/SshTargetStatusRow.tsx`
- `src/renderer/src/store/slices/ssh.ts`

## Related TeamPilot

- `docs/superpowers/specs/2026-07-23-workspace-status-bar-resource-manager-design.md`
- `client/lib/widgets/workspace_status_bar/`
- `client/lib/services/ssh/ssh_profile_connection_coordinator.dart`
- `client/lib/pages/ssh_profiles/`
