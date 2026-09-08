# AGENTS.md

Guidance for Claude Code and other AI assistants working in this repository.
Read the docs below as needed instead of keeping them in context.

**TeamPilot** is a Flutter client (`client/`, package `teampilot`, data ID `com.hhoa.teampilot`) that manages **workspaces**, **team launch identities**, sessions, skills, plugins, and extensions, and embeds terminals running AI agent CLIs (local PTY on desktop, or SSH — always on Android, optional on desktop). The home UI is an Apifox-style workspace shell with a built-in IDE (file tree, editor, Git, worktrees).

All app code lives under `client/lib/` (cubits, pages, repositories, services, models). Vendored deps: `client/packages/` (git submodules: xterm, flutter_pty_new, dartssh2, re-editor, flutter_alacritty, **shared_ui**).

| Doc | Read when |
|-----|-----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Core concepts (Workspace / Launch profile / Expert / Session), bootstrap, routing, storage & CLI config inheritance, TeamBus, "where to change code" map, routes |
| [docs/cli-architecture.md](docs/cli-architecture.md) | Adding or changing a CLI: tool definitions + capability pattern, anti-patterns |
| [docs/workspace-storage-layout.md](docs/workspace-storage-layout.md) | On-disk layout under `<teampilotRoot>` |
| [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) | Layering, file size limits, UI/state conventions, testing conventions |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Clone, commands, tests (incl. test-loop rules), packaging, CI |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | Systematic debugging process |
| [docs/flutter-patches.md](docs/flutter-patches.md) | Mandatory Flutter SDK patches (apply / add / CI) |
| [docs/PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) | DevTools performance JSON offline analysis (`tool/analyze_performance_json.dart`) |
| [README.md](README.md) / [README.zh.md](README.zh.md) | User-facing |

## Hard rules

- **Never invoke `flutter test` directly** — always `cd client && dart run tool/run_tests.dart <paths/options>`; concurrent direct runs corrupt the shared build cache (details: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#tests)).
- **Test loop: fast inner, slow outer.** Inner loop is `flutter analyze`; verify with one test file (`--plain-name` to narrow); full suite only once before claiming done, in the background (details: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#test-loop-fast-inner-slow-outer-do-not-invert-it)).
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- **Member placement:** always `sessionRosterMembers(session, team)` (native writers: `cliTeamRosterMembers` / `runtimeRosterMembers`) — never raw `team.members` or stale `replicas` (details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#member-placement-machines)).
- **Paths:** `AppStorage` / `RuntimeContextRegistry` — never `Directory.current` for workspace or app data roots.
- **CLIs:** add/extend a `CliToolDefinition` + capabilities under `services/cli/registry/`; never scatter `if (cli == …)` checks across features.
- **Logging:** user errors → l10n; diagnostics → `AppLogger`; no `print`.
- **l10n:** edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.
- Do not commit `client/google_fonts/` (gitignored); run `dart run tool/sync_bundled_google_fonts.dart` when touching zh UI fonts.
- Terminal input hooks: filter ANSI CSI sequences (`FirstUserLineCapture`, `BusUserLineCapture`).
- New integration tests: `@Tags(['integration'])` from `package:test`.
- **Extension:** install/uninstall is desktop-local until the design spec remote path is done; keep `ExtensionAcquisitionEngine` URL checks for `script` acquire kind.

Layering, file-size limits, `pages/` vs `widgets/` vs `shared_ui`, test fakes, and other conventions: **[docs/CODE_QUALITY.md](docs/CODE_QUALITY.md)**.
