# BLoC + go_router Migration Design

## Goal

Replace ChangeNotifier-based controllers with flutter_bloc Cubits, and replace `setState`-based navigation with go_router ShellRoute.

## Scope

Full migration: all 5 controllers → Cubits, all routing → go_router, all `addListener`+`setState` → `BlocBuilder`/`BlocListener`.

---

## BLoC Structure

5 Cubs (not Blocs — current API is method-call style, no event indirection needed):

| Controller | Cubit | State fields |
|---|---|---|
| TeamController | TeamCubit | teams, selectedTeamId, statusMessage, isLoading, isLaunching |
| ChatController | ChatCubit | activeTabIndex, selectedMemberId, sessions + session metadata (NOT terminal instances) |
| ConfigController | ConfigCubit | section (ConfigSection), selectedMemberId |
| LlmConfigController | LlmConfigCubit | config, savedConfig, isLoading, statusMessage, selectedProviderName, filePath |
| LayoutController | LayoutCubit | preferences (LayoutPreferences), isLoading |

### Key Rules

- **Cubit, not Bloc** — current controllers expose methods, not event streams
- **State is Equatable** — every state class extends Equatable
- **Mutable objects (TerminalSession) stay OUT of state** — ChatCubit holds terminal references internally; state only carries metadata (isRunning, tab titles)
- **`bloc_concurrency`** — `sequential()` transformer on save-heavy Cubs (Team, LlmConfig) to prevent race conditions
- **Dependency injection** — Repositories and TerminalSession are constructor-injected into Cubs, same as today

---

## go_router Structure

```
ShellRoute
├── /chat               → ChatWorkbench
│   └── /chat/session/:sessionId  (optional deep-link)
└── /config
    ├── /config/team     → TeamConfigWorkspace
    ├── /config/members  → MemberConfigWorkspace
    ├── /config/layout   → LayoutConfigWorkspace
    └── /config/llm      → LlmConfigWorkspace
```

- `ShellRoute.builder` renders ContextSidebar in a Row alongside the child outlet
- Chat tab switching stays in BLoC state (NOT URL-based)
- Initial route: `/chat`
- `context.go('/config/team')` triggered by Settings button in sidebar

### Provider Mounting

5 Cubs provided via `MultiBlocProvider` above `MaterialApp.router`, visible to all routes. Created in `main()` after SharedPreferences init.

---

## Widget Changes Summary

| Current Pattern | Replacement |
|---|---|
| `widget.controller.addListener(_handler)` + `setState` | `BlocBuilder<XxxCubit, XxxState>(builder: ...)` |
| Constructor-passed controller params | `context.read<XxxCubit>()` |
| `controller.selectSection(...)` | `context.read<ConfigCubit>().selectSection(...)` |
| Imperative route switch (`_section = ...`) | `context.go('/config/team')` |

---

## Files Changed

| Action | Files |
|---|---|
| NEW | `lib/cubits/team_cubit.dart` |
| NEW | `lib/cubits/chat_cubit.dart` |
| NEW | `lib/cubits/config_cubit.dart` |
| NEW | `lib/cubits/llm_config_cubit.dart` |
| NEW | `lib/cubits/layout_cubit.dart` |
| NEW | `lib/router/app_router.dart` |
| REWRITE | `lib/main.dart` |
| MODIFY | `lib/pages/workspace_shell.dart`, `chat_workbench.dart`, `config_workspace.dart`, `llm_config_workspace.dart` |
| MODIFY | `lib/widgets/context_sidebar.dart`, `right_tools_panel.dart` |
| DELETE | `lib/controllers/chat_controller.dart`, `config_controller.dart`, `layout_controller.dart`, `llm_config_controller.dart`, `team_controller.dart` |

---

## Dependencies Added

```yaml
dependencies:
  flutter_bloc: ^9.1.0
  bloc_concurrency: ^0.3.0
  equatable: ^2.0.5
  go_router: ^16.3.0
  path_provider: ^2.1.2
  path: ^1.9.0
  json_annotation: ^4.9.0
  uuid: ^4.5.1
  window_manager: ^0.5.1
  web_socket_channel: ^2.4.0
  multi_split_view: ^3.6.1
  logger: ^2.6.0

dev_dependencies:
  build_runner: ^2.6.0
  json_serializable: ^6.9.5
```
