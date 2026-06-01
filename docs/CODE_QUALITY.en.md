# Code quality guidelines

For contributors and AI assistants: builds on [AGENTS.md](../AGENTS.md) with **file size, layering, testing, and known limitations** so pages and cubits do not grow without bound and test gaps stay visible.

中文版：[CODE_QUALITY.md](CODE_QUALITY.md).

## Quality gates (required)

Before merge, from `client/` (same as [Client Build Verify](../.github/workflows/client-verify.yml)):

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

Run these commands and confirm success before claiming work is done.

## Layering

| Layer | Path | Responsibility |
|-------|------|----------------|
| Single-screen module | `pages/<domain>/` | Route **shell** (`*_page.dart` / `*_workspace.dart`), sections, dialogs, route helpers (see `pages/mcp/`) |
| Shared UI | `widgets/` | Controls and layout reused across routes (`dropdown/`, `settings/`, `split_layout.dart`, etc.) |
| State | `cubits/` | Actions, loading/error; calls repositories / services |
| Persistence | `repositories/` | JSON/files via `Filesystem` + `AppStorage` |
| Domain | `services/` | Install, probe, terminal, CLI profiles, skill/plugin linking |
| Models | `models/` | Immutable data, serialization |

**Paths:** `AppStorage` / `RuntimeStorageContext` only — not `Directory.current` for workspace or app data roots.

**DI:** Services that touch processes, network, or disk should accept injectable runners/clients (see `ExtensionAcquisitionEngine`, `ExtensionDetector`).

### `pages/` vs `widgets/`

| Question | Location | Examples |
|----------|----------|----------|
| Used by a single route / settings screen? | `pages/<domain>/` | `pages/skills/skill_discovery_section.dart`, `pages/team_config/team_config_member_section.dart` |
| Imported from unrelated routes? | `widgets/` | `FlashskyDropdownField`, `WorkspaceHubPage`, `AppProviderListPanel` |
| Page shell + enum + hub? | `pages/*_page.dart` (may `export` types from the domain subfolder) | `mcp_management_page.dart`, `skill_management_page.dart` |

**Do not** put route-only sections under `widgets/<feature>/` when the folder name mirrors a page. When splitting oversized pages, prefer **`pages/<domain>/`**, aligned with `pages/mcp/`.

Suggested layout (**shell and sections colocated**, see `pages/mcp/`):

```
pages/
  mcp/
    mcp_management_page.dart
    mcp_installed_section.dart
    ...
  plugins/
    plugin_management_page.dart
    ...
  skills/
    skill_management_page.dart
    ...
  team_config/
    team_config_page.dart
    ...
  llm_config/
    llm_config_workspace.dart
    ...
```

## File size (soft limits)

| Kind | Soft limit |
|------|------------|
| Page / workspace shell | ~400 lines |
| Single file under `pages/<domain>/` | ~500 lines (split further or extract **shared** widgets) |
| `cubits/` | ~500 lines |
| `services/` | ~600 lines |

**Do not** add large UI or business blocks to pages already **~800+ lines** without splitting and adding tests.

**Generated:** `l10n/app_localizations*.dart` is excluded from these limits; never hand-edit.

## UI and state

- Route-specific UI lives under **`pages/<domain>/`**; cross-route UI under **`widgets/`**. Pages connect via `BlocBuilder` / `context.read`.
- **Use `flutter_bloc` (Cubit) for app state**; do not introduce `provider` / `ChangeNotifier` as a parallel pattern in feature code.
- Cubit states: `Equatable` or immutable `copyWith`; explicit load/error; fine-grained busy sets where needed (`ExtensionCubit`).
- User-facing errors: l10n, not raw `e.toString()` as final copy (logging is fine).
- Routing: existing **`go_router`** (`app_router.dart`); short-lived UI (dialogs, sheets) may use `Navigator`.

### Flutter UI practices (when splitting large pages)

When touching oversized files (`team_config_page`, `llm_config_workspace`, `skill_management_page`, etc.), reduce size this way—not by growing a single file:

| Practice | Notes |
|----------|--------|
| Dedicated **Widget classes** | Split large `build()` bodies into `class FooSection extends StatelessWidget` under **`pages/<domain>/`**. **Avoid** private methods that only return a `Widget`. |
| Composition over inheritance | Compose small widgets; limit deep `Row`/`Column` nesting. |
| Long lists | Use **`ListView.builder` / `SliverList`** for skills/plugins/extensions; avoid huge `children: [...]`. |
| Keep `build()` light | **No** disk/network/subprocess, heavy JSON parse, or heavy compute inside `build()`; use Cubit/Service + `BlocBuilder`. |
| `const` | Use `const` constructors where subtrees are stable to cut unnecessary desktop rebuilds. |

Shared pieces for multiple sections on the **same** screen (e.g. `mcp_shared_widgets.dart`) stay in the **same** `pages/<domain>/` folder. Move to `widgets/` only when a second route imports them.

## Function and logic size

- One responsibility per function; past **~30 lines** with branches and IO, move logic to `services/` or a dedicated widget.
- Cubit handlers past **~40 lines** should delegate domain steps to services; the cubit orchestrates and `emit`s.

## Errors and logging

- Expected failures (install failed, probe miss) → result types or cubit error state; **no** silent catches.
- User copy → **l10n + cubit state**; diagnostics → **`AppLogger`** (`utils/logger.dart`). **No** `print`; do not rely on `debugPrint` as persistent logging.
- Follow [DEBUGGING.md](DEBUGGING.md) for framework/engine errors before changing app logic.

## Models and code generation

- Persistence/API models: **`json_serializable` + `json_annotation`**; after edits run `dart run build_runner build --delete-conflicting-outputs` ([DEVELOPMENT.en.md](DEVELOPMENT.en.md)).
- New models should match **existing models in the same domain** for JSON keys and `@JsonSerializable` options.
- `///` docs on **`services/`, `repositories/`, and shared models**; page sections rely on clear names.

## Desktop layout

- Wide forms (settings, team config): **`Expanded` / `Flexible` / `Wrap`** for `Row` overflow; `SingleChildScrollView` for fixed large blocks; lists still use builders.
- Use `LayoutBuilder` / `MediaQuery` when needed; shared mobile/desktop widgets should respect max width and touch targets.

## Accessibility (baseline)

- Icon-only controls: **`tooltip` or `Semantics(label: …)`**.
- Contrast and type via **`ThemeData` / `textTheme`**, not hard-coded low-contrast pairs.
- Verify forms/sidebars remain scrollable and actionable with system text scaling.

## Testing

### Default (CI)

```bash
flutter test --exclude-tags integration
```

New features: unit-test `services/`, `repositories/`, `cubits/` first.
When editing large pages: at least **cubit** tests; newly extracted **`pages/<domain>/`** sections should get **widget tests** (key interactions, empty/error states).
Structure: **Arrange–Act–Assert** (or Given–When–Then); one behavior per `test`.

### Integration tests

- Tag: `@Tags(['integration'])`.
- Real PTY/CLI; excluded from default CI — see [DEVELOPMENT.en.md](DEVELOPMENT.en.md).
- Document local run steps in PRs; aim for **2–3 golden paths** over time (e.g. team session → one member terminal connects).

### Test environment

If code touches `AppStorage` / `RuntimeStorageContext`:

- `setUpTestAppStorage()` / `tearDownTestAppStorage()` in `client/test/support/post_frame_test_harness.dart`.
- Avoid cubit tests that trigger background work without storage — warnings like `RuntimeStorageContext.install() must be called` hide real failures.

For post-frame work (`ChatCubit`), use `PostFrameTestHarness` / `runScheduledCallback`.

### Fakes and mocks

- **Prefer fakes/stubs** (injected `Filesystem`, fake `runner` with fixed `ProcessResult`), as in `ExtensionAcquisitionEngine` tests.
- Use mocks only at hard boundaries; do not adopt `mockito` / `mocktail` by default for new tests.
- Mock when needed: subprocesses, SSH, network, uninitialized `AppStorage` side effects.
- Do not mock: pure functions, trivial types matching real behavior.
- Install flows: inject runners; do not run real `npm install -g` on the host.
- Keep integration tests on **`@Tags(['integration'])` + `package:test`** unless a repo-wide migration to `integration_test` is agreed.

## Bootstrap / `app_shell.dart`

- Wire new types explicitly on `AppShell`; avoid hidden singletons.
- If a single change adds **~80+ lines** to `app_shell.dart`, extract a domain bootstrap factory.
- Tests: `RuntimeStorageContext.installForTesting`, not production `install()` unless testing bootstrap itself.

## Dart conventions

- `async`/`await` + `try/catch` should surface outcomes in cubits/services, not unhandled exceptions in `build`.
- Naming: `PascalCase` types, `camelCase` members, `snake_case` files; avoid opaque abbreviations.
- From `pages/<domain>/`: shared UI → `import '../../widgets/...'`; same domain → `import 'foo_section.dart'`.

## Tech debt

- Avoid new `TODO`/`FIXME` without an issue or same-PR follow-up.
- No `// ignore` without reason; fix analyze issues when possible.
- Comments explain **why**, not what the code obviously does; `///` on public service APIs; keep sections self-explanatory.
- Bugs: [DEBUGGING.md](DEBUGGING.md) — search framework errors before local hacks.

## Manual pre-release checks

- At least one desktop OS: team config → save → team session → member terminal connects.
- Extension/MCP/skill linking changes: toggle in team config and verify `config-profiles` side effects.
- Android/SSH: hand-test when storage or transport changes.

## Related docs

| Doc | Topic |
|-----|--------|
| [AGENTS.md](../AGENTS.md) | Architecture |
| [DEVELOPMENT.en.md](DEVELOPMENT.en.md) | Commands, integration tests |
| [DEBUGGING.md](DEBUGGING.md) | Debugging process |
