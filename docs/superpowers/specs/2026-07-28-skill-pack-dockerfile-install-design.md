# Skill Pack Dockerfile-like Install

## Goal

Replace the author-facing step-graph recipe (`uses` / `needs` / `with` /
`$PACK_BIN`) with a **Dockerfile-shaped `install` instruction list**. Authors
declare intent in familiar verbs; the engine executes a typed instruction AST.
gstack remains the reference pack.

**No backward compatibility.** Delete the public `recipe` / `SkillInstallRecipe`
/`uses` protocol and all dual-read adapters. Internal code must not keep a
parallel legacy graph “for migration.”

## Why

The step-graph IR leaked engine handler names (`git.sync`, `fs.materialize`)
into `pack.json`. That is hard to read and easy to get wrong, while most packs
only need: sync a repo, register skills, optional setup, export `PATH`.

Dockerfile-like instructions keep extensibility (append new verbs) without
hard-coding gstack-only top-level fields (`bin`, `setup`).

## Locked decisions

| Topic | Choice |
|-------|--------|
| Author protocol | `pack.json`: `id`, `name`, optional metadata, `install[]` |
| Instruction shape | Single-key JSON objects (option B), not Dockerfile string lines |
| Engine | Typed instruction AST; dispatch by instruction type (not string `uses`) |
| Paths | Relative to sync root (after `FROM`); no host absolutes; no `$PACK_*` vars |
| Skills catalog | No top-level `skills[]`; use `SKILLS` instruction |
| Materialize | No `LINK` / pack-bin overlay in v1; `PATH` points into sync tree |
| Session exports | `PATH` + `ENV` instructions persist for launch (same role as today’s exports) |
| Non-pack acquire | Same `install[]` AST; repo sugar / `SCRIPT` replace `singleGitDir` / `scriptUrl` |
| Compat | **None** — hard cut disk packs, builtin registry, deps, tests, docs |
| Out of v1 | `CMD`, `LINK`, `LABEL`, `MAINTAINER`, multi-stage, `needs` graph |

## Author surface

### Canonical gstack `pack.json`

```json
{
  "id": "garrytan/gstack",
  "name": "gstack",
  "install": [
    { "FROM": "garrytan/gstack@main" },
    { "SKILLS": "*" },
    { "RUN": "./setup", "optional": true },
    { "PATH": "bin" }
  ]
}
```

### Top-level fields

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | Pack id (e.g. `garrytan/gstack`) |
| `name` | yes | Display name |
| `description` | no | Optional prose |
| `labels` | no | Optional string map (metadata only; not install steps) |
| `install` | yes | Ordered instruction array |

Remove: `repoOwner` / `repoName` / `repoBranch`, `recipe`, top-level `skills[]`.

### Instructions (v1)

Each element is an object with **exactly one** instruction key, plus optional
modifier `optional` where allowed (`RUN` / `SCRIPT` only).

| Key | Value | Behavior |
|-----|-------|----------|
| `FROM` | `"owner/repo@branch"` (`@branch` default `main`) | Git sync; sets workspace root = sync root |
| `SCRIPT` | url string **or** `{ "url", "id"?, "primaryDirectory"?, "alternatives"? }` | Opaque HTTPS installer (replaces `script.run` package path); host-gated like `RUN` |
| `COPY` | `[from, to]` | Copy within workspace (see path rules below) |
| `SKILLS` | see below | Discover/register skill dirs under sync root |
| `SHELL` | `string[]` (e.g. `["bash","-lc"]`) | Default wrapper for subsequent **string** `RUN` |
| `RUN` | `string` or `string[]` | Install-time command; cwd = `WORKDIR` (default sync root) |
| `WORKDIR` | relative path | Affects subsequent `RUN` and `COPY` **destination** |
| `PATH` | `string` or `string[]` | Relative dirs under sync root → session `PATH` prepend |
| `ENV` | `object` string map | → session environment exports |

Default `SHELL` when unset: platform-appropriate (`["sh","-c"]` on Unix; Windows
policy decided at implementation, documented in plan).

`RUN` forms:

- **string** → invoke via current `SHELL` (e.g. `sh -c "./setup"`)
- **string[]** → exec form, does **not** use `SHELL`
- `"optional": true` → failure is warning; install continues

**Modifiers:** only `optional` is allowed, and only on `RUN` (and `SCRIPT` if the
installer may fail non-fatally — same meaning). No other instruction modifiers
in v1.

**Multiple `PATH` / `ENV`:** later `PATH` entries **append** (dedupe preserving
order); later `ENV` keys **override** earlier keys for the same name.

Unknown instruction keys → parse error (no silent ignore).

### `COPY` path rules (Docker-like)

- `from` is always relative to the **sync root** (build context), not `WORKDIR`
- `to` is relative to current `WORKDIR` (default = sync root)
- Both must resolve inside the sync tree; reject absolutes and `..` escape

### Workspace prerequisite

Instructions that need a synced tree (`COPY`, `SKILLS`, `RUN`, `WORKDIR`,
`PATH`) require a prior `FROM` **or** a prior `SCRIPT` that established a
workspace/skill root in context. Literal `ENV` values need no prior source;
if an `ENV` value embeds a relative path meant to resolve against sync root,
resolve it only when a workspace exists (otherwise keep the literal).
Validation: first workspace-relative instruction must follow a successful
source instruction.

### `SKILLS` value forms

```json
{ "SKILLS": "*" }
{ "SKILLS": ["review", "ship"] }
{ "SKILLS": { "include": ["*"], "exclude": ["qa"] } }
```

Sugar:

- `"*"` ≡ `{ "include": "*" }`
- `["a","b"]` ≡ `{ "include": ["a","b"] }`

Object rules:

1. Resolve candidate dirs that contain `SKILL.md` under the sync root (discovery
   policy: direct child directories with `SKILL.md` unless plan widens depth).
2. If `include` omitted or is `"*"` / `["*"]`, start from full discovery set;
   else intersect with named dirs.
3. Subtract `exclude` (if present).
4. Register each remaining dir: skill id = `{packId}:{dirName}`; display name
   from skill metadata (`SKILL.md`), not from `pack.json`.

`SKILLS` must appear after a successful source instruction (`FROM` / `SCRIPT`)
in the same `install` list. Missing `SKILLS` → register no skills from this
install (explicit opt-in).

When the engine is installing a **single dependency** that already carries an
expected local skill id, and `SKILLS` selects exactly one directory, register
that directory under the expected id (dependency `id` / `key`), not only under
`{packId}:{dir}` — pack installs still use `{packId}:{dir}`.

### Path model

- Author paths are relative per rules above (sync root / `WORKDIR`).
- Reject absolute host paths and `..` escape outside sync root.
- No `$SYNC_ROOT` / `$PACK_BIN` / `$PACK_ROOT` in the author protocol.
- Engine keeps internal absolute paths only in runtime context.

### Non-pack JSON (DiscoverableSkill / deps / teams)

Hard cut: remove `recipe` from these JSON shapes.

Resolution order for `resolvedInstall`:

1. If `packId` set → run that pack’s `install` (whole pack), then bind the
   requested skill id / directory.
2. Else if inline `install` array present → parse as instruction AST and run.
3. Else if `repoOwner` + `repoName` + `directory` present → **synthesize**:
   ```json
   [
     { "FROM": "{owner}/{repo}@{branch}" },
     { "SKILLS": ["{directory}"] }
   ]
   ```
   with expected skill id from the dependency’s `id` / `key` rules (unchanged
   product behavior).
4. Else if `scriptUrl` (HTTPS) present → synthesize:
   ```json
   [
     {
       "SCRIPT": {
         "url": "{scriptUrl}",
         "id": "{expectedLocalId}",
         "primaryDirectory": "{directory or omitted}",
         "alternatives": []
       }
     }
   ]
   ```
   Registration behavior matches today’s script acquire (locate skill dir after
   install). Do **not** keep a parallel long-lived `recipe` field.

Authoring preference: packs and hand-written deps use `install[]`. Repo /
`scriptUrl` sugar remains for hub catalogs that only expose those fields today.

### What we deliberately do not copy from Docker

| Docker | Skill pack |
|--------|------------|
| `FROM` image layers | `FROM` = git sync of source |
| Image filesystem | Working tree = synced repo |
| `CMD` / `ENTRYPOINT` | Deferred (session hooks later) |
| `LABEL` / `MAINTAINER` | Top-level metadata / `labels`, not instructions |
| Build-time `PATH` in image | `PATH` instruction = **session launch** export |

## Architecture

```
pack.json
  → SkillPack.fromJson
  → List<SkillPackInstruction>  (typed AST)
  → SkillAcquisitionEngine.run(install)
       onFrom / onScript / onCopy / onSkills / onShell / onRun / onWorkdir / onPath / onEnv
  → persist pack install record (skill ids, pathExports, envExports, sync identity)
  → session launch merges path/env for members using those skills
```

### Models (replace, do not wrap)

Delete with no leftover API:

- `SkillInstallRecipe`, `SkillInstallStep`, `SkillInstallExports`
- `SkillPack.recipe`, `SkillPackEntry` / top-level pack `skills[]`
- String handler registry keyed by `"git.sync"` / `skill.register-pack` /
  `fs.materialize` for install
- `DiscoverableSkill.recipe`, `DiscoverableTeam.recipe`, dependency `recipe`
- Factories `singleGitDir` / `scriptUrl`

Introduce:

- `SkillPackInstruction` sealed/union: `From`, `Script`, `Copy`, `Skills`,
  `Shell`, `Run`, `Workdir`, `PathExport`, `EnvExport`
- `SkillPack.install: List<SkillPackInstruction>`
- `resolvedInstall` on discoverable skill/team/dep → `List<SkillPackInstruction>?`
- Synthesis helpers (not separate protocol types): repo→`From`+`Skills`,
  script→`Script` (+ register)

Builtin `kGstackSkillPack` mirrors disk `install` only (no embedded skill
entry list). Pre-install UI that needs skill names uses Expert Hub deps or
post-sync discovery — not a static pack catalog.

### Skill discovery vs Expert Hub

Expert Hub members keep referencing stable ids
(`garrytan/gstack:review`) via `packId` + `directory`. They do **not** require
a static catalog inside `pack.json`. After install, the engine/registry can
answer “which skills did this pack register.”

### Persistence

After successful pack install, write pack install metadata (same role as today’s
`skills/packs/<packId-safe>/install.json`):

- `packId`, `skillIds[]`, `pathExports[]` (absolute resolved), `envExports`,
  `syncRoot` (or equivalent), `installedAt`

Launch: for session skill ids belonging to an installed pack, prepend that
pack’s `pathExports` and merge `envExports`.

### Host / security

- `RUN` remains host-gated (native local), same posture as current `script.run`
- `COPY` only within sync tree
- No remote SSH `RUN` in v1

## Validation

- `install` non-empty when required; pack `install` must include `FROM` (packs
  are git-sourced in v1) or explicitly documented `SCRIPT`-only packs if added
  later
- Exactly one instruction key per element
- `COPY` length-2; `PATH` non-empty strings; `ENV` string values
- `SKILLS` object: only `include` / `exclude` keys
- Modifiers: only `optional` on `RUN` / `SCRIPT`
- Errors cite instruction index + key (e.g. `install[2] RUN: empty command`)

## Testing (acceptance)

- gstack `pack.json` parses; builtin registry matches disk
- Order: `FROM` → `SKILLS` → optional `RUN` → `PATH` applied to install record
- `SKILLS` `*`, include list, include+exclude
- Repo sugar synthesizes `FROM` + `SKILLS` for a single discoverable skill
- `scriptUrl` sugar synthesizes `SCRIPT` and registers expected id
- `optional` `RUN` failure does not fail install; `PATH` still recorded
- `SHELL` wraps string `RUN`; exec-form `RUN` ignores `SHELL`
- `COPY` then `SKILLS` sees copied files; `from` vs `WORKDIR`/`to` rules
- Reject absolute paths, unknown keys, dual instruction keys
- **No** tests for old `recipe` / `uses` parsing

## Migration / cleanup

Hard cut in one change set (plan will enumerate files):

- Rewrite `skill-packs/gstack/pack.json` and `kGstackSkillPack`
- Delete step-graph author docs references; supersede
  `2026-07-24-skill-acquire-step-graph-design.md` author protocol (engine
  concepts that remain useful may be noted as historical)
- Update `skill-packs/README.md`
- Purge recipe JSON from models, engine, tests

## Non-goals

- Dockerfile string-line DSL / tokenizer
- `CMD` session start hooks
- `LINK` / separate pack-bin materialize directory
- Parallel instruction execution / `needs` DAG
- Unified Extension+Skill engine
- Keeping any `SkillAcquireSpec.kind` or `uses` authoring path
