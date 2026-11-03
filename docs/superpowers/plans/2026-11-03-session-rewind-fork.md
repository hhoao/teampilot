# Session rewind and fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Checkpoint each local seat's `runtime/` after every completed turn, and rewind or fork that seat from the message that closed the turn.

**Architecture:** `services/chat/rewind/` owns one private Git repository per seat (`GIT_DIR` beside the session, `GIT_WORK_TREE` = that session's `runtime/`). Commits are path-limited and append-only. Rewind checks out one seat and relaunches it. Fork copies commits up to the chosen one into a new personal session. The chat UI only adds actions and a divider.

**Tech Stack:** Dart/Flutter, system `git`, existing `AcpChatRuntimeCubit`, `ChatCubit`, `SessionDataStore.createSession`, `AiMessageActionBar`.

## Global Constraints

- Never run `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. One test file per task. Full suite once before claiming done.
- Do not parse or truncate a CLI transcript inside `services/chat/rewind/`.
- Do not write a `.git` directory inside `runtime/<tool>/`, and do not touch the user's project `.git`.
- Rewind and fork are local seats only. SSH work plane and Android do not show the actions.
- ACP load/resume failure must not fall through to `session/new` (existing `AcpSessionRuntime._openSession` rule).
- Logging via `AppLogger`. User-facing copy only in `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- Paths come from injected layout / `Filesystem`. No `Directory.current` for app data roots.
- Spec: `docs/superpowers/specs/2026-11-03-session-rewind-fork-design.md`.

---

## File Structure

**Create:**

- `client/lib/services/chat/rewind/seat_rewind_paths.dart` — seat key, included prefixes, exclude names.
- `client/lib/services/chat/rewind/seat_rewind_store.dart` — init, commit, restore, list, fork the Git repo.
- `client/lib/services/chat/rewind/rewind_fork_service.dart` — stop/relaunch/create-session orchestration. No Git commands of its own.
- `client/test/services/chat/rewind/seat_rewind_paths_test.dart`
- `client/test/services/chat/rewind/seat_rewind_store_test.dart`
- `client/test/services/chat/rewind/rewind_fork_service_test.dart`

**Modify:**

- `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` — after a real turn's `_persist`, call the store.
- `client/lib/cubits/chat_cubit.dart` — PTY `_onTurnEnded` calls the store; rewind and fork entry points.
- `client/packages/ai_message_ui/lib/src/message_action_bar.dart` — optional rewind/fork callbacks.
- `client/lib/pages/chat/session_history_thread.dart` — pass callbacks; render the divider's messages in a weaker style.
- `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`.

`seat_rewind_store.dart` shells out to `git`. Tests use a real `git` and a temp directory. `InMemoryFilesystem` cannot host a Git work tree.

---

### Task 1: Seat paths

**Files:**

- Create: `client/lib/services/chat/rewind/seat_rewind_paths.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_paths_test.dart`

**Interfaces:**

- Consumes: nothing
- Produces:

```dart
enum SeatRewindKind { personalAcp, mixedAcp, personalPty, mixedPty }

final class SeatRewindTarget {
  const SeatRewindTarget({
    required this.kind,
    required this.tool,
    this.memberId,
  });

  final SeatRewindKind kind;
  final String tool;
  final String? memberId;

  String get seatKey =>
      kind == SeatRewindKind.personalAcp || kind == SeatRewindKind.personalPty
      ? 'personal'
      : memberId!.trim();

  /// Repo-relative paths that `git add` / checkout may touch.
  List<String> get includedPrefixes;

  bool includes(String repoRelativePath);
  bool isExcluded(String repoRelativePath);
}

const rewindExcludeNames = {'plugins', 'skills', 'node_modules', 'cache'};
```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:test/test.dart';

void main() {
  test('personal ACP includes the tool dir and both sidecars', () {
    const target = SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    );
    expect(target.seatKey, 'personal');
    expect(target.includes('claude/projects/a.jsonl'), isTrue);
    expect(target.includes('acp-transcript.jsonl'), isTrue);
    expect(target.includes('acp-session.json'), isTrue);
    expect(target.includes('codex/sessions/x.jsonl'), isFalse);
    expect(target.isExcluded('claude/plugins/installed/a'), isTrue);
    expect(target.isExcluded('claude/skills/x'), isTrue);
    expect(target.isExcluded('claude/node_modules/y'), isTrue);
    expect(target.isExcluded('claude/cache/z'), isTrue);
    expect(target.isExcluded('claude/projects/a.jsonl'), isFalse);
  });

  test('mixed ACP prefixes stay under the member id', () {
    const target = SeatRewindTarget(
      kind: SeatRewindKind.mixedAcp,
      tool: 'claude',
      memberId: 'm1',
    );
    expect(target.seatKey, 'm1');
    expect(target.includes('m1/claude/projects/a.jsonl'), isTrue);
    expect(target.includes('acp-transcript-m1.jsonl'), isTrue);
    expect(target.includes('acp-session-m1.json'), isTrue);
    expect(target.includes('claude/projects/a.jsonl'), isFalse);
    expect(target.includes('acp-transcript.jsonl'), isFalse);
  });

  test('PTY seats have no ACP sidecars', () {
    const personal = SeatRewindTarget(
      kind: SeatRewindKind.personalPty,
      tool: 'codex',
    );
    const mixed = SeatRewindTarget(
      kind: SeatRewindKind.mixedPty,
      tool: 'codex',
      memberId: 'm1',
    );
    expect(personal.includes('codex/sessions/rollout.jsonl'), isTrue);
    expect(personal.includes('acp-session.json'), isFalse);
    expect(mixed.includes('m1/codex/sessions/rollout.jsonl'), isTrue);
    expect(mixed.includes('acp-session-m1.json'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_paths_test.dart`

Expected: FAIL, `seat_rewind_paths.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

`includedPrefixes` returns the tool directory plus, for ACP, the two sidecar file names from `acpTranscriptFileName` / `acpAgentSessionFileName` (`client/lib/services/acp/acp_session_files.dart`). `includes` is true when the path equals a sidecar or starts with `{prefix}/`. `isExcluded` is true when any path segment is in `rewindExcludeNames`. A symlink is excluded by the store (Task 2) before `git add`; this class only answers path questions.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_paths_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_paths.dart \
  client/test/services/chat/rewind/seat_rewind_paths_test.dart
git commit -m "Add seat path rules for rewind checkpoints."
```

---

### Task 2: Commit a checkpoint

**Files:**

- Create: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**

- Consumes: `SeatRewindTarget` from Task 1
- Produces:

```dart
final class RewindCheckpoint {
  const RewindCheckpoint({
    required this.commit,
    required this.messageId,
    required this.nativeSessionId,
  });

  final String commit;
  final String messageId;
  final String? nativeSessionId;
}

final class SeatRewindStore {
  SeatRewindStore({
    required this.gitDir,
    required this.workTree,
    required this.target,
    this.gitExecutable = 'git',
  });

  final String gitDir;
  final String workTree;
  final SeatRewindTarget target;
  final String gitExecutable;

  Future<void> ensureRepo();
  Future<RewindCheckpoint> commitTurn({
    required String messageId,
    String? nativeSessionId,
  });
  Future<String?> checkedOut();
  Future<List<RewindCheckpoint>> checkpoints();

  /// `git show <commit>:<path>` bytes decoded as UTF-8, or null when missing.
  Future<String?> showFile(String commit, String path);
}
```

`commitTurn` creates a commit whose parent is `refs/rewind/checked-out` (none on the first commit), writes `Turn-Message:` and `Native-Session:` trailers, points `refs/rewind/keep/<messageId>`, `refs/rewind/live`, and `refs/rewind/checked-out` at the new commit. It `git add`s only `target.includes` paths that are regular files. It does not add symlinks or excluded paths. It does not add another seat's files.

- [ ] **Step 1: Write the failing test**

Use `Directory.systemTemp.createTemp('rewind-')`. Layout:

```text
work/claude/projects/a.jsonl          "one"
work/claude/plugins/link              symlink to a dir outside work
work/acp-transcript.jsonl             "[]"
work/acp-session.json                 {"v":1,"sessionId":"s1"}
work/other/secret.txt                 "nope"
```

```dart
test('commit stores one seat and skips symlink, cache names, and siblings', () async {
  final store = SeatRewindStore(
    gitDir: '$tmp/repo.git',
    workTree: '$tmp/work',
    target: const SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    ),
  );
  final checkpoint = await store.commitTurn(
    messageId: 'm1',
    nativeSessionId: null,
  );
  final names = await _lsTree(store, checkpoint.commit);
  expect(names, containsAll([
    'claude/projects/a.jsonl',
    'acp-transcript.jsonl',
    'acp-session.json',
  ]));
  expect(names.any((n) => n.contains('plugins') || n == 'other/secret.txt'), isFalse);
  expect(await store.checkedOut(), checkpoint.commit);
  expect((await store.checkpoints()).single.messageId, 'm1');
  expect(
    await store.showFile(checkpoint.commit, 'claude/projects/a.jsonl'),
    'one',
  );
});
```

`_lsTree` runs `git --git-dir <gitDir> ls-tree -r --name-only <commit>`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`

Expected: FAIL, `SeatRewindStore` is not defined.

- [ ] **Step 3: Write minimal implementation**

`ensureRepo` runs `git init` in `gitDir` when `HEAD` is missing, then writes `info/exclude` with the four names. Every later command uses `git --git-dir <gitDir> --work-tree <workTree>`.

`commitTurn`:

1. `ensureRepo`.
2. Walk `workTree`. For each regular file whose repo-relative path `includes` and is not `isExcluded` and is not a symlink, `git add -- <path>`.
3. `git write-tree` to get the tree.
4. Read `refs/rewind/checked-out`. `git commit-tree <tree> -p <parent?>` with message:

```text
checkpoint

Turn-Message: <messageId>
Native-Session: <id or empty>
```

5. `git update-ref refs/rewind/keep/<messageId> <commit>`, and the same for `refs/rewind/live` and `refs/rewind/checked-out`.
6. `showFile` runs `git --git-dir <gitDir> show <commit>:<path>` and returns null when Git exits non-zero.
7. Return `RewindCheckpoint`.

`checkpoints` walks `refs/rewind/keep/*` and parses the trailers with `git log -1 --format=%B`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_store.dart \
  client/test/services/chat/rewind/seat_rewind_store_test.dart
git commit -m "Record a per-seat rewind checkpoint in a private Git repo."
```

---

### Task 3: Restore and roll back

**Files:**

- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Modify: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**

- Consumes: `commitTurn`, `checkedOut` from Task 2
- Produces:

```dart
Future<void> restore(String commit);
```

`restore` writes the commit's files for this seat and deletes seat files that are not in the commit. It does not delete excluded paths, symlinks, or paths `includes` rejects. On failure it writes the previous `checked-out` tree back and rethrows. Success sets `refs/rewind/checked-out` to `commit` and leaves `refs/rewind/live` unchanged.

- [ ] **Step 1: Write the failing test**

```dart
test('restore replaces seat bytes, deletes extras, and keeps the sibling', () async {
  final first = await store.commitTurn(messageId: 'm1');
  await File('$work/claude/projects/a.jsonl').writeAsString('two');
  await File('$work/claude/projects/extra.txt').writeAsString('x');
  await store.commitTurn(messageId: 'm2');
  await store.restore(first.commit);
  expect(await File('$work/claude/projects/a.jsonl').readAsString(), 'one');
  expect(File('$work/claude/projects/extra.txt').existsSync(), isFalse);
  expect(await File('$work/other/secret.txt').readAsString(), 'nope');
  expect(await store.checkedOut(), first.commit);
});

test('failed restore puts the previous tree back', () async {
  final first = await store.commitTurn(messageId: 'm1');
  await File('$work/claude/projects/a.jsonl').writeAsString('two');
  final second = await store.commitTurn(messageId: 'm2');
  // Point the store at a git that fails the second checkout.
  // Assert work tree bytes are still "two" and checked-out is second.commit.
});
```

The failure test injects `gitExecutable` as a script: pass through every command except a `checkout` whose target commit equals `first.commit`, which exits 1. After `restore` throws, `a.jsonl` is `two` and `checkedOut()` is `second.commit`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart --plain-name restore`

Expected: FAIL, `restore` is not defined.

- [ ] **Step 3: Write minimal implementation**

1. Remember `previous = checkedOut()`.
2. `git checkout <commit> -- <included prefixes>`.
3. `git ls-tree -r --name-only <commit>` into a set.
4. Walk the work tree. Delete a regular file when `includes` is true, `isExcluded` is false, and the path is not in the set.
5. If any step throws and `previous != null`, run the same write against `previous`, then rethrow.
6. `git update-ref refs/rewind/checked-out <commit>`.

Do not run `git clean` on the whole work tree.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_store.dart \
  client/test/services/chat/rewind/seat_rewind_store_test.dart
git commit -m "Restore one rewind checkpoint without touching sibling seats."
```

---

### Task 4: Fork the repository

**Files:**

- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Modify: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**

- Consumes: `restore`, refs from Task 3
- Produces:

```dart
Future<SeatRewindStore> forkAt({
  required String commit,
  required String destGitDir,
  required String destWorkTree,
  required SeatRewindTarget destTarget,
});
```

The destination repo contains the selected commit and its ancestors only. `live` and `checked-out` both point at that commit. Files are restored through `destTarget` (personal layout). A mixed source path `m1/claude/foo` is written as `claude/foo`. `acp-transcript-m1.jsonl` is written as `acp-transcript.jsonl`. `acp-session-m1.json` is written as `acp-session.json`.

- [ ] **Step 1: Write the failing test**

Commit `m1` then `m2` on a mixed ACP seat (`memberId: m1`, tool `claude`) with `m1/claude/projects/a.jsonl` = `one` then `two`, and `acp-session-m1.json`. `forkAt` the `m1` commit into a personal ACP dest. Assert dest `live` equals the `m1` commit, `claude/projects/a.jsonl` is `one`, `acp-session.json` exists, `acp-session-m1.json` does not, and `git rev-list` on dest does not contain the `m2` commit. Source `a.jsonl` is still `two`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart --plain-name forkAt`

Expected: FAIL, `forkAt` is not defined.

- [ ] **Step 3: Write minimal implementation**

`git init` dest. `git --git-dir dest fetch <sourceGitDir> <commit>`. `update-ref` `refs/rewind/live` and `refs/rewind/checked-out` to `FETCH_HEAD`. Copy ancestor `refs/rewind/keep/*` whose target is reachable from that commit (`git merge-base --is-ancestor`). Map each source path with:

```dart
String personalize(SeatRewindTarget source, String path) {
  final member = source.memberId?.trim() ?? '';
  if (member.isEmpty) return path;
  final prefix = '$member/${source.tool}/';
  if (path.startsWith(prefix)) {
    return '${source.tool}/${path.substring(prefix.length)}';
  }
  if (path == 'acp-transcript-$member.jsonl') return 'acp-transcript.jsonl';
  if (path == 'acp-session-$member.json') return 'acp-session.json';
  return path;
}
```

Checkout mapped paths into `destWorkTree` with `git show <commit>:<path>` written to the personalized relative path. Do not call source `restore`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_store.dart \
  client/test/services/chat/rewind/seat_rewind_store_test.dart
git commit -m "Fork a rewind repo up to one checkpoint into a personal layout."
```

---

### Task 5: Rewind and fork service

**Files:**

- Create: `client/lib/services/chat/rewind/rewind_fork_service.dart`
- Test: `client/test/services/chat/rewind/rewind_fork_service_test.dart`

**Interfaces:**

- Consumes: `SeatRewindStore.restore` and `forkAt`
- Produces:

```dart
abstract interface class SeatProcess {
  bool get turnInFlight;
  bool get localRuntime;
  Future<void> stopAndWait();
  Future<void> relaunch();
}

abstract interface class ForkSessionCreator {
  Future<String> createPersonal({
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
    required String? nativeSessionId,
  });
  Future<void> deleteSession(String sessionId);
}

final class RewindForkService {
  Future<void> rewind({
    required SeatRewindStore store,
    required SeatProcess seat,
    required String commit,
  });

  Future<String> fork({
    required SeatRewindStore source,
    required String commit,
    required SeatRewindTarget destTarget,
    required String destGitDir,
    required String destWorkTree,
    required ForkSessionCreator sessions,
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
  });
}
```

`rewind` throws `StateError` when `turnInFlight` or `localRuntime` is false, or when a call is already running for this store. Otherwise `stopAndWait`, `restore`, `relaunch`. `restore` failure does not call `relaunch`. `relaunch` failure is rethrown after `restore` has succeeded.

`fork` does not call `stopAndWait`. It `createPersonal`, then `forkAt`. Any failure after `createPersonal` calls `deleteSession` and rethrows. Native session id passed to `createPersonal` comes from the checkpoint with that commit.

- [ ] **Step 1: Write the failing test**

Fake `SeatProcess` records `stopAndWait` and `relaunch`. Fake creator records `createPersonal` / `deleteSession`.

```dart
test('rewind stops, restores, then relaunches', () async { ... });
test('rewind refuses an in-flight turn', () async { ... });
test('restore failure does not relaunch', () async { ... });
test('fork does not stop the source and deletes the session on failure', () async { ... });
```

Make `forkAt` throw by pointing `destGitDir` at a file so Git init fails, and expect `deleteSession` with the created id.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/rewind_fork_service_test.dart`

Expected: FAIL, `RewindForkService` is not defined.

- [ ] **Step 3: Write minimal implementation**

Implement the two methods exactly as the interface states. Guard overlapping calls with a `Set<String>` keyed by `store.gitDir`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/rewind_fork_service_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/rewind_fork_service.dart \
  client/test/services/chat/rewind/rewind_fork_service_test.dart
git commit -m "Orchestrate rewind and fork around the seat snapshot store."
```

---

### Task 6: Take the checkpoint when a turn ends

**Files:**

- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` (`_endTurn`, around the `inTurn: false` emit)
- Modify: `client/lib/cubits/chat_cubit.dart` (`_onTurnEnded`)
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` (one new test)
- Test: `client/test/cubits/chat_cubit_turn_rewind_test.dart`

**Interfaces:**

- Consumes: `SeatRewindStore.commitTurn`
- Produces: optional callback on the ACP cubit:

```dart
Future<void> Function(String messageId)? onTurnCheckpoint;
```

Set from `AcpRuntimeAttach` only when the seat's runtime directory is on the local machine and `git` is on `PATH`. The callback builds `SeatRewindStore` with `gitDir = <sessionRuntimeDir>/../rewind/<seatKey>` — the rewind dir is `sessions/<id>/rewind/<seatKey>`, a sibling of `runtime/`, from `WorkspaceLayout`.

- [ ] **Step 1: Write the failing test**

ACP: extend the existing cubit test harness. After a prompt turn reaches idle, expect `onTurnCheckpoint` called once with `state.messages.last.id`. A turn that is still `inTurn` has not called it. The callback is invoked only after `saveMessages` resolves: use the existing `_DelayedReadFilesystem` pattern only if persist is observable; otherwise count callback order with a `Completer` completed inside a fake `AcpChatTranscriptWriter`.

PTY: `_onTurnEnded('s', 'm1')` on a local simple session calls a new `ChatCubit.onPtyTurnCheckpoint` with the seat. When `requiresPtyFallback` is false the existing attention clear still returns early; the checkpoint call stays behind that same guard so a non-fallback CLI is not snapshotted twice (ACP already snapshotted it).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name 'turn checkpoint'`

Expected: FAIL, `onTurnCheckpoint` is not a constructor parameter.

- [ ] **Step 3: Write minimal implementation**

In `_endTurn`, after `emit` sets `inTurn: false` and `_persist` has been awaited for this turn, call `onTurnCheckpoint?.call(state.messages.last.id)` when `state.messages` is not empty. Today `_persist` is fired with `unawaited` before `_endTurn`. Change the turn-completion sites that call both (`_endTurn` callers around lines 690–1051) so the completion path `await _persist()` and then `_endTurn()`. Do not checkpoint from `_endWith` or from history replay.

`_endTurn` itself awaits the callback. Failures are logged and do not change chat phase.

PTY: at the end of `_onTurnEnded`, after the existing attention clear, call `onPtyTurnCheckpoint` with `sessionId`, `memberId`, and the current native session id. No checkpoint when the runtime root is an SSH work plane (`RuntimeKind.ssh`) or the host is Android.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name 'turn checkpoint'`

Expected: PASS

Also run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_turn_rewind_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/lib/cubits/chat_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart \
  client/test/cubits/chat_cubit_turn_rewind_test.dart
git commit -m "Checkpoint a local seat when its turn ends."
```

---

### Task 7: Message actions and the later-checkpoint divider

**Files:**

- Modify: `client/packages/ai_message_ui/lib/src/message_action_bar.dart`
- Modify: `client/packages/ai_message_ui/lib/src/strings.dart` if the bar reads package strings; otherwise only app l10n and pass labels in
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` — `rewindSeatTo`, `forkSeatFrom`
- Test: `client/packages/ai_message_ui/test/message_action_bar_test.dart` (create if absent)
- Test: `client/test/pages/chat/session_history_rewind_divider_test.dart`

**Interfaces:**

- Consumes: `RewindForkService`, `SeatRewindStore.checkpoints`
- Produces: `AiMessageActionBar.onRewind` and `onFork`, each `VoidCallback?`. The history thread takes:

```dart
final Map<String, String> checkpointCommits; // messageId -> commit
final String? checkedOutCommit;
final List<AiMessage> laterMessages;
final void Function(String commit) onRewindTo;
final void Function(String commit) onForkFrom;
```

- [ ] **Step 1: Write the failing test**

Action bar: pump `AiMessageActionBar` with `onRewind` and `onFork`. Find tooltips `Rewind to here` and `Fork from here`. Tap each and expect one call. Omit `onRewind` and expect that tooltip absent while fork remains.

Divider: a thread with two live messages and one `laterMessages` entry shows the later message after a divider, and its rewind callback receives that message's commit.

l10n keys:

```json
"rewindToHere": "Rewind to here",
"@rewindToHere": {},
"forkFromHere": "Fork from here",
"@forkFromHere": {}
```

Chinese: `回溯到这里`, `从这里 fork`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/ai_message_ui && dart test test/message_action_bar_test.dart`

Expected: FAIL, `onRewind` is not a parameter.

- [ ] **Step 3: Write minimal implementation**

Add the two `_LiteIconAction`s next to copy. Icons: `Icons.history` and `Icons.call_split`. Labels come from new optional `rewindLabel` / `forkLabel` parameters so the package does not import app l10n. `session_history_thread.dart` passes `context.l10n.rewindToHere` and `forkFromHere`.

Hide rewind when `checkpointCommits[message.id] == checkedOutCommit`. Disable both while `turnInFlight` is true (new `bool turnInFlight` on the thread, forwarded as `onPressed: null`).

`laterMessages` render under the live list with `Opacity(opacity: 0.55)` and the same action bar. `ChatCubit.rewindSeatTo` / `forkSeatFrom` call `RewindForkService`. Fork display name is `'${source.display} fork'`. `createPersonal` uses `SessionDataStore.createSession` with empty `sessionTeamId`, the source CLI, and the source working directory. After create, `forkAt` into `sessions/<newId>/runtime`. Then open that session with the existing open-session path used by `duplicateSession`.

Ghost messages: for ACP, `git show <commit>:acp-transcript.jsonl` (personal name after fork mapping is not needed here; read the source seat's sidecar path) and `decodeAcpChatTranscript`. Keep messages whose ids are absent from the live transcript. For PTY, read the checkpoint file bytes through `SeatRewindStore.showFile` and pass them to the seat's existing `AiHistoryCapability` adapter.

- [ ] **Step 4: Run test to verify it passes**

Run the action-bar test and:

`cd client && dart run tool/run_tests.dart test/pages/chat/session_history_rewind_divider_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/message_action_bar.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/pages/chat/session_history_thread.dart \
  client/lib/cubits/chat_cubit.dart \
  client/lib/services/chat/rewind/seat_rewind_store.dart \
  client/test/pages/chat/session_history_rewind_divider_test.dart
git commit -m "Rewind or fork a seat from the turn that closed it."
```

---

### Task 8: Analyze and full test

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new issues.

- [ ] **Step 2: Full suite**

Run: `cd client && dart run tool/run_tests.dart`

Expected: PASS

- [ ] **Step 3: Commit** only if the analyze/test fixes changed files.

```bash
git add -u client
git commit -m "Fix rewind and fork analyze findings."
```

Skip the commit when the tree is clean.
