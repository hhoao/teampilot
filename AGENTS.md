# AGENTS.md

Guidance for Claude Code and other AI assistants working in this repository.

**TeamPilot** is a Flutter client (`client/`, package `teampilot`, data ID `com.hhoa.teampilot`) that manages teams, projects, sessions, skills, plugins, and extensions, and embeds terminals running AI agent CLIs (local PTY on desktop, or SSH — always on Android, optional on desktop).

| Docs | Purpose |
|------|---------|
| [README.md](README.md) (English) / [README.zh.md](README.zh.md) (简体中文) | User-facing |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Clone, commands, tests, packaging, CI |
| [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) | File size, layering, tests, Extension conventions |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | Systematic debugging process |

All app code lives under `client/lib/` (cubits, pages, repositories, services, models). Vendored deps: `client/packages/` (git submodules: xterm, flutter_pty, dartssh2, re-editor, flutter_alacritty).

## Architecture

### Bootstrap flow

```
main.dart
  → AppPathsBootstrapper.init()           # Application Support → AppPaths
  → TeamPilotBootstrap / buildAppShell()
      → CliToolRegistry.builtIn()          # capability-based CLI registry
      → RuntimeStorageContext.install()    # native | wsl | ssh filesystem
      → CliBootstrap(...)                  # provision CLI runtime trees
      → SessionRepository, ChatCubit, TeamCubit, TeamHubCubit,
        MemberPresenceCubit, MailboxCubit, …
  → MaterialApp.router (GoRouter)
```

### State, routing, and chat

- **State:** `flutter_bloc` cubits under `client/lib/cubits/`.
- **Routing:** `client/lib/router/app_router.dart`. The workspace is an Apifox-style home — `HomeWorkspaceShell` renders the title bar + open-project tabs; routed pages render the body. Initial location is `/home-v2`.
- **Chat / workbench:** `HomeWorkspaceProjectPage` (route `/home-v2/project/:projectId`) hosts the per-project workbench. `ChatCubit` owns tabbed `TerminalSession`s; `openSessionTab` / `_scheduleMemberConnect` → `SessionLifecycleService.prepareLaunch` → `TerminalSession.connect`.
- **Workspace scope:** `HomeWorkspaceScope { personal, team }` (`home_workspace_page.dart`). **Simple mode** = personal projects (`teamId == ''`), backed by a permanent built-in project (`AppProject.defaultPersonalId`, ensured by `SessionRepository.ensureDefaultPersonalProject`) — a single CLI, no team roster. **Team mode** = team-bound projects with a member roster. Personal projects expose the **full** config surface (`ProjectConfigSection.personalSections` = settings/agent/skills/plugins/mcp/extensions); team projects only show `settings` at project level (rest is team-level). A personal project's `ProjectProfile` (`ProjectProfileCubit`) keeps **per-tool** `providerIdsByTool` / `modelsByTool` / `effortsByTool` maps, so each CLI carries its own provider+model+effort and `setCli` switches the active one — single-agent tiering without a roster.

### Terminal transport

| Mode | When | Implementation |
|------|------|----------------|
| Local PTY | Desktop default | `flutter_pty` → `LocalPtyTransport` |
| SSH | Android always; desktop optional | `dartssh2` → `SshPtyTransport`; remote CLI via `RemoteFlashskyaiCommandBuilder` |

Embedded terminals render with **flutter_alacritty** (Alacritty-based Rust engine). See `client/lib/services/terminal/terminal_transport_factory.dart`, `terminal_session.dart`.

### Storage and app data

`RuntimeStorageContext` (`client/lib/services/storage/runtime_storage_context.dart`). Paths via `AppStorage` (`app_storage.dart`): `AppStorage.paths`, `AppStorage.cwd`, `AppStorage.fs`.

| Backend | Filesystem | `cwd` / data root |
|---------|------------|-------------------|
| `native` | `LocalFilesystem` | App Support; new projects use `DefaultProjectDirectory` (Documents), not `Directory.current` |
| `wsl` | `WslFilesystem` | WSL `$HOME`; app data `~/.local/share/com.hhoa.teampilot` in distro |
| `ssh` | `SftpFilesystem` | Remote home + remote TeamPilot app dir |

**`primaryPath`:** `DefaultProjectDirectory.resolve()` → `getApplicationDocumentsDirectory()`. Set at bootstrap in `app_shell.dart` as `nativeCwd` for `RuntimeStorageContext`.

**`<teampilotRoot>`** = `AppPaths.basePath` / `RuntimeStorageContext.appDataRoot`:

| Environment | Typical path |
|-------------|--------------|
| Linux desktop | `~/.local/share/com.hhoa.teampilot` |
| Windows native | `%APPDATA%\com.hhoa.teampilot` |
| WSL | `$HOME/.local/share/com.hhoa.teampilot` in chosen distro |
| SSH / Android | Remote host (`RemoteSshStoragePathResolver`) |

Top-level under `<teampilotRoot>`: `teams/`, `projects/` (+ `sessions/*.json`), `skills/`, `plugins/`, `providers/{tool}/providers.json` (one per CLI), `ssh_profiles/`, `config-profiles/` (CLI runtime trees; layout in `cli_data_layout.dart`). Team skills/plugins link into `config-profiles/teams/…` via `TeamSkillLinkerService` / `TeamPluginLinkerService`.

### Supported CLIs

`CliTool` enum in `client/lib/models/team_config.dart` — **all five launch-supported** (PTY or SSH):

| CLI | enum value | Notes |
|-----|------------|-------|
| Claude Code | `claude` | Default team CLI; onboarding can detect/install |
| flashskyai | `flashskyai` | Path resolved at startup |
| codex | `codex` | Launchable; participates in mixed teams via TeamBus |
| opencode | `opencode` | Config via `OPENCODE_CONFIG_DIR`; provider creds in `provider.options` |
| cursor | `cursor` | `cursor-agent`; HOME-isolated; doorbell push (no `wait_for_message` block) |

Each CLI is a `CliToolDefinition` in `client/lib/services/cli/registry/tools/`, composed from **capabilities** under `registry/capabilities/` (launch args, config profile, installer, presence, provider catalog/credentials/models, headless run, transcript probe, terminal behavior, …). The registry is built by `CliToolRegistry.builtIn()` and provisioned via `CliBootstrap`. **To add or change a CLI, add/extend a tool definition + capabilities here** — do not special-case CLIs across the app.

Provider catalogs: `providers/{tool}/providers.json` per CLI (`AppProviderRepository`). Config isolation is **app → team → member**; see `cli_data_layout.dart` (its header comment is the canonical `config-profiles/` map) and `SessionLifecycleService`.

### Team modes and TeamBus

`TeamMode` in `team_config.dart`:

| Mode | Meaning |
|------|---------|
| `native` | Single CLI runs its own native multi-agent team; every member uses `team.cli` |
| `mixed` | Cross-CLI team coordinated by **TeamBus**; each member may override `cli` (else falls back to `team.cli`) |

**TeamBus** (`client/lib/services/team_bus/`) is an in-process message bus: router + per-member inbox + a pure-function state machine (`PresenceReducer`) + effects-as-data (`BusEffect`) + a pluggable `CoordinationPolicy` (default leader-star) + lazy materialization. Members talk to it through the teammate-bus MCP server (`team_bus/mcp/`). Key edges:

- `effectiveForceWaitBeforeStop` decides whether a member is pushed back into `wait_for_message` at turn end. **Cursor defaults to `false`** — its MCP tool calls have a ~60s agent-layer hard limit, so it stops to idle-at-prompt and TeamBus delivers via a doorbell (stdin inject + `read_messages`).
- `MemberPresenceCubit` / `MailboxCubit` surface bus presence (working/idle) and messages in the UI.

### TeamHub (discoverable teams)

`client/lib/services/team_hub/` provides shareable team templates. `CompositeTeamHubSource.withDefaults(GitRegistryTeamHubSource())` merges **built-in templates** (`builtin_team_templates.dart`, e.g. the Superpowers Trio mixed-CLI team) with a remote git registry (raw GitHub). Built-in keys (`teampilot/builtin/*`) win on collision and surface first. UI under `client/lib/pages/team_hub/`; state in `TeamHubCubit`.

### Team session CLI identity

Team chat sessions persist:

| Field | Role |
|-------|------|
| `AppSession.sessionId` | UI / routing UUID (unchanged) |
| `AppSession.cliTeamName` | CLI `--team-name` / config-profiles runtime dir (`{teamId}-{seq}`) |
| `AppSession.members[]` | Per-roster `taskId` for CLI `--session-id` / `--resume` |

Allocated in `SessionRepository.createSession` via `SessionTeamCounter` (`config-profiles/teams/{teamId}/session-counter.json`). **No backward compatibility** with old `launchTeam` / chat-UUID runtime paths — users must create new team sessions after upgrade.

## Where to change code

| Area | Path |
|------|------|
| Entry | `client/lib/main.dart` |
| Bootstrap / DI | `client/lib/app/app_shell.dart` |
| Router | `client/lib/router/app_router.dart` |
| Workspace shell / tabs | `client/lib/pages/workspace_shell/`, `client/lib/pages/home_workspace/` |
| Chat / sessions | `client/lib/cubits/chat_cubit.dart` |
| Sessions persistence | `client/lib/repositories/session_repository.dart` |
| Teams | `client/lib/repositories/team_repository.dart`, `client/lib/cubits/team_cubit.dart` |
| Team templates / hub | `client/lib/services/team_hub/`, `client/lib/cubits/team_hub_cubit.dart` |
| Mixed-CLI coordination | `client/lib/services/team_bus/`, `client/lib/cubits/member_presence_cubit.dart`, `mailbox_cubit.dart` |
| CLI registry & capabilities | `client/lib/services/cli/registry/` (tools + capabilities) |
| Launch plan | `client/lib/services/session/session_lifecycle_service.dart` |
| PTY + terminal | `client/lib/services/terminal/terminal_session.dart` |
| Launch args / WSL paths | `client/lib/services/session/launch_command_builder.dart` |
| Paths / Documents default | `client/lib/services/storage/app_storage.dart` |
| Storage backend switch | `client/lib/services/storage/runtime_storage_context.dart` |
| CLI directory layout | `client/lib/services/cli/cli_data_layout.dart` |
| Session title from prompt | `client/lib/utils/first_user_line_capture.dart`, `session_display_title.dart` |
| Extensions (install, state, provision) | `client/lib/services/extension/`, `client/lib/repositories/extension_repository.dart`, `client/lib/cubits/extension_cubit.dart` |

**Routes** (`app_router.dart`): `/home-v2` (workspace home — library, team config, global views via query params), `/home-v2/project/:projectId` (project workbench); `/config/*` (settings, LLM/provider config); `/team-config/*` (members, skills, plugins, mcp, extensions); `/skills/*`, `/plugins/*`, `/extensions/*`, `/mcp/*` (global libraries); `/ssh-profiles`.

## Debugging

See [docs/DEBUGGING.md](docs/DEBUGGING.md) for the systematic debugging process (search-first, root cause over workarounds, etc.).

## Conventions

Full guidelines: **[docs/CODE_QUALITY.md](docs/CODE_QUALITY.md)** (file size, tests, Extension, `app_shell`). Summary:

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (full setup: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)).
- **Layering:** Route shells in `pages/`; **route-only** UI sections in `pages/<domain>/` (see `pages/mcp/`); **cross-route** UI in `widgets/`; logic in `cubits/` + `services/` + `repositories/`; no `Process.run` or raw paths in UI; state is **`flutter_bloc` only** (not `provider`). Details: [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md).
- **File size (soft):** page shells ~400, cubits ~500, services ~600 lines — split oversized screens into `pages/<domain>/` section files (not `widgets/<page-name>/`); keep `build()` free of IO.
- **Logging:** user errors → l10n; diagnostics → `AppLogger`; no `print`.
- State: cubits; paths: `AppStorage` / `RuntimeStorageContext` — never `Directory.current` for default project workspace.
- **CLIs:** add/extend a `CliToolDefinition` + capabilities under `services/cli/registry/`; avoid scattering `if (cli == …)` checks across features.
- **Tests:** mock subprocess/filesystem via constructor injection; cubit tests that touch `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()` in `client/test/support/post_frame_test_harness.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; `app_localizations*.dart` is generated by `flutter pub get`. After changing ARB strings, re-run `dart run tool/gen_warmup_glyphs.dart` to refresh `lib/widgets/warmup_glyphs.g.dart` (startup font-shaping warmup glyph set — keeps first-project-tab-click jank fixed; see `UiWarmup`).
- Terminal input hooks: filter ANSI CSI sequences (`FirstUserLineCapture`, `BusUserLineCapture`).
- Do not commit `client/google_fonts/` (gitignored); run `dart run tool/sync_bundled_google_fonts.dart` when touching zh UI fonts.
- New integration tests: `@Tags(['integration'])` from `package:test` (see DEVELOPMENT.md for Linux PTY run steps); document golden-path manual checks when CI cannot cover a change.
- **Extension:** install/uninstall is desktop-local until design spec remote path is done; keep `ExtensionAcquisitionEngine` URL checks for `script` acquire kind.
