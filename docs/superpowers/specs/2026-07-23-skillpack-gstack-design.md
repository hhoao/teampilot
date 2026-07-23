# SkillPack + gstack member-hub

## Goal

Land [gstack](https://github.com/garrytan/gstack) as a **SkillPack** (install once) with nine Expert Hub personas that each reference a single pack skill. Uses `SkillAcquisitionEngine` with a first-class **`git-pack`** acquire kind (repo cache → register all pack skills). Keep existing **`script`** for opaque third-party installers.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Install unit | `SkillPack` |
| Runtime / expert binding | Single skill id per expert (`garrytan/gstack:<dir>`) |
| Pack acquire | `git-pack` via GitHub tarball/cache (not curl\|sh) |
| `script` | Remains for third-party opaque installers |
| Catalog | Nine `member-hub` experts + builtin pack registry |
| Host gate | Same as script: native local storage only for pack shell-adjacent work; `git-pack` uses existing skill fetch (works wherever skill git-dir works) |

## Why `git-pack` over wrapper `script` for gstack

- Reuses `SkillRepoDiskCache` (one sync, many dirs) — better performance  
- Structured errors / no opaque shell — better UX & security  
- Any GitHub skill monorepo can ship a pack.json — better extensibility  
- `script` stay available when a vendor only publishes an install URL  

## Models

### `SkillPack` / `SkillPackEntry`

- `id`, `name`, `repoOwner` / `repoName` / `repoBranch`
- `acquire` (`git-pack` for gstack)
- `skills[]`: `{ id, directory, name }`

### `SkillDependencyRef`

- Optional `packId`
- When `packId` set: `expectedLocalId` = explicit `id` ?? `$packId:${basename(directory)}`
- When `acquire.kind == git-pack` (or `packId` set): engine installs the whole pack then returns the requested skill id

## Engine

1. Resolve pack from `SkillPackRegistry` by `packId`
2. If requested skill id already installed → success (caller/cubit may short-circuit earlier)
3. Else `ensureSynced` repo once; for each pack skill `installFromDiscovery` with `idOverride`
4. Return requested skill id

## Member Hub (9)

| slug | skill directory |
|------|-----------------|
| gstack-office-hours | office-hours |
| gstack-ceo | plan-ceo-review |
| gstack-eng-manager | plan-eng-review |
| gstack-designer | plan-design-review |
| gstack-reviewer | review |
| gstack-debugger | investigate |
| gstack-qa | qa |
| gstack-cso | cso |
| gstack-release | ship |

## Non-goals

- Full gstack `bin/` / Claude `./setup` parity  
- Remote SSH pack install beyond existing skill fetch  
- Free-form paste URL UI  
