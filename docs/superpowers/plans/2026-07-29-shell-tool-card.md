# Shell Tool Card (Cursor-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render shell/terminal tool calls in History as Cursor-like cards (header summary + expandable `$ command` + dim output) while keeping CoT grouping unchanged.

**Architecture:** Add `AiShellToolTarget` + `DefaultAiShellToolTargetResolver` in `ai_message_core`. In `AiToolCallPartView`, insert a shell branch after subagent and before file/legacy; shell expand uses a dedicated terminal panel that **replaces** the shared args/`Result:` block. Resolver is `const` in the view (no InheritedWidget).

**Tech Stack:** Dart / Flutter; packages `ai_message_core`, `ai_message_ui`.

**Spec:** `docs/superpowers/specs/2026-07-29-shell-tool-card-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/tool_shell_target.dart` | `AiShellToolTarget`, resolver, name set, summary truncation |
| `client/packages/ai_message_core/lib/ai_message_core.dart` | Export `tool_shell_target.dart` |
| `client/packages/ai_message_core/test/tool_shell_target_resolver_test.dart` | Resolver unit tests |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Shell branch, `_ShellToolTrigger`, terminal expand panel |
| `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart` | Widget tests for shell chrome |
| `client/packages/ai_message_ui/test/tool_call_file_target_test.dart` | Update/remove obsolete `Bash keeps legacy` assertion |
| `client/packages/ai_message_ui/test/tool_call_subagent_preview_test.dart` | May also assert Bash legacy — update in Task 3 if needed |
| `client/packages/ai_message_ui/test/ai_message_parts_test.dart` | Bash+command localized assertions may need shell summary |

---

### Task 1: Core shell target + default resolver (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/tool_shell_target.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Create: `client/packages/ai_message_core/test/tool_shell_target_resolver_test.dart`

- [ ] **Step 1: Write failing resolver tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultAiShellToolTargetResolver();

  test('Bash command + description', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Bash',
        args: {
          'command': 'git status --short',
          'description': 'Check worktree git state',
        },
      ),
    );
    expect(t?.command, 'git status --short');
    expect(t?.description, 'Check worktree git state');
    expect(t?.summary, 'Check worktree git state');
  });

  test('no description → truncated command as summary', () {
    final long = 'x' * 120;
    final t = resolver.resolve(
      AiToolCallPart(
        toolCallId: '1',
        toolName: 'Shell',
        args: {'command': long},
      ),
    );
    expect(t?.command, long);
    expect(t?.description, isNull);
    expect(t!.summary.length, lessThanOrEqualTo(81)); // 80 + ellipsis
    expect(t.summary.endsWith('…'), isTrue);
  });

  test('cmd / CommandLine key aliases', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'run_terminal_cmd',
              args: {'cmd': 'ls'},
            ),
          )
          ?.command,
      'ls',
    );
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'Execute',
              args: {'CommandLine': 'pwd'},
            ),
          )
          ?.command,
      'pwd',
    );
  });

  test('command preferred over cmd', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'bash',
        args: {'command': 'echo a', 'cmd': 'echo b'},
      ),
    );
    expect(t?.command, 'echo a');
  });

  test('argsText JSON fallback', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'shell_command',
        argsText: '{"command":"uname","description":"Show kernel"}',
      ),
    );
    expect(t?.command, 'uname');
    expect(t?.description, 'Show kernel');
  });

  test('shell name set coverage', () {
    for (final name in [
      'Bash',
      'Shell',
      'bash',
      'shell_command',
      'exec_command',
      'run_shell_command',
      'run_terminal_cmd',
      'Execute',
    ]) {
      expect(
        resolver
            .resolve(
              AiToolCallPart(
                toolCallId: '1',
                toolName: name,
                args: const {'command': 'true'},
              ),
            )
            ?.command,
        'true',
        reason: name,
      );
    }
  });

  test('missing command → null', () {
    expect(
      resolver.resolve(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Bash',
          args: {'description': 'noop'},
        ),
      ),
      isNull,
    );
  });

  test('non-shell tool → null', () {
    expect(
      resolver.resolve(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Read',
          args: {'command': 'ls', 'file_path': 'a.dart'},
        ),
      ),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_core && dart test test/tool_shell_target_resolver_test.dart
```

Expected: FAIL (library / types not found).

- [ ] **Step 3: Implement `tool_shell_target.dart`**

```dart
import 'dart:convert';

import 'message.dart';

class AiShellToolTarget {
  const AiShellToolTarget({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;

  static const summaryMaxChars = 80;

  /// Header label: non-empty description, else truncated command.
  String get summary {
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return truncateCommand(command);
  }

  static String truncateCommand(String command) {
    final oneLine = command.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= summaryMaxChars) return oneLine;
    return '${oneLine.substring(0, summaryMaxChars)}…';
  }
}

abstract class AiShellToolTargetResolver {
  AiShellToolTarget? resolve(AiToolCallPart part);
}

class DefaultAiShellToolTargetResolver implements AiShellToolTargetResolver {
  const DefaultAiShellToolTargetResolver({
    this.toolNames = defaultToolNames,
  });

  final Set<String> toolNames;

  static const defaultToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
    'execute',
  };

  static const _commandKeys = ['command', 'cmd', 'CommandLine'];

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;

    final map = _argsMap(part);
    final command = _firstNonEmptyString(map, _commandKeys);
    if (command == null) return null;

    final description = _firstNonEmptyString(map, const ['description']);
    return AiShellToolTarget(command: command, description: description);
  }
}

Map<String, Object?>? _argsMap(AiToolCallPart part) {
  if (part.args != null && part.args!.isNotEmpty) return part.args;
  final text = part.argsText?.trim();
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return {
      for (final e in decoded.entries) e.key.toString(): e.value,
    };
  } catch (_) {
    return null;
  }
}

String? _firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
```

Export in `ai_message_core.dart`:

```dart
export 'src/tool_shell_target.dart';
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd client/packages/ai_message_core && dart test test/tool_shell_target_resolver_test.dart
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/tool_shell_target.dart \
  client/packages/ai_message_core/lib/ai_message_core.dart \
  client/packages/ai_message_core/test/tool_shell_target_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_core): add shell tool target resolver

EOF
)"
```

---

### Task 2: Shell chrome + terminal expand panel (TDD)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Create: `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart`
- Modify: `client/packages/ai_message_ui/test/tool_call_file_target_test.dart` (remove/replace obsolete `Bash keeps legacy` assertion)

- [ ] **Step 1: Write failing widget tests**

Create `tool_call_shell_target_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bash shows shell summary; expand shows \$ command + output', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {
                'command': 'git status --short',
                'description': 'Check worktree git state',
              },
              result: ' M client/lib/a.dart',
              status: AiToolCallStatus.complete,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('Check worktree git state'), findsOneWidget);
    expect(find.textContaining('git status --short'), findsNothing);
    expect(find.textContaining('M client/lib/a.dart'), findsNothing);
    expect(find.textContaining('Result:'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.textContaining('\$'), findsWidgets);
    expect(find.textContaining('git status --short'), findsOneWidget);
    expect(find.textContaining('M client/lib/a.dart'), findsOneWidget);
    expect(find.textContaining('Result:'), findsNothing);
    // Must not dump JSON args panel.
    expect(find.textContaining('"command"'), findsNothing);
  });

  testWidgets('shell without description uses truncated command in header', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Shell',
              args: {'command': 'ls -la'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('ls -la'), findsOneWidget);
    expect(find.textContaining('Used tool:'), findsNothing);
  });

  testWidgets('shell name without command stays legacy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Bash',
              args: {'description': 'no command'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsOneWidget);
  });

  testWidgets('Read still uses file summary chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiToolCallPartView(
            part: AiToolCallPart(
              toolCallId: '1',
              toolName: 'Read',
              args: {'file_path': 'lib/foo.dart'},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Used tool:'), findsNothing);
    expect(find.textContaining('foo.dart'), findsOneWidget);
  });
}
```

In `tool_call_file_target_test.dart`, **delete** the test `Bash keeps legacy Used tool chrome` (replaced by shell tests above). Keep a non-shell legacy check if useful, e.g. `Grep` / `WebSearch` still shows `Used tool:`.

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_shell_target_test.dart
```

Expected: FAIL (still legacy `Used tool:` for Bash with command).

- [ ] **Step 3: Implement UI branch + panel**

In `_AiToolCallPartViewState.build`, after subagent detection and **before** file target:

```dart
const shellResolver = DefaultAiShellToolTargetResolver();
final shellTarget =
    useSubagentChrome ? null : shellResolver.resolve(part);
final target = useSubagentChrome || shellTarget != null
    ? null
    : fileActions.resolver.resolve(part);
```

Trigger selection:

```dart
useSubagentChrome
  ? _SubagentToolTrigger(...)
  : shellTarget != null
  ? _ShellToolTrigger(
      part: part,
      shell: shellTarget,
      cancelled: cancelled,
      triggerColor: triggerColor,
      markdown: markdown,
      dense: widget.dense,
      open: _open,
      onToggle: _toggleExpanded,
    )
  : target == null
  ? _LegacyToolTrigger(...)
  : _SummaryToolTrigger(...),
```

**Expanded body:** if `shellTarget != null`, render only `_ShellTerminalPanel` (command + optional output). Else keep existing args/`Result:` block. Do not stack both.

Add `_ShellToolTrigger`:

- Row: `_StatusIcon`, then `Icons.terminal` size 14–16 with `triggerColor`, then `Expanded` `Text(shell.summary, maxLines: 1, overflow: ellipsis)`, then `_ExpandChevron`
- Whole row toggles expand (same as legacy)

Add `_ShellTerminalPanel`:

```dart
class _ShellTerminalPanel extends StatelessWidget {
  // part, command, panel color, radius, scheme
  // Column:
  //   Text.rich: TextSpan('$ ', accent) + TextSpan(command, monospace, onSurface ~0.9)
  //   if result != null: SizedBox + Text(output, monospace, dimmer or error)
}
```

Use `markdown.codeBlock` / theme monospace if available; otherwise `TextStyle(fontFamily: 'monospace', …)`. Dim output: `onSurface.withValues(alpha: 0.65)` (or similar); error: `scheme.error`.

No `Result:` label. No JSON args dump.

- [ ] **Step 4: Run widget tests — expect PASS**

```bash
cd client/packages/ai_message_ui && \
  flutter test test/tool_call_shell_target_test.dart test/tool_call_file_target_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart \
  client/packages/ai_message_ui/test/tool_call_shell_target_test.dart \
  client/packages/ai_message_ui/test/tool_call_file_target_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): Cursor-style shell tool card in History

EOF
)"
```

---

### Task 3: Regression + package verify

**Files:** none new (run existing suites)

- [ ] **Step 1: Run core + UI package tests**

```bash
cd client/packages/ai_message_core && dart test
cd client/packages/ai_message_ui && flutter test
```

Expected: PASS (fix any incidental breakage in CoT / collapsed-parts tests that assumed Bash legacy chrome).

- [ ] **Step 2: If a CoT / parts test asserts `Used tool: Bash`, update to shell summary expectations**

Search:

```bash
rg -n "Used tool:.*Bash|toolName: 'Bash'" client/packages/ai_message_ui/test
```

Update assertions to match shell chrome where applicable; keep legacy only when `command` is absent.

- [ ] **Step 3: Commit any test fixes**

```bash
git add -u client/packages/ai_message_ui/test client/packages/ai_message_core/test
git commit -m "$(cat <<'EOF'
test: align History tool chrome expectations with shell cards

EOF
)"
```

(Skip empty commit if nothing changed.)

---

## Out of scope (do not implement)

- Syntax highlighting / exit code / duration chips
- Changing CoT grouping or pulling shell tools out of CoT
- Transcript adapter changes
- Live permission / agent-status preview UI
- Host InheritedWidget for shell resolver
