# Native CLI roster = session pods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude native-team `config.json` / inboxes / `--agent-id` use session pod ids (`developer-0`) instead of type ids (`developer`), so SendMessage lands in the inbox the running shell polls.

**Architecture:** Seed role `agentType` on `MemberInstance.toMemberConfig`. Add `cliTeamRosterMembers` as a thin alias of `sessionRosterMembers`. Point session launch staging at pods; point no-session preview staging at `runtimeRosterMembers`. No SendMessage aliases, no idle wake-up.

**Tech Stack:** Flutter / Dart, existing `ClaudeTeamRosterService`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-03-native-cli-roster-pods-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/member_instance.dart` | Seed `agentType` on pod `toMemberConfig` |
| `client/lib/models/app_session.dart` | Add `cliTeamRosterMembers` → `sessionRosterMembers` |
| `client/lib/services/launch/session_connect_orchestrator.dart` | `stageTeamLaunch(members: cliTeamRosterMembers(...))` |
| `client/lib/services/session/session_lifecycle_service.dart` | Live seat: pods; preview env: `runtimeRosterMembers` |
| `AGENTS.md` | Document CLI roster hard rule |
| `client/test/models/member_instance_test.dart` | agentType seed + resolver cases |
| `client/test/services/team/claude_team_roster_service_test.dart` | merge/inbox with pods |
| Staging test (extend existing prepare/stage test or small focused test) | Disk `config.json` + `inboxes/developer-0.json` |

**Out of scope (do not touch):** type-name aliases, idle doorbell, `teammateMode`, mixed TeamBus, placement UI.

---

### Task 1: Seed `agentType` on pod expansion (TDD)

**Files:**
- Modify: `client/lib/models/member_instance.dart` (`toMemberConfig`)
- Modify: `client/test/models/member_instance_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `member_instance_test.dart`:

```dart
test('workspaceion seeds agentType from type id when empty', () {
  final cfg = expandTeamRoster(const [
    TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
  ]).first.toMemberConfig();
  expect(cfg.id, 'developer-0');
  expect(cfg.agentType, 'developer');
});

test('workspaceion preserves explicit type.agentType', () {
  final cfg = expandTeamRoster(const [
    TeamMemberConfig(
      id: 'developer',
      name: 'Developer',
      replicas: 2,
      agentType: 'implementer',
    ),
  ]).first.toMemberConfig();
  expect(cfg.agentType, 'implementer');
});

test('cliTeamRosterMembers matches sessionRosterMembers pods', () {
  final profile = team(const [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
    TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
  ]);
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    members: const [
      SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
      SessionMemberBinding(
        rosterMemberId: 'developer-0',
        typeId: 'developer',
        taskId: 't1',
      ),
      SessionMemberBinding(
        rosterMemberId: 'developer-1',
        typeId: 'developer',
        taskId: 't2',
      ),
    ],
  );
  expect(
    cliTeamRosterMembers(session, profile).map((m) => m.id).toList(),
    ['team-lead', 'developer-0', 'developer-1'],
  );
  expect(
    cliTeamRosterMembers(session, profile).map((m) => m.agentType).toList(),
    ['team-lead', 'developer', 'developer'],
  );
});
```

(Import `cliTeamRosterMembers` once Task 2 adds it — either keep this test in Task 2, or stub Task 1 without the `cliTeamRosterMembers` case and move that case to Task 2.)

**Prefer for Task 1 only:** the two `toMemberConfig` agentType tests above. Move `cliTeamRosterMembers` test to Task 2.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/models/member_instance_test.dart
```

Expected: FAIL on `agentType` expectations (today pod keeps empty `agentType`).

- [ ] **Step 3: Implement seed in `toMemberConfig`**

In `member_instance.dart`:

```dart
TeamMemberConfig toMemberConfig() {
  final seededAgentType = () {
    final explicit = type.agentType.trim();
    if (explicit.isNotEmpty) return explicit;
    final fromAgent = type.agent.trim();
    if (fromAgent.isNotEmpty) return fromAgent;
    return type.id;
  }();
  return type.copyWith(
    id: instanceId,
    name: displayName,
    agentType: seededAgentType,
    capabilities: {type.id, ...type.capabilities},
    replicas: 1,
  );
}
```

Lead: `type.id == team-lead` → `agentType` becomes `team-lead` (correct).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/models/member_instance_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/member_instance.dart client/test/models/member_instance_test.dart
git commit -m "$(cat <<'EOF'
fix(roster): seed agentType on pod expansion

Keep Claude agentType as the role/type id when replicas expand to
developer-0 style pods.
EOF
)"
```

---

### Task 2: Add `cliTeamRosterMembers` (TDD)

**Files:**
- Modify: `client/lib/models/app_session.dart`
- Modify: `client/test/models/member_instance_test.dart` (or `app_session` adjacent test)

- [ ] **Step 1: Write failing test**

```dart
test('cliTeamRosterMembers matches sessionRosterMembers', () {
  final profile = team(const [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
    TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
  ]);
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    members: const [
      SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
      SessionMemberBinding(
        rosterMemberId: 'developer-0',
        typeId: 'developer',
        taskId: 't1',
      ),
      SessionMemberBinding(
        rosterMemberId: 'developer-1',
        typeId: 'developer',
        taskId: 't2',
      ),
    ],
  );
  final cli = cliTeamRosterMembers(session, profile);
  final ui = sessionRosterMembers(session, profile);
  expect(cli.map((m) => m.id), ui.map((m) => m.id));
  expect(cli.map((m) => m.id), ['team-lead', 'developer-0', 'developer-1']);
  expect(cli.map((m) => m.agentType), ['team-lead', 'developer', 'developer']);
});

test('singleton replica keeps bare type id', () {
  final profile = team(const [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
    TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 1),
  ]);
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    members: const [
      SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't0'),
      SessionMemberBinding(rosterMemberId: 'developer', taskId: 't1'),
    ],
  );
  expect(
    cliTeamRosterMembers(session, profile).map((m) => m.id),
    ['team-lead', 'developer'],
  );
});
```

- [ ] **Step 2: Run — expect FAIL** (undefined `cliTeamRosterMembers`)

```bash
cd client && flutter test test/models/member_instance_test.dart
```

- [ ] **Step 3: Implement**

In `app_session.dart`, immediately after `sessionRosterMembers`:

```dart
/// Pod list for Claude / native CLI roster writers (`config.json`, inboxes).
///
/// Same members as [sessionRosterMembers] today. Call sites that stage CLI
/// team files must use this (or [runtimeRosterMembers] without a session),
/// never raw [TeamProfile.members].
List<TeamMemberConfig> cliTeamRosterMembers(
  AppSession session,
  TeamProfile team,
) =>
    sessionRosterMembers(session, team);
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test test/models/member_instance_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/app_session.dart client/test/models/member_instance_test.dart
git commit -m "$(cat <<'EOF'
feat(roster): add cliTeamRosterMembers for CLI staging

Named entry point so launch writers take session pods, not type templates.
EOF
)"
```

---

### Task 3: Claude roster merge uses pods (TDD)

**Files:**
- Modify: `client/test/services/team/claude_team_roster_service_test.dart`
- No production change if Task 1+2 done — this locks the contract `mergeConfig` / `ensureInboxes` already satisfy when fed pods.

- [ ] **Step 1: Write tests**

```dart
test('mergeConfig with pods writes pod names and role agentType', () {
  final service = ClaudeTeamRosterService(fs: LocalFilesystem());
  final pods = runtimeRosterMembers(
    const TeamProfile(
      id: 'default-native-team',
      name: 'Default',
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
        TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
      ],
    ),
  );
  final config = service.mergeConfig(
    cliTeamName: 'default-native-team-5',
    members: pods,
    cwd: '/workspace',
    teammateMode: 'in-process',
  );
  final members = (config['members'] as List).cast<Map>();
  expect(members.map((m) => m['name']), [
    'team-lead',
    'developer-0',
    'developer-1',
  ]);
  expect(members.map((m) => m['agentId']), [
    'team-lead',
    'developer-0@default-native-team-5',
    'developer-1@default-native-team-5',
  ]);
  final dev0 = members.firstWhere((m) => m['name'] == 'developer-0');
  expect(dev0['agentType'], 'developer');
});

test('ensureInboxes creates pod files not type file', () async {
  final root = Directory.systemTemp.createTempSync('claude-roster-');
  addTearDown(() => root.deleteSync(recursive: true));
  final fs = LocalFilesystem();
  final service = ClaudeTeamRosterService(fs: fs);
  final rosterDir = p.join(root.path, 'teams', 't');
  final pods = runtimeRosterMembers(
    const TeamProfile(
      id: 't',
      name: 'T',
      members: [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
      ],
    ),
  );
  await service.ensureInboxes(rosterDir: rosterDir, members: pods);
  expect(File(p.join(rosterDir, 'inboxes', 'developer-0.json')).existsSync(), isTrue);
  expect(File(p.join(rosterDir, 'inboxes', 'developer-1.json')).existsSync(), isTrue);
  expect(File(p.join(rosterDir, 'inboxes', 'developer.json')).existsSync(), isFalse);
});
```

Use `package:path/path.dart` as `p` (or `fs.pathContext`) consistent with nearby tests.

- [ ] **Step 2: Run**

```bash
cd client && flutter test test/services/team/claude_team_roster_service_test.dart
```

Expected: PASS after Task 1 (if FAIL on agentType, Task 1 incomplete).

- [ ] **Step 3: Commit**

```bash
git add client/test/services/team/claude_team_roster_service_test.dart
git commit -m "$(cat <<'EOF'
test(roster): lock Claude mergeConfig/inboxes on pod members

EOF
)"
```

---

### Task 4: Wire launch staging call sites

**Files:**
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart` (~line 264: `members: team.members`)
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
  - Live seat `prepareTeamLaunch` inside prepareLaunch (~line 844): `cliTeamRosterMembers(session, team)`
  - Preview `prepareTeamLaunchEnvironment` (~line 416): `runtimeRosterMembers(team)`
- Test: **extend** `client/test/services/session/session_lifecycle_service_test.dart` (has `prepareLaunch` scaffolding that goes through lifecycle → `prepareTeamLaunch`). Do **not** only assert by calling `prepareTeamLaunch`/`stageTeamLaunch` with a hand-built `members:` list — that bypasses the production call sites and stays green before the wire.

- [ ] **Step 1: Write failing lifecycle tests**

Add to `session_lifecycle_service_test.dart` (mirror existing Claude native `prepareLaunch` setup: temp AppStorage, team profile with replicas, session with pod bindings):

```dart
test('prepareLaunch writes Claude roster pods not type names', () async {
  // Team: developer.replicas=2, reviewer.replicas=0
  // Session.members: team-lead, developer-0, developer-1 (with typeId)
  final plan = await service().prepareLaunch(/* … same harness as siblings … */);
  // Locate session Claude teams dir from plan / AppStorage paths used by harness
  final configPath = /* …/runtime/claude/teams/<cliTeamName>/config.json */;
  final decoded = jsonDecode(File(configPath).readAsStringSync()) as Map;
  final names = (decoded['members'] as List)
      .map((m) => (m as Map)['name'])
      .toList();
  expect(names, ['team-lead', 'developer-0', 'developer-1']);
  final inbox0 = /* …/inboxes/developer-0.json */;
  expect(File(inbox0).existsSync(), isTrue);
  expect(File(/* …/inboxes/developer.json */).existsSync(), isFalse);
});

test('prepareTeamLaunchEnvironment expands runtimeRosterMembers', () async {
  // Call prepareTeamLaunchEnvironment with developer.replicas=2
  // Assert written config names include developer-0 / developer-1 (not bare developer only)
});
```

Fill concrete paths using the same path helpers / `AppStorage` layout the existing test file already uses for Claude settings assertions (`prepareLaunch writes Claude provider settings…`).

**Red condition:** before Task 4 wiring, `prepareLaunch` still passes `team.members` → config has `developer` / `reviewer` and/or `inboxes/developer.json` → assertion fails.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/session/session_lifecycle_service_test.dart --name "Claude roster pods"
```

(Adjust `--name` to match the test title.)

- [ ] **Step 3: Wire call sites**

`session_connect_orchestrator.dart`:

```dart
members: cliTeamRosterMembers(session, team),
```

`session_lifecycle_service.dart` live seat:

```dart
members: cliTeamRosterMembers(session, team),
```

`prepareTeamLaunchEnvironment`:

```dart
members: runtimeRosterMembers(team),
```

Add imports for `cliTeamRosterMembers` / `runtimeRosterMembers` as needed.

Do **not** change placement / landing settings call sites that still correctly use `team.members`.

Also wire orchestrator even if this task’s automated test only hits lifecycle — keep both production paths consistent (orchestrator is the primary live staging path in the app).

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test test/models/member_instance_test.dart \
  test/services/team/claude_team_roster_service_test.dart \
  test/services/session/session_lifecycle_service_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_connect_orchestrator.dart \
  client/lib/services/session/session_lifecycle_service.dart \
  client/test/services/session/session_lifecycle_service_test.dart
git commit -m "$(cat <<'EOF'
fix(launch): stage Claude roster from session pods

Stop writing type-level developer/reviewer rows so agent-id and
inboxes match launched replica shells.
EOF
)"
```

---

### Task 5: Docs + verify

**Files:**
- Modify: `AGENTS.md` (session roster / CLI section — one short hard-rule sentence)

- [ ] **Step 1: Document hard rule**

Near member placement / session roster guidance, add:

> Native Claude roster writers (`teams/.../config.json`, inboxes) must use `cliTeamRosterMembers(session, team)` when a session exists, or `runtimeRosterMembers(team)` for preview — never raw `team.members`.

- [ ] **Step 2: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/models/member_instance_test.dart \
  test/services/team/claude_team_roster_service_test.dart \
  test/services/session/session_lifecycle_service_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs: require pod lists for Claude CLI roster writers

EOF
)"
```

---

## Manual acceptance (after implementation)

New native session: `developer.replicas=2`, `reviewer.replicas=0`.

1. Disk roster = `team-lead`, `developer-0`, `developer-1` only; `agentType` for pods = `developer`.
2. Lead `SendMessage(to: "developer-0")` → `inboxes/developer-0.json`.
3. `developer-0` process args include `--agent-id developer-0@<cliTeamName>`.

Optional (YAGNI unless easy): debug assert when staging receives bare type ids while session has numbered pods — **skip** unless needed for regression hunting.

---

## Execution handoff

Plan complete. Two options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute in this session with checkpoints  

Which approach?
