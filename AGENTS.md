# AGENTS.md

Guidance for Claude Code and other AI assistants working in this repository.

**TeamPilot** is a Flutter client (`client/`, package `teampilot`, data ID `com.hhoa.teampilot`) that manages teams, projects, sessions, skills, and plugins, and embeds terminals running AI agent CLIs (local PTY or SSH on Android).

| Docs | Purpose |
|------|---------|
| [README.md](README.md) / [README.en.md](README.en.md) | User-facing |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) / [DEVELOPMENT.en.md](docs/DEVELOPMENT.en.md) | Clone, commands, tests, packaging, CI |

All app code lives under `client/lib/` (cubits, pages, repositories, services). Vendored deps: `client/packages/` (git submodules: xterm, flutter_pty, dartssh2).

## Architecture

### Bootstrap flow

```
main.dart
  → AppPathsBootstrapper.init()     # Application Support → AppPaths
  → TeamPilotBootstrap / buildAppShell()
      → RuntimeStorageContext.install()   # native | wsl | ssh filesystem
      → SessionRepository, ChatCubit, TeamCubit, …
  → MaterialApp.router (GoRouter)
```

### State, routing, and chat

- **State:** `flutter_bloc` cubits under `client/lib/cubits/`.
- **Routing:** `client/lib/router/app_router.dart` — desktop sidebar; Android drawer + pushed routes.
- **Chat:** `ChatCubit` owns tabbed `TerminalSession`s; `openSessionTab` / `_scheduleMemberConnect` → `SessionLifecycleService.prepareLaunch` → `TerminalSession.connect`.

### Terminal transport

| Mode | When | Implementation |
|------|------|----------------|
| Local PTY | Desktop default | `flutter_pty` → `LocalPtyTransport` |
| SSH | Android always; desktop optional | `dartssh2` → `SshPtyTransport`; remote CLI via `RemoteFlashskyaiCommandBuilder` |

See `client/lib/services/terminal/terminal_transport_factory.dart`, `terminal_session.dart`.

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

Top-level under `<teampilotRoot>`: `teams/`, `projects/` (+ `sessions/*.json`), `skills/`, `plugins/`, `providers/{flashskyai,claude,codex}/`, `ssh_profiles/`, `config-profiles/` (CLI runtime trees; layout in `cli_data_layout.dart`). Team skills/plugins link into `config-profiles/teams/…` via `TeamSkillLinkerService` / `TeamPluginLinkerService`.

### Supported CLIs

`TeamCli` in `client/lib/models/team_config.dart`:

| CLI | `isLaunchSupported` | Provider catalog |
|-----|---------------------|------------------|
| `flashskyai` | yes | `providers/flashskyai/providers.json` |
| `claude` | yes | `providers/claude/providers.json` |
| `codex` | no | `providers/codex/providers.json` |

Config isolation: **app → team → member** (member `CONFIG_DIR` for PTY). See `client/lib/services/cli/cli_data_layout.dart` and `SessionLifecycleService`.

## Where to change code

| Area | Path |
|------|------|
| Entry | `client/lib/main.dart` |
| Bootstrap / DI | `client/lib/app/app_shell.dart` |
| Router | `client/lib/router/app_router.dart` |
| Chat / sessions | `client/lib/cubits/chat_cubit.dart` |
| Sessions persistence | `client/lib/repositories/session_repository.dart` |
| Teams | `client/lib/repositories/team_repository.dart`, `client/lib/cubits/team_cubit.dart` |
| Launch plan | `client/lib/services/session/session_lifecycle_service.dart` |
| PTY + xterm | `client/lib/services/terminal/terminal_session.dart` |
| Launch args / WSL paths | `client/lib/services/session/launch_command_builder.dart` |
| Paths / Documents default | `client/lib/services/storage/app_storage.dart` |
| Storage backend switch | `client/lib/services/storage/runtime_storage_context.dart` |
| CLI directory layout | `client/lib/services/cli/cli_data_layout.dart` |
| Session title from prompt | `client/lib/utils/first_user_line_capture.dart`, `session_display_title.dart` |

**Routes** (`app_router.dart`): `/chat`, `/chat/session/:sessionId` (workbench); `/config/*` (settings); `/team-config/*` (team members, skills, plugins); `/skills/*`, `/plugins/*` (global).

## Conventions

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (full setup: [DEVELOPMENT.md](docs/DEVELOPMENT.md)).
- State: cubits; paths: `AppStorage` / `RuntimeStorageContext` — never `Directory.current` for default project workspace.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; `app_localizations*.dart` is generated by `flutter pub get`.
- Terminal input hooks: filter ANSI CSI sequences (`FirstUserLineCapture`).
- Do not commit `client/google_fonts/` (gitignored); run `dart run tool/sync_bundled_google_fonts.dart` when touching zh UI fonts.
- New integration tests: `@Tags(['integration'])` from `package:test` (see DEVELOPMENT.md for Linux PTY run steps).
