# Skill Acquisition Engine

## Goal

Make skill installation **declarative and extensible**: keep today’s git-subdirectory install as the default, and add an Extension-style `acquire` protocol so skills can also be installed via a vetted HTTPS **script** (and later other kinds). This unblocks packs like [gstack](https://github.com/garrytan/gstack) that need more than copying a single `SKILL.md` folder.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Architecture | **Skill-side `SkillAcquisitionEngine`** parallel to `ExtensionAcquisitionEngine` (do **not** merge engines in v1) |
| Protocol | Optional `SkillAcquireSpec` on catalog/deps; missing `acquire` ≡ `git-dir` |
| First new kind | `script` (HTTPS URL → `curl -fsSL "$url" \| sh` after the same URL safety checks as Extension) |
| Default kind | `git-dir` — existing `SkillInstallService.installFromDiscovery` path |
| Host scope | Desktop / local only in v1 (same constraint as Extension acquire Phase 2) |
| Compatibility | Existing `SkillDependencyRef` JSON without `acquire` keeps working |
| Follow-ups (explicitly later) | Unified acquisition layer with Extensions; `git-bundle` / SkillPack; member-hub gstack personas |

## Non-goals (v1)

- SSH / remote work-machine acquire
- Merging skills + extensions into one shared `AcquisitionEngine`
- Implementing `git-bundle` or a first-class SkillPack product
- Adding member-hub gstack expert cards (depends on this landing first)
- Executing arbitrary local shell strings or non-HTTPS script URLs
- Changing team/expert clone “soft-fail one dep” policy

## Protocol

### `SkillAcquireSpec`

Shape mirrors `ExtensionAcquireSpec` (independent type to avoid hard coupling in v1):

| Field | Role |
|-------|------|
| `kind` | Acquisition strategy id |
| `package` | Kind-specific payload (for `script`: HTTPS URL; for `git-dir`: unused — repo/directory live on the parent ref) |
| `alternatives` | Optional fallbacks as `"kind:arg"` strings (same convention as Extension) |

### Kinds

| `kind` | Behavior | v1 |
|--------|----------|----|
| `git-dir` | Fetch `directory/` from `repoOwner/repoName@repoBranch` and install via existing `SkillInstallService` | **Default**; implemented |
| `script` | If URL passes safety check, run injectable runner equivalent to `sh -c 'curl -fsSL "$url" \| sh'` | **New**; implemented |
| `git-bundle` / others | Reserved (e.g. whole-repo layout with `bin/`) | Parse/dispatch table ready; unknown kind → **hard fail** (no silent fallback) |

### URL safety (`script`)

Align with `ExtensionAcquisitionEngine._isSafeScriptUrl`:

- `Uri` parses, scheme is `https`, host non-empty
- Reject if URL matches injection / metacharacter pattern (whitespace, quotes, backticks, `$`, `\`, `;`, `|`, `&`, `<`, `>`, `(`, `)`)

### Backward compatibility

```json
{
  "repoOwner": "obra",
  "repoName": "superpowers",
  "repoBranch": "main",
  "directory": "skills/brainstorming",
  "name": "Brainstorming"
}
```

→ resolve as `acquire: { "kind": "git-dir" }` using the existing repo fields.

New example:

```json
{
  "name": "gstack",
  "acquire": {
    "kind": "script",
    "package": "https://example.com/install-gstack.sh"
  }
}
```

(`git-dir` fields may be absent for pure `script` deps; installer must not require them when `kind == script`.)

## Architecture

```
SkillDependencyRef / DiscoverableSkill
  └─ optional acquire: SkillAcquireSpec
         │
         ▼
SkillAcquisitionEngine.install(...)
  ├─ git-dir  → SkillInstallService.installFromDiscovery
  ├─ script   → validated curl|sh via injectable runner
  │              → scan skills/installed/ for SKILL.md
  │              → upsert Skill rows (primary id = expectedLocalId)
  └─ unknown  → failure (do not pretend success)
         │
         ▼
SkillCubit.installTeamDependency / installFromDiscovery
  (expert/team clone + Skills UI share this path)
```

### Units

| Unit | Responsibility |
|------|----------------|
| `SkillAcquireSpec` | Parse/serialize acquire block; kind + package + alternatives |
| `SkillAcquisitionEngine` | Map kind → commands / install delegates; URL safety; injectable `runner` + FS |
| `SkillInstallService` | Unchanged core for `git-dir` local payload install |
| `SkillCubit` | UI/dep entrypoints call the engine instead of assuming git-dir only |
| `SkillDependencyRef` | Optional `acquire`; `toDiscoverableSkill()` carries it; `expectedLocalId` rules for script deps documented (stable id from name/URL hash or declared id — see below) |

### `expectedLocalId` for `script`

Today `expectedLocalId` is `owner/name:basename(directory)`. For `script` without git fields:

- Prefer an optional explicit `id` on the dependency/catalog entry when present
- Else derive a stable id from the script URL: `script:<host>/<path-basename>` (strip query/fragment)

Document the chosen rule in code next to `SkillDependencyRef`.

**Dep-install contract:** `SkillCubit.installTeamDependency` / busy-id / “already installed?” must key off `ref.expectedLocalId`. After a successful `script` acquire, the engine **must** upsert at least one `Skill` whose `id == ref.expectedLocalId` (not only `local:<directory>` unmanaged ids). Unmanaged scan helpers may discover sibling dirs, but the primary return id for the dep path is always `expectedLocalId`.

### Post-`script` registration

After a successful script run (scan root: **`skills/installed/` only**):

1. Discover directories under `skills/installed/` that contain `SKILL.md` (reuse local-scan helpers where possible).
2. Upsert manifest entries for discovered skills.
3. Ensure the **primary** skill row uses `id = expectedLocalId` for the dep/catalog entry that triggered install:
   - If the script created exactly one new skill dir → register that dir under `expectedLocalId`.
   - If multiple new dirs appear → register the primary under `expectedLocalId` using an optional `primaryDirectory` on the acquire/dep when present; else the sole new dir whose basename matches the URL path basename; else fail with a clear multi-match error (do not guess).
   - Additional sibling skills may be registered with their normal local ids as a side effect; they do not replace the primary id contract.
4. If the runner exits 0 but **no** `SKILL.md` appears under `skills/installed/`, treat as failure (script succeeded but no skills registered).

Scripts that only install into upstream paths (e.g. `~/.claude/skills/...`) are **out of v1 success criteria** unless they also place or symlink content under TeamPilot’s skills root — call that out in UI copy when we add a real script catalog entry later. v1 ships the engine + tests; first production script URL can land in a follow-up once a TeamPilot-aware installer exists (or a thin wrapper script that installs into `skills/installed/`).

### `alternatives`

Same semantics as `ExtensionAcquisitionEngine`: try the primary kind/package first; on failure, try each `alternatives` entry (`"kind:arg"`) **sequentially** until one succeeds or the list is exhausted.

### Unsupported hosts

On platforms where Extension acquire is local-only (non-desktop / SSH storage backends), `script` (and any future shell kinds) **fail fast** with a clear “not supported on this host” error — do not invoke `curl | sh`.

## UI

- Skills discovery install and expert/team dep install use the same engine.
- While `script` runs: busy state on the target id; on failure surface a short stderr/stdout summary (l10n user-facing string + detail).
- v1 does **not** require a free-form “paste script URL” form; acquire comes from catalog/dep JSON (fixtures in tests).
- Optional: badge/label when installed skill’s acquire kind was `script` (nice-to-have, not blocking).

## Error handling

| Case | Behavior |
|------|----------|
| Unsafe script URL | Fail before runner |
| Unknown `kind` | Fail; no fallback to git-dir |
| Runner non-zero | Fail with stderr/stdout summary |
| Success but no `SKILL.md` found under TP skills root | Fail |
| Soft-fail on team/expert clone | Unchanged: log + return null for that dep |

## Testing

- Unit-test `SkillAcquisitionEngine` with fake runner + fake filesystem:
  - `git-dir` delegates to install service (mock)
  - `script` rejects bad URLs
  - `script` success + planted `SKILL.md` → manifest upsert
  - unknown kind fails
- No live network in CI.

## Extensibility (post-v1)

1. Add `git-bundle` kind (clone/cache whole repo, register multiple skill dirs, preserve sibling `bin/`).
2. Extract shared URL safety + runner helpers with Extension (optional merge).
3. SkillPack manifest (one acquire → many skills + tooling).
4. member-hub gstack personas with `skillDeps` pointing at script or bundle acquire.
5. Remote/SSH acquire when Extension remote path exists.

## Success criteria

- Existing superpowers-style deps install unchanged with no JSON migration.
- A fixture `acquire.kind = script` can install through the engine under test and register at least one skill when files land in `skills/installed/`.
- A script `SkillDependencyRef` installed via `installTeamDependency` yields `Skill.id == ref.expectedLocalId`.
- Unsafe URLs never reach the runner.
- Analyze + focused unit tests green.
