# OpenCode shared `node_modules`

OpenCode installs `@opencode-ai/plugin` into every `OPENCODE_CONFIG_DIR` (TeamPilot’s per-session `runtime/opencode/`). That yields ~58MB `node_modules` per session (mostly `effect`), duplicated across sessions.

## Goal

One shared `node_modules` under app CLI defaults; each session `runtime/opencode/node_modules` is a symlink (or copy fallback) to that tree.

## Non-goals

- A batch migration / cleanup job for idle sessions the user never relaunches
- Multi-version coexistence or upgrade detection for `@opencode-ai/plugin`
- Special SSH/WSL behavior beyond existing `LinkStrategy` / `_ensureInheritedChild` and `WorkMachineMaterializer`’s copy of `cli-defaults/{tool}`
- Changing how TeamPilot writes local plugin JS or `opencode.json` `plugin` entries

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Shared root | `<teampilotRoot>/cli-defaults/opencode/` |
| Shared artifacts | `node_modules` + `package.json` under that root |
| Session links | Inherit both `node_modules` and `package.json` into the session opencode dir |
| Populate | TeamPilot `npm install` once into the shared root when missing / incomplete |
| Package pin | `@opencode-ai/plugin` at the version from local `opencode --version` (or equivalent locator) |
| Existing session `node_modules` | On provision, **replace** with the shared link (default `_ensureInheritedChild` / `createSymlink` remove-then-link). No `preservePopulatedDirectory`. No separate cleanup pass. |
| Compat | None — no version backfill policy beyond “shared exists → skip install” |

## Layout

```
cli-defaults/opencode/
  agents/                 # already inherited today
  package.json            # written when seeding (dependencies only)
  node_modules/           # shared install tree
  …

sessions/{sessionId}/runtime/opencode/   # or runtime/{memberId}/opencode
  node_modules -> …/cli-defaults/opencode/node_modules
  package.json -> …/cli-defaults/opencode/package.json   # or same inherit helper
  opencode.json
  AGENTS.md
  teampilot-*.js
  …
```

Also update [docs/workspace-storage-layout.md](../../workspace-storage-layout.md) to note that opencode session `node_modules` / `package.json` inherit from `cli-defaults/opencode/`.

## Provision flow

Hook into existing opencode session materialize (same path that already inherits `agents` and writes plugins / `OPENCODE_CONFIG_DIR`):

1. **Ensure shared tree** (on the home / app `cli-defaults` tree **before** any remote materialize copies it)
   - Shared tree is **complete** only when `node_modules/@opencode-ai/plugin` exists as a directory
   - If incomplete:
     - Remove any partial `node_modules` under the shared root
     - Write `cli-defaults/opencode/package.json` with `{"dependencies":{"@opencode-ai/plugin":"<version>"}}`
     - Run `npm install` in that directory (reuse existing TeamPilot npm/local install helpers where practical)
   - If complete → skip install

2. **Link into session**
   - Inherit `node_modules` and `package.json` from `appToolRoot('opencode')` into the session opencode dir via `_ensureInheritedChild` (symlink preferred, copy fallback)
   - Do **not** set `preservePopulatedDirectory` — a fat real `node_modules` from an older launch is removed and replaced by the link on next provision

3. **Launch**
   - Unchanged env (`OPENCODE_CONFIG_DIR`, `OPENCODE_DB`, …). Linked `package.json` + `node_modules` should satisfy OpenCode’s background dependency install so it does not grow a second full tree under the session dir

## Error handling

- Shared `npm install` failure → delete the incomplete shared `node_modules` (so the next launch retries), fail/warn opencode provision the same way other CLI seed failures do; do not leave sessions linked to a broken shared root
- Symlink failure → copy fallback (existing strategy); accept larger disk on that transport
- Missing `opencode` binary / version → do not invent a version; fail the seed step with a clear diagnostic

## Testing

- Unit: when shared `node_modules` exists, session inherit creates a symlink (or records link in `ManifestFilesystem`) to `cli-defaults/opencode/node_modules`
- Unit: when shared missing, seed writes `package.json` and invokes install once (mock process)
- Unit: second session does not call install again
- Unit: install failure leaves no incomplete shared `node_modules`
- Unit: existing fat real session `node_modules` is removed and replaced by the shared link
- No integration requirement to run real npm in CI if process is injected

## Out of scope follow-ups

- One-shot user cleanup of existing fat session dirs
- Upstream OpenCode change to install `@opencode-ai/plugin` into a global cache instead of each config dir
