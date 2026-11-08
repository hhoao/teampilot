# `services/shared_state/` — home-plane shared UI state

Local-first merge primitives + a small document store for UI state that is
shared by multiple devices through the home plane:

- workspace favourites
- open workspace tabs
- recently closed workspaces
- recently visited workspaces
- workspace display prefs

**This is not the session protocol.** Live agent sessions use an authority-based
duplex protocol (`services/event/` today; see
`docs/superpowers/specs/2026-11-08-session-and-shared-state-sync-design.md`).
Shared UI state is multi-writer and must work offline, so it uses merge, not
RPC.

## Pieces

| File | Role |
|---|---|
| `hlc.dart` | Hybrid Logical Clock (`wallMillis`, `counter`, `nodeId`) |
| `lww_register.dart` | One value with a last-writer-wins stamp |
| `lww_map.dart` | Independent LWW registers per key |
| `or_set.dart` | Observed-remove set (adds win concurrent add/remove) |
| `device_lane.dart` | Per-device ordered lanes (open tabs / recents) |
| `shared_state_document.dart` | Envelope + per-section merge registry |
| `shared_state_store.dart` | Read / mutate / write with revision retry |

## Merge rules

- **LWW**: greater `Hlc` wins; `nodeId` breaks ties.
- **OR-Set**: `remove` tombstones the add tags it has observed, so a concurrent
  add from another device survives.
- **Device lane**: each device writes its own lane; a same-device conflict is
  LWW. `unionItems` is the deduped view across devices.
- **Unknown section**: fall back to the section's `t` stamp; otherwise keep the
  remote value. Old clients must carry new sections through unchanged.

## Store contract

`SharedStateStore.update(mutate)`:

1. read the current document;
2. apply `mutate`;
3. write with a fresh `revision` + `Hlc` stamp;
4. re-read; if another writer's `revision` is observed, merge and retry.

`mutate` must be idempotent and side-effect free because it is re-applied on
conflict.

Corrupt documents throw `SharedStateFormatException` instead of being
overwritten. Conflicts that cannot converge in `maxAttempts` throw
`SharedStateConflictException`.

## Not here

- Device-local state (theme, locale, shortcuts, window size) stays in the
  device plane.
- Real-time session activity/transcript/control stays in the session plane.
- No locks. CAS is optimistic and merge-based.
