# Skill packs

Install-once skill bundles for TeamPilot.

```
skill-packs/
  index.json
  <slug>/pack.json
```

Built-in packs are also registered in-app (`SkillPackRegistry`). The `gstack`
pack maps Garry Tan's [gstack](https://github.com/garrytan/gstack) sprint skills
for Expert Hub personas under `member-hub/`.

## Author protocol

Packs declare an ordered Dockerfile-like `install[]` of **single-key**
instruction objects. There is no step-graph `recipe` / `uses` surface.

Full rules:
[`docs/superpowers/specs/2026-07-28-skill-pack-dockerfile-install-design.md`](../docs/superpowers/specs/2026-07-28-skill-pack-dockerfile-install-design.md).

### Instruction cheat sheet

| Key | Meaning |
|-----|---------|
| `FROM` | Git sync `owner/repo@branch` (default branch `main`) → workspace = sync tree |
| `SKILLS` | `"*"` \| `["dir",…]` \| `{ include?, exclude? }` — register dirs with `SKILL.md` |
| `COPY` | `[from, to]` — `from` relative to sync root; `to` relative to `WORKDIR` |
| `SHELL` | Default wrapper for **string** `RUN` (e.g. `["bash","-lc"]`) |
| `RUN` | Install-time command; string uses `SHELL`, string[] is exec; `optional` ok |
| `WORKDIR` | Changes cwd for later `RUN` and `COPY` destinations |
| `PATH` | Relative dir(s) under sync root → prepended to session `PATH` |
| `ENV` | Map → merged into session environment |
| `SCRIPT` | Opaque HTTPS installer (non-pack / third-party sugar) |

Paths are always relative to the synced repo (or `WORKDIR`). No `$PACK_BIN`.
Host absolute paths and `..` escape are rejected.

Skill id for pack installs: `{packId}:{directoryName}`. Display names come from
each skill’s `SKILL.md`, not from `pack.json`.

---

## Examples

### 1. Minimal pack (gstack)

Real file: [`gstack/pack.json`](gstack/pack.json).

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

What this does:

1. Sync `garrytan/gstack` @ `main`
2. Register every direct child directory that contains `SKILL.md`
3. Optionally run `./setup` (failure does not fail the install)
4. Export `bin/` on the session `PATH` when any of these skills are used

### 2. Whitelist / exclude skills

```json
{
  "id": "acme/playbooks",
  "name": "Acme playbooks",
  "install": [
    { "FROM": "acme/playbooks@main" },
    { "SKILLS": ["review", "ship"] }
  ]
}
```

Only register `review/` and `ship/` (must contain `SKILL.md`).

```json
{
  "id": "acme/playbooks",
  "name": "Acme playbooks",
  "install": [
    { "FROM": "acme/playbooks@main" },
    { "SKILLS": { "exclude": ["internal", "draft"] } }
  ]
}
```

Discover all skill dirs, then drop `internal` and `draft`.

```json
{ "SKILLS": { "include": ["*"], "exclude": ["qa"] } }
```

Same as `"*"` then remove `qa`. Sugar: `"*"` ≡ full discovery; `["a","b"]` ≡
include whitelist; `["*"]` ≡ full discovery.

### 3. COPY shared files into skill dirs

```json
{
  "id": "acme/playbooks",
  "name": "Acme playbooks",
  "install": [
    { "FROM": "acme/playbooks@main" },
    { "COPY": ["shared/checklist.md", "review/checklist.md"] },
    { "COPY": ["shared/checklist.md", "ship/checklist.md"] },
    { "SKILLS": ["review", "ship"] },
    { "PATH": "bin" }
  ]
}
```

`COPY` runs **before** `SKILLS` so registered skill trees already contain the
copied files. `from` is always under the sync root; `to` respects `WORKDIR`
(default = sync root).

### 4. WORKDIR + SHELL + RUN + ENV

```json
{
  "id": "acme/tooling",
  "name": "Acme tooling",
  "description": "Skills plus a small CLI tree",
  "labels": { "owner": "platform" },
  "install": [
    { "FROM": "acme/tooling@main" },
    { "SKILLS": "*" },
    { "SHELL": ["bash", "-lc"] },
    { "WORKDIR": "tools" },
    { "RUN": "npm ci && npm run build" },
    { "RUN": ["./postinstall"], "optional": true },
    { "PATH": ["tools/bin", "bin"] },
    { "ENV": { "ACME_HOME": "." } }
  ]
}
```

Notes:

- String `RUN` goes through `SHELL` (`bash -lc "…"`)
- Array `RUN` is exec form and **ignores** `SHELL`
- `PATH` entries are relative to the **sync root** (not `WORKDIR`)
- `ENV` / `PATH` are persisted on pack install and applied at **session launch**
  when the session uses skills from this pack

### 5. Expert Hub / member dep (packId)

Experts do **not** re-list the whole pack. They pin one skill id + `packId`.
Installing that dep runs the **whole** pack `install`, then binds the expected
skill.

From [`member-hub/members/gstack-ceo/member.json`](../member-hub/members/gstack-ceo/member.json):

```json
{
  "skillDeps": [
    {
      "id": "garrytan/gstack:plan-ceo-review",
      "packId": "garrytan/gstack",
      "name": "CEO Review",
      "repoOwner": "garrytan",
      "repoName": "gstack",
      "repoBranch": "main",
      "directory": "plan-ceo-review"
    }
  ]
}
```

Engine: load pack `garrytan/gstack` → run its `install[]` → require
`garrytan/gstack:plan-ceo-review` among registered skill ids.

### 6. Single-skill dep without a pack (repo sugar)

No `packId` / no inline `install`: owner + repo + directory synthesizes:

```json
[
  { "FROM": "owner/repo@main" },
  { "SKILLS": ["my-skill"] }
]
```

Authoring form on a dependency:

```json
{
  "id": "owner/repo:my-skill",
  "name": "My skill",
  "repoOwner": "owner",
  "repoName": "repo",
  "repoBranch": "main",
  "directory": "my-skill"
}
```

### 7. Inline `install` on a dependency

```json
{
  "id": "owner/repo:review",
  "name": "Review",
  "directory": "review",
  "install": [
    { "FROM": "owner/repo@main" },
    { "COPY": ["shared/rubric.md", "review/rubric.md"] },
    { "SKILLS": ["review"] }
  ]
}
```

### 8. Opaque HTTPS installer (`scriptUrl` / `SCRIPT`)

Catalog sugar:

```json
{
  "id": "script:example.com/install.sh",
  "name": "Vendor skill",
  "directory": "vendor-skill",
  "scriptUrl": "https://example.com/install.sh"
}
```

Synthesizes a `SCRIPT` instruction (host-gated, same posture as local `RUN`).
Prefer git `FROM` + `SKILLS` when the source is a normal GitHub repo.

---

## Non-goals (v1)

- `CMD` / `LINK` / `LABEL` / `MAINTAINER` as install instructions
- Dockerfile string-line DSL
- `$PACK_*` template variables
- Parallel steps / `needs` DAG
