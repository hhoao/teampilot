# CLAUDE.md

Guidance for Claude Code and other AI assistants working in this repository.

## Project overview

**TeamPilot** is a Flutter desktop/mobile client that manages teams, projects, sessions, skills, and plugins in a GUI, and launches embedded terminals running AI agent CLIs on the host (local PTY) or over **SSH** (Android default).

| Identifier | Value |
|------------|--------|
| Product name | TeamPilot |
| Dart package | `teampilot` (`client/pubspec.yaml`) |
| App / data ID | `com.hhoa.teampilot` |
| Supported CLIs | `flashskyai`, `claude`, `codex` (see Supported CLIs below) |
| Version | `client/pubspec.yaml` |

User-facing docs: [README.md](README.md) / [README.en.md](README.en.md). Contributor setup, tests, packaging: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) / [docs/DEVELOPMENT.en.md](docs/DEVELOPMENT.en.md).

## Commands

All app work happens under `client/`. First clone must init submodules (vendored packages):

```bash
git submodule update --init --recursive
```

Daily development:

```bash
cd client
flutter pub get                                      # also triggers l10n generation (generate: true in pubspec.yaml)
dart run tool/sync_bundled_google_fonts.dart         # Noto Sans SC (~50MB, gitignored); required for zh UI

flutter run -d linux                                 # macos | windows | android

dart run build_runner build --delete-conflicting-outputs   # after json_serializable model changes

flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration

# Single test:
flutter test --plain-name="test name"                # or: flutter test test/some_file_test.dart

# Linux PTY integration tests (after debug build):
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib flutter test --tags integration
```

Integration tests use `@Tags(['integration'])` from `package:test` — use the same tag for new integration tests.

Packaging (maintainers):

```bash
dart pub global activate fastforge
cd client && flutter pub get && dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform linux --targets deb,appimage
fastforge package --platform windows --targets exe   # needs Inno Setup 6
```

CI: `.github/workflows/client-verify.yml` (analyze + unit tests on Linux/Windows/macOS/Android), `.github/workflows/release.yml` (`v*` tags → GitHub Release).

## Repository layout

```
project-root/
├── client/
│   ├── lib/
│   │   ├── main.dart              # entry: fonts, window_manager, AppPathsBootstrapper, TeamPilotBootstrap
│   │   ├── app/app_shell.dart     # DI graph, ChatCubit, repos, storage roots
│   │   ├── router/app_router.dart # go_router: /chat, /config, /team-config, /skills, /plugins
│   │   ├── cubits/                # ChatCubit, TeamCubit, LayoutCubit, SessionPreferencesCubit, …
│   │   ├── pages/                 # chat_workbench, config_workspace, team_config_page, …
│   │   ├── repositories/          # session, team, skill, plugin, ssh, …
│   │   ├── services/              # terminal, launch, storage, lifecycle
│   │   ├── models/
│   │   └── widgets/
│   ├── packages/                  # vendored (git submodules): xterm, flutter_pty, dartssh2
│   ├── assets/                    # icons, rtk/rtk-rewrite.sh, terminal fonts
│   ├── test/                      # unit/widget; integration/ for PTY
│   └── linux/packaging/           # fastforge notes
├── docs/superpowers/specs/        # plugin + RTK design docs
├── assets/                        # repo-level (e.g. README screenshot)
└── .github/workflows/
```

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

### State and UI

- **State:** `flutter_bloc` cubits under `client/lib/cubits/`.
- **Routing:** `client/lib/router/app_router.dart` — desktop sidebar shell; Android uses drawer + pushed routes.
- **Chat:** `ChatCubit` owns tabbed `TerminalSession`s; `openSessionTab` / `_scheduleMemberConnect` call `SessionLifecycleService.prepareLaunch` then `TerminalSession.connect`.

### Terminal transport

| Mode | When | Implementation |
|------|------|----------------|
| Local PTY | Desktop default | `flutter_pty` → `LocalPtyTransport` |
| SSH | Android always; desktop optional | `dartssh2` → `SshPtyTransport`; remote CLI via `RemoteFlashskyaiCommandBuilder` |

`client/lib/services/terminal_transport_factory.dart`, `terminal_session.dart`.

### Storage backends

`RuntimeStorageContext` (`client/lib/services/runtime_storage_context.dart`):

| Backend | Filesystem | `cwd` / data root |
|---------|------------|-------------------|
| `native` | `LocalFilesystem` | App Support + `DefaultProjectDirectory` (Documents) for new projects |
| `wsl` | `WslFilesystem` | WSL `$HOME`; app data at `~/.local/share/com.hhoa.teampilot` in distro |
| `ssh` | `SftpFilesystem` | Remote home + remote TeamPilot app dir |

Access paths via `AppStorage` (`client/lib/services/app_storage.dart`): `AppStorage.paths`, `AppStorage.cwd`, `AppStorage.fs`.

**Default project workspace (`primaryPath`):** `DefaultProjectDirectory.resolve()` → `getApplicationDocumentsDirectory()`. Not `Directory.current`. Set at bootstrap in `app_shell.dart` as `nativeCwd` for `RuntimeStorageContext`.

### Supported CLIs

`TeamCli` in `client/lib/models/team_config.dart`:

| CLI | `isLaunchSupported` | Provider catalog |
|-----|---------------------|------------------|
| `flashskyai` | yes | `providers/flashskyai/providers.json` |
| `claude` | yes | `providers/claude/providers.json` |
| `codex` | no | `providers/codex/providers.json` |

CLI config isolation uses three layers (app → team → member). See `client/lib/services/cli_data_layout.dart` and `SessionLifecycleService`.

## App data directory layout

Root: `AppPaths.basePath` / `RuntimeStorageContext.appDataRoot` (`<teampilotRoot>`).

| Environment | Typical `<teampilotRoot>` |
|-------------|---------------------------|
| Linux desktop | `~/.local/share/com.hhoa.teampilot` |
| Windows native | `%APPDATA%\com.hhoa.teampilot` |
| WSL backend | `$HOME/.local/share/com.hhoa.teampilot` inside chosen distro |
| SSH / Android | Resolved on remote host (`RemoteSshStoragePathResolver`) |

```
<teampilotRoot>/
├── teams/                         # Team UI JSON (one file per team name)
├── projects/
│   ├── projects.json              # project index
│   └── sessions/*.json            # session metadata (display, paths, launch state)
├── skills/                        # installed skill packages
├── skill-backups/
├── skills.json                    # skill repo sources
├── skill-repo-cache/
├── plugins/
├── plugin-backups/
├── plugins.json
├── plugin-marketplaces.json
├── plugin-marketplace-cache/
├── plugin-external-cache/
├── providers/
│   ├── flashskyai/providers.json
│   ├── claude/providers.json
│   └── codex/providers.json
├── ssh_profiles/
└── config-profiles/               # CLI runtime trees (see cli_data_layout.dart)
    ├── flashskyai/
    ├── claude/
    ├── codex/
    └── teams/<teamId>/{tool}/
        └── members/<sessionId>/{tool}/   # member CONFIG_DIR for PTY env
```

Team skills/plugins are linked into `config-profiles/teams/…` via `TeamSkillLinkerService` / `TeamPluginLinkerService`.

## Key source files

| Area | Path |
|------|------|
| Entry | `client/lib/main.dart` |
| Bootstrap / DI | `client/lib/app/app_shell.dart` |
| Router | `client/lib/router/app_router.dart` |
| Chat / sessions | `client/lib/cubits/chat_cubit.dart` |
| Sessions persistence | `client/lib/repositories/session_repository.dart` |
| Teams | `client/lib/repositories/team_repository.dart`, `client/lib/cubits/team_cubit.dart` |
| Launch plan | `client/lib/services/session_lifecycle_service.dart` |
| PTY + xterm | `client/lib/services/terminal_session.dart` |
| Launch args / WSL paths | `client/lib/services/launch_command_builder.dart` |
| Paths / Documents default | `client/lib/services/app_storage.dart` |
| Storage backend switch | `client/lib/services/runtime_storage_context.dart` |
| CLI directory layout | `client/lib/services/cli_data_layout.dart` |
| Session title from prompt | `client/lib/utils/first_user_line_capture.dart`, `session_display_title.dart` |

## Routes (summary)

| Path | Purpose |
|------|---------|
| `/chat`, `/chat/session/:sessionId` | Chat workbench |
| `/config/*` | Settings (layout, LLM, session, SSH, about, logs) |
| `/team-config/*` | Team / members / skills / plugins for team |
| `/skills/*` | Global skill management |
| `/plugins/*` | Global plugin management |

## Conventions for changes

- Run `flutter analyze` and `flutter test --exclude-tags integration` under `client/` before claiming done.
- Match existing patterns: cubits for state, `AppStorage` / `RuntimeStorageContext` for paths (do not hardcode `Directory.current` for project defaults).
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only. Generated files (`app_localizations*.dart` in the same dir) are auto-generated by `flutter pub get` — never hand-edit them.
- Terminal input hooks must filter ANSI CSI sequences (see `FirstUserLineCapture`).
- Do not commit `client/google_fonts/` (gitignored); document font sync script when touching zh UI fonts.
