# User-Message Branches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user edit one of their own messages and resend it as a new version, keeping every version as a branch of the seat's private snapshot tree.

**Architecture:** Each completed turn already commits the seat's `runtime/` into a private Git repo. The commit graph becomes the branch tree: sibling commits are versions of the same user message. Switching a version restores the newest descendant of that commit and relaunches the seat; editing restores the parent commit and resends the text.

**Tech Stack:** Flutter (Dart 3), `flutter_bloc` cubits, Git via `Process.run`, `ai_message_ui` for the bar and bubble.

**Worktree:** `/home/hhoa/git/hhoa/teampilot/.worktrees/feat-session-rewind-fork`, branch `feat/session-rewind-fork`.

**Spec:** `docs/superpowers/specs/2026-11-04-user-message-branches-design.md`.

## Global Constraints

- Never run `flutter test` directly in `client/`. Use `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. Outer loop: the full suite once before claiming done.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb`, then `cd client && flutter gen-l10n`. Never hand-edit `app_localizations*.dart`.
- No `print`; diagnostics go through `AppLogger`.
- `services/chat/rewind/` owns Git and never parses a CLI transcript.
- Keep the state key names `rewindForkInProgress`, `rewindForkError`, `rewindHistoryGeneration`.
- Only personal sessions (`session.isSimple`) offer branches in this version.

---

## File Structure

| File | Responsibility |
|---|---|
| `client/lib/services/chat/rewind/seat_rewind_store.dart` | Git: turn metadata, root commit, sibling/tip queries, restore (including the empty root). |
| `client/lib/services/chat/rewind/seat_branches.dart` (new) | Read model: version index/count/commits per user message. |
| `client/lib/cubits/chat_cubit.dart` | `switchSeatVersion`, `editSeatTurn`, checkpoint call sites. |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | ACP checkpoint supplies the turn's user message id. |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | Forwards that id into `commitTurn`. |
| `client/packages/ai_message_ui/lib/src/message_action_bar.dart` | Edit action beside the version control. |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | Inline editor for a user bubble. |
| `client/lib/pages/chat/session_history_thread.dart` | Places the control and the edit affordance on user messages. |
| `client/lib/pages/chat/session_history_rewind_host.dart` | Loads `SeatBranches`, runs switch/edit/fork, owns busy + toasts. |
| `client/lib/services/chat/rewind/seat_rewind_history.dart` | **Delete** in Task 4, replaced by `seat_branches.dart`. |

---

### Task 1: Turn metadata, parent link, root commit, branch tip

**Files:**
- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**
- Produces:
  - `RewindCheckpoint({required String commit, required String parentCommit, required String messageId, required String userMessageId, required int turnAt, required String? nativeSessionId})`
  - `Future<RewindCheckpoint> commitTurn({required String messageId, String userMessageId = '', String? nativeSessionId, RewindWorkGate? gate})`
  - `Future<String> root()`
  - `Future<String> branchTip(String commit)`

- [ ] **Step 1: Write the failing tests**

Append to `client/test/services/chat/rewind/seat_rewind_store_test.dart`:

```dart
  test('a turn records its user message above the root commit', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );

    final first = await store.commitTurn(
      messageId: 'a1',
      userMessageId: 'u1',
      nativeSessionId: 's1',
    );
    final second = await store.commitTurn(
      messageId: 'a2',
      userMessageId: 'u2',
    );

    expect(first.userMessageId, 'u1');
    expect(first.messageId, 'a1');
    expect(first.nativeSessionId, 's1');
    expect(first.turnAt, greaterThan(0));
    expect(first.parentCommit, await store.root());
    expect(second.parentCommit, first.commit);
    expect(await store.branchTip(first.commit), second.commit);
    expect(await store.branchTip(second.commit), second.commit);
  });

  test('a second turn from the same parent is a sibling', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    final root = await store.root();
    final versionOne = await store.commitTurn(
      messageId: 'a1',
      userMessageId: 'u1',
    );
    await store.restore(root);
    final versionTwo = await store.commitTurn(
      messageId: 'b1',
      userMessageId: 'u2',
    );

    expect(versionOne.parentCommit, root);
    expect(versionTwo.parentCommit, root);
    expect(await store.branchTip(versionOne.commit), versionOne.commit);
    expect(await store.checkedOut(), versionTwo.commit);
  });
```

- [ ] **Step 2: Run them**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`
Expected: FAIL — no `userMessageId`, no `root`.

- [ ] **Step 3: Extend the checkpoint model**

Replace `RewindCheckpoint` in `seat_rewind_store.dart`:

```dart
/// One recorded turn in a seat's private rewind repository.
final class RewindCheckpoint {
  const RewindCheckpoint({
    required this.commit,
    required this.parentCommit,
    required this.messageId,
    required this.userMessageId,
    required this.turnAt,
    required this.nativeSessionId,
  });

  final String commit;

  /// Empty for a root commit.
  final String parentCommit;

  /// Last message of the turn.
  final String messageId;

  /// User message that opened the turn. Empty for commits written before
  /// user-message branches existed.
  final String userMessageId;

  /// Milliseconds since epoch; orders sibling turns.
  final int turnAt;

  final String? nativeSessionId;
}
```

- [ ] **Step 4: Write the metadata and the parent**

In `commitTurn`, replace the parent/message block and the return value:

```dart
  Future<RewindCheckpoint> commitTurn({
    required String messageId,
    String userMessageId = '',
    String? nativeSessionId,
    RewindWorkGate? gate,
  }) async {
    if (gate != null && gate.isInProgress(gitDir)) {
      AppLogger.instance.d(
        '[rewind] commitTurn skipped; rewind or fork in progress '
        'gitDir=$gitDir',
      );
      throw const RewindTurnSkipped();
    }
    await ensureRepo();
    await _dropStaleSeatIndexEntries();
    for (final relative in _includedRuntimeFiles()) {
      await _runGit([..._repoArgs, 'add', '--', relative]);
    }
    final tree = (await _runGit([..._repoArgs, 'write-tree'])).trim();
    final parent = await checkedOut() ?? await root();
    final turnAt = DateTime.now().millisecondsSinceEpoch;
    final message =
        'checkpoint\n'
        '\n'
        'Turn-Message: $messageId\n'
        'Turn-User: $userMessageId\n'
        'Turn-At: $turnAt\n'
        'Native-Session: ${nativeSessionId ?? ''}';
    final commit = (await _runGit([
      ..._repoArgs,
      'commit-tree',
      tree,
      '-p',
      parent,
      '-m',
      message,
    ], environment: _gitIdentity)).trim();
    await _runGit([
      ..._repoArgs,
      'update-ref',
      'refs/rewind/keep/$messageId',
      commit,
    ]);
    await _runGit([..._repoArgs, 'update-ref', 'refs/rewind/live', commit]);
    await _runGit([
      ..._repoArgs,
      'update-ref',
      'refs/rewind/checked-out',
      commit,
    ]);
    return RewindCheckpoint(
      commit: commit,
      parentCommit: parent,
      messageId: messageId,
      userMessageId: userMessageId,
      turnAt: turnAt,
      nativeSessionId: nativeSessionId,
    );
  }
```

- [ ] **Step 5: Add the root and the tip**

Insert after `checkedOut()`:

```dart
  /// Empty seat state, used as the parent of the first turn.
  ///
  /// Written once per seat. Restoring it clears the seat's included files so
  /// the next launch starts a fresh agent session.
  Future<String> root() async {
    if (!Directory(gitDir).existsSync()) await ensureRepo();
    final existing = (await _runGit([
      ..._repoArgs,
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/rewind/root',
    ], allowFailure: true)).trim();
    if (existing.isNotEmpty) return existing;
    final indexFile = p.join(gitDir, 'root-index');
    try {
      final tree = (await _runGit([
        ..._repoArgs,
        'write-tree',
      ], environment: {'GIT_INDEX_FILE': indexFile})).trim();
      final commit = (await _runGit([
        ..._repoArgs,
        'commit-tree',
        tree,
        '-m',
        'root',
      ], environment: _gitIdentity)).trim();
      await _runGit([..._repoArgs, 'update-ref', 'refs/rewind/root', commit]);
      return commit;
    } finally {
      final index = File(indexFile);
      if (index.existsSync()) index.deleteSync();
    }
  }

  /// Newest descendant of [commit], including [commit] itself.
  Future<String> branchTip(String commit) async {
    final turns = await checkpoints();
    final byCommit = {for (final turn in turns) turn.commit: turn};
    final start = byCommit[commit];
    if (start == null) return commit;
    final children = <String, List<RewindCheckpoint>>{};
    for (final turn in turns) {
      if (turn.parentCommit.isEmpty) continue;
      children.putIfAbsent(turn.parentCommit, () => []).add(turn);
    }
    var best = start;
    final stack = <String>[start.commit];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final child in children[current] ?? const <RewindCheckpoint>[]) {
        if (child.turnAt >= best.turnAt) best = child;
        stack.add(child.commit);
      }
    }
    return best.commit;
  }
```

- [ ] **Step 6: Parse parents and the new fields**

In `checkpoints()`, replace the body-reading block:

```dart
    final bodies = await _runGit([
      ..._repoArgs,
      'log',
      '--no-walk=unsorted',
      '--format=%H%x00%P%x00%B%x01',
      ...ordered,
    ], allowFailure: true);
    final records = <String, ({String parents, String body})>{};
    for (final record in bodies.split('\x01')) {
      final entry = record.trimLeft();
      final first = entry.indexOf('\x00');
      if (first <= 0) continue;
      final second = entry.indexOf('\x00', first + 1);
      if (second < 0) continue;
      records[entry.substring(0, first).trim()] = (
        parents: entry.substring(first + 1, second).trim(),
        body: entry.substring(second + 1),
      );
    }
    return [
      for (final commit in ordered)
        _parseCheckpoint(
          commit,
          records[commit]?.body ?? '',
          records[commit]?.parents ?? '',
        ),
    ];
```

Replace `_parseCheckpoint`:

```dart
  RewindCheckpoint _parseCheckpoint(
    String commit,
    String body,
    String parents,
  ) {
    String messageId = '';
    String userMessageId = '';
    var turnAt = 0;
    String? nativeSessionId;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('Turn-Message:')) {
        messageId = line.substring('Turn-Message:'.length).trim();
      } else if (line.startsWith('Turn-User:')) {
        userMessageId = line.substring('Turn-User:'.length).trim();
      } else if (line.startsWith('Turn-At:')) {
        turnAt = int.tryParse(line.substring('Turn-At:'.length).trim()) ?? 0;
      } else if (line.startsWith('Native-Session:')) {
        final value = line.substring('Native-Session:'.length).trim();
        nativeSessionId = value.isEmpty ? null : value;
      }
    }
    return RewindCheckpoint(
      commit: commit,
      parentCommit: parents.split(' ').first.trim(),
      messageId: messageId,
      userMessageId: userMessageId,
      turnAt: turnAt,
      nativeSessionId: nativeSessionId,
    );
  }
```

- [ ] **Step 7: Run the store tests**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`
Expected: PASS. Existing tests that construct `RewindCheckpoint` (the cubit tests) need only the constructor change; the analyzer will list them.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_store.dart client/test/services/chat/rewind/seat_rewind_store_test.dart
git commit -m "Record the turn's user message, parent, and time on every checkpoint."
```

---

### Task 2: Restoring the root empties the seat

**Files:**
- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart` (`_writeSeatFromCommit`)
- Test: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  test('restoring the root clears the seat but keeps excluded paths', () async {
    final tmp = tmpDir.path;
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
    );
    final root = await store.root();
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    expect(File('$tmp/work/acp-transcript.jsonl').existsSync(), isTrue);

    await store.restore(root);

    expect(File('$tmp/work/acp-transcript.jsonl').existsSync(), isFalse);
    expect(File('$tmp/work/acp-session.json').existsSync(), isFalse);
    expect(File('$tmp/work/claude/projects/a.jsonl').existsSync(), isFalse);
    expect(Directory('$tmp/work/claude/plugins').existsSync(), isTrue);
    expect(await store.checkedOut(), root);
  });
```

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`
Expected: FAIL — the transcript still exists.

- [ ] **Step 3: Empty the seat for an empty tree**

In `_writeSeatFromCommit`, after `final treePaths = await _treePaths(commit);`:

```dart
    if (treePaths.isEmpty && target.seatKey == 'personal') {
      // The root checkpoint: the seat had no files before its first turn.
      await _deleteIncludedFilesNotIn(const {});
      return;
    }
```

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/rewind/seat_rewind_store.dart client/test/services/chat/rewind/seat_rewind_store_test.dart
git commit -m "Clear the seat when the root checkpoint is restored."
```

---

### Task 3: Branch read model and the switch entry

**Files:**
- Create: `client/lib/services/chat/rewind/seat_branches.dart`
- Create: `client/test/services/chat/rewind/seat_branches_test.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (add `loadSeatBranches`, `switchSeatVersion`; keep `rewindSeatTo` for now)

**Interfaces:**
- Produces:
  - `SeatBranchVersion({required int index, required int count, required String commit, required List<String> siblings})` with `String? get previous` / `String? get next`
  - `SeatBranches({required Map<String, SeatBranchVersion> turns, required String? checkedOutCommit})`, `SeatBranches.empty()`, `SeatBranchVersion? turnOf(String userMessageId)`
  - `Future<SeatBranches> readSeatBranches({required SeatRewindStore store})`
  - `Future<SeatBranches> ChatCubit.loadSeatBranches({required AppSession session, required String memberId})`
  - `Future<void> ChatCubit.switchSeatVersion({required String sessionId, required String memberId, required String commit})`

- [ ] **Step 1: Write the failing test**

`client/test/services/chat/rewind/seat_branches_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/seat_branches.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('seat-branches-');
    await Directory('${tmpDir.path}/work/claude/projects').create(
      recursive: true,
    );
    await File('${tmpDir.path}/work/claude/projects/a.jsonl').writeAsString(
      'one',
    );
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('siblings of the same parent become versions ordered by turn', () async {
    final store = _store(tmpDir.path);
    final root = await store.root();
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.restore(root);
    await store.commitTurn(messageId: 'b1', userMessageId: 'u2');

    final branches = await readSeatBranches(store: store);

    expect(branches.turnOf('u1')!.count, 2);
    expect(branches.turnOf('u1')!.index, 1);
    expect(branches.turnOf('u2')!.index, 2);
    expect(branches.turnOf('u1')!.siblings, hasLength(2));
    expect(branches.turnOf('u1')!.next, branches.turnOf('u2')!.commit);
    expect(branches.turnOf('u2')!.previous, branches.turnOf('u1')!.commit);
  });

  test('a linear branch reports one version per turn', () async {
    final store = _store(tmpDir.path);
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.commitTurn(messageId: 'a2', userMessageId: 'u2');

    final branches = await readSeatBranches(store: store);

    expect(branches.turnOf('u1')!.count, 1);
    expect(branches.turnOf('u1')!.previous, isNull);
    expect(branches.turnOf('u2')!.count, 1);
    expect(branches.checkedOutCommit, branches.turnOf('u2')!.commit);
  });

  test('turns written before the anchor are ignored', () async {
    final store = _store(tmpDir.path);
    await store.commitTurn(messageId: 'a1');

    final branches = await readSeatBranches(store: store);

    expect(branches.turns, isEmpty);
  });
}

SeatRewindStore _store(String tmp) => SeatRewindStore(
  gitDir: '$tmp/repo.git',
  workTree: '$tmp/work',
  target: const SeatRewindTarget(
    kind: SeatRewindKind.personalAcp,
    tool: 'claude',
  ),
);
```

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_branches_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Write the read model**

`client/lib/services/chat/rewind/seat_branches.dart`:

```dart
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

/// One version of a user message: the turn it opened.
final class SeatBranchVersion {
  const SeatBranchVersion({
    required this.index,
    required this.count,
    required this.commit,
    required this.siblings,
  });

  /// 1-based position among the versions of this message.
  final int index;

  /// How many versions this message has.
  final int count;

  /// Commit of this version's turn.
  final String commit;

  /// Commits of every version, oldest first.
  final List<String> siblings;

  /// Commit one version older, or null at the oldest end.
  String? get previous => index > 1 ? siblings[index - 2] : null;

  /// Commit one version newer, or null at the newest end.
  String? get next => index < count ? siblings[index] : null;
}

/// Branch tree of one seat, keyed by the user message that opened a turn.
final class SeatBranches {
  const SeatBranches({required this.turns, required this.checkedOutCommit});

  const SeatBranches.empty() : turns = const {}, checkedOutCommit = null;

  final Map<String, SeatBranchVersion> turns;

  /// Commit currently written into the seat's runtime.
  final String? checkedOutCommit;

  SeatBranchVersion? turnOf(String userMessageId) => turns[userMessageId];
}

/// Groups [store]'s checkpoints by parent and indexes them per user message.
Future<SeatBranches> readSeatBranches({required SeatRewindStore store}) async {
  final checkpoints = await store.checkpoints();
  final checkedOut = await store.checkedOut();
  final groups = <String, List<RewindCheckpoint>>{};
  for (final checkpoint in checkpoints) {
    if (checkpoint.userMessageId.isEmpty) continue;
    groups.putIfAbsent(checkpoint.parentCommit, () => []).add(checkpoint);
  }
  final turns = <String, SeatBranchVersion>{};
  for (final group in groups.values) {
    group.sort((a, b) => a.turnAt.compareTo(b.turnAt));
    final siblings = [for (final turn in group) turn.commit];
    for (var index = 0; index < group.length; index++) {
      final checkpoint = group[index];
      turns[checkpoint.userMessageId] = SeatBranchVersion(
        index: index + 1,
        count: group.length,
        commit: checkpoint.commit,
        siblings: List.unmodifiable(siblings),
      );
    }
  }
  return SeatBranches(turns: turns, checkedOutCommit: checkedOut);
}
```

- [ ] **Step 4: Add the cubit entry points**

In `client/lib/cubits/chat_cubit.dart`, add the import
`'../services/chat/rewind/seat_branches.dart'` and next to `rewindSeatTo`:

```dart
  /// Versions of every user message on this seat.
  Future<SeatBranches> loadSeatBranches({
    required AppSession session,
    required String memberId,
  }) async {
    final store = _seatRewindStore(session, memberId);
    if (store == null) return const SeatBranches.empty();
    if (!Directory(store.gitDir).existsSync()) {
      return const SeatBranches.empty();
    }
    return readSeatBranches(store: store);
  }

  /// Restore the branch that [commit] belongs to, then relaunch the seat.
  Future<void> switchSeatVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    final session = _sessionForRewind(sessionId);
    if (session == null) return;
    final store = _seatRewindStore(session, memberId);
    if (store == null) return;
    emit(
      state.copyWith(rewindForkInProgress: true, clearRewindForkError: true),
    );
    try {
      final tip = await store.branchTip(commit);
      await _rewindFork.rewind(
        store: store,
        seat: _CubitSeatProcess(this, session, memberId),
        commit: tip,
      );
      onSessionHistoryStale?.call(sessionId);
      _publishRewindHistory();
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] switchSeatVersion failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(rewindForkError: 'branchSwitchFailed'));
      }
      rethrow;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(rewindForkInProgress: false));
      }
    }
  }
```

- [ ] **Step 5: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/rewind/seat_branches_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/chat/rewind/seat_branches.dart client/test/services/chat/rewind/seat_branches_test.dart client/lib/cubits/chat_cubit.dart
git commit -m "Read user-message versions from the checkpoint graph."
```

---

### Task 4: Move the version control onto user messages

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_history_rewind_host.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/pages/chat/session_chat_message_area.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Delete: `client/lib/services/chat/rewind/seat_rewind_history.dart`, `client/test/services/chat/rewind/seat_rewind_history_test.dart`
- Test: `client/test/pages/chat/session_history_rewind_actions_test.dart`, `client/test/cubits/chat_cubit_rewind_fork_fix_test.dart`

**Interfaces:**
- Consumes: `SeatBranches`, `switchSeatVersion`.
- Produces: `SessionHistoryRewindBinding({required SeatBranches branches, void Function(String commit)? onSwitchVersion, void Function(String commit)? onForkFrom, bool busy})`; `SessionHistoryThread({required SeatBranches branches, void Function(String commit)? onSwitchVersion, void Function(String commit)? onForkFrom, bool turnInFlight})`.

- [ ] **Step 1: Write the failing widget test**

Replace `client/test/pages/chat/session_history_rewind_actions_test.dart` with a
user-message test:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/chat/session_history_rewind_host.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';
import 'package:teampilot/services/chat/rewind/seat_branches.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('a user message offers versions and a switch', (tester) async {
    final cubit = _BranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byTooltip('Fork from here'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    expect(cubit.switchedTo, ['c-first']);
  });
}

/// Pumps the history host around a personal session with one user message and
/// one reply. Task 8 adds `onEditUserMessage` to the thread here.
Future<void> _pumpThread(WidgetTester tester, ChatCubit cubit) async {
  final runtime = ExternalStoreAiThreadRuntime()
    ..setMessages(const [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'first version')],
      ),
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'answer')],
      ),
    ]);
  final session = AppSession(sessionId: 's1', workspaceId: 'w1', createdAt: 1);
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  await tester.pumpWidget(
    BlocProvider<ChatCubit>.value(
      value: cubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: SessionHistoryRewindHost(
              session: session,
              workspace: workspace,
              memberId: session.sessionId,
              builder: (context, binding) {
                return SessionHistoryThread(
                  runtime: runtime,
                  hasOlder: false,
                  isLoadingOlder: false,
                  branches: binding.branches,
                  onSwitchVersion: binding.onSwitchVersion,
                  onForkFrom: binding.onForkFrom,
                  turnInFlight: binding.busy,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await pumpUntilSettled(tester);
}

final class _BranchCubit extends ChatCubit {
  _BranchCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  final switchedTo = <String>[];

  @override
  bool rewindActionsAllowed(AppSession session, String memberId) => true;

  @override
  Future<SeatBranches> loadSeatBranches({
    required AppSession session,
    required String memberId,
  }) async {
    return const SeatBranches(
      turns: {
        'u1': SeatBranchVersion(
          index: 2,
          count: 2,
          commit: 'c-second',
          siblings: ['c-first', 'c-second'],
        ),
      },
      checkedOutCommit: 'c-second',
    );
  }

  @override
  Future<void> switchSeatVersion({
    required String sessionId,
    required String memberId,
    required String commit,
  }) async {
    switchedTo.add(commit);
  }
}
```

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_history_rewind_actions_test.dart`
Expected: FAIL — `branches` is not a parameter of `SessionHistoryThread`.

- [ ] **Step 3: Thread takes branches**

In `session_history_thread.dart`, replace the three checkpoint props with:

```dart
    this.branches = const SeatBranches.empty(),
    this.onSwitchVersion,
    this.onForkFrom,
    this.turnInFlight = false,
```

```dart
  /// Versions of each user message on this seat.
  final SeatBranches branches;

  /// Restores the branch that the commit belongs to.
  final void Function(String commit)? onSwitchVersion;

  /// Copies the branch through the commit into a new session.
  final void Function(String commit)? onForkFrom;

  /// When true, the controls stay visible but disabled.
  final bool turnInFlight;
```

In `build`, compute the labels once:

```dart
    final forkLabel = context.l10n.forkFromHere;
    final previousVersionLabel = context.l10n.branchPrevious;
    final nextVersionLabel = context.l10n.branchNext;
```

In `messageBuilder`:

```dart
                          final version = ai.role == AiRole.user
                              ? widget.branches.turnOf(ai.id)
                              : null;
                          final showsVersion =
                              version != null && version.count > 1;
                          final previous = version?.previous;
                          final next = version?.next;
```

and replace the action props:

```dart
                            onFork: version == null || widget.onForkFrom == null
                                ? null
                                : () => widget.onForkFrom!(version.commit),
                            forkLabel: forkLabel,
                            versionIndex: showsVersion ? version!.index : null,
                            versionCount: showsVersion ? version!.count : null,
                            onPreviousVersion:
                                showsVersion &&
                                    previous != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(previous)
                                : null,
                            onNextVersion:
                                showsVersion &&
                                    next != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(next)
                                : null,
                            previousVersionLabel: previousVersionLabel,
                            nextVersionLabel: nextVersionLabel,
                            rewindForkEnabled: !widget.turnInFlight,
```

Remove the old `laterIds` / divider code if any remains, and set:

```dart
                        bodyCacheKey: (
                          widget.turnInFlight,
                          widget.branches,
                          widget.onSwitchVersion != null,
                          widget.onForkFrom != null,
                        ),
```

Add the import `package:teampilot/services/chat/rewind/seat_branches.dart`.

- [ ] **Step 4: Host loads branches**

In `session_history_rewind_host.dart`, replace `SeatRewindHistory` with
`SeatBranches`:

```dart
final class SessionHistoryRewindBinding {
  const SessionHistoryRewindBinding({
    required this.branches,
    this.onSwitchVersion,
    this.onForkFrom,
    this.busy = false,
  });

  final SeatBranches branches;
  final void Function(String commit)? onSwitchVersion;
  final void Function(String commit)? onForkFrom;
  final bool busy;
}
```

```dart
  SeatBranches _branches = const SeatBranches.empty();
  ...
        _branches = await cubit.loadSeatBranches(
          session: widget.session,
          memberId: widget.memberId,
        );
```

Rename `_onRewindTo` to `_onSwitchVersion` and call `switchSeatVersion`; keep the
single-flight guard and the toast, using `context.l10n.branchSwitchFailed`.

In `build`:

```dart
    return widget.builder(
      context,
      SessionHistoryRewindBinding(
        branches: _branches,
        onSwitchVersion: _allowed ? _onSwitchVersion : null,
        onForkFrom: _allowed ? _onForkFrom : null,
        busy: _busy,
      ),
    );
```

- [ ] **Step 5: Message area and review wrapper**

`session_chat_message_area.dart`:

```dart
                                              branches: rewind.branches,
                                              onSwitchVersion:
                                                  rewind.onSwitchVersion,
                                              onForkFrom: rewind.onForkFrom,
                                              turnInFlight:
                                                  turnInFlight || rewind.busy,
```

`session_history_review_messages.dart` forwards `branches`, `onSwitchVersion`,
`onForkFrom`, `turnInFlight` the same way.

- [ ] **Step 6: Delete the old model and rename the labels**

Delete `client/lib/services/chat/rewind/seat_rewind_history.dart` and its test.
Remove `loadSeatRewindHistory` and `rewindSeatTo` from `ChatCubit`; update every
remaining caller (tests included) to `loadSeatBranches` / `switchSeatVersion`.

In `app_en.arb` replace:

```json
  "rewindPreviousVersion": "Previous version",
  "rewindNextVersion": "Next version",
  "sessionRewindFailed": "Failed to rewind conversation",
```

with:

```json
  "branchPrevious": "Previous version",
  "@branchPrevious": {},
  "branchNext": "Next version",
  "@branchNext": {},
  "branchSwitchFailed": "Failed to switch version",
  "@branchSwitchFailed": {},
```

In `app_zh.arb` replace the two version strings with:

```json
  "branchPrevious": "上一版本",
  "branchNext": "下一版本",
  "branchSwitchFailed": "切换版本失败",
```

Remove `rewindToHere` and `sessionRewindFailed` from both files if nothing
references them. Run `cd client && flutter gen-l10n`.

- [ ] **Step 7: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/ test/cubits/chat_cubit_rewind_fork_fix_test.dart`
Expected: PASS after the mechanical renames.

- [ ] **Step 8: Commit**

```bash
git add -A client/lib client/test
git commit -m "Move the version control onto user messages."
```

---

### Task 5: Checkpoints carry the user message id

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` (`_endTurn`, `onTurnCheckpoint`)
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` (`_turnCheckpointCallback`)
- Modify: `client/lib/cubits/chat_cubit.dart` (`_checkpointPtyTurn`, `_commitPtyTurnOnce`, `debugCommitPtyTurn`, new helpers)
- Test: `client/test/cubits/chat_cubit_turn_rewind_test.dart`, `client/test/cubits/session/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Produces:
  - `AcpChatRuntimeCubit.onTurnCheckpoint` is `Future<void> Function(String messageId, String userMessageId)?`
  - `ChatCubit.debugCommitPtyTurn` requires `String userMessageId`

- [ ] **Step 1: Write the failing ACP test**

Add to `client/test/cubits/session/acp/acp_chat_runtime_cubit_test.dart`:

```dart
    test('the turn checkpoint carries the user message that opened it', () async {
      final cubit = _checkpointCubit();
      String? seenLast;
      String? seenUser;
      cubit.onTurnCheckpoint = (messageId, userMessageId) async {
        seenLast = messageId;
        seenUser = userMessageId;
      };
      cubit.debugSetMessagesForTest(const [
        AiMessage(id: 'u1', role: AiRole.user, parts: [AiTextPart(text: 'hi')]),
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'yo')],
        ),
      ]);
      await cubit.debugEndTurnForTest();

      expect(seenLast, 'a1');
      expect(seenUser, 'u1');
    });
```

Construct the cubit exactly as the neighbouring checkpoint test in the same file
does (same fake runtime, same `start()` call); the assertions are the new part.

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_chat_runtime_cubit_test.dart`
Expected: FAIL — the callback takes one argument.

- [ ] **Step 3: Send it from ACP**

In `acp_chat_runtime_cubit.dart`, change the field:

```dart
  /// Runs when a turn ends, before the runtime publishes idle.
  Future<void> Function(String messageId, String userMessageId)?
  onTurnCheckpoint;
```

and in `_endTurn`:

```dart
    final callback = onTurnCheckpoint;
    final messageId = state.messages.isEmpty ? '' : state.messages.last.id;
    String userMessageId = '';
    for (final message in state.messages.reversed) {
      if (message.role != AiRole.user) continue;
      userMessageId = message.id;
      break;
    }
    if (wasInTurn && callback != null && messageId.isNotEmpty) {
      try {
        await callback(messageId, userMessageId);
      } on Object catch (error, stackTrace) {
```

Add the test hooks if they do not exist:

```dart
  @visibleForTesting
  void debugSetMessagesForTest(List<AiMessage> messages) {
    emit(state.copyWith(messages: messages, inTurn: true));
  }

  @visibleForTesting
  Future<void> debugEndTurnForTest() => _endTurn();
```

- [ ] **Step 4: Forward it into the store**

In `acp_runtime_attach.dart`:

```dart
    return (messageId, userMessageId) async {
```

and:

```dart
          await store.commitTurn(
            messageId: messageId,
            userMessageId: userMessageId,
            gate: gate,
          );
```

- [ ] **Step 5: Send it from the PTY path**

In `chat_cubit.dart`, add beside `_observedPtyMessageId`:

```dart
  /// User message that opened the turn: the last user-role message in the
  /// seat's loaded history, else in the loader cache.
  String? _observedPtyUserMessageId({
    required String sessionId,
    required String historyMemberId,
  }) {
    final seat = podRuntime(sessionId)?.history?.seatOf(
      sessionId: sessionId,
      memberId: historyMemberId,
    );
    final fromSeat = _lastUserMessageId(seat?.loadedMessages);
    if (fromSeat != null) return fromSeat;
    return _lastUserMessageId(_loaderVisible(sessionId, historyMemberId));
  }

  String? _lastUserMessageId(List<AiMessage>? messages) {
    if (messages == null) return null;
    for (final message in messages.reversed) {
      if (message.role != AiRole.user) continue;
      final id = message.id.trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }
```

In `_checkpointPtyTurn`, inside `runSnapshot`, after `messageId` resolves:

```dart
        final userMessageId = _observedPtyUserMessageId(
          sessionId: sessionId,
          historyMemberId: historyMemberId,
        );
        if (userMessageId == null) return;
        await _commitPtyTurnOnce(
          gitDir: gitDir,
          workTree: workTree,
          target: target,
          messageId: messageId,
          userMessageId: userMessageId,
          nativeSessionId: nativeSessionId,
          seatKey: seatKey,
          sessionId: sessionId,
          memberId: memberId,
        );
```

`_commitPtyTurnOnce` gains `required String userMessageId`, forwards it to
`debugCommitPtyTurn` and `store.commitTurn`. The hook field becomes:

```dart
  @visibleForTesting
  Future<RewindCheckpoint> Function({
    required String gitDir,
    required String workTree,
    required SeatRewindTarget target,
    required String messageId,
    required String userMessageId,
    required String? nativeSessionId,
  })?
  debugCommitPtyTurn;
```

- [ ] **Step 6: Update the cubit tests' hooks**

Every `debugCommitPtyTurn` closure in
`client/test/cubits/chat_cubit_turn_rewind_test.dart` and
`client/test/cubits/chat_cubit_rewind_fork_fix_test.dart` gains
`required String userMessageId`. In the first test seed a user message before
the turn:

```dart
      loader.debugSetCachedMessages(
        sessionId: session.sessionId,
        memberId: '',
        messages: const [
          AiMessage(
            id: 'msg-user',
            role: AiRole.user,
            parts: [AiTextPart(text: 'go')],
          ),
          AiMessage(
            id: 'msg-last',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'done')],
          ),
        ],
        cli: CliTool.claude,
      );
```

and record the ids:

```dart
      final userIds = <String>[];
      cubit.debugCommitPtyTurn =
          ({
            required gitDir,
            required workTree,
            required target,
            required messageId,
            required userMessageId,
            nativeSessionId,
          }) async {
            storeArgs.add((gitDir: gitDir, workTree: workTree, target: target));
            userIds.add(userMessageId);
            final checkpoint = RewindCheckpoint(
              commit: 'c1',
              parentCommit: 'root',
              messageId: messageId,
              userMessageId: userMessageId,
              turnAt: 1,
              nativeSessionId: nativeSessionId,
            );
            commits.add(checkpoint);
            return checkpoint;
          };
```

Assert `expect(userIds, ['msg-user']);` at the end of that test.

- [ ] **Step 7: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_turn_rewind_test.dart test/cubits/chat_cubit_rewind_fork_fix_test.dart test/cubits/session/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add client/lib client/test
git commit -m "Anchor every checkpoint to the user message that opened the turn."
```

---

### Task 6: Edit a user message

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat_cubit_branch_edit_test.dart` (new)

**Interfaces:**
- Consumes: `SeatRewindStore.checkpoints()`, `RewindForkService.rewind`, `submitSessionOperatorMessage`.
- Produces: `Future<void> ChatCubit.editSeatTurn({required String sessionId, required String memberId, required String userMessageId, required String text})` and `@visibleForTesting debugDeliverEditedMessage`.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/chat_cubit_branch_edit_test.dart`. Reuse the harness
shape from `chat_cubit_rewind_fork_fix_test.dart` (`_openPersonal`, `_Env`,
`_HarnessCubit`), then:

```dart
void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('editing restores the parent and sends the new text', () async {
    final env = await _openPersonal();
    final store = env.store;
    final first = await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    await store.commitTurn(messageId: 'a2', userMessageId: 'u2');
    final sent = <String>[];
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async {
          sent.add(message);
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        };

    await env.cubit.editSeatTurn(
      sessionId: env.session.sessionId,
      memberId: env.session.sessionId,
      userMessageId: 'u2',
      text: 'edited text',
    );

    expect(sent, ['edited text']);
    final turns = await store.checkpoints();
    expect(turns.where((t) => t.userMessageId == 'u2'), hasLength(2));
    expect(
      turns.where((t) => t.userMessageId == 'u2').map((t) => t.parentCommit),
      everyElement(first.commit),
    );
  });

  test('a failed send puts the previous branch back', () async {
    final env = await _openPersonal();
    final store = env.store;
    await store.commitTurn(messageId: 'a1', userMessageId: 'u1');
    final second = await store.commitTurn(messageId: 'a2', userMessageId: 'u2');
    env.cubit.debugDeliverEditedMessage =
        ({required sessionId, required memberId, required message}) async =>
            const HistoryContinueSubmitResult.failed();

    await expectLater(
      env.cubit.editSeatTurn(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        userMessageId: 'u2',
        text: 'edited text',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await store.checkedOut(), second.commit);
    expect(env.cubit.state.rewindForkError, 'branchEditFailed');
    expect(env.cubit.state.rewindForkInProgress, isFalse);
  });
}
```

The harness must expose `store` (build the same `SeatRewindStore` the cubit
uses) and a real `rewindFork` that can stop/relaunch the fake seat; copy that
wiring from `chat_cubit_rewind_fork_fix_test.dart`.

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_branch_edit_test.dart`
Expected: FAIL — `editSeatTurn` is undefined.

- [ ] **Step 3: Implement the edit**

Add the test hook field beside `debugCommitPtyTurn`:

```dart
  @visibleForTesting
  Future<HistoryContinueSubmitResult> Function({
    required String sessionId,
    required String memberId,
    required String message,
  })?
  debugDeliverEditedMessage;
```

Add the method:

```dart
  /// Restore the turn before [userMessageId] and resend [text].
  ///
  /// The new turn checkpoints as a sibling of the edited one, so the previous
  /// version stays on the other branch.
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
  }) async {
    final session = _sessionForRewind(sessionId);
    if (session == null) return;
    final store = _seatRewindStore(session, memberId);
    if (store == null) return;
    RewindCheckpoint? target;
    for (final turn in await store.checkpoints()) {
      if (turn.userMessageId == userMessageId) {
        target = turn;
        break;
      }
    }
    if (target == null) {
      throw StateError('No checkpoint for the edited user message');
    }
    final before = await store.checkedOut();
    emit(
      state.copyWith(rewindForkInProgress: true, clearRewindForkError: true),
    );
    try {
      await _rewindFork.rewind(
        store: store,
        seat: _CubitSeatProcess(this, session, memberId),
        commit: target.parentCommit.isEmpty
            ? await store.root()
            : target.parentCommit,
      );
      final deliver =
          debugDeliverEditedMessage ?? _deliverEditedMessage;
      final result = await deliver(
        sessionId: sessionId,
        memberId: memberId,
        message: text,
      );
      if (!result.ok) {
        throw StateError('The edited message was not delivered');
      }
      onSessionHistoryStale?.call(sessionId);
      _publishRewindHistory();
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] editSeatTurn failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (before != null) {
        try {
          await _rewindFork.rewind(
            store: store,
            seat: _CubitSeatProcess(this, session, memberId),
            commit: before,
          );
        } on Object catch (rollbackError, rollbackStack) {
          appLogger.e(
            '[rewind] edit rollback failed session=$sessionId: '
            '$rollbackError',
            error: rollbackError,
            stackTrace: rollbackStack,
          );
        }
      }
      if (!isClosed) {
        emit(state.copyWith(rewindForkError: 'branchEditFailed'));
      }
      rethrow;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(rewindForkInProgress: false));
      }
    }
  }

  Future<HistoryContinueSubmitResult> _deliverEditedMessage({
    required String sessionId,
    required String memberId,
    required String message,
  }) => submitSessionOperatorMessage(
    sessionId: sessionId,
    memberId: memberId,
    message: message,
  );
```

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_branch_edit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_branch_edit_test.dart
git commit -m "Edit a user message by restoring its parent and resending."
```

---

### Task 7: Edit action and inline editor in `ai_message_ui`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/message_action_bar.dart`
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart`
- Test: `client/packages/ai_message_ui/test/message_action_bar_test.dart`, `client/packages/ai_message_ui/test/user_message_edit_test.dart` (new)

**Interfaces:**
- Produces:
  - `AiMessageActionBar({VoidCallback? onEdit, String editLabel = 'Edit message', ...})`
  - `AiMessageView({VoidCallback? onEdit, String editLabel, bool editing = false, ValueChanged<String>? onSubmitEdit, VoidCallback? onCancelEdit, String editSendLabel = 'Send', String editCancelLabel = 'Cancel', ...})`

- [ ] **Step 1: Write the failing tests**

`client/packages/ai_message_ui/test/user_message_edit_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editing replaces the user bubble and sends trimmed text', (
    tester,
  ) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: Scaffold(
          body: AiMessageView(
            message: const AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: 'original')],
            ),
            editing: true,
            onSubmitEdit: (text) => sent = text,
            onCancelEdit: () {},
          ),
        ),
      ),
    );

    expect(find.text('original'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  changed  ');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sent, 'changed');
  });

  testWidgets('the bar offers edit on a user message', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: const AiMessage(
              id: 'u1',
              role: AiRole.user,
              parts: [AiTextPart(text: 'hi')],
            ),
            reveal: AiActionBarReveal.always,
            onEdit: () => edits++,
            editLabel: 'Edit message',
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit message'));
    expect(edits, 1);
  });
}
```

- [ ] **Step 2: Run them**

Run: `cd client/packages/ai_message_ui && flutter test test/user_message_edit_test.dart`
Expected: FAIL — `editing` / `onEdit` undefined.

- [ ] **Step 3: Add the bar action**

In `message_action_bar.dart`:

```dart
    this.onEdit,
    this.editLabel = 'Edit message',
```

```dart
  /// When set, shows an edit action (user messages only).
  final VoidCallback? onEdit;

  /// Tooltip / semantics for edit. Package stays free of app l10n.
  final String editLabel;
```

In `_mountActions`, add `widget.onEdit != null` to the condition, and in the
row before the fork icon:

```dart
        if (widget.onEdit != null)
          Tooltip(
            message: widget.editLabel,
            child: _LiteIconAction(
              label: widget.editLabel,
              icon: Icons.edit_outlined,
              color: color,
              onPressed: widget.rewindForkEnabled ? widget.onEdit : null,
            ),
          ),
```

- [ ] **Step 4: Add the inline editor**

Add the props to `AiMessageView`, `_UserBubble`, `_AssistantBlock`, and
`_HoverScopedActionBar` (only `_UserBubble` renders it):

```dart
    this.onEdit,
    this.editLabel = 'Edit message',
    this.editing = false,
    this.onSubmitEdit,
    this.onCancelEdit,
    this.editSendLabel = 'Send',
    this.editCancelLabel = 'Cancel',
```

At the top of `_UserBubble.build`:

```dart
    if (editing) {
      return _UserMessageEditor(
        scheme: scheme,
        theme: aiTheme,
        initialText: plainTextForCopy(message),
        sendLabel: editSendLabel,
        cancelLabel: editCancelLabel,
        onSubmit: (text) => onSubmitEdit?.call(text),
        onCancel: onCancelEdit,
      );
    }
```

Append at the end of the file:

```dart
class _SendEditIntent extends Intent {
  const _SendEditIntent();
}

class _CancelEditIntent extends Intent {
  const _CancelEditIntent();
}

/// In-place editor for a user message. Enter sends, Shift+Enter is a newline.
class _UserMessageEditor extends StatefulWidget {
  const _UserMessageEditor({
    required this.scheme,
    required this.theme,
    required this.initialText,
    required this.sendLabel,
    required this.cancelLabel,
    required this.onSubmit,
    required this.onCancel,
  });

  final ColorScheme scheme;
  final AiMessageTheme theme;
  final String initialText;
  final String sendLabel;
  final String cancelLabel;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onCancel;

  @override
  State<_UserMessageEditor> createState() => _UserMessageEditorState();
}

class _UserMessageEditorState extends State<_UserMessageEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  var _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focus = FocusNode()..requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final text = _controller.text.trim();
    if (text.isEmpty || text == widget.initialText.trim()) {
      widget.onCancel?.call();
      return;
    }
    _submitted = true;
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.theme.userBubbleMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _SendEditIntent(),
                SingleActivator(LogicalKeyboardKey.escape): _CancelEditIntent(),
              },
              child: Actions(
                actions: {
                  _SendEditIntent: CallbackAction<_SendEditIntent>(
                    onInvoke: (_) {
                      _submit();
                      return null;
                    },
                  ),
                  _CancelEditIntent: CallbackAction<_CancelEditIntent>(
                    onInvoke: (_) {
                      widget.onCancel?.call();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: widget.theme.resolveUserBubble(widget.scheme),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        widget.theme.userBubbleRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: Text(widget.cancelLabel),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.sendLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

`plainTextForCopy` is already imported by `message_action_bar.dart`; import the
same package here. Add `package:flutter/services.dart` for `LogicalKeyboardKey`.

- [ ] **Step 5: Run the package suite**

Run: `cd client/packages/ai_message_ui && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/packages/ai_message_ui
git commit -m "Add an edit action and an inline editor for user messages."
```

---

### Task 8: Wire edit into the history thread

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_history_rewind_host.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/pages/chat/session_chat_message_area.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Test: `client/test/pages/chat/session_history_rewind_actions_test.dart`

**Interfaces:**
- Consumes: `editSeatTurn`, the package props from Task 7.
- Produces: `SessionHistoryRewindBinding.onEditUserMessage`, `SessionHistoryThread.onEditUserMessage`.

- [ ] **Step 1: Extend the widget test**

In `session_history_rewind_actions_test.dart`, add:

```dart
  testWidgets('editing a user message sends the new text', (tester) async {
    final cubit = _BranchCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);
    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(cubit.edits, [('u1', 'edited')]);
  });
```

Add `final edits = <(String, String)>[];` and an `editSeatTurn` override to
`_BranchCubit`:

```dart
  @override
  Future<void> editSeatTurn({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((userMessageId, text));
  }
```

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_history_rewind_actions_test.dart`
Expected: FAIL — no edit action.

- [ ] **Step 3: Thread props and editing state**

Add to `SessionHistoryThread`:

```dart
    this.onEditUserMessage,
```

```dart
  /// Called with the user message id and the edited text.
  final void Function(String messageId, String text)? onEditUserMessage;
```

Add state to `_SessionHistoryThreadState`:

```dart
  String? _editingMessageId;
```

In `messageBuilder`, for user messages:

```dart
                          final editing =
                              ai.role == AiRole.user &&
                              _editingMessageId == ai.id;
```

and pass:

```dart
                            editing: editing,
                            onEdit:
                                version == null || widget.onEditUserMessage == null
                                ? null
                                : () => setState(() => _editingMessageId = ai.id),
                            editLabel: editLabel,
                            onSubmitEdit: (text) {
                              setState(() => _editingMessageId = null);
                              widget.onEditUserMessage?.call(ai.id, text);
                            },
                            onCancelEdit: () =>
                                setState(() => _editingMessageId = null),
                            editSendLabel: editSendLabel,
                            editCancelLabel: editCancelLabel,
```

with the labels read in `build`:

```dart
    final editLabel = context.l10n.editUserMessage;
    final editSendLabel = context.l10n.editSend;
    final editCancelLabel = context.l10n.editCancel;
```

Add `_editingMessageId` to `bodyCacheKey`.

In `client/test/pages/chat/session_history_rewind_actions_test.dart`, add
`onEditUserMessage: binding.onEditUserMessage` to the `SessionHistoryThread`
inside `_pumpThread`.

- [ ] **Step 4: Host wiring**

```dart
    this.onEditUserMessage,
```

```dart
  final void Function(String messageId, String text)? onEditUserMessage;
```

```dart
  Future<void> _onEditUserMessage(String messageId, String text) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cubit!.editSeatTurn(
        sessionId: widget.session.sessionId,
        memberId: widget.memberId,
        userMessageId: messageId,
        text: text,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[rewind] editSeatTurn failed session=${widget.session.sessionId}: '
        '$error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.branchEditFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

Binding:

```dart
        onEditUserMessage: _allowed ? _onEditUserMessage : null,
```

- [ ] **Step 5: l10n**

Add to `app_en.arb`:

```json
  "editUserMessage": "Edit message",
  "@editUserMessage": {},
  "editSend": "Send",
  "@editSend": {},
  "editCancel": "Cancel",
  "@editCancel": {},
  "branchEditFailed": "Failed to send the edited message",
  "@branchEditFailed": {},
```

Add to `app_zh.arb`:

```json
  "editUserMessage": "编辑消息",
  "editSend": "发送",
  "editCancel": "取消",
  "branchEditFailed": "改后的消息发送失败",
```

Run `cd client && flutter gen-l10n`.

- [ ] **Step 6: Restrict to personal sessions**

In `ChatCubit.rewindActionsAllowed`, add at the top:

```dart
    if (!session.isSimple) return false;
```

Add to `client/test/pages/chat/session_history_rewind_actions_test.dart`:

```dart
  testWidgets('a team session offers no branch controls', (tester) async {
    final cubit = _TeamCubit();
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await _pumpThread(tester, cubit);

    expect(find.byTooltip('Edit message'), findsNothing);
    expect(find.byTooltip('Fork from here'), findsNothing);
  });
```

with `_TeamCubit.rewindActionsAllowed` returning `false`.

- [ ] **Step 7: Run the page tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A client/lib client/test
git commit -m "Edit a user message from its action bar."
```

---

### Task 9: Analyze and full suite

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: exit 0; no new issues beyond the pre-existing 37 infos/warnings.

- [ ] **Step 2: Full suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS.

- [ ] **Step 3: Manual check**

Run `cd client && flutter run -d linux --no-pub`. Send two turns, edit the first
user message, confirm `2 / 2` appears on that message, the new answer replaces
the old one, and `1 / 2` restores the first answer and its follow-up turns.

- [ ] **Step 4: Fix and commit what the checks surface**

```bash
git add -A client
git commit -m "Fix user-message branch analyze and test findings."
```

Skip when the tree is clean.

---

## Notes for the implementer

- `SeatRewindStore` owns every Git call; the cubit never shells out.
- Do not parse a CLI transcript for branch data.
- Old checkpoints (no `Turn-User`) must simply not appear in `SeatBranches`.
- Fork copies commits, so a forked session keeps its versions.
- A user message with no `SeatBranchVersion` renders neither the control nor
  the edit action; that covers assistant messages and pre-anchor commits.
