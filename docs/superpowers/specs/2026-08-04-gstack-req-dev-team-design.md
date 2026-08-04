# gstack Requirement Dev team (Team Hub)

## Goal

Add a public Team Hub template for **day-to-day requirement development**: a five-seat roster that mirrors common product delivery roles (PM → architect → developer → QA → release), each backed by advanced gstack skills via Expert Hub personas.

## Decision

| Item | Choice |
|------|--------|
| Team slug / key | `gstack-req-dev` → `hhoao/teampilot/team-hub/gstack-req-dev` |
| Display name | `gstack Requirement Dev` |
| Description | `Day-to-day requirement delivery: product framing → architecture → implementation (self-review + investigate) → QA → release.` |
| Category / author | `Development` / `gstack` |
| CLI / mode | `claude` / `native` |
| Lead | Office Hours as `team-lead` (product entry) |
| Skill ownership | Per-expert `skillDeps` only; team-level `skillDeps` empty |
| New expert | `member-hub/members/gstack-developer` with `/review` + `/investigate` |
| `updatedAt` | `1784764800000` (same stamp as other shipped `gstack-*` members) |

Rejected alternatives:

- **Full gstack sprint roster** (CEO, designer, CSO, dedicated reviewer, debugger as seats) — too heavy for daily feature work; review/debug are developer capabilities, not separate headcount.
- **Reuse `gstack-reviewer` as the developer seat** — wrong persona (review-only framing).
- **Team-level dump of entire `garrytan/gstack` pack** — skills install without clear role binding.

## Roster

| Slot id | Role | expertKey |
|---------|------|-----------|
| `team-lead` | Product manager | `hhoao/teampilot/member-hub/gstack-office-hours` |
| `architect` | Architect | `hhoao/teampilot/member-hub/gstack-eng-manager` |
| `developer` | Senior developer | `hhoao/teampilot/member-hub/gstack-developer` (new) |
| `qa` | QA | `hhoao/teampilot/member-hub/gstack-qa` |
| `release` | Release / ops | `hhoao/teampilot/member-hub/gstack-release` |

Collaboration chain: Office Hours frames the problem → Eng Manager locks the plan → Developer implements (self-review + investigate when stuck) → QA verifies → Release ships.

No dedicated Reviewer / CSO / Debugger / Designer / CEO seats in this template.

## New expert: `gstack-developer`

| Field | Value |
|-------|-------|
| `name` | `gstack Developer` |
| `description` | `Senior implementer: ship against the eng plan; self-review with /review; root-cause with /investigate before speculative fixes.` |
| `category` | `Development` |
| `author` | `gstack` |
| `member.name` | `developer` |
| `updatedAt` | `1784764800000` |

- **responsibilities:** Implement against an approved eng plan; small commits; self-review before handoff; investigate before speculative fixes. Do not expand scope, replace QA acceptance, or own release.
- **playbook:** Follow the gstack `/review` and `/investigate` skill methodology when available. Prefer the installed skill pack over improvising a parallel process.
- **skillDeps:**
  - `garrytan/gstack:review` (`directory`: `review`)
  - `garrytan/gstack:investigate` (`directory`: `investigate`)
- **i18n.zh:**
  - `name`: `gstack 开发者`
  - `description`: `高级实现者：按工程计划交付；用 /review 自审；没有调查前不做投机式修复。`
  - `category`: `开发`
  - `member.responsibilities` / `playbook`: Chinese mirrors of the English fields above (same tone as other `gstack-*` members).
- gstack has no standalone `/build` skill; advanced developer capability is expressed via review + investigate on an implementer persona.

## Files

```
member-hub/members/gstack-developer/member.json   # create
member-hub/index.json                             # add "gstack-developer"
team-hub/teams/gstack-req-dev/team.json           # create
team-hub/index.json                               # teams: [{ "slug": "gstack-req-dev" }]
```

`team.json`: roster slots are `id` + `expertKey` only (no overrides). Empty `skillDeps` / `pluginDeps` / `mcpDeps`. No team `i18n` (`DiscoverableTeam` does not support it today).

Team Hub `index.json` uses `{ "teams": [ { "slug": "…" } ] }` (object slugs), not the member-hub string-array form.

## Clone behavior

Installing the team resolves five expert keys; each expert’s `skillDeps` install as today. `gstack-developer`, `gstack-reviewer`, and `gstack-debugger` share `packId` `garrytan/gstack` — pack install-once semantics unchanged.

## Out of scope

- Flutter / builtin template code changes
- New Team Hub i18n support
- Separate teams for full sprint / security-heavy / design-heavy variants
- Updating product README beyond optional one-line hub catalog notes
