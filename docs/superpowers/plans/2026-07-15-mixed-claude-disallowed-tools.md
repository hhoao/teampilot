# Mixed Claude `--disallowedTools` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In mixed mode, Claude Code launches get `--disallowedTools` so members cannot use native swarm tools (lead also loses `Agent`).

**Architecture:** Constants + helper on `MemberRoleProvision`; `ClaudeCodeCliToolAdapter.buildArguments` appends `['--disallowedTools', ...tools]` when `teamMode == mixed`. Native / settings.deny / delegate hooks unchanged.

**Tech Stack:** Flutter/Dart, existing `CliLaunchContext` / `TeamMemberNaming`

**Spec:** `docs/superpowers/specs/2026-07-15-mixed-claude-disallowed-tools-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/services/session/member_role_provision.dart` | Own deny-list constants + `disallowedToolsForMixedClaude` |
| `client/lib/services/cli/cli_tool_adapter.dart` | Emit flag in `ClaudeCodeCliToolAdapter` |
| `client/test/services/session/member_role_provision_test.dart` | Helper unit tests |
| `client/test/services/cli/cli_tool_adapter_test.dart` | Adapter integration tests |

---

### Task 1: Constants + helper (TDD)

**Files:**
- Modify: `client/lib/services/session/member_role_provision.dart` (after `mixedTeamSessionAllowTools` ~L28)
- Test: `client/test/services/session/member_role_provision_test.dart`

- [ ] **Step 1: Write failing helper tests**

Append to `member_role_provision_test.dart`:

```dart
test('disallowedToolsForMixedClaude worker omits Agent', () {
  final tools = MemberRoleProvision.disallowedToolsForMixedClaude(isLead: false);
  expect(tools, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
  expect(tools, isNot(contains('Agent')));
  expect(tools, isNot(contains('Bash')));
});

test('disallowedToolsForMixedClaude lead includes Agent', () {
  final tools = MemberRoleProvision.disallowedToolsForMixedClaude(isLead: true);
  expect(tools, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
  expect(tools, contains('Agent'));
  expect(
    tools,
    containsAllInOrder([
      ...MemberRoleProvision.mixedClaudeDisallowedTools,
      'Agent',
    ]),
  );
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/session/member_role_provision_test.dart
```

Expected: compile/runtime error — `disallowedToolsForMixedClaude` / `mixedClaudeDisallowedTools` undefined.

- [ ] **Step 3: Implement constants + helper**

In `member_role_provision.dart`, after `mixedTeamSessionAllowTools`:

```dart
  /// Native Claude swarm / task tools denied via CLI `--disallowedTools` in
  /// mixed mode (settings `permissions.deny` is omitted there — see
  /// [teamSessionDenyTools]).
  static const mixedClaudeDisallowedTools = <String>[
    'TeamCreate',
    'TeamDelete',
    'SendMessage',
    'TaskCreate',
    'TaskUpdate',
    'TaskList',
    'TaskGet',
    'TaskStop',
    'TaskOutput',
  ];

  /// Extra CLI deny for mixed team-lead only (workers keep Agent for subagents).
  static const mixedClaudeLeadExtraDisallowedTools = <String>['Agent'];

  /// Tools passed to Claude Code `--disallowedTools` in mixed mode.
  static List<String> disallowedToolsForMixedClaude({required bool isLead}) {
    if (!isLead) return List<String>.from(mixedClaudeDisallowedTools);
    return [
      ...mixedClaudeDisallowedTools,
      ...mixedClaudeLeadExtraDisallowedTools,
    ];
  }
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/session/member_role_provision_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/member_role_provision.dart \
  client/test/services/session/member_role_provision_test.dart
git commit -m "$(cat <<'EOF'
feat(session): add mixed Claude disallowed-tools helper

EOF
)"
```

---

### Task 2: Adapter emits `--disallowedTools` (TDD)

**Files:**
- Modify: `client/lib/services/cli/cli_tool_adapter.dart` (`ClaudeCodeCliToolAdapter.buildArguments` ~L116–156)
- Test: `client/test/services/cli/cli_tool_adapter_test.dart`

- [ ] **Step 1: Write failing adapter tests**

Append to `cli_tool_adapter_test.dart`:

```dart
  test('claude mixed worker gets shared disallowedTools without Agent', () {
    const adapter = ClaudeCodeCliToolAdapter();
    const mixedTeam = TeamProfile(
      id: 'team-x',
      name: 'mixers',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const worker = TeamMemberConfig(id: 'worker-1', name: 'Worker');

    final args = adapter.buildArguments(
      CliLaunchContext(team: mixedTeam, member: worker),
    );

    expect(args, isNot(contains('--team-name')));
    final flagAt = args.indexOf('--disallowedTools');
    expect(flagAt, isNonNegative);
    final tools = args.sublist(flagAt + 1);
    // Stop at next flag if any trailing flags exist after the tool list.
    final nextFlag = tools.indexWhere((t) => t.startsWith('--'));
    final denied = nextFlag < 0 ? tools : tools.sublist(0, nextFlag);
    expect(denied, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
    expect(denied, isNot(contains('Agent')));
  });

  test('claude mixed team-lead disallowedTools includes Agent', () {
    const adapter = ClaudeCodeCliToolAdapter();
    const mixedTeam = TeamProfile(
      id: 'team-x',
      name: 'mixers',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');

    final args = adapter.buildArguments(
      CliLaunchContext(team: mixedTeam, member: lead),
    );

    final flagAt = args.indexOf('--disallowedTools');
    expect(flagAt, isNonNegative);
    final tools = args.sublist(flagAt + 1);
    final nextFlag = tools.indexWhere((t) => t.startsWith('--'));
    final denied = nextFlag < 0 ? tools : tools.sublist(0, nextFlag);
    expect(denied, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
    expect(denied, contains('Agent'));
  });

  test('claude native omits disallowedTools', () {
    const adapter = ClaudeCodeCliToolAdapter();
    final args = adapter.buildArguments(
      CliLaunchContext(
        team: const TeamProfile(
          id: 'team-1',
          name: 'agent',
          cli: CliTool.claude,
        ),
        member: const TeamMemberConfig(id: 'm1', name: 'My Planner'),
      ),
    );

    expect(args, isNot(contains('--disallowedTools')));
    expect(args, contains('--team-name'));
  });
```

Add import if missing:

```dart
import 'package:teampilot/services/session/member_role_provision.dart';
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/cli/cli_tool_adapter_test.dart
```

Expected: FAIL — mixed cases lack `--disallowedTools`.

- [ ] **Step 3: Implement adapter wiring**

In `ClaudeCodeCliToolAdapter.buildArguments`, after the initial `args` list is built (after the `if (!mixed) ...[--team-name…]` block) and **before** model/settings/`extraArgs`:

```dart
    if (mixed) {
      final denied = MemberRoleProvision.disallowedToolsForMixedClaude(
        isLead: TeamMemberNaming.isTeamLead(member),
      );
      args.addAll(['--disallowedTools', ...denied]);
    }
```

Add import at top of `cli_tool_adapter.dart`:

```dart
import '../session/member_role_provision.dart';
```

(`TeamMemberNaming` is already imported.)

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/cli/cli_tool_adapter_test.dart \
  test/services/session/member_role_provision_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_tool_adapter.dart \
  client/test/services/cli/cli_tool_adapter_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): deny native swarm tools for mixed Claude via --disallowedTools

EOF
)"
```

---

### Task 3: Verify

- [ ] **Step 1: Analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/session/member_role_provision.dart \
  lib/services/cli/cli_tool_adapter.dart
cd client && flutter test \
  test/services/session/member_role_provision_test.dart \
  test/services/cli/cli_tool_adapter_test.dart
```

Expected: no issues; all tests PASS.

- [ ] **Step 2: Done** — no further commit unless analyze forced edits.
