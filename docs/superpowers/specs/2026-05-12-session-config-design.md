# Session Configuration & Configurable CLI Path — Design

**Date:** 2026-05-12
**Status:** Approved (pending implementation)

## Motivation

Today the workspace configuration page has two sections — Layout and LLM — and
the "auto-launch all members on connect" toggle is awkwardly grouped under
Layout. Meanwhile, the `flashskyai` CLI is always launched via the bare
executable name `flashskyai`, relying on it being on `PATH`. Users with custom
install locations have no way to point the UI at a specific binary, and the
`FlashskyaiCliLocator.locate()` result found at startup is not actually used by
any launch site.

This work introduces a new **Session** configuration section that owns:

1. The previously-misplaced **"auto-launch all members on connect"** toggle.
2. A new **flashskyai CLI executable path** preference, honoured by every
   CLI-launch site in the app.

## Non-Goals

- Backwards compatibility with the old storage layout: the project is still in
  open development and has no production users. We delete the old field rather
  than migrating it.
- Per-session overrides (CLI path is global, not per-team or per-session).
- Auto-detecting a moved CLI at runtime — detection happens once at startup;
  user-configured path always wins.

## Architecture

### Data Model

New file `client/lib/models/session_preferences.dart`:

```dart
class SessionPreferences {
  const SessionPreferences({
    this.cliExecutablePath = '',
    this.autoLaunchAllMembersOnConnect = false,
  });

  final String cliExecutablePath;      // '' means fall back to PATH lookup
  final bool autoLaunchAllMembersOnConnect;

  // fromJson / toJson / copyWith — mirrors LayoutPreferences shape
}
```

`LayoutPreferences.autoLaunchAllMembersOnConnect` is deleted outright (field,
constructor parameter, copyWith parameter, fromJson/toJson entries, and the
internal `withAtLeastOneToolVisible` re-emit).

### Persistence

New `client/lib/repositories/session_preferences_repository.dart`:

- Storage key: `flashskyai.session_preferences.v1`
- Implementation parallels `LayoutRepository`: read JSON string from
  `SharedPreferences`, decode into `SessionPreferences.fromJson`; on write,
  encode and store.

### Cubit

New `client/lib/cubits/session_preferences_cubit.dart`:

```dart
class SessionPreferencesState {
  const SessionPreferencesState({required this.preferences});
  final SessionPreferences preferences;
}

class SessionPreferencesCubit extends Cubit<SessionPreferencesState> {
  SessionPreferencesCubit({
    required SessionPreferencesRepository repository,
    String? locatedExecutable,
  }) : _repository = repository,
       _locatedExecutable = locatedExecutable,
       super(const SessionPreferencesState(
         preferences: SessionPreferences(),
       ));

  final SessionPreferencesRepository _repository;
  final String? _locatedExecutable;

  Future<void> load();
  Future<void> setCliExecutablePath(String value);
  Future<void> setAutoLaunchAllMembersOnConnect(bool value);

  /// Resolves the actual executable to use:
  /// 1. user-configured path (if non-empty)
  /// 2. located-at-startup path (if found)
  /// 3. literal 'flashskyai' (shell resolves via PATH)
  String resolveExecutable();
}
```

`resolveExecutable()` is the single source of truth for which binary to spawn.

### CLI Launch Sites — Adaptation

`LaunchCommandBuilder.executable` (the `static const`) is removed. Every entry
point that previously relied on it now receives the executable explicitly.

- `LaunchCommandBuilder.launch(...)` signature gains
  `required String executable`. Internal uses of the old constant are replaced.
- `LaunchCommandBuilder.preview(...)` signature gains
  `required String executable`.
- `LaunchCommandBuilder.buildArguments(...)` is unchanged — it never included
  the executable.
- `TerminalSession` (client/lib/services/terminal_session.dart) takes
  `executable` via its constructor (or its existing factory), replacing the
  hardcoded `LaunchCommandBuilder.executable` at line 105.
- `ui_warmup.dart` line 184 reads `SessionPreferencesCubit.resolveExecutable()`
  (via `context.read<SessionPreferencesCubit>()`) instead of literal
  `'flashskyai'` when rendering the preview command string.

`ChatCubit` and `TeamCubit` need a way to obtain the current executable at
launch time. We follow the existing `llmConfigPathOverride` pattern:

```dart
ChatCubit({
  ...,
  required String Function() executableResolver,
  ...
});
```

`main.dart` wires `() => sessionCubit.resolveExecutable()` into the resolver.

### LlmConfigCubit alignment

`LlmConfigCubit` currently receives `cliExecutablePath` as a one-shot value in
its constructor. We change it to accept a `String Function() executableResolver`
so that path-resolution logic (which uses the CLI install location to find
`llm/...`) immediately reflects user changes. This keeps the launch-time and
LLM-config-path code paths consistent.

### UI

#### Section enum and routing

`ConfigSection` becomes `enum ConfigSection { layout, llm, session }`.

`app_router.dart` adds `/config/session` → `ConfigWorkspace(section: ConfigSection.session)`.

`config_workspace.dart`:

- `_ConfigNavPanel` displays nav items in order: **LLM → Layout → Session**
  (Session appended).
- The body switch adds `ConfigSection.session => const SessionConfigWorkspace()`.

#### Session config page

New `client/lib/pages/session_config_workspace.dart`:

A `SettingsSurfaceCard` containing two `SettingsLabeledRow`s, mirroring the
visual language of `LayoutConfigWorkspace`:

1. **CLI executable path**
   - Title: `l10n.cliExecutablePathLabel`
   - Subtitle: `l10n.cliExecutablePathDescription`
   - Trailing: a row containing
     - a `TextField` bound to a `TextEditingController` initialised from
       `preferences.cliExecutablePath`. On submit / blur, calls
       `cubit.setCliExecutablePath(value.trim())`.
     - A "Browse" button — opens `FilePicker.platform.pickFiles(type: FileType.any)`
       (single file); on selection, updates the controller and persists.
     - A "Reset" button — clears the field and persists `''`, falling back to
       PATH lookup.
   - Below the row: a small helper line showing the **currently effective**
     path (e.g. `Using: /usr/local/bin/flashskyai` or `Using PATH lookup`).

   Implementation reference: see `llm_config_workspace.dart` lines 60–180 for
   the existing browse+text+reset pattern in this codebase.

2. **Auto-launch all members on connect**
   - Switch bound to `preferences.autoLaunchAllMembersOnConnect`.
   - Title: existing `l10n.autoLaunchAllMembersTitle`.
   - Subtitle: existing `l10n.autoLaunchAllMembersDescription`.

#### Layout config page

The "Shell session" group (heading + `autoLaunchAllMembersOnConnect` row) is
removed from `LayoutConfigWorkspace`.

### Localization

Add to `client/lib/l10n/app_localizations.dart`:

| key                              | en                                                                                | zh                                                          |
| -------------------------------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `session`                        | Session                                                                           | 会话                                                        |
| `sessionPageSubtitle`            | Configure how shell sessions are launched.                                        | 配置 Shell 会话的启动方式。                                 |
| `cliExecutablePathLabel`         | flashskyai CLI path                                                               | flashskyai CLI 路径                                         |
| `cliExecutablePathDescription`   | Absolute path to the flashskyai executable. Leave empty to use the one on PATH.   | flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。 |
| `cliExecutablePathBrowse`        | Browse…                                                                           | 浏览…                                                       |
| `cliExecutablePathReset`         | Reset                                                                             | 重置                                                        |
| `cliExecutablePathUsing`         | Using: {path}                                                                     | 当前生效：{path}                                            |
| `cliExecutablePathUsingFallback` | Using PATH lookup                                                                 | 使用 PATH 中查找的版本                                      |

Existing keys retained: `autoLaunchAllMembersTitle`, `autoLaunchAllMembersDescription`.

The `appRailConfig` / `configure` / `layout` / `llmConfig` style strings remain
unchanged; we just add `session` alongside them.

### App composition (`main.dart`)

```dart
final cliLocated = await FlashskyaiCliLocator.locate();

final sessionCubit = SessionPreferencesCubit(
  repository: SessionPreferencesRepository(preferences),
  locatedExecutable: cliLocated,
);
await sessionCubit.load();

final llmConfigCubit = LlmConfigCubit(
  appSettings: appSettings,
  currentDirectory: Directory.current.path,
  homeDirectory: homeDirectory,
  executableResolver: () => sessionCubit.resolveExecutable(),
);

final chatCubit = ChatCubit(
  tempTeamCleaner: tempTeamCleaner,
  llmConfigPathOverride: llmConfigPathOverrideForLaunch,
  autoLaunchAllMembersOnConnect: () =>
      sessionCubit.state.preferences.autoLaunchAllMembersOnConnect,
  executableResolver: () => sessionCubit.resolveExecutable(),
);
```

The `MultiBlocProvider` block adds `BlocProvider.value(value: sessionCubit)`.

### App keys

Add to `client/lib/utils/app_keys.dart`:

- `configSessionSectionButton`
- `cliExecutablePathField`
- `cliExecutablePathBrowseButton`
- `cliExecutablePathResetButton`

The existing `autoLaunchAllMembersOnConnectSwitch` key is kept (moves with the
row).

## Testing

- **Unit:** `SessionPreferences` JSON round-trip; `resolveExecutable()`
  precedence rules (user-set > located > literal).
- **Unit:** `LaunchCommandBuilder.preview` honours the passed executable.
- **Widget:** `SessionConfigWorkspace` renders both rows; toggling the switch
  emits the expected cubit call; clearing the path falls back to the located
  one in the helper text.
- **Integration:** existing chat-launch tests continue to pass with the new
  `executableResolver` plumbing.

## Migration

None. `autoLaunchAllMembersOnConnect` is removed from `LayoutPreferences`
without migration code; existing SharedPreferences entries silently lose the
field on next read, which is the desired behaviour for this stage of the
project.

## Risks

- **Broken launch if user enters an invalid path.** Mitigation: the "Browse"
  button gives the easiest path to a known-good file; the helper text shows
  the effective resolved value so issues are visible before connecting.
- **Process spawn behaviour with absolute paths on Linux terminals.** The
  existing `_tryStartTerminal` helper passes the executable as an argument to
  `gnome-terminal`/`konsole`/etc., which accept absolute paths just as well as
  bare names — verified manually before merge.
