# Skill Acquire Step Graph

> **Superseded (author protocol):** Pack and skill install authoring now uses the
> Dockerfile-like `install[]` instruction AST. See
> [`2026-07-28-skill-pack-dockerfile-install-design.md`](./2026-07-28-skill-pack-dockerfile-install-design.md).
> This document remains historical context for the former `recipe` / `uses`
> step-graph IR (no longer the public protocol).

## Goal

Replace kind-based skill acquire (`git-dir` / `git-pack` / `script`) with a
**composable step graph + handler registry**. gstack is the reference pack:
sync once → register skills → materialize `bin/` → optional `./setup` → export
PATH for sessions.

**No backward compatibility** with `SkillAcquireSpec.kind` or implicit
`missing acquire ≡ git-dir` as a public protocol. Authoring sugar may still
synthesize a recipe from repo fields, but the engine only runs recipes.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Core | `SkillInstallRecipe { steps[], exports? }` |
| Dispatch | Open `uses` handler registry |
| Pack | `SkillPack.recipe` (not `acquire.kind`) |
| Dep | `packId` → pack recipe, or inline `recipe`, or synthesized from repo+directory |
| gstack | Full recipe: `git.sync` → `skill.register-pack` → `fs.materialize(bin)` → `script.run(./setup)` (native only) |
| Session | Recipe `exports.path` persisted per pack; launch prepends to PATH |
| Compat | **None** — remove kind switch / old acquire JSON |

## Models

### `SkillInstallStep`

```json
{
  "id": "sync",
  "uses": "git.sync",
  "with": { "owner": "garrytan", "name": "gstack", "branch": "main" },
  "needs": [],
  "optional": false
}
```

### `SkillInstallExports`

```json
{
  "skills": ["garrytan/gstack:review"],
  "path": ["$PACK_BIN"],
  "env": {}
}
```

### `SkillInstallRecipe`

`steps` + optional `exports`. Engine topological-sorts by `needs` (v1: linear
order with needs validation; no parallel).

### Handlers (v1)

| `uses` | Behavior |
|--------|----------|
| `git.sync` | Ensure repo on disk via `SkillRepoDiskCacheService` / fetch; set context `syncRoot` |
| `skill.install-dir` | Install one discovery dir → skill id (`idOverride`) |
| `skill.register-pack` | For each pack skill entry, install-dir with pack ids |
| `fs.materialize` | Link/copy `from` under syncRoot → pack-managed dir (`mode: link\|copy`) |
| `script.run` | Safe local `./setup` or HTTPS curl\|sh; host-gated native |

### Context vars

`$SYNC_ROOT`, `$PACK_ROOT`, `$PACK_BIN`, `$SKILLS_INSTALLED` resolved at run time.

## gstack recipe (canonical)

```json
{
  "steps": [
    {
      "id": "sync",
      "uses": "git.sync",
      "with": { "owner": "garrytan", "name": "gstack", "branch": "main" }
    },
    {
      "id": "skills",
      "uses": "skill.register-pack",
      "needs": ["sync"]
    },
    {
      "id": "bins",
      "uses": "fs.materialize",
      "needs": ["sync"],
      "with": { "from": "bin", "to": "$PACK_BIN", "mode": "link" }
    },
    {
      "id": "setup",
      "uses": "script.run",
      "needs": ["bins"],
      "with": { "cwd": "$SYNC_ROOT", "command": ["./setup"] },
      "optional": true
    }
  ],
  "exports": {
    "path": ["$PACK_BIN"]
  }
}
```

Member-hub deps only need `packId` + skill `id` / `directory` (no acquire kind).

## Persistence

After successful pack install, write
`skills/packs/<packId-safe>/install.json`:

- `packId`, `binPath`, `pathExports[]`, `skillIds[]`, `installedAt`

Launch: for session skill ids that belong to an installed pack, merge that
pack's path exports into member environment `PATH`.

## Non-goals

- Unified Extension+Skill engine (shape-aligned only)
- Parallel step execution
- Remote SSH `script.run` / `./setup`
- Keeping `SkillAcquireSpec.kind` readers
