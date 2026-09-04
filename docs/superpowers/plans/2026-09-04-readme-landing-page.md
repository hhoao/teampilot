# README Landing Page Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `README.md` / `README.zh.md` as ~100-line landing pages for TeamPilot's new "AI agent workbench" positioning, migrating all dropped detail into new `docs/features.md` / `docs/features.zh.md`.

**Architecture:** Docs-only change. Detail content moves first (features docs, Tasks 1–2), then the READMEs are rewritten against stable anchors (Tasks 3–4), then `AGENTS.md`'s docs index is updated and everything is verified (Task 5). Each task ends with an independently reviewable commit.

**Tech Stack:** Markdown (GitHub-flavored). No code changes.

**Spec:** `docs/superpowers/specs/2026-09-04-readme-landing-page-design.md`

## Global Constraints

- No new feature claims: every feature named must already exist in the codebase. In-chat permission cards are Claude-family CLIs only — word it that way.
- README.md target ≈ 100 lines (±20). README.zh.md mirrors README.md section-for-section.
- Install commands, supported-CLI table, community links, acknowledgements, license text: reuse verbatim from the current READMEs (verified links).
- Screenshots stay `assets/image.png` + `assets/image1.png`, with an italic note that they are slightly outdated.
- `docs/features.zh.md` mirrors `docs/features.md`; `docs/features.md` mirrors content from current `README.md` (migrated, not invented) plus the four new short sections written out below.
- ZH terminology follows the existing `README.zh.md` vocabulary (工作台 / 团队 / 成员 / 技能 / 插件 / 工作区 / 会话 / 混合团队).
- Commits end with `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Anchor contract (used across tasks)

`docs/features.md` headings produce these GitHub anchors — README feature-matrix links must use exactly these slugs:

| Heading | Anchor |
|---------|--------|
| `## Two ways to work` | `#two-ways-to-work` |
| `## Team configuration` | `#team-configuration` |
| `## In-chat permission cards` | `#in-chat-permission-cards` |
| `## Discover, reuse, and publish` | `#discover-reuse-and-publish` |
| `## Workspace & built-in IDE` | `#workspace--built-in-ide` |
| `### Git worktrees` | `#git-worktrees` |
| `### CLI presets` | `#cli-presets` |
| `### Skills / MCP / plugins` | `#skills-mcp--plugins` |
| `### Built-in IDE features` | `#built-in-ide-features` |
| `## Provider management` | `#provider-management` |
| `## Automations` | `#automations` |
| `## Remote agents & Android` | `#remote-agents--android` |

---

### Task 1: Create `docs/features.md`

**Files:**
- Create: `docs/features.md`

**Interfaces:**
- Consumes: current `README.md` content (migration source, on disk).
- Produces: the anchor set in the Anchor contract above; Tasks 3–5 link to these.

- [ ] **Step 1: Build the document from migrated + new content**

Create `docs/features.md` with this exact structure. Migrated sections are copied from current `README.md` with only the link-path edits noted; new sections use the text written out below.

````markdown
# TeamPilot features

Detailed companion to the [README](../README.md). Covers what each feature does
and where it is configured.

## Two ways to work

<copy current README.md lines 10–22 ("## Two ways to work" section, table +
"Simple mode is not stripped-down" bullets) verbatim>

## Team configuration

<copy current README.md lines 24–55 ("## Core feature: team configuration"
section incl. the pieces table, "### Per-member model tiers: save tokens, split
the work" and its tier table + prose, and the "Typical workflows" bullets).
Rename the heading from "Core feature: team configuration" to "Team
configuration"; keep "### Per-member model tiers: save tokens, split the work"
and "### Typical workflows" as `###` subsections>

## In-chat permission cards

Agents ask before they act — running a command, editing a file, finishing a
plan. TeamPilot surfaces these requests as a card in the chat: answer **Yes**,
**Yes, always** (with multiple always-options where the CLI offers them), or
**No** without grabbing the member's terminal. Currently supported for the
Claude-family CLIs; support for other CLIs is expanding.

## Discover, reuse, and publish

<copy current README.md lines 57–68 ("### Discover, reuse, and publish" section,
table + resources paragraph). Promote the heading to `##`. Change the
`[resources/](resources/)` link to `[../resources/](../resources/)`

## Workspace & built-in IDE

<copy current README.md lines 70–72 intro paragraph of "## Workspace & built-in
IDE" verbatim>

### Git worktrees

<copy current README.md lines 74–85 ("### Git worktree" section) verbatim,
retitled "Git worktrees">

### CLI presets

<copy current README.md lines 87–97 ("### CLI presets" section) verbatim>

### Skills / MCP / plugins

<copy current README.md lines 99–109 ("### Skills / MCP / plugins: global
library + cross-CLI reuse" section) verbatim, retitled "Skills / MCP / plugins">

### Built-in IDE features

<copy current README.md lines 111–123 ("### Built-in IDE features" section,
module table + closing line) verbatim>

## Provider management

Each CLI has its own provider catalog (`/providers/:cli/…`): add provider
entries with model and reasoning-effort maps, keep credentials on their own
dedicated rows, and trigger official login flows per entry. Personal launch
identities store a provider + model + effort map per CLI, so several models per
tool can coexist and the active one switches without global retuning.

## Automations

Per-workspace automation rules (`automations/automations.json`) store
landing-aligned launch params (identity, preset, team, expert, folder,
dangerously-skip-permissions) and fire on a schedule via the automation
scheduler — launch a team or solo agent without opening the app UI.

## Remote agents & Android

Desktop agents run in a local PTY by default; switch to SSH in settings to run
them on a remote host, or point the CLI path / app data at WSL on Windows.
Android has no local PTY: the Android app connects over SSH to a machine that
already has your agent CLI installed.

## Storage layout

Session config inheritance (app → identity → workspace → session), workspaces,
sessions, launch profiles, and worktrees live under a documented tree — see
[workspace storage layout](workspace-storage-layout.md).
````

Additional migration edits while copying:
- Any `[Development guide](docs/DEVELOPMENT.md)` style link becomes `(DEVELOPMENT.md)` (same directory now).
- `[workspace storage layout](docs/workspace-storage-layout.md)` becomes `(workspace-storage-layout.md)`.

- [ ] **Step 2: Verify anchors and links**

Run from repo root:

```bash
grep -n '^#' docs/features.md
```

Expected: every heading in the Anchor contract appears with exact spelling.
Then check relative links resolve:

```bash
test -f docs/workspace-storage-layout.md && test -f README.md && test -d resources && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/features.md
git commit -m "docs: add detailed features guide (migrated from README)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create `docs/features.zh.md`

**Files:**
- Create: `docs/features.zh.md`

**Interfaces:**
- Consumes: `docs/features.md` (Task 1) as structural source; current `README.zh.md` sections as ZH migration source.

- [ ] **Step 1: Write the mirrored Chinese document**

Mirror `docs/features.md` section-for-section (same headings translated, same anchor slugs will differ in Chinese — that's fine, no one links to ZH anchors). Migration sources in current `README.zh.md`:

| Target section | Source section in current `README.zh.md` |
|----------------|------------------------------------------|
| 两种用法 | `## 两种用法` (lines 10–22) |
| 团队配置 | `## 核心功能：团队配置` incl. `### 按成员隔离模型：省 Token、分档协作` and 典型工作流 bullets (lines 24–55), retitle to `## 团队配置` |
| 发现、复用与发布 | `### 发现、复用与发布` (lines 57–68), promote to `##` |
| 工作区与内置 IDE | intro of `## 工作区与内置 IDE` (lines 70–72) |
| Git Worktree | `### Git Worktree` (lines 74–85) |
| CLI 预设 | `### CLI 预设` (lines 87–97) |
| 技能 / MCP / 插件 | `### 技能 / MCP / 插件：全局库 + 跨 CLI 复用` (lines 99–109), retitle `### 技能 / MCP / 插件` |
| 内置 IDE 能力 | `### 内置 IDE 能力` (lines 111–123) |

New sections translated from the Task 1 English text (natural Chinese, not literal):

- `## 会话内权限卡片` — Claude 系 CLI 支持，卡片上回答 是 / 总是 / 否，无需切到终端。
- `## Provider 管理` — 每个 CLI 独立的 provider 目录、按条目专用凭据行、官方登录流程；个人身份为每个 CLI 保存 provider + 模型 + 推理强度映射。
- `## 自动化` — 每工作区的自动化规则（`automations/automations.json`），按计划调度启动团队或单体智能体。
- `## 远程智能体与 Android` — 桌面默认本地 PTY，可切 SSH / WSL；Android 通过 SSH 连接已装好 CLI 的机器。
- `## 存储布局` — 指向 `workspace-storage-layout.md` 的链接。

Apply the same link-path edits as Task 1 (`[resources/](resources/)` → `[../resources/](../resources/)`, `docs/…` → same-directory).

- [ ] **Step 2: Verify mirror structure**

```bash
diff <(grep -c '^#' docs/features.md) <(grep -c '^#' docs/features.zh.md) && echo MIRROR-OK
```

Expected: `MIRROR-OK` (same heading count).

- [ ] **Step 3: Commit**

```bash
git add docs/features.zh.md
git commit -m "docs: add Chinese features guide

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Rewrite `README.md` as landing page

**Files:**
- Modify: `README.md` (full rewrite)

**Interfaces:**
- Consumes: anchors from Task 1 (Anchor contract); install commands / CLI table / community links from current `README.md`.

- [ ] **Step 1: Replace README.md with the landing page**

Use exactly this content (line ~100):

````markdown
# TeamPilot

[![License](https://img.shields.io/badge/License-AGPL%20v3.0-blue.svg)](LICENSE)
[![Releases](https://img.shields.io/github/v/release/hhoao/teampilot)](https://github.com/hhoao/teampilot/releases)

[简体中文](README.zh.md) · [Detailed features](docs/features.md) · [Development guide](docs/DEVELOPMENT.md)

**TeamPilot is the workbench for terminal AI coding agents.** Chat with Claude
Code, Codex, opencode, cursor-agent, or flashskyai — with a built-in file tree,
code editor, Git panel, and multi-agent teams in one window, locally or over
SSH.

![App preview](assets/image.png)
![App preview](assets/image1.png)

*The screenshots above are slightly outdated — the UI keeps evolving.*

## Why TeamPilot?

### One window, full workbench

Jumping between an IDE and a terminal of agent chats breaks your flow.
TeamPilot puts the file tree, a multi-tab code editor, and a VS Code–style Git
panel — diffs, commits, AI-generated commit messages — right next to the
embedded agent terminals, all on the same working directory.
[→ Workspace & IDE](docs/features.md#workspace--built-in-ide)

### Multi-agent teams, tiered per member

Running one model for everything either burns premium tokens on trivial edits
or underpowers planning and review. Define a team once and launch **one
terminal per member**, each with its own model, provider, system prompt — and
in mixed teams, its own CLI — coordinating through a built-in team bus.
[→ Team configuration](docs/features.md#team-configuration)

### Bring your own agents

Every CLI wants its own MCP servers, skills, and credentials, on every machine.
TeamPilot manages five agent CLIs in one GUI, provisions capabilities into each
tool's native format at launch, and runs them on a local PTY, WSL, or SSH —
from desktop all the way to an Android tablet.
[→ Skills / MCP / plugins](docs/features.md#skills-mcp--plugins)

## Features

| Feature | What it does |
|---------|--------------|
| [Workspaces & sessions](docs/features.md#two-ways-to-work) | Organize work by repo folder and conversation, with the selected identity bound to each session. |
| [Built-in IDE](docs/features.md#built-in-ide-features) | File tree, multi-tab editor, Git panel with diff view and AI commit messages — next to agent terminals. |
| [Git worktrees](docs/features.md#git-worktrees) | Parallel feature branches with their own checkouts; sessions grouped by worktree in the sidebar. |
| [In-chat permission cards](docs/features.md#in-chat-permission-cards) | Answer agent permission requests (yes / always / no) without leaving the chat. |
| [Multi-agent teams](docs/features.md#team-configuration) | Native or mixed-CLI teams; per-member model, provider, prompt, and machine placement. |
| [Team Hub & Expert Hub](docs/features.md#discover-reuse-and-publish) | Browse, clone, and publish shareable team and expert templates. |
| [Skills · MCP · plugins](docs/features.md#skills-mcp--plugins) | Global library mounted per identity/workspace, written into every CLI's format on launch. |
| [CLI presets](docs/features.md#cli-presets) | Named CLI + provider + model + effort combos; switch with one click. |
| [Provider management](docs/features.md#provider-management) | Per-CLI provider catalogs with per-entry credentials and official login flows. |
| [Automations](docs/features.md#automations) | Schedule per-workspace launch rules to run teams or solo agents automatically. |
| [Remote agents](docs/features.md#remote-agents--android) | Run agents over SSH or WSL from the desktop; Android connects over SSH. |

More detail on every feature: [docs/features.md](docs/features.md).

## Quick start

1. Download the latest [GitHub Release](https://github.com/hhoao/teampilot/releases) for your system.
2. Install and launch **TeamPilot**.
3. Make sure your agent CLI (e.g. Claude Code) is on the login shell **PATH** on the machine where agents run — first launch can detect it, or set the path under **Settings → Session**. Then open a workspace and start chatting.

<details>
<summary>Linux (deb / AppImage)</summary>

```bash
sudo dpkg -i teampilot-*-linux.deb
# If dependencies are missing:
sudo apt install -f
```

AppImage: `chmod +x teampilot-*-linux.AppImage && ./teampilot-*-linux.AppImage`
(requires `libfuse2` on many distros).

</details>

<details>
<summary>macOS</summary>

Open `teampilot-*-macos.dmg` and drag **TeamPilot** into **Applications**. If
Gatekeeper blocks the first launch, allow it under **System Settings → Privacy
& Security** or right-click the app → **Open**.

</details>

<details>
<summary>Windows</summary>

`*-windows-setup.exe` (recommended), `*.msix`, or portable `*.zip` — all from
the same release. If your CLI lives in **WSL**, point app data or the CLI path
at WSL in settings.

</details>

<details>
<summary>Android</summary>

Android does **not** run a local PTY — connect over **SSH** to a machine that
already has your agent CLI installed. Install
`teampilot-*-arm64-v8a.apk` (most phones) or `*-armeabi-v7a.apk`, then
configure the SSH host, user, and key in **Settings**.

</details>

## Supported agents

| CLI | Notes |
|-----|-------|
| **Claude Code** | Default team CLI; onboarding can detect/install. |
| **Codex** | Launchable; joins mixed teams via the team bus. |
| **opencode** | Config via `OPENCODE_CONFIG_DIR`. |
| **cursor** | `cursor-agent`; HOME-isolated per member. |
| **flashskyai** | Path resolved at startup. |

## Documentation

| Doc | Topic |
|-----|-------|
| [Feature guide](docs/features.md) | Detailed walkthrough of every feature (start here) |
| [Development guide](docs/DEVELOPMENT.md) | Setup, run, test, package, CI |
| [AGENTS.md](AGENTS.md) | Repo layout, architecture, conventions |
| [Workspace storage layout](docs/workspace-storage-layout.md) | On-disk paths under `<teampilotRoot>` |

## Terminal

Embedded terminals use **[flutter_alacritty](https://github.com/hhoao/flutter_alacritty)** — a Flutter widget backed by an Alacritty-based Rust engine.

## Acknowledgements

- File icons: [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) (MIT) by Philipp Kief / material-extensions.

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).

## Community

| Channel | Link |
|---------|------|
| **QQ group** | `1016450915` |
| **Discord** | [Join the server](https://discord.com/channels/1518523215767666719/1518523216912449669) |

Questions, usage tips, and feedback are welcome.
````

- [ ] **Step 2: Verify line count and anchors**

```bash
wc -l README.md   # expect ~100–120
grep -o 'docs/features.md#[a-z-]*' README.md | sort -u
```

Then confirm each slug printed above exists as a heading in `docs/features.md` (Task 1's anchor set).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as workbench landing page

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Rewrite `README.zh.md` as mirror

**Files:**
- Modify: `README.zh.md` (full rewrite)

**Interfaces:**
- Consumes: Task 3's `README.md` as source of truth for structure and content.

- [ ] **Step 1: Write the Chinese mirror**

Mirror `README.md` section-for-section: same heading order, badges line, screenshot block + outdated note, three `###` sell-point paragraphs, feature matrix (same rows; the detail-column links point at `docs/features.zh.md` instead of `docs/features.md`), Quick start with the same `<details>` blocks (install commands copied verbatim from current `README.zh.md` lines 143–195), supported-agents table (from current `README.zh.md` `## 支持的 CLI`), docs table (add 特性指南 → `docs/features.zh.md` first row; keep the rest), terminal / acknowledgements / license / community sections translated as in current `README.zh.md`.

Section titles in Chinese:

- `## 为什么选择 TeamPilot？` — subsections `### 一个窗口，完整工作台`、`### 多智能体团队，按成员分级`、`### 用你自己的智能体`
- `## 功能`、`## 快速开始`、`## 支持的智能体`、`## 文档`、`## 终端`、`## 致谢`、`## 许可证`、`## 社区`

Hero line (adapt, keep natural):

> **TeamPilot 是终端 AI 编程智能体的工作台。** 在同一个窗口里与 Claude
> Code、Codex、opencode、cursor-agent、flashskyai 对话——内置文件树、代码
> 编辑器、Git 面板和多智能体团队，本地或 SSH 皆可。

- [ ] **Step 2: Verify mirror structure and line count**

```bash
grep -c '^#' README.md    # expect 13
grep -c '^#' README.zh.md # expect 13 — identical heading count
wc -l README.zh.md        # expect ~100–120, same ballpark as README.md
```

Also confirm all install commands and URLs are byte-identical to the current `README.zh.md` (before rewrite).

- [ ] **Step 3: Commit**

```bash
git add README.zh.md
git commit -m "docs: rewrite Chinese README as workbench landing page

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Update `AGENTS.md` index and final verification

**Files:**
- Modify: `AGENTS.md` (docs table near the top)

**Interfaces:**
- Consumes: existence of `docs/features.md` / `docs/features.zh.md` from Tasks 1–2.

- [ ] **Step 1: Add the features row to the docs table**

In `AGENTS.md`'s `| Docs | Purpose |` table, insert directly after the README row:

```markdown
| [docs/features.md](docs/features.md) (English) / [docs/features.zh.md](docs/features.zh.md) (简体中文) | User-facing feature guide — detailed companion to the README |
```

- [ ] **Step 2: Run the full verification checklist**

```bash
# 1. No stale self-references left in READMEs (old section names should be gone)
! grep -n 'Two ways to work\|Core feature: team configuration' README.md
# 2. All repo-relative link targets exist
for f in $(grep -o '](docs/[a-z-]*\.md' README.md README.zh.md | cut -d: -f3 | tr -d '](' | sort -u); do test -f "$f" || echo "MISSING $f"; done
# 3. Line targets
wc -l README.md README.zh.md   # both ~100–120
# 4. Analyze still clean (docs-only change must not affect it)
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no output from 1 and 2, line counts in range, analyze exits 0.

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: index feature guide in AGENTS.md docs table

Co-Authored-By: Claude <noreply@anthropic.com>"
```
