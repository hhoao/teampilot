# README Landing Page Rewrite — Design Spec

Date: 2026-09-04
Status: Approved (brainstormed with maintainer)

## Problem

TeamPilot's positioning has shifted from "team-orchestration launcher" to an
**AI agent workbench / IDE**, but `README.md` / `README.zh.md` still read like a
feature document: dense tables, no one-line statement of what the product is,
selling points buried mid-page. New features since the last substantive rewrite
(in-chat permission cards, Git graph, per-entry provider credentials) are
absent. Screenshots date from 2026-06-10. The README does not attract new users.

## Goals

- Lead with the new positioning: **the workbench for terminal AI coding agents**.
- A scannable ~100-line landing-page README (EN + ZH, mirrored).
- Top three selling points up front: (1) all-in-one workbench, (2) multi-agent
  team orchestration with per-member tiering, (3) broad compatibility (5 CLIs,
  local PTY / SSH / WSL, desktop + Android).
- Preserve all factual detail by moving it to a new pair of docs rather than
  deleting it.

## Non-goals

- No new screenshots (old images stay as placeholders, annotated as outdated).
- No changes to product code, AGENTS.md beyond the docs index table, or other
  docs content.
- No new feature claims — every feature named in the README must already exist
  in the codebase.

## Decisions from brainstorming

| Decision | Choice |
|----------|--------|
| Positioning | AI Agent workbench / IDE |
| Top selling points | All-in-one workbench, team orchestration, broad compatibility |
| Length / style | Landing-page style, ~100 lines |
| Detail disposal | Move to new `docs/features.md` + `docs/features.zh.md` |
| Screenshots | Keep old images as placeholders with an "outdated" note |
| Structure | Approach A (classic landing page) with approach B's pain-point opening sentences inside each "Why" paragraph |

## File changes

| File | Action |
|------|--------|
| `README.md` | Rewrite as landing page (~100 lines) |
| `README.zh.md` | Mirror rewrite of `README.md` |
| `docs/features.md` | New: migrated detail content |
| `docs/features.zh.md` | New: mirror of `docs/features.md` |
| `AGENTS.md` | Add a `docs/features.md` row to the docs table (AGENTS.md is English-only) |

## README structure

```
# TeamPilot
hero one-liner + secondary sentence
badges: License · Releases · QQ · Discord · 简体中文 link
screenshots (existing assets/image.png, image1.png) + outdated note
## Why TeamPilot?           — 3 paragraphs, each opens with a pain point
## Features                 — compact matrix (~12 rows), links to docs/features.md anchors
## Quick start              — 3 steps + per-OS <details> with existing install commands
## Supported agents         — 5-CLI table (kept from current README)
## Documentation            — link table incl. new features docs
## Community / Acknowledgements / License  — unchanged from current README
```

### Hero text (EN draft)

> **The workbench for terminal AI coding agents.** Chat with Claude Code,
> Codex, opencode, cursor-agent and flashskyai side by side — with a built-in
> file tree, editor, Git panel and multi-agent teams in one window, locally or
> over SSH.

ZH mirror to be written during implementation (natural Chinese, not literal).

### Why TeamPilot? paragraphs

| Paragraph | Pain-point opener → payoff |
|-----------|---------------------------|
| One window, full workbench | Context-switching between IDE and terminal → file tree, multi-tab editor, Git (diff / commit / AI commit messages) and embedded terminals in the same window |
| Multi-agent teams, tiered per member | One model for everything is either expensive or underpowered → per-member model / CLI / permissions, native or mixed teams, one terminal per member running in parallel |
| Bring your own agents | Every CLI needs its own MCP / skills / credentials setup → 5 CLIs managed in one GUI, local PTY / SSH / WSL, desktop to Android |

### Features matrix (~12 rows, one line each)

Workspaces & sessions · Built-in IDE · Git & worktrees · In-chat permission
cards · Multi-agent teams (native/mixed) · Team Hub / Expert Hub · Skills /
MCP / plugins global library · CLI presets · Automations · Provider management
(per-entry credentials) · Remote (SSH) agents · Android client. Each row links
to the corresponding anchor in `docs/features.md`.

## docs/features.md structure

Content migrated from the current README (reorganized, not newly written):

1. Two ways to work (Simple / Team mode table + "Simple is not stripped-down" bullets)
2. Team configuration (pieces table, per-member model tiers, typical workflows, hubs)
3. Workspace & built-in IDE (worktrees, CLI presets, skills/MCP/plugins two-layer model, IDE module table)
4. Storage layout pointer (links to `docs/workspace-storage-layout.md`)

`docs/features.zh.md` mirrors it.

## Fact-check requirements

- In-chat permission cards: merged via the Claude general permission card work
  (commits through 2e0546d21); describe as "answer permission prompts from the
  chat card" without over-promising CLI coverage — gate wording to CLIs where it
  shipped (Claude family).
- Per-entry provider credentials: merged (45aeea360, b14f830b0).
- Git graph exists but is a detail, not a README selling point — mention only in
  features doc IDE section if desired.
- Supported CLIs, install commands, community links: copy verbatim from current
  README (verified working links).

## Verification

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` unaffected
  (docs-only change); run anyway to confirm clean tree.
- Manual check: all internal links resolve (README ↔ features docs ↔ docs table),
  anchors match, EN/ZH sections mirror each other, no content dropped without a
  new home in `docs/features.md`.
- Line count target: README.md ≈ 100 lines (±20).
