# Native Compose Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface a small static CLI-native slash-command catalog in both TeamPilot compose surfaces, while execution and command state remain owned by the CLI.

**Architecture:** Add a registry-only `NativeCommandCapability` with immutable per-CLI metadata. The existing compose slash catalog merges those values with skills and plugin commands; compose widgets resolve the effective CLI and render localized metadata.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, TeamPilot CLI registry capabilities, ARB l10n, `flutter_test`.

## Global Constraints

- Native commands are static declarations: do not query a terminal, CLI SDK, or remote host.
- Matrix: `goal` for Codex/Claude/Cursor (Cursor experimental), `compact` for Codex/Claude/OpenCode, `plan` for Claude, and `help` for all five launch-supported CLIs.
- Native command insertion always begins `/`; existing skill syntax, including Codex `$skill`, is unchanged.
- Do not expose model, permission, session-lifecycle, terminal-exit, or external-editor commands excluded by the approved design.
- Do not preflight availability; a CLI rejection is ordinary terminal output.
- Edit only `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` for l10n sources.

---

## File structure

| File | Responsibility |
| --- | --- |
| `client/lib/services/cli/registry/capabilities/native_command_capability.dart` | CLI-neutral command metadata and capability contract. |
| `client/lib/services/cli/{codex,claude,flashskyai,opencode,cursor}/capabilities/native_commands.dart` | Fixed per-CLI command catalog. |
| `client/lib/services/cli/{codex,claude,flashskyai,opencode,cursor}/*_tool.dart` | Attach the appropriate catalog to each definition. |
| `client/lib/services/compose/compose_slash_catalog.dart` | Merge/filter/order native, skill, and plugin candidates. |
| `client/lib/widgets/compose/compose_trigger_field.dart` | Query the merged catalog and render metadata. |
| `client/lib/widgets/compose/workspace_compose_card.dart` | Carry native commands through the shared compose wrapper. |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Resolve landing effective CLI once and forward its catalog. |
| `client/lib/pages/chat/session_chat_compose_section.dart` | Forward selected member `lockedCli` catalog. |
| `client/lib/l10n/app_{en,zh}.arb` | Native description/source/availability strings. |
| `client/test/services/cli/registry/native_command_capability_test.dart` | Five-CLI catalog matrix. |
| `client/test/services/compose/compose_slash_catalog_test.dart` | Pure candidate merge/insertion behavior. |
| `client/test/widgets/compose/compose_trigger_field_test.dart` | Menu rendering and selection. |

### Task 1: Declare native commands in the CLI registry

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/native_command_capability.dart`
- Create: five CLI-specific `capabilities/native_commands.dart` files named above
- Modify: `client/lib/services/cli/{codex,claude,flashskyai,opencode,cursor}/*_tool.dart`
- Create: `client/test/services/cli/registry/native_command_capability_test.dart`

**Interfaces:**
- Produces: `NativeCommandCapability.commands`, `NativeCommand`, `NativeCommandDescription`, `NativeCommandAvailability`.
- Consumes: `CliCapability`, `CliToolRegistry`, existing tool definition constructor injection.

- [ ] **Step 1: Write the failing catalog-matrix test**

```dart
test('built-in tools expose only the approved native command matrix', () {
  final registry = CliToolRegistry.builtIn();
  List<String> names(CliTool cli) => registry
      .capability<NativeCommandCapability>(cli)!
      .commands.map((command) => command.name).toList();

  expect(names(CliTool.codex), ['goal', 'compact', 'help']);
  expect(names(CliTool.claude), ['goal', 'compact', 'plan', 'help']);
  expect(names(CliTool.flashskyai), ['help']);
  expect(names(CliTool.opencode), ['compact', 'help']);
  expect(names(CliTool.cursor), ['goal', 'help']);

  final cursorGoal = registry.capability<NativeCommandCapability>(CliTool.cursor)!
      .commands.firstWhere((command) => command.name == 'goal');
  expect(cursorGoal.availability, NativeCommandAvailability.experimental);
  expect(cursorGoal.argumentHint, '<objective>');
});
```

- [ ] **Step 2: Run it to prove the contract does not exist**

Run: `cd client && flutter test test/services/cli/registry/native_command_capability_test.dart`

Expected: compilation fails because `NativeCommandCapability` is undefined.

- [ ] **Step 3: Add the immutable capability contract**

```dart
import '../cli_capability.dart';

enum NativeCommandDescription { goal, compact, plan, help }
enum NativeCommandAvailability { stable, experimental }

final class NativeCommand {
  const NativeCommand({
    required this.name,
    required this.description,
    this.argumentHint,
    this.availability = NativeCommandAvailability.stable,
  });

  final String name;
  final NativeCommandDescription description;
  final String? argumentHint;
  final NativeCommandAvailability availability;
  bool get acceptsArgument => argumentHint != null;
  String get insertText => acceptsArgument ? '/$name ' : '/$name';
}

abstract interface class NativeCommandCapability implements CliCapability {
  List<NativeCommand> get commands;
}
```

- [ ] **Step 4: Create and inject the five catalogs**

Create one class per CLI, e.g. `CodexNativeCommands`, which implements the
contract and returns a `const` list. Codex is:

```dart
final class CodexNativeCommands implements NativeCommandCapability {
  const CodexNativeCommands();
  @override
  List<NativeCommand> get commands => const [
    NativeCommand(name: 'goal', description: NativeCommandDescription.goal,
      argumentHint: '<objective>'),
    NativeCommand(name: 'compact', description: NativeCommandDescription.compact,
      argumentHint: '[instructions]'),
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
```

Apply the exact global matrix to the other four tools; only Cursor's `goal`
has `availability: NativeCommandAvailability.experimental`. In every
`*CliTool`, add a `nativeCommands` constructor parameter with the CLI catalog
as its default, a typed field, and that field in `capabilities` immediately
after `skill`.

- [ ] **Step 5: Format and rerun the matrix test**

Run: `cd client && dart format lib/services/cli && flutter test test/services/cli/registry/native_command_capability_test.dart`

Expected: exits 0; every assertion passes.

- [ ] **Step 6: Commit the registry contract**

```bash
git add client/lib/services/cli client/test/services/cli/registry/native_command_capability_test.dart
git commit -m "feat(cli): declare native compose commands"
```

### Task 2: Merge native candidates without changing skill invocation

**Files:**
- Modify: `client/lib/services/compose/compose_slash_catalog.dart`
- Modify: `client/test/services/compose/compose_slash_catalog_test.dart`

**Interfaces:**
- Consumes: `List<NativeCommand>`.
- Produces: `ComposeSlashCandidate.source`, `.description`, `.availability`, and `buildComposeSlashCandidates(nativeCommands: ...)`.

- [ ] **Step 1: Write failing merge tests**

```dart
test('merges native commands before plugin commands and keeps syntax', () {
  final candidates = buildComposeSlashCandidates(
    skills: [standaloneSkill], plugins: [superpowers], enabledBundle: bundle,
    query: '', syntax: codexSyntax,
    nativeCommands: const [
      NativeCommand(name: 'goal', description: NativeCommandDescription.goal,
        argumentHint: '<objective>'),
      NativeCommand(name: 'help', description: NativeCommandDescription.help),
    ],
  );
  expect(candidates.map((item) => item.insertText), [
    r'$using-git-worktrees', r'$superpowers:using-git-worktrees',
    '/goal ', '/help', '/review',
  ]);
  expect(candidates[2].source, ComposeSlashCandidateSource.native);
  expect(candidates[4].source, ComposeSlashCandidateSource.plugin);
});

test('filters a native command by name and description key', () {
  final candidates = buildComposeSlashCandidates(
    skills: const [], plugins: const [], enabledBundle: const ConfigBundle(),
    query: 'compact', nativeCommands: const [
      NativeCommand(name: 'compact', description: NativeCommandDescription.compact),
    ],
  );
  expect(candidates.single.insertText, '/compact');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/compose/compose_slash_catalog_test.dart`

Expected: compilation fails because native candidate inputs/metadata are absent.

- [ ] **Step 3: Implement the pure merge**

Keep `ComposeSlashCandidateKind.skill` and `.command` for section headers.
Add `ComposeSlashCandidateSource { native, plugin }`; extend candidates with
nullable `source` and `description`, plus `availability` defaulting to stable.
Add `List<NativeCommand> nativeCommands = const []` to the builder. Add native
values after skill values and before plugin commands:

```dart
add(ComposeSlashCandidate(
  insertText: command.insertText,
  label: command.name,
  kind: ComposeSlashCandidateKind.command,
  source: ComposeSlashCandidateSource.native,
  description: command.description,
  availability: command.availability,
));
```

Search native candidates by `label` and `description.name`. Sort section first,
then command source (native before plugin), then case-insensitive `label`.
Preserve the existing insertion-text de-duplication set.

- [ ] **Step 4: Verify catalog and trigger behavior**

Run: `cd client && flutter test test/services/compose/compose_slash_catalog_test.dart test/services/compose/compose_trigger_query_test.dart`

Expected: passes; Codex skills remain `$` invocations and native commands are `/` invocations.

- [ ] **Step 5: Commit candidate merging**

```bash
git add client/lib/services/compose/compose_slash_catalog.dart client/test/services/compose/compose_slash_catalog_test.dart
git commit -m "feat(compose): merge native command candidates"
```

### Task 3: Resolve and render commands in both compose surfaces

**Files:**
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart`
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/test/widgets/compose/compose_trigger_field_test.dart`

**Interfaces:**
- Consumes: Task 1 capability and Task 2 candidate metadata.
- Produces: CLI-appropriate native suggestions in landing and existing-session compose; selection still uses normal compose submit.

- [ ] **Step 1: Write a failing compose-field selection test**

Extend `pumpField` to accept and pass `nativeCommands`, then add:

```dart
testWidgets('native command shows source and inserts argument space', (tester) async {
  // pumpField supplies /goal <objective> as a native command.
  focusNode.requestFocus();
  await tester.pump();
  await tester.enterText(find.byType(TextField), '/go');
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  expect(find.text('/goal'), findsWidgets);
  expect(find.textContaining('Native'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(controller.text, '/goal ');
});
```

- [ ] **Step 2: Run it to prove plumbing/rendering is missing**

Run: `cd client && flutter test test/widgets/compose/compose_trigger_field_test.dart`

Expected: compilation fails because the field has no native-command input.

- [ ] **Step 3: Add localized strings and generate l10n**

Add exact English entries to `app_en.arb`:

```json
"composeCommandNative": "Native",
"composeCommandPlugin": "Plugin",
"composeCommandExperimental": "Experimental",
"composeNativeCommandGoal": "Keep a durable objective for long-running work.",
"composeNativeCommandCompact": "Compact the active conversation context.",
"composeNativeCommandPlan": "Switch the session into a planning workflow.",
"composeNativeCommandHelp": "Show commands available in this CLI session."
```

Add semantically equivalent Simplified Chinese entries to `app_zh.arb`, then
run: `cd client && flutter gen-l10n`.

- [ ] **Step 4: Thread catalogs through shared widgets and resolve the effective CLI once**

Add `this.nativeCommands = const []` and `final List<NativeCommand>
nativeCommands;` to `WorkspaceComposeCard` and `ComposeTriggerField`; pass it
to `buildComposeSlashCandidates(nativeCommands: widget.nativeCommands)`.

In the landing body, factor the existing CLI-selection portion of
`_skillSyntaxForDraft` into `_cliForDraft(...) -> CliTool?`, then derive both
capabilities from that one CLI:

```dart
final skillSyntax = cli == null ? null : registry.capability<SkillCapability>(cli);
final nativeCommands = cli == null
    ? const <NativeCommand>[]
    : registry.capability<NativeCommandCapability>(cli)?.commands ?? const <NativeCommand>[];
```

In the session section, use its existing `lockedCli` and registry to compute
the same list. Forward both lists to `WorkspaceComposeCard`; do not create
another CLI-resolution branch.

- [ ] **Step 5: Render source, description, and experimental badge**

Keep `Skills`/`Commands` headers determined by candidate kind. For command
rows, render `Native` or `Plugin` plus the localized description; append
`Experimental` when availability is experimental. Add a private extension in
`compose_trigger_field.dart` mapping the four `NativeCommandDescription`
values to the generated l10n getters. Leave `_selectSuggestion` unchanged so
normal trigger replacement and submit deliver text to the CLI.

- [ ] **Step 6: Run focused verification**

Run: `cd client && dart format lib/services/cli lib/services/compose/compose_slash_catalog.dart lib/widgets/compose/compose_trigger_field.dart lib/widgets/compose/workspace_compose_card.dart lib/pages/home_workspace/workspace/unbound_compose_body.dart lib/pages/chat/session_chat_compose_section.dart test/services/cli/registry/native_command_capability_test.dart test/services/compose/compose_slash_catalog_test.dart test/widgets/compose/compose_trigger_field_test.dart && flutter test test/services/cli/registry/native_command_capability_test.dart test/services/compose/compose_slash_catalog_test.dart test/services/compose/compose_trigger_query_test.dart test/widgets/compose/compose_trigger_field_test.dart`

Expected: formatter exits 0 and every focused test passes.

- [ ] **Step 7: Run required project verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`

Expected: both commands exit 0.

- [ ] **Step 8: Commit compose integration**

```bash
git add client/lib/widgets/compose client/lib/pages/chat/session_chat_compose_section.dart client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/compose/compose_trigger_field_test.dart
git commit -m "feat(compose): show CLI native commands"
```

## Plan self-review

- **Spec coverage:** Task 1 covers static capability and the exact five-CLI matrix; Task 2 covers merging, filtering, ordering, de-duplication, and invocation syntax; Task 3 resolves effective CLI on both surfaces, localizes/groups rows, preserves normal submission, and verifies it.
- **Placeholder scan:** no `TODO`, `TBD`, or undefined task references remain.
- **Type consistency:** Tasks use `NativeCommandCapability`, `NativeCommand`, `NativeCommandDescription`, `NativeCommandAvailability`, and `ComposeSlashCandidateSource` as declared in earlier tasks.
