# TeamPilot

[简体中文](README.zh.md) · [Development guide](docs/DEVELOPMENT.md) · Architecture & AI: [AGENTS.md](AGENTS.md)

**TeamPilot** is a desktop client based on terminal AI Agent Team. Its centerpiece is **team capabilities**: assign **a model — and even a different CLI — per member** for tiered collaboration (save tokens, implement fast, review accurately), plus roles, prompts, skills, and plugins in the GUI—then launch **one embedded terminal per member** that talks to agents through Claude Code, Codex, opencode, cursor, or flashskyai, locally or over SSH. Projects and sessions attach that team to a repo and conversation.

![App preview](assets/image.png)
![App preview](assets/image1.png)

## Two ways to work

| Mode | When | What you get |
|------|------|--------------|
| **Simple mode** (personal) | You just want one agent in a repo | Skip the team roster—launch a **single CLI** and start chatting. No member list to build. |
| **Team mode** | Multi-agent / tiered or mixed-CLI collaboration | Define a team once, then run **one terminal per member** in parallel. This is TeamPilot's centerpiece (below). |

**Simple mode is not stripped-down.** A personal project still gives you the full per-project config—you just skip the multi-member roster:

- **Multiple CLIs and models, switchable.** Each CLI (Claude Code, Codex, opencode, cursor, flashskyai) keeps **its own provider + model + reasoning-effort** in the project, so you can configure several models per tool and switch the active CLI/model without retuning globally—the same tiering benefit as teams, for a single agent.
- **CLI presets**: Save frequent CLI + model combos as named presets and switch with one click. 
- **Per-project agent, skills, plugins, MCP, and extensions**—the personal project carries its own prompt and capability set; skills / MCP / plugins are installed once in the global library and shared across CLIs.
- **A permanent built-in *Personal assistant* project**, plus any personal projects you create, all alongside your team projects—start simple and graduate to a team when a task needs it.

## Core feature: team configuration

Team configuration is what sets TeamPilot apart from a single terminal and hand-typed flags: **define the team first, then work in parallel from the chat workbench**.

| Piece | Purpose |
|-------|---------|
| **Team** | A full multi-agent preset: pick a coordination mode (single-CLI **native** team, or **mixed** cross-CLI), team-level CLI options, and the skills/plugins bound to this team only. |
| **Member** | A role inside the team (e.g. `team-lead`, developer, reviewer): **its own** model, provider, system prompt, launch flags—and, in mixed mode, its own CLI. Connecting a session **spawns a separate PTY per member**—models and context do not mix. |
| **Skills / plugins** | Capabilities attached per team; at launch they are written into an isolated CLI config tree that member terminals inherit. |

### Per-member model tiers: save tokens, split the work

Using one model for everything either burns premium tokens on trivial edits or underpowers planning and cross-checking. TeamPilot lets **each member run a different model tier** in parallel—mixing capability, speed, and cost in the same team:

| Role (example) | Typical tier | Good for |
|----------------|--------------|----------|
| Lead / planning | High (e.g. Opus, flagship) | Requirements, design docs, scope and acceptance criteria |
| Implementation | Fast / light (e.g. Haiku, small models) | Bulk edits, scaffolding, getting the happy path working |
| Review | Mid (e.g. Sonnet) | Code review, gap checks against the plan, cross-file consistency |

This is not coding-only: docs, research, ops triage, or any **multi-step pipeline** can use the same pattern—strong models to **think and specify**, light models to **execute quickly**, mid-tier models to **verify and align cross-cutting constraints**—so you spend less on tokens, ship faster, and hit complex **cross-module / cross-functional** goals without one chat playing architect, worker, and QA at once.

**Typical workflows:**

- **Tiered models**: Set different providers/models for `team-lead`, implementer, and reviewer; switch member tabs to switch terminal and model—no global retuning each time.
- **Parallel roles**: `team-lead` coordinates and delegates (Claude Code expects a member named exactly `team-lead`); other members handle implementation, review, etc.—switch terminals in one window.
- **Mixed CLIs**: In a **mixed** team, members can run different CLIs (Claude Code, Codex, opencode, cursor, flashskyai) and still coordinate through an in-process team bus—use each tool where it's strongest.
- **Scenario presets**: Maintain teams for “daily dev”, “deep refactor”, “docs”—switch teams instead of retyping models and prompts. Browse and import shareable team templates from the built-in **Team Hub**.
- **Session binding**: Opening a project session injects the active team into CLI args (e.g. `--team-name` / per-member session id, per-member `CONFIG_DIR`) and can resume prior CLI sessions.

Configure under **Settings → Team configuration** (route `/team-config`). Team JSON lives under `teams/` in app data; per-member runtime CLI dirs under `config-profiles/teams/<team>/members/…`.

## Workspace & built-in IDE

TeamPilot is more than “several agent terminals in one window”—you can browse the repo, edit files, review diffs, and commit Git in the same UI, side by side with embedded terminals. The workspace sidebar groups sessions by **worktree**; the right tools panel offers a file tree, source control, members, mailbox, and more—less hopping between an IDE and a terminal.

### Git worktree

For workspaces bound to a Git repo, TeamPilot supports a native **git worktree** workflow (desktop local / WSL; create/remove is not available over SSH / Android):

| Capability | What it does |
|------------|--------------|
| **Group by branch** | Sidebar sessions fold under each worktree; selecting a branch switches the active working directory—the file tree and Git panel follow. |
| **Create worktree** | Spin off a new branch or check out an existing one; the default path is `worktrees/<repo>/<branch>` under app data, adjustable in the dialog. |
| **Remove worktree** | Optional force (when there are uncommitted changes), optional branch deletion, optional deletion of sessions under that worktree. |
| **Start chatting** | Optionally “start a conversation here” after creation to launch an agent in the new worktree immediately. |

Useful for parallel feature branches or giving each agent session its own checkout without disturbing the main tree.

### CLI presets

A **preset** saves “which CLI + which provider / model / reasoning-effort” as a reusable named profile so you do not re-pick everything each time you chat:

| Context | How to use |
|---------|------------|
| **Personal workspace** | Pick the **active preset** on the **Agent** config page; the preset sets the default CLI and model tier, while per-CLI provider + model + effort maps remain available for fine-tuning. |
| **Team** | Teams can assign a **default preset** per member; in **native** mode presets are usually locked to the team CLI, in **mixed** mode members can use presets for different CLIs. |
| **Manage** | The **Manage presets** dialog creates, edits, and deletes entries—each with name, CLI, provider, model, and effort. |

Typical pattern: presets for “quick edits”, “deep planning”, and “cheap bulk work”—switch tasks without touching global provider settings.

### Skills / MCP / plugins: global library + cross-CLI reuse

Capabilities use a **two-layer model**—install and enable in the app-level **global library**, then **check the ones you want** on a workspace / team identity; at session launch TeamPilot writes each target CLI’s isolated config in that tool’s format, so the **same checked list** works for Claude Code, Codex, opencode, cursor, flashskyai, and every other supported CLI:

| Layer | Role |
|-------|------|
| **Global library** | Browse, install, and enable skills, plugins, and MCP server definitions from the home sidebar or `/skills`, `/plugins`, `/mcp`. |
| **Identity / workspace mount** | A personal or team identity’s `ConfigBundle` stores `skillIds` / `pluginIds` / `mcpServerIds`; personal and team workspace config pages let you toggle a subset. |
| **Per-CLI provisioning** | Each CLI uses registry writers / provisioners for its format (e.g. Claude-shaped `mcpServers`, Codex TOML, opencode config dirs); member terminals inherit on launch. |

**Maintain the library once**—no reinstalling the same MCP for every CLI. Switch CLIs or run a mixed team: keep the same capability selection on the identity and TeamPilot materializes per-tool configs. **Extensions** have a separate install/enable flow, keyed by identity id.

### Built-in IDE features

The right tools panel and editor area provide common IDE workflows on the same working directory as agent terminals. Disk changes refresh the file tree and Git status (live watch on local / WSL; polling on SSH after agent turns, etc.):

| Module | Features |
|--------|----------|
| **File tree** | Browse the workspace; multi-root folders (VS Code–style fold headers), filter, new file/folder, copy/cut/paste, rename, delete, copy path, open with system app, **reveal active editor file**. |
| **Code editor** | Multi-tab embedded editor based on **re-editor**; open from the file tree or Git diff, dirty markers for unsaved edits, save prompt on close. |
| **Source control (Git)** | VS Code–style change list: stage / unstage, stage by file or folder, discard, branch switch, inline **diff view** (syntax highlight + hunk navigation), commit message + **commit**; ✨ **AI-generated commit messages** for staged changes (configurable in settings). |
| **Workspace search** | Sidebar search across session titles and file contents—jump to a chat or file quickly. |
| **Team collaboration panels** | In team mode: **members** list, **mailbox** (TeamBus messages), and **board** (mixed-team task status; tap a card to open that member’s terminal). |

Personal workspaces default to file tree + Git; team workspaces add members, mailbox, board, and related collaboration views.

## Why TeamPilot?

### Skills & plugins

- **Skills**: Install and enable in the **global library**; when mounted on a personal identity or team, every member terminal under that identity shares the same capabilities.
- **Plugins**: Visual install and management; check which plugins to enable in workspace / team config—written into each CLI’s directory on launch so environments stay aligned.

### Chat workbench

- **Multi-tab terminal**: Several members and/or sessions in one window instead of many OS terminal tabs.
- **Projects & sessions**: Organize by repo and chat, with the **selected team** bound to that work.
- **Auto session titles**: See what each chat is about in the sidebar.
- **Right tools panel**: File tree, Git, member list, and prompts next to the chat with less context switching.

### Settings & integrations

- **RTK (optional)**: Can be enabled in settings to reduce session overhead and stretch usable context.

## Installation

Open the latest [GitHub Release](https://github.com/hhoao/teampilot/releases) and download the asset for your system (names look like `teampilot-<version>-…`).

### Linux

**Debian / Ubuntu (`.deb`, recommended)**

```bash
sudo dpkg -i teampilot-*-linux.deb
# If dependencies are missing:
sudo apt install -f
```

Launch **TeamPilot** from the app menu. Uninstall: `sudo apt remove flashskyai-client` (exact package name is in the deb metadata).

**AppImage (portable)**

```bash
chmod +x teampilot-*-linux.AppImage
./teampilot-*-linux.AppImage
```

Requires `libfuse2` on many distros (`sudo apt install libfuse2` on Ubuntu 22.04+). For menu/Dock integration, use [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher).

On desktop, agents run in a **local PTY** by default. You can switch to **SSH** in settings so the CLI runs on a remote host.

### macOS

1. Download `teampilot-*-macos.dmg`.
2. Open the DMG and drag **TeamPilot** into **Applications**.
3. If Gatekeeper blocks the first launch: allow it under **System Settings → Privacy & Security**, or right‑click the app → **Open**.

### Windows

Pick one artifact from the same release:

| File | Notes |
|------|--------|
| `*-windows-setup.exe` | **Recommended**: Inno Setup installer with shortcuts |
| `*.msix` | For sideloading / managed deployment |
| `*.zip` | Portable: extract and run `TeamPilot.exe` |

If your CLI lives in **WSL**, point app data or the CLI path at WSL in settings. **SSH** to a remote Linux dev box is also supported.

### Android

Android does **not** run a local PTY. You connect over **SSH** to a machine that already has your agent CLI installed.

1. Download `teampilot-*-arm64-v8a.apk` (most phones) or `teampilot-*-armeabi-v7a.apk`.
2. Allow installs from unknown sources, then install the APK.
3. In **Settings**, configure SSH host, user, and key (or password).
4. On the remote host, ensure the CLI is installed and works in the shell you get after SSH login.

## Supported CLIs

| CLI | Terminal sessions | Provider config | Notes |
|-----|-------------------|-----------------|-------|
| **Claude Code** | Yes | Yes | Default team CLI; onboarding can detect/install. |
| **Codex** | Yes | Yes | Launchable; joins mixed teams via the team bus. |
| **opencode** | Yes | Yes | Config via `OPENCODE_CONFIG_DIR`. |
| **cursor** | Yes | Yes | `cursor-agent`; HOME-isolated per member. |
| **flashskyai** | Yes | Yes | Path resolved at startup. |

## Before you start

After [installation](#installation), on the machine where agents actually run (local desktop, or the SSH host on Android):

| Item | Notes |
|------|--------|
| **Your agent CLI** | Whichever CLI your team uses (Claude Code, Codex, opencode, cursor, flashskyai) on the login shell **PATH**, or set the CLI path under **Settings → Session** |

First launch can run the built-in CLI detection. Installers are built by CI; building from source: **[Development guide](docs/DEVELOPMENT.md)**.

## More documentation

| Doc | Audience | Topic |
|-----|----------|--------|
| [Development guide](docs/DEVELOPMENT.md) | Contributors / maintainers | Setup, run, test, package, CI |
| [AGENTS.md](AGENTS.md) | Contributors / AI | Repo layout, data dirs, architecture |

## Terminal

Embedded terminals use **[flutter_alacritty](https://github.com/hhoao/flutter_alacritty)** — a Flutter widget backed by an Alacritty-based Rust engine .

## Acknowledgements

- File icons: [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) (MIT) by Philipp Kief / material-extensions.

## License

This project is licensed under the [MIT License](LICENSE).

## Community

| Channel | Link |
|---------|------|
| **QQ group** | `1016450915` |
| **Discord** | [Join the server](https://discord.com/channels/1518523215767666719/1518523216912449669) |

Questions, usage tips, and feedback are welcome.
