# Session runtime shared deps (OpenCode + Codex `.tmp`)

**Date:** 2026-07-31  
**Status:** Approved (chat)  
**Scope:** Reclaim duplicated session runtime for OpenCode `node_modules` and Codex `.tmp/plugins` without changing Codex launch provisioners in this phase.

## Problem

After Cursor fake-HOME passthrough cleanup, remaining large sessions are dominated by:

1. **OpenCode** — per-session real `runtime/opencode/node_modules` (~50–55MB) on sessions created before shared inherit landed; newer sessions already symlink to `cli-defaults/opencode/node_modules`.
2. **Codex** — per-session real `runtime/codex/.tmp/plugins` (~67MB), including vendored `.git` packs; not hard-linked across sessions.

## Goals

- One shared tree per machine for each of the above.
- Session paths remain the same (CLI still sees `CONFIG_DIR/node_modules` or `CONFIG_DIR/.tmp/plugins`).
- Prefer symlink (copy fallback only where FS requires it).
- OpenCode: rely on existing `ensureSessionInheritsOpencodePluginDeps`; migrate fat dirs on disk.
- Codex: **data-plane only** this phase — consolidate + symlink existing `.tmp/plugins`; do **not** change `CodexPluginProvisioner` / launch contribute yet.

## Non-goals

- Deleting sessions or Cursor `.cursor/chats`.
- Full Codex launch-time inherit (follow-up if Codex recreates fat `.tmp`).

## Design

### OpenCode

Shared root (existing):

```
<teampilotRoot>/cli-defaults/opencode/
  package.json
  package-lock.json
  node_modules/          # seeded by OpencodeSharedPluginDeps
```

Session inherit (existing): `RuntimeLayout.ensureSessionInheritsOpencodePluginDeps` links those three names into `session …/runtime/opencode/` (replace existing real dirs/files).

**Migration:** For each `…/runtime/opencode/node_modules` that is a real directory (not a symlink), remove and symlink to the shared `node_modules`. Same for `package.json` / `package-lock.json` when they are real files and the shared copies exist.

### Codex (phase 1 — disk only)

Shared root (new convention):

```
<teampilotRoot>/cli-defaults/codex/.tmp/plugins/
```

**Migration:**

1. If shared plugins dir is missing/empty, **rename** (move) the largest existing session `runtime/codex/.tmp/plugins` into the shared root (avoid a second ~67MB copy).
2. For every other session `…/runtime/codex/.tmp/plugins` that is a real directory: delete and symlink to the shared root.
3. Ensure parent `…/runtime/codex/.tmp/` exists before linking.

**Follow-up (done 2026-07-31):** `RuntimeLayout.ensureSessionInheritsCodexTmpPlugins` runs from `CodexConfigProfileCapability.contributeLaunch`. Empty/missing shared + fat session → promote then link; otherwise replace fat with symlink to shared.

### Verification

- `du` on `workspace/workspaces` drops by roughly OpenCode fat copies + (n−1)×Codex plugins.
- Spot-check: session `node_modules` / `.tmp/plugins` are symlinks into `cli-defaults/…`.

## Risks

- Codex writing through the shared plugins symlink mutates the shared tree (acceptable; matches “one cache”).
- Codex deleting `.tmp` and re-cloning breaks the link until phase-2 inherit.
