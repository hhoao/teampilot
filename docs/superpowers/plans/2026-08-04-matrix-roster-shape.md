# Matrix RosterShape + native replicated L2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `RosterShape` as a third CLI-message-matrix axis and green the first full-path cell `claude × native × replicated` (pod roster/inbox identity + worker-0 consume + 2 lead History composes).

**Architecture:** Extract roster/shape builders from the matrix harness; add `nativeCollabReplica2Plus` gateway recipe and `native_roster_assertions`; migrate singleton worker type id to `developer`; boot/session paths use session pods. Fix product bugs uncovered while greening — no compat shims.

**Tech Stack:** Flutter integration tests (`linux-pty`), `mock_model_gateway`, existing `CliMessageMatrixHarness` / `CliTestProfile`.

**Spec:** `docs/superpowers/specs/2026-08-04-matrix-roster-shape-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/test/integration/support/roster_shape.dart` | `RosterShape` enum + team/pod builders + placementFiltered omit helper |
| `client/test/integration/support/native_roster_assertions.dart` | Claude `config.json` / inbox disk asserts |
| `client/test/integration/support/cli_message_matrix_harness.dart` | Wire `shape`, pod boot list, recipes, worker id = `developer` |
| `client/test/integration/support/cli_message_matrix_harness_test.dart` | Unit tests for shape builders / boot ids |
| `tools/mock_model_gateway/lib/scenarios/native_collab_replica_2plus.dart` | New gateway recipe |
| `tools/mock_model_gateway/lib/scenarios/native_collab_3plus.dart` | Align worker naming if needed |
| `tools/mock_model_gateway/lib/scenarios/mixed_collab_3plus.dart` | Worker id → `developer` if mail asserts depend on it |
| `client/test/integration/cli_message_matrix_*_test.dart` | Pass `shape: singleton`; add claude replicated cell |
| `docs/MATRIX.md` | Document CLI × Mode × RosterShape |
| Product files (as discovered) | Root-cause fixes only while greening |

**Constants (lock):**

```dart
const kMatrixLeadMemberId = 'team-lead';
const kMatrixWorkerTypeId = 'developer'; // was worker-1 — breaking rename
// pods: developer-0, developer-1 when replicated
```

**Round shape (acceptance):** 2 lead History composes + 1 worker-0 reply (not 2 full ping-pongs).

---

### Task 1: `RosterShape` builders (TDD)

**Files:**
- Create: `client/test/integration/support/roster_shape.dart`
- Create: `client/test/integration/support/roster_shape_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('singleton team: developer replicas 1 → pods team-lead, developer', () {
  final team = buildMatrixTeam(
    tool: CliTool.claude,
    mode: CliMatrixMode.native,
    shape: RosterShape.singleton,
  );
  expect(team.members.map((m) => m.id), ['team-lead', 'developer']);
  expect(team.members.last.replicas, 1);
  expect(
    expandTeamRoster(team.members).map((i) => i.instanceId),
    ['team-lead', 'developer'],
  );
});

test('replicated team: developer replicas 2 → pods developer-0/1', () {
  final team = buildMatrixTeam(
    tool: CliTool.claude,
    mode: CliMatrixMode.native,
    shape: RosterShape.replicated,
  );
  expect(team.members.last.replicas, 2);
  expect(
    expandTeamRoster(team.members).map((i) => i.instanceId),
    ['team-lead', 'developer-0', 'developer-1'],
  );
});

test('placementFiltered omits developer-1 from bindings helper', () {
  final bindings = matrixSessionBindings(
    shape: RosterShape.placementFiltered,
    team: buildMatrixTeam(
      tool: CliTool.claude,
      mode: CliMatrixMode.native,
      shape: RosterShape.placementFiltered,
    ),
  );
  expect(bindings.map((b) => b.rosterMemberId), [
    'team-lead',
    'developer-0',
    // developer-1 omitted
  ]);
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/integration/support/roster_shape_test.dart
```

- [ ] **Step 3: Implement `roster_shape.dart`**

- `enum RosterShape { singleton, replicated, placementFiltered }`
- `buildMatrixTeam(...)` — lead + `developer` with replicas 1 / 2 / 2
- `matrixExpectedPodIds(shape)` / `matrixPrimaryWorkerPodId(shape)` → `developer` or `developer-0`
- `matrixSessionBindings(...)` — full expand; for `placementFiltered` drop `developer-1`

Use same provider/model/effort fields as current `buildHomogeneousTeam` (or accept them as params from harness). Keep this file free of ChatCubit / gateway.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/test/integration/support/roster_shape.dart \
  client/test/integration/support/roster_shape_test.dart
git commit -m "$(cat <<'EOF'
test(matrix): add RosterShape team and pod builders

EOF
)"
```

---

### Task 2: Rename matrix worker type id → `developer`

**Files:**
- Modify: `cli_message_matrix_harness.dart` (`kMatrixWorkerMemberId = 'developer'`)
- Modify: all `cli_message_matrix_*_test.dart` / mail asserts using `worker-1`
- Modify: gateway scenarios that hardcode `worker-1` / `to: worker-1` if any
- Modify: `cli_message_matrix_harness_test.dart` as needed

- [ ] **Step 1: Replace constant and grep-fix `worker-1` under matrix + related scenarios**

```bash
rg -n "worker-1|kMatrixWorkerMemberId" client/test/integration tools/mock_model_gateway/lib/scenarios
```

- [ ] **Step 2: Run non-PTY unit tests**

```bash
cd client && flutter test test/integration/support/cli_message_matrix_harness_test.dart \
  test/integration/support/roster_shape_test.dart
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(matrix): rename worker type id to developer

Align matrix naming with product native roster pods (no compat).
EOF
)"
```

---

### Task 3: Harness takes `RosterShape` + boots session pods

**Files:**
- Modify: `cli_message_matrix_harness.dart`
- Modify: `cli_message_matrix_harness_test.dart`

**Note:** `openSession` keeps passing **type** `rosterMembers` with `replicas` set — production `createSession` / `expandTeamRoster` already materializes pods. Do **not** change that contract; only fix boot/iteration lists to use session pods after open.

- [ ] **Step 1: Failing unit tests**

```dart
test('bootMemberIds uses pods for replicated shape', () {
  final h = CliMessageMatrixHarness.forCli(
    CliTool.claude,
    mode: CliMatrixMode.native,
    shape: RosterShape.replicated,
  );
  final team = h.buildHomogeneousTeam();
  expect(h.bootMemberIdsFor(team: team), [
    'team-lead',
    'developer-0',
    'developer-1',
  ]);
});
```

Expose `bootMemberIdsFor` as a pure helper (expand team or, when session is set, `sessionRosterMembers`).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

- Add `final RosterShape shape` (default `singleton`) to harness / `forCli`.
- `buildHomogeneousTeam()` delegates to `buildMatrixTeam(..., shape: shape)`.
- `bootAllMembersToPrompt`: use `bootMemberIdsFor` (session pods when `session`+`team` set).
- Add `CliMatrixRecipe.nativeCollabReplica2Plus` enum value (wire scenarios in Task 4).
- `defaultRecipeFor`: singleton native → `nativeCollab3Plus`; replicated native → `nativeCollabReplica2Plus`.

- [ ] **Step 4: PASS unit tests; existing matrix tests default `shape: singleton`**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(matrix): wire RosterShape into harness and pod boot list

EOF
)"
```

---

### Task 4: Gateway recipe `nativeCollabReplica2Plus`

**Files:**
- Create: `tools/mock_model_gateway/lib/scenarios/native_collab_replica_2plus.dart`
- Modify: gateway package export if required
- Modify: harness `scenariosFor(recipe)` mapping
- Test: gateway unit test if package has scenario tests; else harness unit that recipe is selected

- [ ] **Step 1: Define markers**

```dart
const markReplicaLead1 = 'MARK_REPLICA_LEAD_1';
const markReplicaW01 = 'MARK_REPLICA_W0_1';
const markReplicaLead2 = 'MARK_REPLICA_LEAD_2';
```

- [ ] **Step 2: Lead / worker-0 turns**

Lead (`leadScriptApiKey`):

1. Native team/task tools as needed + `native.SendMessage` with `to: developer-0` (and content that worker will “see”)
2. `TextTurn(markReplicaLead1)`
3. (After worker reply in real time, second compose drives:) tools optional + `TextTurn(markReplicaLead2)`

Worker (`workerScriptApiKey` → pod `developer-0`):

1. TaskGet / read path as profile requires
2. `TextTurn(markReplicaW01)`
3. `native.SendMessage` reply to `team-lead`

Keep `developer-1` idle. **Provider caveat:** both pods inherit type `developer`’s `mock-worker` key — “no script” means “do not kick off requests,” not a separate empty scenario. If greening shows `developer-1` stealing worker turns, give `developer-1` a distinct dummy provider or bind the active script to a dedicated `worker0ScriptApiKey` only used by `developer-0`’s settings.

Mirror structure/comments of `native_collab_3plus.dart`. Ensure toolRefs stay `native.*` for profile mapping.

- [ ] **Step 3: Wire enum → `nativeCollabReplica2PlusScenarios()` in harness**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(gateway): add nativeCollabReplica2Plus scenario

EOF
)"
```

---

### Task 5: `native_roster_assertions` (TDD)

**Files:**
- Create: `client/test/integration/support/native_roster_assertions.dart`
- Create: `client/test/integration/support/native_roster_assertions_test.dart`

- [ ] **Step 1: Unit tests with temp dirs**

Write a minimal `config.json` + `inboxes/developer-0.json`; assert helpers pass/fail as expected.

```dart
expectClaudeRosterPods(
  claudeDir: root,
  cliTeamName: 't-1',
  expectedNames: ['team-lead', 'developer-0', 'developer-1'],
  expectedAgentTypes: {
    'team-lead': 'team-lead',
    'developer-0': 'developer',
    'developer-1': 'developer',
  },
);
expectClaudeInboxExists(claudeDir: root, cliTeamName: 't-1', memberId: 'developer-0');
expectClaudeInboxAbsent(claudeDir: root, cliTeamName: 't-1', memberId: 'developer');
```

`expectClaudeRosterPods` **must** assert each member row’s `agentType` (Acceptance #2 — catches pod id leaking into `agentType`).

Use `ClaudeTeamRosterService.safeClaudePathSegment` for paths (same as product).

- [ ] **Step 2–4: Implement → PASS → Commit**

```bash
git commit -m "$(cat <<'EOF'
test(matrix): add Claude native roster disk assertions

EOF
)"
```

---

### Task 6: L2 cell `claude × native × replicated`

**Files:**
- Modify: `client/test/integration/cli_message_matrix_claude_test.dart`
- Possibly product code if red

**Resolving Claude runtime dir (concrete):**

After `openSession` + at least lead connect/staging:

```dart
final cliTeam = harness.session!.cliTeamName.trim().isNotEmpty
    ? harness.session!.cliTeamName
    : harness.session!.sessionId;
final claudeDir = RuntimeLayout(teampilotRoot: AppStorage.appDataRoot)
    .sessionRuntimeToolDir(
      harness.session!.workspaceId,
      harness.session!.sessionId,
      'claude',
    );
// teams/<safe(cliTeam)>/config.json lives under claudeDir
```

Mirror path joining used in `session_lifecycle_service_test` (`ClaudeTeamRosterService.safeClaudePathSegment(cliTeam)`).

- [ ] **Step 1: Add test**

Copy the settle pattern from existing `claude native: History compose → collab ≥3` (gateway `before + 1`, `bootComposeSeatToPrompt` between composes).

```dart
test('claude native replicated: pods inbox + worker-0 + 2 lead composes', () async {
  IntegrationPrerequisites.skipUnlessNativePty();
  final claudePath = IntegrationPrerequisites.requireClaudePath();
  if (claudePath == null) return;

  final harness = CliMessageMatrixHarness.forCli(
    CliTool.claude,
    mode: CliMatrixMode.native,
    shape: RosterShape.replicated,
    recipe: CliMatrixRecipe.nativeCollabReplica2Plus,
    cliPath: claudePath,
  );
  final postFrame = PostFrameTestHarness();
  addTearDown(() async {
    await harness.dispose();
    await postFrame.flush();
    await drainPendingAsyncWork();
    await Future<void>.delayed(const Duration(seconds: 3));
  });

  await harness.startGateway();
  await harness.writeMockProviders();
  harness.createCubit(postFrame: postFrame);
  await harness.openSession();
  await harness.bootAllMembersToPrompt();
  await harness.loadHistory();

  final leadBefore1 = harness.gateway!.requestCountFor(leadScriptApiKey);
  final r1 = await harness.submitCompose('matrix replica turn one coordinate');
  expect(r1.ok, isTrue, reason: harness.diagnosticsBundle());
  await harness.waitForGatewayTurns(
    apiKey: leadScriptApiKey,
    minTurns: leadBefore1 + 1,
  );
  await harness.waitForPtyMarkers(
    [markReplicaLead1],
    memberId: kMatrixLeadMemberId,
  );

  final cliTeam = harness.session!.cliTeamName.trim().isNotEmpty
      ? harness.session!.cliTeamName
      : harness.session!.sessionId;
  final claudeDir = RuntimeLayout(teampilotRoot: AppStorage.appDataRoot)
      .sessionRuntimeToolDir(
        harness.session!.workspaceId,
        harness.session!.sessionId,
        'claude',
      );
  expectClaudeRosterPods(
    claudeDir: claudeDir,
    cliTeamName: cliTeam,
    expectedNames: const ['team-lead', 'developer-0', 'developer-1'],
    expectedAgentTypes: const {
      'team-lead': 'team-lead',
      'developer-0': 'developer',
      'developer-1': 'developer',
    },
  );
  expectClaudeInboxExists(
    claudeDir: claudeDir,
    cliTeamName: cliTeam,
    memberId: 'developer-0',
  );
  expectClaudeInboxAbsent(
    claudeDir: claudeDir,
    cliTeamName: cliTeam,
    memberId: 'developer',
  );

  await harness.waitForPtyMarkers(
    [markReplicaW01],
    memberId: 'developer-0',
  );

  await harness.bootComposeSeatToPrompt();
  final leadBefore2 = harness.gateway!.requestCountFor(leadScriptApiKey);
  final r2 = await harness.submitCompose('matrix replica turn two continue');
  expect(r2.ok, isTrue, reason: harness.diagnosticsBundle());
  await harness.waitForGatewayTurns(
    apiKey: leadScriptApiKey,
    minTurns: leadBefore2 + 1,
  );
  await harness.waitForPtyMarkers(
    [markReplicaLead2],
    memberId: kMatrixLeadMemberId,
  );
});
```

- [ ] **Step 2: Run L2 (local, long)**

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_claude_test.dart \
  --plain-name="replicated"
```

Expected initially: FAIL with actionable diagnostics.

- [ ] **Step 3: Green the cell**

Debug checklist:

1. Session bindings / connect schedule for `developer-0/1`
2. Claude roster disk + `agentType`
3. Gateway `to: developer-0` vs Claude tool schema
4. Worker wake/consume — fix product root cause if required; do not drop asserts

- [ ] **Step 4: Pin existing native test to `shape: RosterShape.singleton`**

- [ ] **Step 5: Commit test + any product fixes**

```bash
git commit -m "$(cat <<'EOF'
test(matrix): green claude native replicated roster cell

Prove pod inboxes and worker-0 consume across two lead composes.
EOF
)"
```

(If product fixes are large, separate commit(s) before the test commit.)

---

### Task 7: Docs + verify

**Files:**
- Modify: `docs/MATRIX.md`
- Optional: one-line pointer in `docs/DEVELOPMENT.md` if matrix section lists cells

- [ ] **Step 1: Rewrite MATRIX.md** for CLI × Mode × RosterShape; mark `claude native replicated` green when Task 6 passes; note `placementFiltered` deferred. Add one line: later **flashskyai native replicated** = new/shared recipe + one test registration (same shape axis).

- [ ] **Step 2: Run unit suite**

```bash
cd client && flutter test \
  test/integration/support/roster_shape_test.dart \
  test/integration/support/native_roster_assertions_test.dart \
  test/integration/support/cli_message_matrix_harness_test.dart
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: document matrix RosterShape axis

EOF
)"
```

---

## Manual / CI notes

- L2 cell requires Linux PTY + installed `claude` + mock gateway (same as existing matrix).
- Do not weaken disk or marker asserts to pass.
- `placementFiltered` L2 is out of scope; only builder unit tests from Task 1.

---

## Execution handoff

Plan complete. Two options:

1. **Subagent-Driven (recommended)** — fresh subagent per task  
2. **Inline Execution** — this session with checkpoints  

Which approach?
