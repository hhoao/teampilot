# TeamPilot

[简体中文](README.zh.md) · [Development guide](docs/DEVELOPMENT.en.md) · Architecture & AI: [CLAUDE.md](CLAUDE.md)

**TeamPilot** is a desktop client based on terminal AI Agent Team. Its centerpiece is **team capabilities**: assign **a model per member** for tiered collaboration (save tokens, implement fast, review accurately), plus roles, prompts, skills, and plugins in the GUI—then launch **one embedded terminal per member** that talks to agents through the **`flashskyai`** or **`claude`** CLI locally or over SSH. Projects and sessions attach that team to a repo and conversation.

| Name | Meaning |
|------|---------|
| Product | **TeamPilot** (window title, installers) |
| Package / data ID | `com.hhoa.teampilot` (Dart package `teampilot`) |
| Primary CLI | **`flashskyai`** (recommended; PATH or explicit path) |
| Version | See [`client/pubspec.yaml`](client/pubspec.yaml) |

![App preview](assets/image.png)

## Core feature: team configuration

Team configuration is what sets TeamPilot apart from a single terminal and hand-typed flags: **define the team first, then work in parallel from the chat workbench**.

| Piece | Purpose |
|-------|---------|
| **Team** | A full multi-agent preset: pick `flashskyai` / `claude` (etc.), team-level CLI options, and the skills/plugins bound to this team only. |
| **Member** | A role inside the team (e.g. `team-lead`, developer, reviewer): **its own** model, provider, system prompt, and launch flags. Connecting a session **spawns a separate PTY per member**—models and context do not mix. |
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
- **Parallel roles**: `team-lead` coordinates and delegates (FlashSky AI expects a member named exactly `team-lead`); other members handle implementation, review, etc.—switch terminals in one window.
- **Scenario presets**: Maintain teams for “daily dev”, “deep refactor”, “docs”—switch teams instead of retyping models and prompts.
- **Session binding**: Opening a project session injects the active team into CLI args (e.g. `--team` / `--member`, per-member `CONFIG_DIR`) and can resume prior CLI sessions.

Configure under **Settings → Team configuration** (route `/team-config`). Team JSON lives under `teams/` in app data; per-member runtime CLI dirs under `config-profiles/teams/<team>/members/…`.

## Why TeamPilot?

### Skills & plugins (team-scoped)

- **Skills**: Browse, install, and enable in one place; when mounted **on a team**, every member terminal in that team shares the same capabilities.
- **Plugins**: Visual install and management; agree per team which extensions a project uses so environments stay aligned.

### Chat workbench

- **Multi-tab terminal**: Several members and/or sessions in one window instead of many OS terminal tabs.
- **Projects & sessions**: Organize by repo and chat, with the **selected team** bound to that work.
- **Auto session titles**: See what each chat is about in the sidebar.
- **Right tools panel**: File tree, member list, and prompts next to the chat with less context switching.

### Settings & integrations

- **RTK (optional)**: Can be enabled in settings to reduce session overhead and stretch usable context.

## Installation

Open the latest [GitHub Release](https://github.com/hhoa/flashskyai-ui/releases) and download the asset for your system (names look like `teampilot-<version>-…`).

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

Android does **not** run a local PTY. You connect over **SSH** to a machine that already has `flashskyai` / `claude`.

1. Download `teampilot-*-arm64-v8a.apk` (most phones) or `teampilot-*-armeabi-v7a.apk`.
2. Allow installs from unknown sources, then install the APK.
3. In **Settings**, configure SSH host, user, and key (or password).
4. On the remote host, ensure the CLI is installed and works in the shell you get after SSH login.

## Supported CLIs

| CLI | Terminal sessions | Provider config | Notes |
|-----|-------------------|-----------------|-------|
| **flashskyai** | Yes | Yes | Default team CLI; path resolved at startup. |
| **claude** | Yes | Yes | Onboarding can detect/install. |
| **codex** | No | Yes | Provider catalog only; PTY launch not supported yet. |

## Before you start

After [installation](#installation), on the machine where agents actually run (local desktop, or the SSH host on Android):

| Item | Notes |
|------|--------|
| **`flashskyai`** | On the login shell **PATH**, or set the CLI path under **Settings → Session** |
| **`claude`** | Optional; needed for Claude teams or first-run onboarding |

First launch can run the built-in CLI detection. Installers are built by CI; building from source: **[Development guide](docs/DEVELOPMENT.en.md)**.

## More documentation

| Doc | Audience | Topic |
|-----|----------|--------|
| [Development guide](docs/DEVELOPMENT.en.md) | Contributors / maintainers | Setup, run, test, package, CI |
| [CLAUDE.md](CLAUDE.md) | Contributors / AI | Repo layout, data dirs, architecture |

## Terminal

Embedded terminals use **[flutter_alacritty](https://github.com/hhoao/flutter_alacritty)** — a Flutter widget backed by an Alacritty-based Rust engine .

## License

This project is licensed under the [MIT License](LICENSE).
