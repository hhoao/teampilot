# AGENTS.md

Guidance for Claude Code and other AI assistants working in this repository.

**TeamPilot** is a Flutter client (`client/`, package `teampilot`, data ID `com.hhoa.teampilot`) that manages **workspaces**, **team launch identities**, sessions, skills, plugins, and extensions, and embeds terminals running AI agent CLIs (local PTY on desktop, or SSH — always on Android, optional on desktop). The home UI is an Apifox-style workspace shell with a built-in IDE (file tree, editor, Git, worktrees).

| Docs | Purpose |
|------|---------|
| [README.md](README.md) (English) / [README.zh.md](README.zh.md) (简体中文) | User-facing |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Clone, commands, tests, packaging, CI |
| [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) | File size, layering, tests, Extension conventions |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | Systematic debugging process |
| [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) | DevTools performance JSON offline analysis (`tool/analyze_performance_json.dart`) |
| [docs/workspace-storage-layout.md](docs/workspace-storage-layout.md) | On-disk layout under `<teampilotRoot>` |

All app code lives under `client/lib/` (cubits, pages, repositories, services, models). Vendored deps: `client/packages/` (git submodules: xterm, flutter_pty_new, dartssh2, re-editor, flutter_alacritty, **shared_ui**). Cross-route UI primitives live in **`shared_ui`** as the **Tp** design system (`TpButton`, `TpInput`, `TpTheme`, …); see [client/packages/shared_ui/README.md](client/packages/shared_ui/README.md).

## Core concepts

| Concept | Model / cubit | Role |
|---------|---------------|------|
| **Workspace** | `Workspace`, `SessionRepository` | *Where* work happens: repo folder(s), sessions, workspace-scoped resource bindings (`project-config.json`). |
| **Launch profile** | `TeamProfile` (`LaunchProfile`), `LaunchProfileCubit` | *Who/how* to launch a **team**: roster of expert keys, `ConfigBundle`, per-tool provider/model/effort, skills/plugins/MCP. Persisted under `launch-profiles/{id}/profile.json`. |
| **Expert** | `DiscoverableMember`, `ExpertCapabilityPack` | Capability pack: persona + `skillDeps` / `pluginDeps` / `mcpDeps`. Resolved via `ExpertCapabilityResolver` into session config. |
| **Session** | `AppSession`, `ChatCubit` | One chat workbench tab; owns member terminals, TeamBus (mixed teams), and session runtime dirs. |

**Simple mode** = unteamed launch (empty `sessionTeam`) — not a launch-identity document. Optional `AppSession.expertKey` / CLI preset selects an expert pack. **Team mode** = launch with a `TeamProfile` and one PTY per roster member. **Automations** store landing-aligned launch params (`isPersonal`, `presetId`, `teamId`, `expertKey`, `projectFolderPath`, `workingDirectoryPath`, `dangerouslySkipPermissions`) per workspace in `automations/automations.json`.

Session config merge (skills / plugins / MCP ids):

```
SessionRuntimeBundle = merge(team > expert > workspace)
```

See [docs/superpowers/specs/2026-07-10-expert-capability-pack-design.md](docs/superpowers/specs/2026-07-10-expert-capability-pack-design.md). Team identities configure members, skills, plugins, MCP, and extensions under `/team-config`.

## Architecture

### Bootstrap flow

```
main.dart
  → AppPathsBootstrapper.init()              # Application Support → AppPaths
  → TeamPilotBootstrap / buildAppShell()
      → CliToolRegistry.builtIn()             # capability-based CLI registry
      → RuntimeContextRegistry / AppStorage.bindHome()
      → CliBootstrap(...)                     # provision cli-defaults trees
      → LaunchProfileRepository, SessionRepository, SessionLifecycleService
      → TeammateBusMcpGateway.ensureStarted()
      → LaunchProfileCubit, ChatCubit, TeamHubCubit, ExpertHubCubit,
        MemberPresenceCubit, MailboxCubit, BoardCubit,
        AutomationCubit, WorkspaceTerminalRegistry, …
  → MaterialApp.router (GoRouter)
```

### State, routing, and chat

- **State:** `flutter_bloc` cubits under `client/lib/cubits/`.
- **Routing:** `client/lib/router/app_router.dart`. **[HomeShell](client/lib/pages/home_workspace/home_workspace_shell.dart)** (`home_workspace_shell.dart`) renders the title bar + open-workspace tabs; **[HomeWorkspaceBodyStack](client/lib/pages/home_workspace/home_workspace_body_stack.dart)** keeps one alive **[WorkspacePage](client/lib/pages/home_workspace/workspace/workspace_page.dart)** per tab. Initial location is `/home-v2` (or last workspace per `LayoutCubit` / `applyWorkspaceEntryMode`).
- **Chat / workbench:** `WorkspacePage` (route `/home-v2/workspace/:workspaceId`) hosts conversations + manage panes. `ChatCubit` owns tabbed `TerminalSession`s; **[SessionLaunchService](client/lib/cubits/chat/session_launch_service.dart)** handles `requestOpenSession` / `connectWorkspaceSession` / `_scheduleMemberConnect` → `SessionLifecycleService.prepareLaunch` → `TerminalSession.connect`.
- **Workspace manage config:** `WorkspaceConfigSection` = settings / skills / plugins / mcp / extensions (`workspace_config_section.dart`). Agent + provider tiering for personal identities live on the **launch profile**, not in workspace manage.

### Terminal transport

| Mode | When | Implementation |
|------|------|----------------|
| Local PTY | Desktop default | `flutter_pty_new` → `LocalPtyTransport` |
| SSH | Android always; desktop optional | `dartssh2` → `SshPtyTransport`; remote CLI via `RemoteFlashskyaiCommandBuilder` |

Embedded terminals render with **flutter_alacritty** (Alacritty-based Rust engine). Fullscreen submit uses `TerminalFullscreenInputChannel` / `TerminalFullscreenPtyPort`. See `terminal_transport_factory.dart`, `terminal_session.dart`.

### Storage and app data

`AppStorage` (`app_storage.dart`) is the control-plane facade; it binds to the home `RuntimeContext` via `RuntimeContextRegistry`. Paths: `AppStorage.paths`, `AppStorage.cwd`, `AppStorage.fs`.

| Backend | Filesystem | `cwd` / data root |
|---------|------------|-------------------|
| `native` | `LocalFilesystem` | App Support; new workspaces use `DefaultWorkspaceDirectory` (Documents), not `Directory.current` |
| `wsl` | `WslFilesystem` | WSL `$HOME`; app data `~/.local/share/com.hhoa.teampilot` in distro |
| `ssh` | `SftpFilesystem` | Remote home + remote TeamPilot app dir |

**`<teampilotRoot>`** = `AppPaths.basePath` / `AppStorage.appDataRoot`. Full tree: [docs/workspace-storage-layout.md](docs/workspace-storage-layout.md); code: `WorkspaceLayout` + `RuntimeLayout`.

**CLI config inheritance** (see `RuntimeLayout.ensure*Inherits*`): **app** (`cli-defaults/{tool}/`) → **identity** (`identities-runtime/{profileId}/{tool}/` — **team** launch profiles only; Simple skips this layer) → **workspace** (`workspace/workspaces/{id}/config/{tool}/`) → **session** (`…/sessions/{sessionId}/runtime/…`). `SessionLifecycleService` materializes the final PTY `CONFIG_DIR` from a `SessionRuntimePlan`.

### Supported CLIs

`CliTool` enum in `client/lib/models/team_config.dart` — **all five launch-supported** (PTY or SSH):

| CLI | enum value | Notes |
|-----|------------|-------|
| Claude Code | `claude` | Default team CLI; onboarding can detect/install |
| flashskyai | `flashskyai` | Path resolved at startup |
| codex | `codex` | Launchable; participates in mixed teams via TeamBus |
| opencode | `opencode` | Config via `OPENCODE_CONFIG_DIR`; provider creds in `provider.options` |
| cursor | `cursor` | `cursor-agent`; HOME-isolated; doorbell push (no `wait_for_message` block) |

Each CLI is a `CliToolDefinition` in `client/lib/services/cli/registry/tools/`, composed from **capabilities** under `registry/capabilities/`. The registry is built by `CliToolRegistry.builtIn()` and provisioned via `CliBootstrap`. **To add or change a CLI, add/extend a tool definition + capabilities here** — do not special-case CLIs across the app.

Provider catalogs: `providers/{tool}/providers.json` per CLI (`AppProviderRepository`).

### Team modes and TeamBus

`TeamMode` in `team_config.dart`:

| Mode | Meaning |
|------|---------|
| `native` | Single CLI runs its own native multi-agent team; every member uses `team.cli` |
| `mixed` | Cross-CLI team coordinated by **TeamBus**; each member may override `cli` (else falls back to `team.cli`) |

**TeamBus** (`client/lib/services/team_bus/`) is an in-process message bus: router + per-member inbox + `PresenceReducer` + `BusEffect` + `CoordinationPolicy` (default leader-star). Each mixed session owns one `TeamBus` + `TeammateBusMcpHandler`; members reach it through the app-wide **`TeammateBusMcpGateway`** — loopback HTTP (`/mcp`, `/idle`) plus a multiplexed raw-socket port for long-blocking remote relays. `TabTeamBusCoordinator.installBusForTab` registers the session; `disposeSessionBus` unregisters. Local MCP configs send `X-Session`; remote tunnels send `X-Bus-Token`. See [docs/superpowers/specs/2026-07-02-teammate-bus-mcp-gateway-design.md](docs/superpowers/specs/2026-07-02-teammate-bus-mcp-gateway-design.md).

- `effectiveForceWaitBeforeStop`: **Cursor defaults to `false`** — doorbell delivery via stdin inject + `read_messages`.
- `MemberPresenceCubit` / `MailboxCubit` / `BoardCubit` surface bus presence, messages, and task cards in the UI.

### TeamHub & Expert Hub (discoverable catalogs)

| Hub | Code | Default registry |
|-----|------|------------------|
| **Team Hub** | `client/lib/services/team_hub/`, `TeamHubCubit`, UI `pages/team_hub/` | `TeamHubRegistry` → `hhoao/teampilot` + `rootPath: team-hub` ([`team-hub/`](team-hub/)) |
| **Expert Hub** | `client/lib/services/expert_hub/`, `ExpertHubCubit`, UI `pages/expert_hub/` | `ExpertHubRegistry` → `hhoao/teampilot` + `rootPath: member-hub` ([`member-hub/`](member-hub/)) |

Both registries support a subdirectory via `rootPath` / `catalogPrefix` / `repoPath`. `Composite*Source.withDefaults(GitRegistry*Source())` merges built-ins with the remote git catalog; built-in keys (`teampilot/builtin/*`) win on collision.

**My Teams / My Experts** (`pages/my_teams/`, `pages/my_experts/`) manage local launch identities and expert personas. **Hub publish** (`services/hub_publish/`, `pages/hub_publish/`) opens a PR against the default registry when a GitHub token is configured.

### Member placement (Machines)

Workspace + landing **Machine assignment** pins each roster replica to `local` or an SSH profile. Placement writes `roster.overrides.replicas` and host targets; mixed session create omits unpinned instances from `AppSession.members` and TeamBus. Prefer **`sessionRosterMembers(session, team)`** (in `app_session.dart`) for UI / presence / materialize — do **not** re-expand stale `TeamMemberConfig.replicas` from an in-memory team after placement saves.

### Team session CLI identity

| Field | Role |
|-------|------|
| `AppSession.sessionId` | UI / routing UUID |
| `AppSession.cliTeamName` | CLI `--team-name` argument only (not a disk path) |
| `AppSession.members[]` | Per-roster `taskId` for CLI `--session-id` / `--resume` |

Session runtime dirs: `workspace/workspaces/{workspaceId}/sessions/{sessionId}/runtime/`. `cliTeamName` is allocated in `SessionRepository.createSession` via `SessionTeamCounter` (`identities-runtime/{profileId}/session-counter.json`).

### Built-in IDE, worktrees, automations

| Feature | Key paths |
|---------|-----------|
| **File tree / editor / Git** | `WorkspaceFileTreeStore`, `GitRepoStore`, `EditorCubit`, `pages/home_workspace/workspace/` right-tools panels |
| **Git worktrees** | `WorkspaceWorktreeRegistry`, `WorkspaceWorktreeStore`; disk under `<teampilotRoot>/worktrees/{repo}/{branch}`; sidebar groups sessions by worktree |
| **Workspace shell terminal** | `WorkspaceTerminalRegistry`, `WorkspaceShellConnector` — bottom-shell PTY scoped to active workspace folder |
| **Automations** | `AutomationCubit`, `AutomationScheduler`, `AutomationDispatcher`; rules per workspace under `workspace/workspaces/{id}/automations/automations.json` (launch params mirror landing compose) |
| **CLI presets** | `CliPresetsCubit`, `cli-presets.json`; Simple launch may pin a global preset; per-member `activePresetId` on `TeamMemberConfig` |

## Where to change code

| Area | Path |
|------|------|
| Entry | `client/lib/main.dart` |
| Bootstrap / DI | `client/lib/app/app_shell.dart`, `app_data_bootstrap.dart` |
| Router | `client/lib/router/app_router.dart` |
| Workspace shell / tabs | `client/lib/pages/home_workspace/` (`HomeShell`, `HomeWorkspaceBodyStack`, `WorkspacePage`) |
| Chat / sessions | `client/lib/cubits/chat_cubit.dart`, `cubits/chat/session_launch_service.dart` |
| Sessions persistence | `client/lib/repositories/session_repository.dart` |
| Launch identities (personal + team) | `client/lib/repositories/launch_profile_repository.dart`, `client/lib/cubits/launch_profile_cubit.dart` |
| Workspace project config | `client/lib/repositories/workspace_project_config_repository.dart`, `cubits/workspace_project_config_cubit.dart` |
| Team templates / hub | `client/lib/services/team_hub/`, `client/lib/cubits/team_hub_cubit.dart` |
| Expert hub | `client/lib/services/expert_hub/`, `client/lib/cubits/expert_hub_cubit.dart` |
| My Teams / My Experts | `client/lib/pages/my_teams/`, `client/lib/pages/my_experts/` |
| Hub publish | `client/lib/services/hub_publish/`, `client/lib/pages/hub_publish/` |
| Member placement | landing Machines UI + workspace member targets; `sessionRosterMembers` in `models/app_session.dart` |
| Mixed-CLI coordination | `client/lib/services/team_bus/`, `member_presence_cubit.dart`, `mailbox_cubit.dart`, `board_cubit.dart` |
| CLI registry & capabilities | `client/lib/services/cli/registry/` |
| Launch plan | `client/lib/services/session/session_lifecycle_service.dart` |
| PTY + terminal | `client/lib/services/terminal/terminal_session.dart` |
| Launch args / WSL paths | `client/lib/services/session/launch_command_builder.dart` |
| Paths / Documents default | `client/lib/services/storage/app_storage.dart` |
| Storage backend / contexts | `client/lib/services/storage/runtime_context_registry.dart`, `runtime_context_resolver.dart` |
| Storage layout | `workspace_layout.dart`, `runtime_layout.dart` |
| Worktrees | `client/lib/services/workspace/workspace_worktree_registry.dart` |
| Automations | `client/lib/services/automation/`, `client/lib/cubits/automation_cubit.dart` |
| Session title from prompt | `client/lib/utils/first_user_line_capture.dart`, `session_display_title.dart` |
| Extensions | `client/lib/services/extension/`, `extension_repository.dart`, `extension_cubit.dart` |
| Shared UI / Tp design system | `client/packages/shared_ui` — cross-route `Tp*` primitives + `TpTheme` / `TpTextStyles` / `TpFontTheme`; wrap `MaterialApp` with `TpTheme` (see package README) |
| Product / domain chrome | `client/lib/widgets/` — app-specific layout reused across routes (not new generic controls) |
| Performance snapshot CLI | `client/tool/analyze_performance_json.dart` — [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) |

**Routes** (`app_router.dart`):

- `/home-v2` — workspace home (library, identity/team config, global views via `?global=` query)
- `/home-v2?global=myTeams` / `myExperts` / `teamHub` / `expertHub` — local libraries and public catalogs (`HomeGlobalView`; optional `&team=` / `&member=` deep links via `HomeWorkspaceRoute`)
- `/home-v2?global=skills` / `plugins` / `mcp` / `extensions` / `providers` / `automations` — other home globals
- `/home-v2/workspace/:workspaceId` — workspace workbench (`?view=manage&section=…&profile=…` for config)
- `/config/*` — app settings (layout, AI features, SSH profiles, logs, …)
- `/providers/:cli/…` — per-CLI provider catalog and credential forms
- `/team-config/*` — team identity (members, skills, plugins, mcp, extensions)
- `/skills/*`, `/plugins/*`, `/extensions/*`, `/mcp/*` — global libraries (also reachable via `?global=`)

## Debugging

See [docs/DEBUGGING.md](docs/DEBUGGING.md) for the systematic debugging process (search-first, root cause over workarounds, etc.).

**UI jank / slow frames:** export a recording from DevTools Performance, then run `dart run tool/analyze_performance_json.dart <snapshot.json> --format summary` from `client/`. Full options: [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md).

## Conventions

Full guidelines: **[docs/CODE_QUALITY.md](docs/CODE_QUALITY.md)**. Summary:

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (full setup: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)).
- **Layering:** Route shells in `pages/`; **route-only** UI sections in `pages/<domain>/`; **cross-route design primitives** in `packages/shared_ui` as `Tp*`; **product/domain chrome** in `widgets/`; logic in `cubits/` + `services/` + `repositories/`; no `Process.run` or raw paths in UI; state is **`flutter_bloc` only** (not `provider`).
- **Shared UI:** New buttons, inputs, selects, dialogs, forms, etc. go in `client/packages/shared_ui` (`Tp*` + `TpTheme`). Do not add generic controls under `client/lib/widgets/`.
- **File size (soft):** page shells ~400, cubits ~500, services ~600 lines — split oversized screens into `pages/<domain>/` section files; keep `build()` free of IO.
- **Logging:** user errors → l10n; diagnostics → `AppLogger`; no `print`.
- Paths: `AppStorage` / `RuntimeContextRegistry` — never `Directory.current` for default workspace directory.
- **CLIs:** add/extend a `CliToolDefinition` + capabilities under `services/cli/registry/`; avoid scattering `if (cli == …)` checks across features.
- **Tests:** mock subprocess/filesystem via constructor injection; cubit tests that touch `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()` in `client/test/support/post_frame_test_harness.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; after ARB changes, re-run `dart run tool/gen_warmup_glyphs.dart` for `warmup_glyphs.g.dart`.
- Terminal input hooks: filter ANSI CSI sequences (`FirstUserLineCapture`, `BusUserLineCapture`).
- Do not commit `client/google_fonts/` (gitignored); run `dart run tool/sync_bundled_google_fonts.dart` when touching zh UI fonts.
- New integration tests: `@Tags(['integration'])` from `package:test` (see DEVELOPMENT.md).
- **Extension:** install/uninstall is desktop-local until design spec remote path is done; keep `ExtensionAcquisitionEngine` URL checks for `script` acquire kind.
