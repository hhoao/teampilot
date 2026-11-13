# ACP 可用命令接入组合斜杠菜单 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ACP 会话把 agent 通过 `available_commands_update` 下发的命令列表接入组合斜杠菜单，非空时整体替换静态表，未下发时回退静态表。

**Architecture:** 沿用 `modelState` 的现有链路：`AcpAgentSession` 映射并保留命令列表 → `AcpChatRuntimeCubit` 状态 → `AcpRuntimeScope` 投影 → `SessionChatComposeSection` 选择动态或静态命令。握手期推送用可选能力接口的 pull getter 播种，避免 broadcast 流在订阅前丢帧。

**Tech Stack:** Flutter / Dart 3, flutter_bloc (Cubit), acpd (ACP schema package), flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-13-acp-available-commands-design.md`

## Global Constraints

- **Never** invoke `flutter test` directly. Every test run is:
  `cd client && dart run tool/run_tests.dart <test paths>`.
- Inner loop is `cd client && flutter analyze`; do not run the full suite for these local changes.
- Agent-provided descriptions are shown verbatim (English); do **not** add l10n keys for them.
- Command names are slash-free at rest. `NativeCommand` tolerates one leading `/` only in its getters.
- No new local command execution path: commands remain plain `session/prompt` text.
- Diagnostics use `AppLogger`; no `print`.

---

### Task 1: Native command model, catalog, and menu subtitle

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/native_command_capability.dart`
- Modify: `client/lib/services/chat/conversation/compose/compose_slash_catalog.dart`
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart:1054-1071`
- Test: `client/test/services/cli/registry/native_command_capability_test.dart`
- Test: `client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart`
- Test: `client/test/widgets/compose/compose_trigger_field_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `NativeCommand({required String name, NativeCommandDescription? description, String? descriptionText, String? argumentHint, NativeCommandAvailability availability})`
  - `String NativeCommand.slashName`
  - `String NativeCommand.insertText` (uses `slashName`)
  - `ComposeSlashCandidate.descriptionText` (`String?`)
  - `List<ComposeSlashCandidate> buildComposeSlashCandidates(...)` unchanged signature

- [ ] **Step 1: Write the failing model tests**

Append to `client/test/services/cli/registry/native_command_capability_test.dart` inside `main()`:

```dart
  test('normalizes one leading slash from command names', () {
    const command = NativeCommand(
      name: '/compact',
      description: NativeCommandDescription.compact,
    );

    expect(command.slashName, 'compact');
    expect(command.insertText, '/compact');
  });

  test('agent-provided descriptions do not require an enum value', () {
    const command = NativeCommand(
      name: 'create_plan',
      descriptionText: 'Create an implementation plan',
      argumentHint: '<what>',
    );

    expect(command.description, isNull);
    expect(command.descriptionText, 'Create an implementation plan');
    expect(command.insertText, '/create_plan ');
  });
```

- [ ] **Step 2: Run the model tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/native_command_capability_test.dart`

Expected: FAIL — `slashName` and `descriptionText` are not defined on `NativeCommand`.

- [ ] **Step 3: Implement the model change**

Replace `NativeCommand` in `client/lib/services/cli/registry/capabilities/native_command_capability.dart`:

```dart
final class NativeCommand {
  const NativeCommand({
    required this.name,
    this.description,
    this.descriptionText,
    this.argumentHint,
    this.availability = NativeCommandAvailability.stable,
  });

  final String name;

  /// Localized enum used by the curated static tables.
  final NativeCommandDescription? description;

  /// Agent-provided free text (ACP `AvailableCommand.description`).
  final String? descriptionText;

  final String? argumentHint;
  final NativeCommandAvailability availability;

  /// Command names are slash-free; tolerate one leading `/` from adapter data.
  String get slashName => name.startsWith('/') ? name.substring(1) : name;

  bool get acceptsArgument => argumentHint != null;

  String get insertText => acceptsArgument ? '/$slashName ' : '/$slashName';
}
```

- [ ] **Step 4: Run the model tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/native_command_capability_test.dart`

Expected: PASS (all tests in the file).

- [ ] **Step 5: Write the failing catalog tests**

Append to `client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart` inside `main()`:

```dart
  test('normalizes a leading slash in native command labels', () {
    final candidates = buildComposeSlashCandidates(
      skills: const [],
      plugins: const [],
      enabledBundle: const ConfigBundle(),
      query: '',
      nativeCommands: const [
        NativeCommand(
          name: '/compact',
          description: NativeCommandDescription.compact,
        ),
      ],
    );

    expect(candidates.single.label, 'compact');
    expect(candidates.single.insertText, '/compact');
  });

  test('filters native commands by agent-provided description text', () {
    final candidates = buildComposeSlashCandidates(
      skills: const [],
      plugins: const [],
      enabledBundle: const ConfigBundle(),
      query: 'diagram',
      nativeCommands: const [
        NativeCommand(name: 'create_plan', descriptionText: 'Draft a diagram'),
      ],
    );

    expect(candidates.single.label, 'create_plan');
    expect(candidates.single.insertText, '/create_plan');
  });
```

- [ ] **Step 6: Run the catalog tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_slash_catalog_test.dart`

Expected: FAIL — label is `/compact` and the `diagram` query returns no candidate.

- [ ] **Step 7: Implement the catalog change**

In `client/lib/services/chat/conversation/compose/compose_slash_catalog.dart`:

Add the field to `ComposeSlashCandidate` (constructor parameter `this.descriptionText,` and member `final String? descriptionText;` next to `description`).

Replace the native command loop (currently lines 76-90) with:

```dart
  for (final command in nativeCommands) {
    final name = command.slashName.trim();
    if (name.isEmpty) continue;
    add(
      ComposeSlashCandidate(
        insertText: command.insertText,
        label: name,
        kind: ComposeSlashCandidateKind.command,
        source: ComposeSlashCandidateSource.native,
        description: command.description,
        descriptionText: command.descriptionText,
        availability: command.availability,
        insertionSuffix: '',
      ),
    );
  }
```

Replace the filter inside `add` (currently lines 52-57) with:

```dart
    if (needle.isNotEmpty) {
      final haystack = [
        candidate.description?.searchTerms,
        candidate.descriptionText,
      ].whereType<String>().join(' ').toLowerCase();
      if (!candidate.label.toLowerCase().contains(needle) &&
          !haystack.contains(needle)) {
        return;
      }
    }
```

- [ ] **Step 8: Run the catalog tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_slash_catalog_test.dart`

Expected: PASS.

- [ ] **Step 9: Write the failing widget test**

Append to `client/test/widgets/compose/compose_trigger_field_test.dart` inside `main()`:

```dart
  testWidgets('agent-provided command description is shown in the menu', (
    tester,
  ) async {
    final bus = CommandBus();
    final controller = ComposeTextController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpField(
      tester,
      bus: bus,
      controller: controller,
      focusNode: focusNode,
      onSubmit: () {},
      nativeCommands: const [
        NativeCommand(
          name: 'create_plan',
          descriptionText: 'Create an implementation plan',
          argumentHint: '<what>',
        ),
      ],
    );

    focusNode.requestFocus();
    await tester.pump();
    await enterComposeText(tester, '/cre');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.textContaining('Create an implementation plan'), findsOneWidget);
  });
```

- [ ] **Step 10: Run the widget test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/compose/compose_trigger_field_test.dart`

Expected: FAIL — the subtitle only renders the localized enum.

- [ ] **Step 11: Implement the subtitle change**

In `client/lib/widgets/compose/compose_trigger_field.dart`, replace `_commandDetails` (lines 1054-1071) with:

```dart
  String? _commandDetails(
    BuildContext context,
    ComposeSlashCandidate candidate,
  ) {
    final l10n = context.l10n;
    final agentDescription = candidate.descriptionText?.trim();
    final descriptionDetail =
        agentDescription != null && agentDescription.isNotEmpty
        ? agentDescription
        : (candidate.description?.localized(context) ?? '');
    final details = <String>[
      switch (candidate.source) {
        ComposeSlashCandidateSource.native => l10n.compose.commandNative,
        ComposeSlashCandidateSource.plugin => l10n.compose.commandPlugin,
        null => '',
      },
      if (candidate.subtitle?.trim().isNotEmpty == true)
        candidate.subtitle!.trim(),
      if (descriptionDetail.isNotEmpty) descriptionDetail,
    ].where((detail) => detail.isNotEmpty).toList();
    return details.isEmpty ? null : details.join(' · ');
  }
```

- [ ] **Step 12: Run all three affected suites**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/cli/registry/native_command_capability_test.dart \
  test/services/chat/conversation/compose/compose_slash_catalog_test.dart \
  test/widgets/compose/compose_trigger_field_test.dart
```

Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/native_command_capability.dart \
  client/lib/services/chat/conversation/compose/compose_slash_catalog.dart \
  client/lib/widgets/compose/compose_trigger_field.dart \
  client/test/services/cli/registry/native_command_capability_test.dart \
  client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart \
  client/test/widgets/compose/compose_trigger_field_test.dart
git commit -m "feat(compose): support agent-provided native command descriptions"
```

---

### Task 2: Map ACP available commands and retain the latest list

**Files:**
- Modify: `client/lib/services/acp/acp_session.dart` (types near `AcpModelStateUpdate:348`, `_onSessionUpdate:930-997`, `_mapUpdate:1153-1214`)
- Modify: `client/lib/services/acp/acp_session_runtime.dart` (optional capability near `AcpModelSwitchApi:238`, impl list `:256-261`, getter near `modelState:579-581`)
- Test: `client/test/services/acp/acp_session_test.dart`

**Interfaces:**
- Consumes: `acpd.AvailableCommandsSessionUpdate` (`update.update.availableCommands`, each `acpd.AvailableCommand{name, description, input}` with `input: acpd.UnstructuredCommandInput{hint}`).
- Produces:
  - `AcpAvailableCommand({required String name, required String description, String? inputHint})`
  - `AcpAvailableCommandsUpdate(List<AcpAvailableCommand> commands)` extends `AcpSessionUpdate`
  - `List<AcpAvailableCommand> AcpAgentSession.availableCommands`
  - `abstract interface class AcpAvailableCommandsApi { List<AcpAvailableCommand> get availableCommands; }`
  - `AcpSessionRuntime implements AcpAvailableCommandsApi`

- [ ] **Step 1: Write the failing acp_session tests**

Append to `client/test/services/acp/acp_session_test.dart` inside `main()`:

```dart
  test('maps available_commands_update and retains the latest list', () async {
    session = await openSession();
    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);

    agentCtx.sessionUpdate(
      sessionId: sessionId,
      update: acpd.AvailableCommandsUpdate(
        availableCommands: [
          acpd.AvailableCommand(
            name: 'create_plan',
            description: 'Create an implementation plan',
            input: const acpd.UnstructuredCommandInput(hint: '<what>'),
          ),
          acpd.AvailableCommand(name: '/compact', description: 'Compact'),
          acpd.AvailableCommand(name: '   ', description: 'ignored'),
        ],
      ),
    );
    await pumpEventQueue();

    final mapped = events.whereType<AcpAvailableCommandsUpdate>().single;
    expect(mapped.commands.map((command) => command.name), [
      'create_plan',
      'compact',
    ]);
    expect(mapped.commands.first.description, 'Create an implementation plan');
    expect(mapped.commands.first.inputHint, '<what>');
    expect(mapped.commands.last.inputHint, isNull);
    expect(session.availableCommands.map((command) => command.name), [
      'create_plan',
      'compact',
    ]);

    // An empty advertisement is "not ready yet" — it must not clear the list.
    agentCtx.sessionUpdate(
      sessionId: sessionId,
      update: const acpd.AvailableCommandsUpdate(availableCommands: []),
    );
    await pumpEventQueue();
    sub.cancel();

    expect(events.whereType<AcpAvailableCommandsUpdate>(), hasLength(1));
    expect(session.availableCommands.map((command) => command.name), [
      'create_plan',
      'compact',
    ]);
  });

  test('a load session still accepts available_commands_update', () async {
    agent.connection.onRequest(
      'session/load',
      (params) => acpd.LoadSessionResponse().toJson(),
    );
    session = await conn.loadSession(sessionId: 'agent-9', cwd: cwd);

    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);

    agentCtx.sessionUpdate(
      sessionId: 'agent-9',
      update: const acpd.AvailableCommandsUpdate(
        availableCommands: [
          acpd.AvailableCommand(name: 'deploy', description: 'Deploy the app'),
        ],
      ),
    );
    await pumpEventQueue();
    sub.cancel();

    final mapped = events.whereType<AcpAvailableCommandsUpdate>().single;
    expect(mapped.commands.single.name, 'deploy');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart`

Expected: FAIL — `AcpAvailableCommandsUpdate` / `session.availableCommands` are undefined; the load-session case emits nothing.

- [ ] **Step 3: Add the internal types**

In `client/lib/services/acp/acp_session.dart`, after `AcpModelStateUpdate` (around line 348), add:

```dart
/// One command the agent advertised through `available_commands_update`.
final class AcpAvailableCommand {
  const AcpAvailableCommand({
    required this.name,
    required this.description,
    this.inputHint,
  });

  final String name;
  final String description;
  final String? inputHint;
}

/// The agent replaced its advertised command list (non-empty only).
final class AcpAvailableCommandsUpdate extends AcpSessionUpdate {
  const AcpAvailableCommandsUpdate(this.commands);

  final List<AcpAvailableCommand> commands;
}
```

- [ ] **Step 4: Retain the latest list and map the wire update**

In `AcpAgentSession`, next to the `_configOptions` field (around line 571), add:

```dart
  List<AcpAvailableCommand> _availableCommands = const [];

  /// The last non-empty command list advertised during this session.
  List<AcpAvailableCommand> get availableCommands => _availableCommands;
```

In `_onSessionUpdate` (line 930), replace the suppression guard:

```dart
    final collecting = _collectingHistory;
    if (_suppressBootstrap &&
        !collecting &&
        !_isAvailableCommandsUpdate(params)) {
      return;
    }
```

Add the helper next to `_onSessionUpdate`:

```dart
  static bool _isAvailableCommandsUpdate(Object? params) {
    if (params is! Map) return false;
    final update = params['update'];
    return update is Map &&
        update['sessionUpdate'] == 'available_commands_update';
  }
```

Replace the mapping tail (lines 990-996) with:

```dart
    final mapped = _mapUpdate(update);
    if (mapped == null) return;
    if (mapped is AcpAvailableCommandsUpdate) {
      _availableCommands = mapped.commands;
    }
    // Commands are session metadata, not transcript: emit them even while a
    // history replay is being collected so the chat layer never misses them.
    if (collecting && mapped is! AcpAvailableCommandsUpdate) {
      _historyBuffer?.add(mapped);
      return;
    }
    _emit(mapped);
```

In `_mapUpdate`, add the case before `default:` (line 1211):

```dart
      case acpd.AvailableCommandsSessionUpdate():
        final commands = <AcpAvailableCommand>[];
        for (final command in update.update.availableCommands) {
          final name = _stripSlash(command.name.trim());
          if (name.isEmpty) continue;
          final hint = command.input?.hint.trim();
          commands.add(
            AcpAvailableCommand(
              name: name,
              description: command.description.trim(),
              inputHint: (hint == null || hint.isEmpty) ? null : hint,
            ),
          );
        }
        return commands.isEmpty ? null : AcpAvailableCommandsUpdate(commands);
```

Add `_stripSlash` as a private top-level helper in the same file:

```dart
String _stripSlash(String name) =>
    name.startsWith('/') ? name.substring(1) : name;
```

- [ ] **Step 5: Run the acp_session tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart`

Expected: PASS.

- [ ] **Step 6: Expose the optional capability on the runtime**

In `client/lib/services/acp/acp_session_runtime.dart`, after `AcpModelSwitchApi` (line 238-244), add:

```dart
/// Optional ACP capability: commands advertised by the agent.
///
/// Separate from [AcpSessionRuntimeApi] so existing all-stub fakes stay valid,
/// mirroring [AcpModelSwitchApi]. The list is the last non-empty one seen in
/// the open session, so a handshake-time advertisement survives the gap before
/// the chat layer subscribes to [AcpSessionRuntimeApi.updates].
abstract interface class AcpAvailableCommandsApi {
  List<AcpAvailableCommand> get availableCommands;
}
```

Add `AcpAvailableCommandsApi` to the `implements` list of `AcpSessionRuntime` (line 256-261), and add the getter next to `modelState`:

```dart
  @override
  List<AcpAvailableCommand> get availableCommands =>
      _session?.availableCommands ?? const [];
```

- [ ] **Step 7: Run analyze on the touched files**

Run: `cd client && flutter analyze lib/services/acp`

Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/acp/acp_session.dart \
  client/lib/services/acp/acp_session_runtime.dart \
  client/test/services/acp/acp_session_test.dart
git commit -m "feat(acp): map available_commands_update into chat updates"
```

---

### Task 3: Track available commands in the chat runtime cubit

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` (`AcpChatRuntimeState:84-151`, `_readModelState:427-431`, ready emit `:647-649`, `_onUpdate:993-1088`, `_isTurnContentUpdate:1092-1098`)
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` (`_FakeAcpRuntime:140-259`)

**Interfaces:**
- Consumes: `AcpAvailableCommandsUpdate`, `AcpAvailableCommand`, `AcpAvailableCommandsApi` from Task 2; `NativeCommand` from Task 1.
- Produces:
  - `AcpChatRuntimeState.availableCommands` (`List<NativeCommand>`, default `const []`)
  - `copyWith({..., List<NativeCommand>? availableCommands})`

- [ ] **Step 1: Write the failing cubit tests**

In `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`:

Add `AcpAvailableCommandsApi` to `_FakeAcpRuntime`'s `implements` list and add its field:

```dart
  @override
  List<AcpAvailableCommand> availableCommands = const [];
```

Append these tests inside `main()`:

```dart
  test('available command updates replace the compose command list', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );

    runtime.emit(
      const AcpAvailableCommandsUpdate([
        AcpAvailableCommand(
          name: 'create_plan',
          description: 'Create a plan',
          inputHint: '<what>',
        ),
        AcpAvailableCommand(name: 'compact', description: ''),
      ]),
    );
    await pumpEventQueue();

    expect(cubit.state.availableCommands.map((command) => command.name), [
      'create_plan',
      'compact',
    ]);
    final first = cubit.state.availableCommands.first;
    expect(first.descriptionText, 'Create a plan');
    expect(first.argumentHint, '<what>');
    expect(cubit.state.availableCommands.last.descriptionText, isNull);
    await cubit.close();
  });

  test('an empty available command update keeps the previous list', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );

    runtime.emit(
      const AcpAvailableCommandsUpdate([
        AcpAvailableCommand(name: 'deploy', description: 'Deploy'),
      ]),
    );
    await pumpEventQueue();
    runtime.emit(const AcpAvailableCommandsUpdate([]));
    await pumpEventQueue();

    expect(cubit.state.availableCommands.single.name, 'deploy');
    await cubit.close();
  });

  test('handshake-time available commands seed the compose list', () async {
    runtime.availableCommands = const [
      AcpAvailableCommand(name: 'deploy', description: 'Deploy the app'),
    ];
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );

    expect(cubit.state.availableCommands.single.name, 'deploy');
    expect(cubit.state.availableCommands.single.descriptionText, 'Deploy the app');
    await cubit.close();
  });
```

- [ ] **Step 2: Run the cubit tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: FAIL — `cubit.state.availableCommands` is undefined and `_FakeAcpRuntime` does not implement the new getter.

- [ ] **Step 3: Add the state field**

In `AcpChatRuntimeState` (line 84-151):

- Constructor: add `this.availableCommands = const [],`
- Field:

```dart
  /// Commands the agent advertised for this session (empty = fall back to the
  /// CLI's static table).
  final List<NativeCommand> availableCommands;
```

- `copyWith`: add parameter `List<NativeCommand>? availableCommands,` and pass-through `availableCommands: availableCommands ?? this.availableCommands,`.

Add the import at the top of the file:

```dart
import '../../../services/cli/registry/capabilities/native_command_capability.dart';
```

- [ ] **Step 4: Convert, seed, and handle live updates**

Add helpers near `_readModelState` (line 427):

```dart
  /// Reads commands the agent advertised during the handshake, through the
  /// optional ACP capability (the update stream is not subscribed yet).
  List<NativeCommand> _readAvailableCommands() {
    final runtime = _runtime;
    if (runtime is! AcpAvailableCommandsApi) return const [];
    return _toNativeCommands(runtime.availableCommands);
  }

  static List<NativeCommand> _toNativeCommands(
    List<AcpAvailableCommand> commands,
  ) => [
    for (final command in commands)
      NativeCommand(
        name: command.name,
        descriptionText:
            command.description.isEmpty ? null : command.description,
        argumentHint: command.inputHint,
      ),
  ];
```

Change the ready emit (line 647-649) to:

```dart
    emit(
      state.copyWith(
        phase: AcpChatPhase.ready,
        modelState: _readModelState(),
        availableCommands: _readAvailableCommands(),
      ),
    );
```

Add the update case in `_onUpdate` next to `AcpModelStateUpdate` (line 1054-1056):

```dart
      case AcpAvailableCommandsUpdate():
        if (isClosed || update.commands.isEmpty) return;
        emit(
          state.copyWith(
            availableCommands: _toNativeCommands(update.commands),
          ),
        );
```

Add `AcpAvailableCommandsUpdate()` to the false group in `_isTurnContentUpdate` (line 1092-1098):

```dart
    AcpStop() ||
    AcpOutOfTurnStop() ||
    AcpAuthNotice() ||
    AcpModelStateUpdate() ||
    AcpAvailableCommandsUpdate() => false,
```

- [ ] **Step 5: Run the cubit tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "feat(acp): track available commands in chat runtime state"
```

---

### Task 4: Project commands through the scope and consume them in compose

**Files:**
- Modify: `client/lib/pages/chat/acp_runtime_scope.dart:14-40`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart:237-239`
- Modify: `client/lib/services/chat/conversation/compose/compose_slash_catalog.dart`
- Create: `client/test/pages/chat/acp_runtime_scope_test.dart`
- Test: `client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart`

**Interfaces:**
- Consumes: `AcpChatRuntimeState.availableCommands` from Task 3; `NativeCommandCapability` static table.
- Produces:
  - `AcpRuntimeUiState.availableCommands` (`List<NativeCommand>`) included in `of`/`==`/`hashCode`
  - `List<NativeCommand> selectComposeNativeCommands({required List<NativeCommand> agentCommands, required List<NativeCommand> staticCommands})`

- [ ] **Step 1: Write the failing scope test**

Create `client/test/pages/chat/acp_runtime_scope_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/pages/chat/acp_runtime_scope.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';

void main() {
  test('projects available commands into the scope snapshot', () {
    const commands = [
      NativeCommand(name: 'deploy', descriptionText: 'Deploy the app'),
    ];
    final state = AcpChatRuntimeState(availableCommands: commands);

    final ui = AcpRuntimeUiState.of(state);

    expect(ui.availableCommands, commands);
    expect(ui, AcpRuntimeUiState.of(state));
  });
}
```

- [ ] **Step 2: Run the scope test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/acp_runtime_scope_test.dart`

Expected: FAIL — `availableCommands` is not defined on `AcpRuntimeUiState`.

- [ ] **Step 3: Implement the projection**

In `client/lib/pages/chat/acp_runtime_scope.dart`, add the import:

```dart
import '../../services/cli/registry/capabilities/native_command_capability.dart';
```

Extend `AcpRuntimeUiState`:

- Constructor: `required this.availableCommands,`
- Field: `final List<NativeCommand> availableCommands;`
- `of`: `availableCommands: state.availableCommands,`
- `==`: `&& other.availableCommands == availableCommands`
- `hashCode`: `Object.hash(pendingClient, inTurn, modelState, availableCommands)`

- [ ] **Step 4: Run the scope test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/acp_runtime_scope_test.dart`

Expected: PASS.

- [ ] **Step 5: Write the failing selector test**

Append to `client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart` inside `main()`:

```dart
  test('agent commands replace the static table only when non-empty', () {
    const agent = [
      NativeCommand(name: 'deploy', descriptionText: 'Deploy the app'),
    ];
    const curated = [
      NativeCommand(name: 'help', description: NativeCommandDescription.help),
    ];

    expect(
      selectComposeNativeCommands(
        agentCommands: agent,
        staticCommands: curated,
      ),
      agent,
    );
    expect(
      selectComposeNativeCommands(
        agentCommands: const [],
        staticCommands: curated,
      ),
      curated,
    );
  });
```

- [ ] **Step 6: Run the selector test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_slash_catalog_test.dart`

Expected: FAIL — `selectComposeNativeCommands` is undefined.

- [ ] **Step 7: Implement the selector**

Add to `client/lib/services/chat/conversation/compose/compose_slash_catalog.dart` (above `buildComposeSlashCandidates`):

```dart
/// Agent-advertised commands are the session's source of truth once any
/// arrive; an empty list means "not advertised yet" and falls back to the
/// curated per-CLI table.
List<NativeCommand> selectComposeNativeCommands({
  required List<NativeCommand> agentCommands,
  required List<NativeCommand> staticCommands,
}) => agentCommands.isNotEmpty ? agentCommands : staticCommands;
```

- [ ] **Step 8: Run the selector test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_slash_catalog_test.dart`

Expected: PASS.

- [ ] **Step 9: Wire the compose section**

In `client/lib/pages/chat/session_chat_compose_section.dart`, add the relative import next to the other compose imports (line 37-44):

```dart
import '../../services/chat/conversation/compose/compose_slash_catalog.dart';
```

Replace lines 237-239:

```dart
    final nativeCommands =
        registry.capability<NativeCommandCapability>(lockedCli)?.commands ??
        const <NativeCommand>[];
```

with:

```dart
    final agentCommands = acpRuntime == null
        ? const <NativeCommand>[]
        : (acpUi?.availableCommands ?? const <NativeCommand>[]);
    final nativeCommands = selectComposeNativeCommands(
      agentCommands: agentCommands,
      staticCommands:
          registry.capability<NativeCommandCapability>(lockedCli)?.commands ??
          const <NativeCommand>[],
    );
```

- [ ] **Step 10: Run analyze and the affected suites**

Run:

```bash
cd client && flutter analyze lib/pages/chat lib/services/chat/conversation/compose lib/cubits/session/acp lib/services/acp
cd client && dart run tool/run_tests.dart \
  test/pages/chat/acp_runtime_scope_test.dart \
  test/services/chat/conversation/compose/compose_slash_catalog_test.dart \
  test/pages/chat/session_chat_workspace_bundle_test.dart \
  test/pages/chat/session_chat_view_acp_test.dart
```

Expected: analyze clean; all tests pass (the two existing page suites guard against regressions in compose wiring).

- [ ] **Step 11: Commit**

```bash
git add client/lib/pages/chat/acp_runtime_scope.dart \
  client/lib/pages/chat/session_chat_compose_section.dart \
  client/lib/services/chat/conversation/compose/compose_slash_catalog.dart \
  client/test/pages/chat/acp_runtime_scope_test.dart \
  client/test/services/chat/conversation/compose/compose_slash_catalog_test.dart
git commit -m "feat(chat): prefer agent commands in the compose slash menu"
```

---

### Task 5: End-to-end verification

**Files:**
- No source changes expected.
- Test: all files touched in Tasks 1-4.

**Interfaces:**
- Consumes: everything above.
- Produces: a green targeted run for delivery.

- [ ] **Step 1: Run the full targeted matrix**

```bash
cd client && dart run tool/run_tests.dart \
  test/services/cli/registry/native_command_capability_test.dart \
  test/services/chat/conversation/compose/compose_slash_catalog_test.dart \
  test/widgets/compose/compose_trigger_field_test.dart \
  test/services/acp/acp_session_test.dart \
  test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart \
  test/pages/chat/acp_runtime_scope_test.dart \
  test/pages/chat/session_chat_workspace_bundle_test.dart \
  test/pages/chat/session_chat_view_acp_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis on the client**

Run: `cd client && flutter analyze`

Expected: No new issues.

- [ ] **Step 3: Confirm the spec's non-goals were not violated**

Check by inspection:
- `git diff --stat main...HEAD -- client` mentions only the files listed in the spec's change list.
- No `startsWith('/')` interception was added to the prompt path (`grep -n "startsWith('/')" client/lib/services/chat client/lib/pages/chat` returns no new hits).
- No new l10n keys were added for agent descriptions (`git diff --stat -- client/lib/l10n` is empty).

- [ ] **Step 4: Report**

Summarize the commits and the targeted test result. Do not run the full suite unless `docs/DEVELOPMENT.md`'s change→verification table requires it for ACP mapping + UI together; if in doubt, ask the user before starting a full run.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| 内部类型与映射 | Task 2, Steps 3-4 |
| Bootstrap 抑制旁路 | Task 2, Step 4 |
| 保留值 + 可选能力接口 | Task 2, Steps 4 and 6 |
| 命令模型（可空描述、slashName） | Task 1, Step 3 |
| Catalog descriptionText / label | Task 1, Step 7 |
| Cubit 状态、实时更新、握手播种 | Task 3, Steps 3-4 |
| UI 投影与消费 | Task 4, Steps 3, 7, 9 |
| 边界（空列表、空名、空 hint、取消） | Task 1 (empty hint is mapped to null in Task 2), Task 2 Step 4, Task 3 Step 4 |
| 测试矩阵 | Tasks 1-4 tests + Task 5 |

**Placeholder scan:** No TBD/TODO; every code step contains the literal code.

**Type consistency:** `AcpAvailableCommand` field names (`name`, `description`, `inputHint`) are identical in Tasks 2, 3, and the acp_session tests; `availableCommands` is spelled the same on `AcpAgentSession`, `AcpAvailableCommandsApi`, `AcpChatRuntimeState`, and `AcpRuntimeUiState`; `selectComposeNativeCommands` parameters (`agentCommands`, `staticCommands`) match between Task 4 Steps 7 and 9.
