# Session Configuration & Configurable CLI Path — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a new "Session" configuration section that owns the auto-launch-all-members toggle (relocated from Layout) and a user-configurable `flashskyai` CLI executable path threaded through every launch site.

**Architecture:** New `SessionPreferences` model + repository + cubit. `LaunchCommandBuilder.executable` is removed; `launch()` and `preview()` accept the executable as a parameter. `TerminalSession`, `ChatCubit`, `TeamCubit` get an `executableResolver` (function returning the active path). `LlmConfigCubit` is converted from a one-shot `cliExecutablePath` to the same resolver pattern. UI adds a third config section with a path text-field + browse + reset and migrates the auto-launch switch into it.

**Tech Stack:** Flutter, `flutter_bloc`, `shared_preferences`, `file_picker`, `flutter_pty`, `xterm`. Tests use `flutter_test`.

**Project root:** `/home/hhoa/git/hhoa/flashskyai-ui`. All commands assume `cd client` first.

---

## File Structure

**New files:**

- `client/lib/models/session_preferences.dart` — immutable `SessionPreferences` value type
- `client/lib/repositories/session_preferences_repository.dart` — JSON storage in `SharedPreferences` (key `flashskyai.session_preferences.v1`)
- `client/lib/cubits/session_preferences_cubit.dart` — state + `resolveExecutable()` precedence logic
- `client/lib/pages/session_config_workspace.dart` — settings page with two rows
- `client/test/session_preferences_test.dart` — model JSON round-trip
- `client/test/session_preferences_repository_test.dart` — repo round-trip via mocked SharedPreferences
- `client/test/session_preferences_cubit_test.dart` — resolver precedence + mutation tests

**Modified files:**

- `client/lib/models/layout_preferences.dart` — remove `autoLaunchAllMembersOnConnect`
- `client/lib/services/launch_command_builder.dart` — remove `static const executable`; add `executable` parameter
- `client/lib/services/terminal_session.dart` — accept executable via constructor
- `client/lib/cubits/chat_cubit.dart` — add `executableResolver`, pass into `TerminalSession`
- `client/lib/cubits/team_cubit.dart` — add `executableResolver`, pass into `LaunchCommandBuilder`
- `client/lib/cubits/layout_cubit.dart` — remove `setAutoLaunchAllMembersOnConnect`
- `client/lib/cubits/llm_config_cubit.dart` — replace `cliExecutablePath` with `executableResolver`
- `client/lib/cubits/config_cubit.dart` — add `ConfigSection.session`
- `client/lib/pages/config_workspace.dart` — render new section, nav button, remove shell-session group from Layout
- `client/lib/router/app_router.dart` — add `/config/session` route
- `client/lib/widgets/ui_warmup.dart` — read effective executable from cubit
- `client/lib/utils/app_keys.dart` — add four new keys
- `client/lib/l10n/app_localizations.dart` — new keys: `session`, `sessionPageSubtitle`, `cliExecutablePathLabel`, `cliExecutablePathDescription`, `cliExecutablePathBrowse`, `cliExecutablePathReset`, `cliExecutablePathUsing`, `cliExecutablePathUsingFallback`
- `client/lib/main.dart` — wire up `SessionPreferencesCubit`, swap resolvers
- `client/test/launch_command_builder_test.dart` — update for new `executable` parameter
- `client/test/llm_config_cubit_test.dart` — update for resolver-based constructor

---

## Task 1: SessionPreferences model

**Files:**
- Create: `client/lib/models/session_preferences.dart`
- Create: `client/test/session_preferences_test.dart`

- [ ] **Step 1.1: Write the failing model tests**

Create `client/test/session_preferences_test.dart`:

```dart
import 'package:flashskyai_client/models/session_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path and auto-launch off', () {
      const prefs = SessionPreferences();
      expect(prefs.cliExecutablePath, '');
      expect(prefs.autoLaunchAllMembersOnConnect, false);
    });

    test('toJson/fromJson round-trips', () {
      const prefs = SessionPreferences(
        cliExecutablePath: '/opt/bin/flashskyai',
        autoLaunchAllMembersOnConnect: true,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.cliExecutablePath, '/opt/bin/flashskyai');
      expect(restored.autoLaunchAllMembersOnConnect, true);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePath, '');
      expect(restored.autoLaunchAllMembersOnConnect, false);
    });

    test('copyWith updates only specified fields', () {
      const prefs = SessionPreferences();
      final next = prefs.copyWith(cliExecutablePath: '/a/b');
      expect(next.cliExecutablePath, '/a/b');
      expect(next.autoLaunchAllMembersOnConnect, false);
    });
  });
}
```

- [ ] **Step 1.2: Verify the tests fail to compile**

Run: `cd client && flutter test test/session_preferences_test.dart`
Expected: build error — `Target of URI doesn't exist: 'package:flashskyai_client/models/session_preferences.dart'`.

- [ ] **Step 1.3: Create the model**

Create `client/lib/models/session_preferences.dart`:

```dart
class SessionPreferences {
  const SessionPreferences({
    this.cliExecutablePath = '',
    this.autoLaunchAllMembersOnConnect = false,
  });

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      cliExecutablePath: json['cliExecutablePath'] as String? ?? '',
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? false,
    );
  }

  /// Absolute path to the flashskyai CLI executable. Empty means "fall back
  /// to the path located at startup, then to bare 'flashskyai' (resolved by
  /// the OS via PATH)".
  final String cliExecutablePath;

  /// When true, connecting or restarting the shell session starts every valid
  /// team member instead of only the selected one.
  final bool autoLaunchAllMembersOnConnect;

  SessionPreferences copyWith({
    String? cliExecutablePath,
    bool? autoLaunchAllMembersOnConnect,
  }) {
    return SessionPreferences(
      cliExecutablePath: cliExecutablePath ?? this.cliExecutablePath,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cliExecutablePath': cliExecutablePath,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
    };
  }
}
```

- [ ] **Step 1.4: Run the tests to verify they pass**

Run: `cd client && flutter test test/session_preferences_test.dart`
Expected: 4 tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add client/lib/models/session_preferences.dart client/test/session_preferences_test.dart
git commit -m "feat(client): add SessionPreferences model"
```

---

## Task 2: SessionPreferencesRepository

**Files:**
- Create: `client/lib/repositories/session_preferences_repository.dart`
- Create: `client/test/session_preferences_repository_test.dart`

- [ ] **Step 2.1: Write the failing repository tests**

Create `client/test/session_preferences_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:flashskyai_client/models/session_preferences.dart';
import 'package:flashskyai_client/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns defaults when no stored value', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '');
    expect(loaded.autoLaunchAllMembersOnConnect, false);
  });

  test('round-trips through SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    await repo.save(const SessionPreferences(
      cliExecutablePath: '/usr/local/bin/flashskyai',
      autoLaunchAllMembersOnConnect: true,
    ));

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '/usr/local/bin/flashskyai');
    expect(loaded.autoLaunchAllMembersOnConnect, true);
  });

  test('falls back to defaults on malformed JSON', () async {
    SharedPreferences.setMockInitialValues({
      'flashskyai.session_preferences.v1': 'not-json',
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '');
    expect(loaded.autoLaunchAllMembersOnConnect, false);
  });

  test('stores JSON under the documented key', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    await repo.save(const SessionPreferences(cliExecutablePath: '/x'));

    final raw = prefs.getString('flashskyai.session_preferences.v1');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['cliExecutablePath'], '/x');
  });
}
```

- [ ] **Step 2.2: Verify the tests fail to compile**

Run: `cd client && flutter test test/session_preferences_repository_test.dart`
Expected: build error — repository import not found.

- [ ] **Step 2.3: Create the repository**

Create `client/lib/repositories/session_preferences_repository.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_preferences.dart';

class SessionPreferencesRepository {
  const SessionPreferencesRepository(this._preferences);

  static const storageKey = 'flashskyai.session_preferences.v1';

  final SharedPreferences _preferences;

  Future<SessionPreferences> load() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return const SessionPreferences();
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return const SessionPreferences();
      }
      return SessionPreferences.fromJson(
          Map<String, Object?>.from(decoded));
    } on FormatException {
      return const SessionPreferences();
    } on TypeError {
      return const SessionPreferences();
    }
  }

  Future<void> save(SessionPreferences preferences) async {
    await _preferences.setString(storageKey, jsonEncode(preferences.toJson()));
  }
}
```

- [ ] **Step 2.4: Run the tests to verify they pass**

Run: `cd client && flutter test test/session_preferences_repository_test.dart`
Expected: 4 tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add client/lib/repositories/session_preferences_repository.dart client/test/session_preferences_repository_test.dart
git commit -m "feat(client): add SessionPreferencesRepository"
```

---

## Task 3: SessionPreferencesCubit

**Files:**
- Create: `client/lib/cubits/session_preferences_cubit.dart`
- Create: `client/test/session_preferences_cubit_test.dart`

- [ ] **Step 3.1: Write the failing cubit tests**

Create `client/test/session_preferences_cubit_test.dart`:

```dart
import 'package:flashskyai_client/cubits/session_preferences_cubit.dart';
import 'package:flashskyai_client/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionPreferencesCubit> makeCubit({String? located}) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutable: located,
    );
  }

  test('resolveExecutable prefers user path over located path', () async {
    final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
    await cubit.load();
    await cubit.setCliExecutablePath('/opt/custom/flashskyai');

    expect(cubit.resolveExecutable(), '/opt/custom/flashskyai');
  });

  test('resolveExecutable falls back to located path when user path empty',
      () async {
    final cubit = await makeCubit(located: '/usr/local/bin/flashskyai');
    await cubit.load();

    expect(cubit.resolveExecutable(), '/usr/local/bin/flashskyai');
  });

  test('resolveExecutable falls back to bare flashskyai when nothing known',
      () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();

    expect(cubit.resolveExecutable(), 'flashskyai');
  });

  test('setCliExecutablePath persists and emits new state', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setCliExecutablePath('/a/b/flashskyai');

    expect(cubit.state.preferences.cliExecutablePath, '/a/b/flashskyai');

    // New cubit reads the persisted value.
    final cubit2 = await makeCubit(located: null);
    await cubit2.load();
    expect(cubit2.state.preferences.cliExecutablePath, '/a/b/flashskyai');
  });

  test('setAutoLaunchAllMembersOnConnect persists the flag', () async {
    final cubit = await makeCubit(located: null);
    await cubit.load();
    await cubit.setAutoLaunchAllMembersOnConnect(true);

    expect(cubit.state.preferences.autoLaunchAllMembersOnConnect, true);
  });

  test('setCliExecutablePath trims whitespace and treats blank as cleared',
      () async {
    final cubit = await makeCubit(located: '/located');
    await cubit.load();
    await cubit.setCliExecutablePath('   ');

    expect(cubit.state.preferences.cliExecutablePath, '');
    expect(cubit.resolveExecutable(), '/located');
  });
}
```

- [ ] **Step 3.2: Verify the tests fail to compile**

Run: `cd client && flutter test test/session_preferences_cubit_test.dart`
Expected: build error — cubit import not found.

- [ ] **Step 3.3: Create the cubit**

Create `client/lib/cubits/session_preferences_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/session_preferences.dart';
import '../repositories/session_preferences_repository.dart';

class SessionPreferencesState extends Equatable {
  const SessionPreferencesState({
    this.preferences = const SessionPreferences(),
    this.isLoading = true,
  });

  final SessionPreferences preferences;
  final bool isLoading;

  SessionPreferencesState copyWith({
    SessionPreferences? preferences,
    bool? isLoading,
  }) {
    return SessionPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [preferences, isLoading];
}

class SessionPreferencesCubit extends Cubit<SessionPreferencesState> {
  SessionPreferencesCubit({
    required SessionPreferencesRepository repository,
    String? locatedExecutable,
  })  : _repository = repository,
        _locatedExecutable = locatedExecutable,
        super(const SessionPreferencesState());

  final SessionPreferencesRepository _repository;
  final String? _locatedExecutable;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository.load();
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(SessionPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository.save(preferences);
  }

  Future<void> setCliExecutablePath(String value) {
    return _save(state.preferences.copyWith(cliExecutablePath: value.trim()));
  }

  Future<void> setAutoLaunchAllMembersOnConnect(bool value) {
    return _save(
        state.preferences.copyWith(autoLaunchAllMembersOnConnect: value));
  }

  /// Returns the actual executable string to invoke:
  ///   1. user-configured path (if non-empty after trim)
  ///   2. path discovered at startup (if non-null and non-empty)
  ///   3. literal `'flashskyai'` (OS resolves via PATH)
  String resolveExecutable() {
    final user = state.preferences.cliExecutablePath.trim();
    if (user.isNotEmpty) return user;
    final located = _locatedExecutable;
    if (located != null && located.isNotEmpty) return located;
    return 'flashskyai';
  }
}
```

- [ ] **Step 3.4: Run the tests to verify they pass**

Run: `cd client && flutter test test/session_preferences_cubit_test.dart`
Expected: 6 tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add client/lib/cubits/session_preferences_cubit.dart client/test/session_preferences_cubit_test.dart
git commit -m "feat(client): add SessionPreferencesCubit with resolveExecutable"
```

---

## Task 4: Parameterise LaunchCommandBuilder.executable

**Files:**
- Modify: `client/lib/services/launch_command_builder.dart`
- Modify: `client/test/launch_command_builder_test.dart`

- [ ] **Step 4.1: Update tests to expect the new signature**

Edit `client/test/launch_command_builder_test.dart`. The existing test at the bottom (`'quotes command preview for display'`) calls `LaunchCommandBuilder.preview(team, reviewer)`. Change it to pass an explicit executable:

Replace:
```dart
  test('quotes command preview for display', () {
    const team = TeamConfig(
      id: '1',
      name: 'hello team',
    );
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(team, reviewer),
      "flashskyai --team 'hello team' --member 'code reviewer'",
    );
  });
```

With:
```dart
  test('quotes command preview for display', () {
    const team = TeamConfig(
      id: '1',
      name: 'hello team',
    );
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(
        team,
        reviewer,
        executable: 'flashskyai',
      ),
      "flashskyai --team 'hello team' --member 'code reviewer'",
    );
  });

  test('preview honours the supplied executable path', () {
    const team = TeamConfig(id: '1', name: 'agent');
    const planner = TeamMemberConfig(id: 'm', name: 'planner');

    expect(
      LaunchCommandBuilder.preview(
        team,
        planner,
        executable: '/opt/custom/flashskyai',
      ),
      '/opt/custom/flashskyai --team agent --member planner',
    );
  });
```

- [ ] **Step 4.2: Run the tests to verify they fail with the missing parameter**

Run: `cd client && flutter test test/launch_command_builder_test.dart`
Expected: compile error — `preview` does not accept named parameter `executable`.

- [ ] **Step 4.3: Update `LaunchCommandBuilder` to require executable**

Edit `client/lib/services/launch_command_builder.dart`:

Delete the line `static const executable = 'flashskyai';` (currently line 17).

Update `preview`:
```dart
  static String preview(
    TeamConfig team,
    TeamMemberConfig member, {
    String? sessionTeam,
    required String executable,
  }) {
    return [
      executable,
      ...buildArguments(team, member, sessionTeam: sessionTeam, workingDirectory: ''),
    ].map(_quoteForPreview).join(' ');
  }
```

Update `launch` signature and replace each previous use of `executable` (the deleted constant) with the new parameter. Replace the entire method:

```dart
  static Future<void> launch(
    TeamConfig team, {
    required TeamMemberConfig member,
    required String executable,
    String? sessionTeam,
    String? workingDirectory,
    Map<String, String>? extraEnvironment,
    ProcessStarter starter = Process.start,
  }) async {
    final wd = workingDirectory ?? '';
    final args = buildArguments(team, member, sessionTeam: sessionTeam, workingDirectory: wd);
    final env = extraEnvironment;

    if (Platform.isLinux) {
      if (await _tryStartTerminal(starter, 'x-terminal-emulator', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'gnome-terminal', [
        '--',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'konsole', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'xterm', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
    } else if (Platform.isMacOS) {
      final exports = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'export ${e.key}=${_shellQuote(e.value)}').join('; ')}; ';
      final script =
          '${exports}cd ${_shellQuote(wd)} && '
          '${_shellQuote(executable)} ${args.map(_shellQuote).join(' ')}';
      if (await _tryStartTerminal(starter, 'open', [
        '-a',
        'Terminal',
        script,
      ], wd, env)) {
        return;
      }
    } else if (Platform.isWindows) {
      final sets = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'set ${e.key}=${e.value}').join(' && ')} && ';
      final command =
          '$sets${[executable, ...args].map(_windowsQuote).join(' ')}';
      if (await _tryStartTerminal(starter, 'cmd', [
        '/c',
        'start',
        'FlashskyAI',
        'cmd',
        '/k',
        command,
      ], wd, env)) {
        return;
      }
    }

    await starter(
      executable,
      args,
      workingDirectory: wd,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
  }
```

- [ ] **Step 4.4: Run the LaunchCommandBuilder tests to verify they pass**

Run: `cd client && flutter test test/launch_command_builder_test.dart`
Expected: all tests pass (including the two updated ones).

- [ ] **Step 4.5: Verify the rest of the project still compiles** (the constant removal breaks `terminal_session.dart` and `team_cubit.dart`)

Run: `cd client && flutter analyze lib/services/launch_command_builder.dart`
Expected: no errors in this file.

Run: `cd client && flutter analyze`
Expected: errors in `lib/cubits/team_cubit.dart` (calls `LaunchCommandBuilder.preview(team, member)` and `LaunchCommandBuilder.launch(team, member: member, ...)` without `executable:`) and `lib/services/terminal_session.dart` (references `LaunchCommandBuilder.executable`). These will be fixed in the next tasks — do **not** try to fix them here. Note them and move on.

- [ ] **Step 4.6: Commit**

```bash
git add client/lib/services/launch_command_builder.dart client/test/launch_command_builder_test.dart
git commit -m "refactor(client): require executable arg in LaunchCommandBuilder"
```

---

## Task 5: TerminalSession accepts executable

**Files:**
- Modify: `client/lib/services/terminal_session.dart`

- [ ] **Step 5.1: Update `TerminalSession` constructor**

Edit `client/lib/services/terminal_session.dart`. Replace the constructor (lines 10–17) with:

```dart
class TerminalSession {
  TerminalSession({required this.executable})
    : terminal = Terminal(
        maxLines: 10000,
        platform: defaultTargetPlatform == TargetPlatform.macOS
            ? TerminalTargetPlatform.macos
            : TerminalTargetPlatform.linux,
      );

  final String executable;
  final Terminal terminal;
```

(The original `final Terminal terminal;` line stays; only `executable` is added as a new field.)

- [ ] **Step 5.2: Use the field in `_spawnPty`**

In `_spawnPty`, replace `LaunchCommandBuilder.executable,` (line 105) with `executable,`. After the change the call site reads:

```dart
      _pty = Pty.start(
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: _extraEnvironment,
      );
```

The `import 'launch_command_builder.dart';` line at the top stays — it is still used by `LaunchCommandBuilder.splitArgs` calls further down.

- [ ] **Step 5.3: Run analyzer to confirm only chat_cubit / team_cubit still error**

Run: `cd client && flutter analyze lib/services/terminal_session.dart`
Expected: no errors.

Run: `cd client && flutter analyze`
Expected: errors remain only in `lib/cubits/chat_cubit.dart` (uses `TerminalSession.new` without `executable:`) and `lib/cubits/team_cubit.dart` (still missing `executable:` on LaunchCommandBuilder calls). Both fixed next.

- [ ] **Step 5.4: Commit**

```bash
git add client/lib/services/terminal_session.dart
git commit -m "refactor(client): require executable in TerminalSession"
```

---

## Task 6: ChatCubit takes an executableResolver

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`

- [ ] **Step 6.1: Change the TerminalSessionFactory signature**

Edit `client/lib/cubits/chat_cubit.dart`. Replace the typedef on line 14:

Old:
```dart
typedef TerminalSessionFactory = TerminalSession Function();
```

New:
```dart
typedef TerminalSessionFactory = TerminalSession Function({required String executable});
```

- [ ] **Step 6.2: Add the resolver to the ChatCubit constructor**

Replace the constructor block (currently lines 113–125). The auto-launch resolver is renamed `executableResolver` is **added**; the existing `autoLaunchAllMembersOnConnect` stays — it just gets wired to the session cubit in main.dart later.

```dart
class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    TerminalSessionFactory terminalSessionFactory = TerminalSession.new,
    PostFrameScheduler? postFrameScheduler,
    TempTeamCleaner? tempTeamCleaner,
    String? Function()? llmConfigPathOverride,
    bool Function()? autoLaunchAllMembersOnConnect,
    required String Function() executableResolver,
  }) : _terminalSessionFactory = terminalSessionFactory,
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _tempTeamCleaner = tempTeamCleaner,
       _llmConfigPathOverride = llmConfigPathOverride,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _executableResolver = executableResolver,
       super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  final TerminalSessionFactory _terminalSessionFactory;
  final PostFrameScheduler _postFrameScheduler;
  final TempTeamCleaner? _tempTeamCleaner;
  final String? Function()? _llmConfigPathOverride;
  final bool Function()? _autoLaunchAllMembersOnConnect;
  final String Function() _executableResolver;
```

- [ ] **Step 6.3: Pass the resolver into every factory call**

Every call to `_terminalSessionFactory()` (lines 214, 283, 433, 436 — confirm exact lines with `grep -n "_terminalSessionFactory" client/lib/cubits/chat_cubit.dart`) must now read:

```dart
_terminalSessionFactory(executable: _executableResolver())
```

For example, line 214 changes from `final ts = _terminalSessionFactory();` to `final ts = _terminalSessionFactory(executable: _executableResolver());`.

Use a search-and-replace approach: find each `_terminalSessionFactory()` and replace with `_terminalSessionFactory(executable: _executableResolver())`. Verify with:

Run: `cd client && grep -n "_terminalSessionFactory" lib/cubits/chat_cubit.dart`
Expected: no bare `_terminalSessionFactory()` remains; only `_terminalSessionFactory(executable: _executableResolver())` and the typedef / field declarations.

- [ ] **Step 6.4: Analyze chat_cubit.dart**

Run: `cd client && flutter analyze lib/cubits/chat_cubit.dart`
Expected: no errors in this file.

- [ ] **Step 6.5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart
git commit -m "refactor(client): inject executableResolver into ChatCubit"
```

---

## Task 7: TeamCubit takes an executableResolver

**Files:**
- Modify: `client/lib/cubits/team_cubit.dart`

- [ ] **Step 7.1: Add the resolver and use it in launcher + preview helpers**

Edit `client/lib/cubits/team_cubit.dart`. Replace the constructor and the helper methods on lines 58–91:

```dart
class TeamCubit extends Cubit<TeamState> {
  TeamCubit({
    required TeamRepository repository,
    required String Function() executableResolver,
    TeamLauncher? launcher,
    String? Function()? llmConfigPathOverride,
  })  : _repository = repository,
        _executableResolver = executableResolver,
        _llmConfigPathOverride = llmConfigPathOverride,
        _launcher = launcher ??
            ((team, member) => LaunchCommandBuilder.launch(team,
                member: member,
                executable: executableResolver(),
                extraEnvironment:
                    _envFromOverride(llmConfigPathOverride?.call()))),
        super(const TeamState());

  final TeamRepository _repository;
  final TeamLauncher _launcher;
  final String Function() _executableResolver;
  // ignore: unused_field
  final String? Function()? _llmConfigPathOverride;

  static Map<String, String>? _envFromOverride(String? override) {
    if (override == null || override.isEmpty) return null;
    return {'LLM_CONFIG_PATH': override};
  }

  String previewFor(TeamMemberConfig member) {
    final team = state.selectedTeam;
    return team == null
        ? ''
        : LaunchCommandBuilder.preview(
            team,
            member,
            executable: _executableResolver(),
          );
  }

  String get selectedCommandPreview {
    final team = state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(
      team,
      team.members.first,
      executable: _executableResolver(),
    );
  }
```

- [ ] **Step 7.2: Find and update any remaining LaunchCommandBuilder.preview call**

Run: `cd client && grep -n "LaunchCommandBuilder.preview" lib/cubits/team_cubit.dart`
Expected: previously line 225 had `LaunchCommandBuilder.preview(team, member)`. Update that call to:

```dart
LaunchCommandBuilder.preview(team, member, executable: _executableResolver())
```

- [ ] **Step 7.3: Analyze team_cubit.dart**

Run: `cd client && flutter analyze lib/cubits/team_cubit.dart`
Expected: no errors.

- [ ] **Step 7.4: Run the team_repository tests to ensure nothing regressed**

Run: `cd client && flutter test test/team_repository_test.dart test/launch_command_builder_test.dart`
Expected: all pass.

- [ ] **Step 7.5: Commit**

```bash
git add client/lib/cubits/team_cubit.dart
git commit -m "refactor(client): inject executableResolver into TeamCubit"
```

---

## Task 8: LlmConfigCubit uses executableResolver

**Files:**
- Modify: `client/lib/cubits/llm_config_cubit.dart`
- Modify: `client/test/llm_config_cubit_test.dart`

- [ ] **Step 8.1: Update existing tests to use the new constructor**

Edit `client/test/llm_config_cubit_test.dart`. In the existing test bodies, every call that passes `cliExecutablePath: '...'` must be replaced with `executableResolver: () => '...'`. The test cases that pass **no** `cliExecutablePath` should switch to `executableResolver: () => ''` (preserves the "unknown" semantics).

For the test on lines 30–46 (`'load uses CLI install dir as default when CLI is known'`), change:
```dart
      cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
```
to:
```dart
      executableResolver: () => '/opt/flashskyai/dist/flashskyai',
```

For the test on lines 48–60 (`'load returns empty effective path when CLI is unknown'`), add `executableResolver: () => ''` to the cubit constructor call. The cubit constructor below the change should read:
```dart
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
      executableResolver: () => '',
    );
```

For the test on lines 62+ (`'load uses override path when one is stored'`), add `executableResolver: () => ''` similarly.

Scan the whole file for any other instances:

Run: `cd client && grep -n "cliExecutablePath" test/llm_config_cubit_test.dart`
Expected after edits: no matches.

- [ ] **Step 8.2: Verify the tests fail with the new constructor**

Run: `cd client && flutter test test/llm_config_cubit_test.dart`
Expected: compile error — `LlmConfigCubit` does not accept `executableResolver`.

- [ ] **Step 8.3: Replace `_cliExecutablePath` with `_executableResolver` in the cubit**

Edit `client/lib/cubits/llm_config_cubit.dart`. Replace the constructor (lines 85–100) with:

```dart
class LlmConfigCubit extends Cubit<LlmConfigState> {
  LlmConfigCubit({
    required AppSettingsRepository appSettings,
    required String currentDirectory,
    required String? homeDirectory,
    required String Function() executableResolver,
    LlmConfigRepositoryFactory? repositoryFactory,
    LlmConfig initialConfig = const LlmConfig(),
  })  : _appSettings = appSettings,
        _currentDirectory = currentDirectory,
        _homeDirectory = homeDirectory,
        _executableResolver = executableResolver,
        _repositoryFactory =
            repositoryFactory ?? ((path) => LlmConfigRepository(File(path))),
        super(LlmConfigState(
            config: initialConfig, savedConfig: initialConfig));

  final AppSettingsRepository _appSettings;
  final String _currentDirectory;
  final String? _homeDirectory;
  final String Function() _executableResolver;
  final LlmConfigRepositoryFactory _repositoryFactory;
  LlmConfigRepository? _repository;
```

In `load()` (lines 114–139), replace the `cliExecutablePath: _cliExecutablePath,` line with:

```dart
      cliExecutablePath: _executableResolver(),
```

Note: `resolveLlmConfigPath` still accepts a string. We pass the resolved string in. An empty string preserves the "unknown" branch in the resolver.

- [ ] **Step 8.4: Run the llm config tests**

Run: `cd client && flutter test test/llm_config_cubit_test.dart`
Expected: all tests pass.

- [ ] **Step 8.5: Commit**

```bash
git add client/lib/cubits/llm_config_cubit.dart client/test/llm_config_cubit_test.dart
git commit -m "refactor(client): LlmConfigCubit takes executableResolver"
```

---

## Task 9: Remove autoLaunchAllMembersOnConnect from LayoutPreferences

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`

- [ ] **Step 9.1: Strip the field from `LayoutPreferences`**

Edit `client/lib/models/layout_preferences.dart`.

- Delete the constructor default `this.autoLaunchAllMembersOnConnect = false,` (line 22)
- Delete the fromJson branch (lines 56–57: `autoLaunchAllMembersOnConnect: json[...]`)
- Delete the doc comment lines 85–86 and the field declaration on line 87
- Delete `bool? autoLaunchAllMembersOnConnect,` from `copyWith` (line 103)
- Delete the `autoLaunchAllMembersOnConnect: autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,` line in the copyWith body (lines 129–130)
- Delete the `autoLaunchAllMembersOnConnect: autoLaunchAllMembersOnConnect,` line in `withAtLeastOneToolVisible` (line 152)
- Delete the `'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,` line in `toJson` (line 171)

After edits, run `cd client && grep -n autoLaunchAllMembers lib/models/layout_preferences.dart`. Expected: no matches.

- [ ] **Step 9.2: Strip the method from `LayoutCubit`**

Edit `client/lib/cubits/layout_cubit.dart`. Delete the `setAutoLaunchAllMembersOnConnect` method (lines 86–88):

```dart
  Future<void> setAutoLaunchAllMembersOnConnect(bool value) => _save(
        state.preferences.copyWith(autoLaunchAllMembersOnConnect: value),
      );
```

- [ ] **Step 9.3: Analyze; expect errors only in main.dart and config_workspace.dart**

Run: `cd client && flutter analyze`
Expected errors:
- `lib/main.dart` — reads `layoutCubit.state.preferences.autoLaunchAllMembersOnConnect` (line ~100)
- `lib/pages/config_workspace.dart` — references `preferences.autoLaunchAllMembersOnConnect` and `controller.setAutoLaunchAllMembersOnConnect(value)` (lines 240–243)

Both fixed in later tasks. No need to fix now.

- [ ] **Step 9.4: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart
git commit -m "refactor(client): remove autoLaunchAllMembersOnConnect from LayoutPreferences"
```

---

## Task 10: Add ConfigSection.session, AppKeys, and i18n strings

**Files:**
- Modify: `client/lib/cubits/config_cubit.dart`
- Modify: `client/lib/utils/app_keys.dart`
- Modify: `client/lib/l10n/app_localizations.dart`

- [ ] **Step 10.1: Extend ConfigSection enum**

Edit `client/lib/cubits/config_cubit.dart`. Update line 6 from:

```dart
enum ConfigSection { layout, llm }
```

to:

```dart
enum ConfigSection { layout, llm, session }
```

Update `title` and `breadcrumb` getters:

```dart
  String get title => switch (section) {
        ConfigSection.layout => 'Layout Configuration',
        ConfigSection.llm => 'LLM Configuration',
        ConfigSection.session => 'Session Configuration',
      };

  String get breadcrumb => switch (section) {
        ConfigSection.layout => 'Config / Layout',
        ConfigSection.llm => 'Config / LLM',
        ConfigSection.session => 'Config / Session',
      };
```

- [ ] **Step 10.2: Add AppKeys**

Edit `client/lib/utils/app_keys.dart`. Add these four keys somewhere near the other config keys (e.g., right after line 39 `configLlmSectionButton`):

```dart
  static const configSessionSectionButton =
      Key('config-session-section-button');
  static const cliExecutablePathField = Key('cli-executable-path-field');
  static const cliExecutablePathBrowseButton =
      Key('cli-executable-path-browse-button');
  static const cliExecutablePathResetButton =
      Key('cli-executable-path-reset-button');
```

Leave the existing `autoLaunchAllMembersOnConnectSwitch` key as-is.

- [ ] **Step 10.3: Add i18n keys (getter declarations)**

Edit `client/lib/l10n/app_localizations.dart`. Find the getter list (the cluster around line 107–134). After `String get layoutPageSubtitle` (line 107) — and **adjacent** to it for readability — add:

```dart
  String get session => _strings['session']!;
  String get sessionPageSubtitle => _strings['sessionPageSubtitle']!;
  String get cliExecutablePathLabel => _strings['cliExecutablePathLabel']!;
  String get cliExecutablePathDescription =>
      _strings['cliExecutablePathDescription']!;
  String get cliExecutablePathBrowse => _strings['cliExecutablePathBrowse']!;
  String get cliExecutablePathReset => _strings['cliExecutablePathReset']!;
  String get cliExecutablePathUsing => _strings['cliExecutablePathUsing']!;
  String get cliExecutablePathUsingFallback =>
      _strings['cliExecutablePathUsingFallback']!;
```

- [ ] **Step 10.4: Add i18n strings (the map)**

In the same file, locate the `'layout': {'en': 'Layout', 'zh': '通用'},` entry (around line 388). Right after it (before `layoutSubtitle`), add:

```dart
    'session': {'en': 'Session', 'zh': '会话'},
    'sessionPageSubtitle': {
      'en': 'Configure how shell sessions are launched.',
      'zh': '配置 Shell 会话的启动方式。',
    },
    'cliExecutablePathLabel': {
      'en': 'flashskyai CLI path',
      'zh': 'flashskyai CLI 路径',
    },
    'cliExecutablePathDescription': {
      'en':
          'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.',
      'zh': 'flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。',
    },
    'cliExecutablePathBrowse': {'en': 'Browse…', 'zh': '浏览…'},
    'cliExecutablePathReset': {'en': 'Reset', 'zh': '重置'},
    'cliExecutablePathUsing': {'en': 'Using: ', 'zh': '当前生效：'},
    'cliExecutablePathUsingFallback': {
      'en': 'Using PATH lookup',
      'zh': '使用 PATH 中查找的版本',
    },
```

- [ ] **Step 10.5: Analyze**

Run: `cd client && flutter analyze lib/cubits/config_cubit.dart lib/utils/app_keys.dart lib/l10n/app_localizations.dart`
Expected: no errors.

- [ ] **Step 10.6: Commit**

```bash
git add client/lib/cubits/config_cubit.dart client/lib/utils/app_keys.dart client/lib/l10n/app_localizations.dart
git commit -m "feat(client): add ConfigSection.session, AppKeys, and i18n strings"
```

---

## Task 11: Create SessionConfigWorkspace page

**Files:**
- Create: `client/lib/pages/session_config_workspace.dart`

- [ ] **Step 11.1: Implement the page**

Create `client/lib/pages/session_config_workspace.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/app_workspace_settings_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_settings_widgets.dart';

class SessionConfigWorkspace extends StatelessWidget {
  const SessionConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.watch<SessionPreferencesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionHeading(
          title: l10n.session,
          subtitle: l10n.sessionPageSubtitle,
        ),
        const SizedBox(height: 16),
        _SessionControls(cubit: cubit),
      ],
    );
  }
}

class _SessionHeading extends StatelessWidget {
  const _SessionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: tokens.workspaceHeadingTitleStyle(onSurface)),
        SizedBox(height: tokens.workspaceHeadingTitleSubtitleGap),
        Text(subtitle, style: tokens.workspaceHeadingSubtitleStyle(onSurface)),
      ],
    );
  }
}

class _SessionControls extends StatefulWidget {
  const _SessionControls({required this.cubit});

  final SessionPreferencesCubit cubit;

  @override
  State<_SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<_SessionControls> {
  late final TextEditingController _pathController;
  String _lastSyncedPath = '';

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.cubit.state.preferences.cliExecutablePath,
    );
    _lastSyncedPath = widget.cubit.state.preferences.cliExecutablePath;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _syncFromState(String stored) {
    if (stored != _lastSyncedPath) {
      _lastSyncedPath = stored;
      _pathController.value = TextEditingValue(
        text: stored,
        selection: TextSelection.collapsed(offset: stored.length),
      );
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    _pathController.text = picked;
    await widget.cubit.setCliExecutablePath(picked);
  }

  Future<void> _apply() async {
    await widget.cubit.setCliExecutablePath(_pathController.text);
  }

  Future<void> _reset() async {
    _pathController.clear();
    await widget.cubit.setCliExecutablePath('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    _syncFromState(state.preferences.cliExecutablePath);
    final effective = widget.cubit.resolveExecutable();
    final isFallback = state.preferences.cliExecutablePath.trim().isEmpty;
    final helper = isFallback
        ? l10n.cliExecutablePathUsingFallback
        : '${l10n.cliExecutablePathUsing}$effective';

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsLabeledRow(
                title: l10n.cliExecutablePathLabel,
                subtitle: l10n.cliExecutablePathDescription,
                trailing: SizedBox(
                  width: 420,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: AppKeys.cliExecutablePathField,
                          controller: _pathController,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                          onSubmitted: (_) => _apply(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        key: AppKeys.cliExecutablePathBrowseButton,
                        onPressed: _pickFile,
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: Text(l10n.cliExecutablePathBrowse),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        key: AppKeys.cliExecutablePathResetButton,
                        onPressed: isFallback ? null : _reset,
                        child: Text(l10n.cliExecutablePathReset),
                      ),
                    ],
                  ),
                ),
                showDividerBelow: true,
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  helper,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              SettingsLabeledRow(
                title: l10n.autoLaunchAllMembersTitle,
                subtitle: l10n.autoLaunchAllMembersDescription,
                trailing: Switch(
                  key: AppKeys.autoLaunchAllMembersOnConnectSwitch,
                  value: state.preferences.autoLaunchAllMembersOnConnect,
                  onChanged: (value) =>
                      widget.cubit.setAutoLaunchAllMembersOnConnect(value),
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 11.2: Analyze the new file**

Run: `cd client && flutter analyze lib/pages/session_config_workspace.dart`
Expected: no errors.

- [ ] **Step 11.3: Commit**

```bash
git add client/lib/pages/session_config_workspace.dart
git commit -m "feat(client): add SessionConfigWorkspace page"
```

---

## Task 12: Wire SessionConfigWorkspace into ConfigWorkspace + router

**Files:**
- Modify: `client/lib/pages/config_workspace.dart`
- Modify: `client/lib/router/app_router.dart`

- [ ] **Step 12.1: Add Session nav item and route the body**

Edit `client/lib/pages/config_workspace.dart`.

At the top, add the import:
```dart
import 'session_config_workspace.dart';
```

Update the body switch (around lines 87–92) to handle the new section. Replace:
```dart
                            child: switch (configCubit.state.section) {
                              ConfigSection.layout =>
                                const LayoutConfigWorkspace(),
                              ConfigSection.llm =>
                                const LlmConfigWorkspace(),
                            },
```

With:
```dart
                            child: switch (configCubit.state.section) {
                              ConfigSection.layout =>
                                const LayoutConfigWorkspace(),
                              ConfigSection.llm =>
                                const LlmConfigWorkspace(),
                              ConfigSection.session =>
                                const SessionConfigWorkspace(),
                            },
```

Update `_ConfigNavPanel.build` (around lines 408–425) to append a Session nav item after Layout. Replace the inner `Column.children`:

```dart
        children: [
          _ConfigNavItem(
            key: AppKeys.configLlmSectionButton,
            title: l10n.llmConfig,
            icon: Icons.memory_outlined,
            compact: compact,
            selected: section == ConfigSection.llm,
            onTap: () => onSelectSection(ConfigSection.llm),
          ),
          _ConfigNavItem(
            key: AppKeys.configLayoutSectionButton,
            title: l10n.layout,
            icon: Icons.dashboard_customize_outlined,
            compact: compact,
            selected: section == ConfigSection.layout,
            onTap: () => onSelectSection(ConfigSection.layout),
          ),
        ],
```

With:

```dart
        children: [
          _ConfigNavItem(
            key: AppKeys.configLlmSectionButton,
            title: l10n.llmConfig,
            icon: Icons.memory_outlined,
            compact: compact,
            selected: section == ConfigSection.llm,
            onTap: () => onSelectSection(ConfigSection.llm),
          ),
          _ConfigNavItem(
            key: AppKeys.configLayoutSectionButton,
            title: l10n.layout,
            icon: Icons.dashboard_customize_outlined,
            compact: compact,
            selected: section == ConfigSection.layout,
            onTap: () => onSelectSection(ConfigSection.layout),
          ),
          _ConfigNavItem(
            key: AppKeys.configSessionSectionButton,
            title: l10n.session,
            icon: Icons.terminal_outlined,
            compact: compact,
            selected: section == ConfigSection.session,
            onTap: () => onSelectSection(ConfigSection.session),
          ),
        ],
```

- [ ] **Step 12.2: Remove the Shell session group from LayoutConfigWorkspace**

In the same file, find `_LayoutControls.build` (around lines 142–298). Delete the `SettingsGroupHeader(title: l10n.shellSession),` followed by the `SettingsLabeledRow` for `autoLaunchAllMembersTitle` (lines 235–246):

```dart
              SettingsGroupHeader(title: l10n.shellSession),
              SettingsLabeledRow(
                title: l10n.autoLaunchAllMembersTitle,
                subtitle: l10n.autoLaunchAllMembersDescription,
                trailing: Switch(
                  key: AppKeys.autoLaunchAllMembersOnConnectSwitch,
                  value: preferences.autoLaunchAllMembersOnConnect,
                  onChanged: (value) =>
                      controller.setAutoLaunchAllMembersOnConnect(value),
                ),
                showDividerBelow: true,
              ),
```

After deletion the file no longer references `autoLaunchAllMembers...` on `preferences` or `controller`. Verify:

Run: `cd client && grep -n "autoLaunchAllMembers" lib/pages/config_workspace.dart`
Expected: no matches.

- [ ] **Step 12.3: Add the router entry**

Edit `client/lib/router/app_router.dart`. After the `/config/llm` GoRoute (lines 68–73), add:

```dart
        GoRoute(
          path: '/config/session',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.session),
          ),
        ),
```

- [ ] **Step 12.4: Analyze**

Run: `cd client && flutter analyze lib/pages/config_workspace.dart lib/router/app_router.dart`
Expected: no errors.

- [ ] **Step 12.5: Commit**

```bash
git add client/lib/pages/config_workspace.dart client/lib/router/app_router.dart
git commit -m "feat(client): expose Session config section in nav and router"
```

---

## Task 13: Read effective executable in ui_warmup preview

**Files:**
- Modify: `client/lib/widgets/ui_warmup.dart`

- [ ] **Step 13.1: Locate the hardcoded command string**

Run: `cd client && grep -n "'flashskyai " lib/widgets/ui_warmup.dart`
Expected: line ~184: `command: 'flashskyai --member ${member.name}',`

Note: also check surrounding context for whether this widget already has a `BuildContext` and whether `flutter_bloc` is imported.

Run: `cd client && grep -n "import\|class.*StatelessWidget\|class.*State<" lib/widgets/ui_warmup.dart | head`

- [ ] **Step 13.2: Add the import and read the cubit**

Edit `client/lib/widgets/ui_warmup.dart`. Add the import near the existing ones:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
```

(Only add `flutter_bloc` if not already imported in this file.)

Inside the `build` method of the widget containing line ~184, near the top before the `ListView`/`Column` is constructed, read the executable:

```dart
    final executable = context.watch<SessionPreferencesCubit>().resolveExecutable();
```

Then replace the offending line:

```dart
                    command: 'flashskyai --member ${member.name}',
```

with:

```dart
                    command: '$executable --member ${member.name}',
```

- [ ] **Step 13.3: Analyze**

Run: `cd client && flutter analyze lib/widgets/ui_warmup.dart`
Expected: no errors.

- [ ] **Step 13.4: Commit**

```bash
git add client/lib/widgets/ui_warmup.dart
git commit -m "feat(client): show effective CLI path in warmup preview"
```

---

## Task 14: Wire everything in main.dart

**Files:**
- Modify: `client/lib/main.dart`

- [ ] **Step 14.1: Update imports**

Edit `client/lib/main.dart`. Add the new imports next to the existing ones:

```dart
import 'cubits/session_preferences_cubit.dart';
import 'repositories/session_preferences_repository.dart';
```

- [ ] **Step 14.2: Replace the cubit wiring**

Find the block lines 74–101 (the section starting `final appSettings = ...`). Replace lines 77–101 with:

```dart
  final cliLocated = await FlashskyaiCliLocator.locate();

  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutable: cliLocated,
  );

  final llmConfigCubit = LlmConfigCubit(
    appSettings: appSettings,
    currentDirectory: Directory.current.path,
    homeDirectory: homeDirectory,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
  );

  String? llmConfigPathOverrideForLaunch() {
    final s = llmConfigCubit.state;
    return s.isUsingCustomPath ? s.effectiveConfigPath : null;
  }

  final teamCubit = TeamCubit(
    repository: teamRepo,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
  );
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final chatCubit = ChatCubit(
    tempTeamCleaner: tempTeamCleaner,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    autoLaunchAllMembersOnConnect: () =>
        sessionPreferencesCubit.state.preferences.autoLaunchAllMembersOnConnect,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
  );
```

- [ ] **Step 14.3: Load the session cubit and register it in the provider tree**

Right after the existing `await teamCubit.load();` block, add:

```dart
  await sessionPreferencesCubit.load();
```

In the `MultiBlocProvider.providers` list, add a provider entry:

```dart
        BlocProvider.value(value: sessionPreferencesCubit),
```

(Place it next to the other `BlocProvider.value` entries — e.g., after `layoutCubit`.)

- [ ] **Step 14.4: Analyze the whole project**

Run: `cd client && flutter analyze`
Expected: no errors anywhere.

- [ ] **Step 14.5: Run all tests**

Run: `cd client && flutter test`
Expected: all tests pass. If `widget_test.dart` fails because it constructs cubits without the new required parameters, update its fixture to provide `executableResolver: () => 'flashskyai'` and a fake `SessionPreferencesCubit` registered in the provider tree.

If widget_test fails, inspect it first:

Run: `cd client && head -80 test/widget_test.dart`

Update the test setup to register the session cubit and pass the new required args, then re-run tests.

- [ ] **Step 14.6: Commit**

```bash
git add client/lib/main.dart client/test
git commit -m "feat(client): wire SessionPreferencesCubit through app startup"
```

---

## Task 15: Manual smoke verification

**Files:** _(no code changes)_

- [ ] **Step 15.1: Launch the app**

Run: `cd client && flutter run -d linux` (or the appropriate desktop target).

- [ ] **Step 15.2: Verify the Session section exists in settings**

Navigate to Settings (gear icon). Confirm the nav panel shows three items in order: **Provider (LLM), Layout, Session**. Click **Session**.

- [ ] **Step 15.3: Verify CLI path control behaviour**

- The text field starts empty; the helper line below reads **"Using PATH lookup"** (or zh equivalent).
- Click **Browse**, pick the `flashskyai` binary; the field populates with its absolute path, and the helper line now reads **"Using: <path>"**.
- Click **Reset**; the field clears, helper reverts to "Using PATH lookup".
- Hit Enter in a manually-typed path; the helper reflects the entered value.

- [ ] **Step 15.4: Verify auto-launch toggle works in the new location and is gone from Layout**

- Toggle **Start all members on connect** on/off in Session. Confirm the persisted value survives an app restart.
- Switch to the **Layout** section. Confirm there is no longer a "Shell session" group.

- [ ] **Step 15.5: Verify chat launch uses the configured path**

- Set the CLI path to a deliberately wrong value (e.g., `/tmp/nope`). Click **Connect** on a team. Expect a failure message in the terminal pane that references `/tmp/nope`, proving the configured path is being used.
- Set the path to the real binary (or reset). Click **Connect**. Confirm a session starts normally.

- [ ] **Step 15.6: Verify warmup preview reflects the configured path**

Open the warmup overlay (the screen that lists "Member launch order"). Confirm the preview command at each member row begins with the configured path rather than literal `flashskyai`.

- [ ] **Step 15.7: Final test sweep**

Run: `cd client && flutter test`
Expected: all green.

Run: `cd client && flutter analyze`
Expected: no warnings or errors.

- [ ] **Step 15.8: Final commit (only if verification surfaced fixes)**

If smoke testing required tweaks, commit them. Otherwise no commit is needed.

```bash
git status
# If clean: done. Otherwise:
git add -A
git commit -m "fix(client): smoke-test polish for session config"
```

---

## Self-Review Notes

Verified before publishing:

1. **Spec coverage.** Every item in `docs/superpowers/specs/2026-05-12-session-config-design.md` is covered by a task:
   - Model + repository + cubit → Tasks 1–3
   - LaunchCommandBuilder parameterisation → Task 4
   - TerminalSession constructor change → Task 5
   - ChatCubit / TeamCubit resolver plumbing → Tasks 6–7
   - LlmConfigCubit resolver alignment → Task 8
   - Removal of `autoLaunchAllMembersOnConnect` from LayoutPreferences → Task 9
   - ConfigSection enum, AppKeys, i18n → Task 10
   - Session UI page → Task 11
   - Nav + router wiring + Layout cleanup → Task 12
   - `ui_warmup.dart` preview → Task 13
   - main.dart assembly → Task 14
   - Manual smoke → Task 15
2. **No placeholders.** Every code step contains real Dart; commands list expected output.
3. **Type consistency.** `String Function()` is used uniformly for `executableResolver` across ChatCubit, TeamCubit, and LlmConfigCubit. `SessionPreferencesCubit.resolveExecutable()` returns a non-empty `String` always, so callers never need to null-check.
4. **TerminalSessionFactory signature.** Updated typedef matches the new `TerminalSession({required this.executable})` constructor (positional → named with required `executable`). All `_terminalSessionFactory(...)` call sites adjusted in Task 6.
