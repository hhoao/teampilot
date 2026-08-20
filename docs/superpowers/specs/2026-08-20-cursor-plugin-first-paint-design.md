# Cursor isolated-HOME plugin first paint — Design

**Date:** 2026-08-20
**Status:** Approved (continue black-screen work; keep `--add-dir`)

## Problem

`cursor-agent` blocks first TUI paint on `LocalPluginsService.load` →
`CursorPluginsAgentSkillsService.loadAll`. Observed: `first_paint_ms ≈ 145s`
with 29 skills while the PTY stayed black. TeamPilot cannot make the CLI
paint *before* that scan finishes.

Two TeamPilot-owned inputs make the scan expensive:

1. **`plugins/local` is a symlink to the shared pool.** cursor-agent
   `listDirectory`s the plugin root. A pool checkout includes `.git` /
   `node_modules`. The user-local loader also `realpath`s each child of
   `plugins/local` and **rejects** anything whose real path escapes that
   directory — so a whole-tree symlink to the pool is either a huge walk
   or a rejected plugin that then falls through to marketplace install.
2. **Isolated `$HOME/.cursor/plugins/cache` is empty.** cursor-agent
   marketplace load (`listEnabledPlugins` then `isCached` /
   `installPlugin`) looks under
   `$HOME/.cursor/plugins/cache/<marketplace>/<id>/<version>/` for a
   `.cache-complete` marker (`cacheRoot = join(home, ".cursor",
   "plugins/cache")`). Real `~/.cursor` is *not* passthrough (by design).
   Cold isolated HOMEs therefore miss the cache and re-install.

Composer-surface wait (`4777b1768`) already keeps the first message until
the input box exists. This spec only shortens the black screen.

## Goals

1. First paint in seconds on a warm machine for the same workspace, plugin
   set, and **all `--add-dir` roots**.
2. Keep extra workspace folders / `--add-dir` unchanged.
3. Keep marketplace / TeamPilot-enabled plugin skills available.
4. Do not `copyTree` a full superpowers (or similar) checkout on the UI
   isolate.

## Non-goals

- Do not drop or cap `--add-dir` / extra folders.
- Do not treat an empty/ANSI-only PTY as boot-frame ready.
- Do not set `loadCursorFirstParty: false` (that would drop Cursor
  account marketplace plugins).
- Do not skip `.claude` passthrough in this change (`loadClaude` is gated
  on `importThirdPartyPlugins`, which isolated `settings.json` does not
  set).
- Do not change composer wait / landing inject.

## Decisions

| Topic | Choice |
|-------|--------|
| Local plugin materialization | **Contained runtime tree**: real directory under `plugins/local/<name>/`. Copy small manifests. Symlink only component dirs (`skills`, `agents`, `commands`, `hooks`, `rules`, `apps`). Never link/copy `.git` or `node_modules`. |
| Marketplace cache | **Symlink** `$memberHome/.cursor/plugins/cache` → warm/real `$HOME/.cursor/plugins/cache` when the source exists. Never `copyTree` the cache. |
| Warm source | Existing `warmCacheHomeRoot` (`ctx.paths.home`) used for statsig / `serverConfigCache`. Same root for plugin cache. |
| Symlink failure | Skip (leave cache missing). Do not fall back to copy. |
| `--add-dir` | Unchanged. |

## Design

### Contained runtime tree

`CursorPluginCapability._materializeToLocal` stops calling
`CliPluginLayout.linkOrCopyTree` on the **plugin root**.

New helper `CursorPluginRuntimeTree.materialize`:

```
plugins/local/<name>/                  # real directory (realpath stays inside local)
  .cursor-plugin/   (copied)
  .claude-plugin/   (copied if present)
  .plugin/          (copied if present)
  skills/           → symlink to pool/.../skills
  agents/           → symlink to pool/.../agents
  …
  .mcp.json         (copied if present)
```

cursor-agent then:

- Accepts the plugin (realpath of `<name>` is inside `plugins/local`).
- `listDirectory` of the plugin root does not see `.git`.
- Skill discovery follows the `skills/` symlink only.

`ClaudeFlavorRegistryWriter` already records `installPath` from the
materialized member dir, not the pool path.

Mixed-mode warm tier still owns `plugins/local`; member HOME keeps
symlinking that directory. The slim trees live in the warm tier (built
once per workspace+team) so later members do not re-copy manifests.

### Marketplace cache seed

`CursorHomeLayout.pluginsCache(home)` =
`join(home, ".cursor", "plugins", "cache")`.

`CursorHomeProvisioner._seedWarmCaches` additionally:

1. If `pluginsCache(warm)` does not exist, return.
2. If `pluginsCache(member)` already points at that source, return.
3. Else replace dest with a symlink to source.

Covers simple `provision` and mixed `provisionOverlayOnly`.

### Error handling

- Missing warm cache: no seed; cursor-agent may download on first
  isolated launch (same as today).
- Symlink unsupported: skip seed; local slim trees still avoid the git
  walk.
- Corrupt dest cache dir: `removeRecursive` then symlink.

## Testing

- Runtime tree: dest is a directory, not a pool symlink; `.git` is absent;
  `skills/SKILL.md` is readable through the component symlink.
- Provisioner: `plugins/cache` is a symlink to warm home; existing statsig
  seed still works.
- Cursor plugin provisioner: update the “links the whole pool tree” case
  to the contained-tree contract.

## Success

Same 6-root workspace no longer spends ~2 minutes with `ptyObserved=false`
before first paint, without removing workspace folders.
