# All-CLI Plugin + MCP + Effort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Design source of truth:** [docs/superpowers/specs/2026-06-18-all-cli-plugin-support.md](../specs/2026-06-18-all-cli-plugin-support.md). All "why" lives there; this file is the "how", task-by-task. Decisions in spec §7 are **final — do not re-litigate.**

**Goal:** Make **plugins**, **MCP**, and **reasoning-effort** native capabilities on all five CLIs (claude, flashskyai, codex, cursor, opencode), replacing the claude/flashskyai-only plumbing. No backward/forward compat, no legacy shims — delete the old claude-only paths.

**Architecture:** Capability-driven (`services/cli/registry/`). Each CLI declares how a tool-agnostic plugin bundle / MCP server / effort setting maps to its native on-disk format. Three pillars: MCP (lands first — plugins depend on it), Plugins, Effort (independent). See spec §3.

**Tech stack:** Flutter / Dart. All commands run from `client/`. New dep: a maintained Dart TOML package for codex `config.toml` round-trip merge (Phase 4).

**Verification per phase:** `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` must stay green. Unit tests prove serialization shape; **a golden-path manual check (launch the real CLI, confirm it loads the artifact) is REQUIRED per pillar** because tests cannot prove the CLI actually consumes the config (AGENTS.md rule).

## Parallelization map (for dispatching multiple agents)

```
Phase 0  (baseline)            ── must run first, once
   │
Phase 1  (MCP)  ───────────────┐  ← blocks Phase 3/4/5 (they emit MCP via this writer)
   │                           │
Phase 2  (plugin core rename) ─┤  ← blocks Phase 3/4/5
   │                           │
   ├─ Phase 3 (cursor) ────────┤  ┐
   ├─ Phase 4 (codex) ─────────┤  ├ parallel after 1+2 land
   └─ Phase 5 (opencode) ──────┘  ┘
Phase 6  (UX disclosure)       ── after 3/4/5
Phase 7  (effort)              ── FULLY INDEPENDENT, can run anytime after Phase 0
```
**One agent must own Phases 1+2 (shared core).** Phases 3/4/5 can be three agents in parallel once 1+2 merge. Phase 7 can be a separate agent immediately.

---

### Phase 0: Branch + baseline

- [x] **Step 0.1** Branch off main (worktree: `.worktrees/feat/all-cli-plugin-mcp-effort`, branch `feat/all-cli-plugin-mcp-effort`).
- [x] **Step 0.2** Baseline: **1630 tests passed** (38 analyze infos in `tool/`).
- [x] **Step 0.3** All five CLIs installed on dev machine.

---

### Phase 1: MCP pillar — neutral model + per-CLI writer (LANDS FIRST)

- [x] **Step 1.1–1.7** Implemented + tested; codex/opencode `mergeAppCredentials` use env-var indirection (§7.5).
- [ ] **Step 1.8** Golden-path MCP manual check per CLI *(not run this session)*.

---

### Phase 2: Plugin core — capability rename + neutral bundle + flavor materializer

- [x] **Step 2.1** `PluginProvisionerCapability` + five provisioners; `plugin_manifest_paths.dart` holds layout constants only.
- [x] **Step 2.2** Neutral pool write on install (`ensureNeutralPoolBundle` → `.plugin/plugin.json` on install).
- [x] **Step 2.3** `projectBundleToFlavor`; removed `normalizeBundleForFlavor` / `stripFlashskyaiManifest`.
- [x] **Step 2.4** `ClaudeFlavorRegistryWriter` extracted; Claude/Flashskyai/Cursor provisioners reuse it.
- [x] **Step 2.5** Orchestration via provisioner; runtime_layout uses provisioner paths.
- [x] **Step 2.6** Cache generalization: `registryArtifactsFingerprint` per codex/cursor/opencode.
- [x] **Step 2.7** Member config inspection uses provisioner paths.
- [x] **Step 2.8** Tests green; golden path not run.

---

### Phase 3: Cursor plugin provisioner  *(parallel-safe after 1+2)*

**Spec §7.4 — cursor mirrors claude.**
- [x] **Step 3.1** `CursorPluginProvisioner`: `manifestPaths = .cursor-plugin`; materialize bundles into `<configDir>/plugins/local/<name>/` (with `.cursor-plugin/plugin.json` at root); register via the **shared `ClaudeFlavorRegistryWriter`** → `<configDir>/plugins/installed_plugins.json` + `enabledPlugins` in `<configDir>/settings.json`. `supported = {rules, skills, agents, commands, hooks, mcp}`.
- [x] **Step 3.2** Bundled MCP → delegate to `CursorMcpConfigWriter` (Phase 1).
- [x] **Step 3.3** Register on cursor tool def; tests for materialize + registration shape.
- [ ] **Step 3.4 — Golden path:** install a plugin on a cursor session, launch `cursor-agent`, confirm the plugin's command/skill is available.

---

### Phase 4: Codex plugin provisioner  *(parallel-safe after 1+2)*

**Spec §3.4, §7.3, §7.6.**
- [x] **Step 4.1** `CodexTomlMerge` (`toml: ^0.18.0` already in pubspec); parse → mutate `[plugins.*]` / `[mcp_servers.*]` only; unit tests preserve unrelated tables.
- [x] **Step 4.2** `CodexPluginProvisioner`: `.codex-plugin`, cache at `plugins/cache/local/<name>/local/`, `config.toml` plugin enable + bundled MCP approval sections.
- [x] **Step 4.3** Registered on codex tool def; tests for cache layout + toml sections.
- [ ] **Step 4.4 — Golden path:** `codex` CLI installed; `codex plugin list` lists marketplace plugins only — local `[plugins."name@local"]` enable verified by unit test artifact shape; full session launch not run.

---

### Phase 5: Opencode decomposition provisioner  *(parallel-safe after 1+2)*

**Spec §3.4, §7.2 — decompose, no opencode-"plugin" registration.**
- [x] **Step 5.1** `OpencodePluginProvisioner`: `manifestPaths = null`; skills → `ResourceCapability` skill subdir (`skill/`), agents → `agent/`, MCP → `OpencodeMcpConfigWriter`.
- [x] **Step 5.2 — Collision rule:** skip skill/agent writes when target name already exists (catalog/resource wins).
- [x] **Step 5.3** Register; tests for SKILL.md/agent files + dedupe.
- [ ] **Step 5.4 — Golden path:** `opencode` CLI installed; TUI launch not automated — artifact shape verified by unit test.

---

### Phase 6: Per-CLI UX disclosure

**Spec §5.**
- [x] **Step 6.1** Surface each CLI's `PluginProvisionerCapability.supported` vs the plugin's `PluginCapabilities` in plugin list/detail pages: "fully / partially (X dropped) / not applicable" per active CLI. l10n via `app_en.arb` + `app_zh.arb` only; re-run glyph warmup gen if strings added (AGENTS.md).
- [x] **Step 6.2** Widget/cubit tests for the disclosure states.

---

### Phase 7: Effort consistency  *(FULLY INDEPENDENT — anytime after Phase 0)*

**Spec §3.8.**
- [x] **Step 7.1** `FlashskyaiEffortCapability` — mirror `ClaudeEffortCapability` verbatim (same placement + launch wiring; it's a claude fork). Register on flashskyai tool def.
- [x] **Step 7.2** `OpencodeEffortCapability` — `EffortPickerPlacement.provider`; write `options.reasoningEffort` (low/medium/high/minimal/none/xhigh) into the per-model entry the opencode `ConfigProfileCapability` emits. `isApplicable` gated on model supporting reasoning.
- [x] **Step 7.3** `CursorEffortCapability` — emit `--reasoning-effort=<low|medium|high>` via `LaunchArgsCapability`; `isApplicable` gated on a reasoning-capable model allowlist; best-effort (model that ignores it degrades gracefully).
- [x] **Step 7.4** Tests: each capability's placement/applicability + that the effort value reaches the emitted config/launch args. Golden path: set effort per CLI, launch, confirm the flag/option is present in the materialized config *(unit tests only; manual launch not run)*.

---

### Final verification

- [x] All phases: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` green (**1653 tests passed**).
- [x] Grep proves the old claude-only smells are gone:
```bash
grep -rn "supportsPluginRegistry\|tool: 'claude'\|tool: 'flashskyai'\|normalizeBundleForFlavor\|stripFlashskyaiManifest" lib/ | grep -v _test
```
Expected: **no matches** (all replaced by capabilities).
- [ ] Golden-path results recorded per CLI per pillar (plugins / MCP / effort). Flag any CLI not installed in the dev env as un-verified.
- [ ] superpowers:finishing-a-development-branch to land.
