# Duplicate Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Duplicate conversation" for Simple-mode sessions: copy launch config plus the CLI-side conversation history so the fork resumes the copied transcript in its own isolated runtime dir.

**Architecture:** Zero-mutation fork — verbatim `runtime/{tool}/` tree copy + seeding the new session's `nativeSessionIds`. claude/flashskyai (`clientPinned`) learn "persisted id wins, taskId probe falls back" so resume/history resolve against the copied transcript without renames. Repository does the fork under lock; ChatCubit guards liveness; sidebar tile hosts the menu item.

**Tech Stack:** Flutter / flutter_bloc, existing `Filesystem` abstraction (`copyTree`, `removeRecursive`), `pinned_transcript_probe`, `TpActionMenu*` primitives, arb l10n.

**Spec:** `docs/superpowers/specs/2026-08-26-duplicate-session-design.md`

## Global Constraints

- Verify with: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` then `cd client && dart run tool/run_tests.dart`.
- l10n edits go ONLY in `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- Diagnostics via `appLogger`; never `print`. User-facing errors via l10n strings.
- No `if (cli == …)` special-cases outside `services/cli/` capabilities.
- Tests construct repos/services directly (`SessionRepository(rootDir: tmp.path)`, `SessionLifecycleService(appDataBasePath: tmp.path)`); widget tests use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `client/test/support/post_frame_test_harness.dart`.
- Scope: Simple sessions only; source must not be running; team/mixed stays untouched this iteration.

---

### Task 1: Claude clientPinned capability honors persisted native ids

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/history/ai_history_capability.dart` (`detectNativeId`, lines 61-73)
- Modify: `client/lib/services/cli/claude/capabilities/history/ai_transcript.dart` (`locateClaudeTranscript`, lines 12-55)
- Test: `client/test/services/cli/claude/claude_persisted_native_id_test.dart` (new)

**Interfaces:**
- Consumes: `probePinnedTranscript` / `pinnedTranscriptExists` from `../../../registry/capabilities/resume/pinned_transcript_probe.dart`; `ResumeContext.persistedNativeId`; `SessionHistoryContext.persistedNativeId`.
- Produces: `ClaudeAiHistoryCapability.detectNativeId` returns the persisted id first when its transcript exists, else taskId probe result; `locateClaudeTranscript` probes the persisted id first. Task 3/4 rely on this semantics; Task 4 seeds `'claude': <sourceSessionId>`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/claude/claude_persisted_native_id_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late String toolRoot;
  const capability = ClaudeAiHistoryCapability();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('claude_persisted_id_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    toolRoot = fs.pathContext.join(tmp.path, 'claude-config');
  });

  Future<void> writeTranscript(String id, {String bucket = 'b1'}) async {
    final dir = fs.pathContext.join(toolRoot, 'projects', bucket);
    await fs.ensureDir(dir);
    await fs.writeString(
      fs.pathContext.join(dir, '$id.jsonl'),
      '{"type":"user","message":{"content":"hi"}}\n',
    );
  }

  ResumeContext resumeCtx({String? persisted}) => ResumeContext(
        fs: fs,
        toolValue: 'claude',
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  SessionHistoryContext historyCtx({String? persisted}) =>
      SessionHistoryContext(
        fs: fs,
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  test('detect prefers a persisted id whose transcript exists', () async {
    await writeTranscript('old-session-id');
    final id = await capability.detectNativeId(
      resumeCtx(persisted: 'old-session-id'),
    );
    expect(id, 'old-session-id');
  });

  test('detect falls back to taskId probe when persisted transcript misses',
      () async {
    await writeTranscript('new-task-id');
    final id = await capability.detectNativeId(resumeCtx(persisted: 'gone'));
    expect(id, 'new-task-id');
  });

  test('detect returns null when neither id has a transcript', () async {
    final id = await capability.detectNativeId(resumeCtx(persisted: 'gone'));
    expect(id, isNull);
  });

  test('taskId-only behavior unchanged when no persisted id', () async {
    await writeTranscript('new-task-id');
    final id = await capability.detectNativeId(resumeCtx());
    expect(id, 'new-task-id');
  });

  test('locate prefers the persisted transcript', () async {
    await writeTranscript('old-session-id');
    final bundle = await locateClaudeTranscript(historyCtx(
      persisted: 'old-session-id',
    ));
    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.name, 'old-session-id.jsonl');
  });

  test('locate falls back to taskId when persisted transcript misses',
      () async {
    await writeTranscript('new-task-id');
    final bundle = await locateClaudeTranscript(historyCtx(persisted: 'gone'));
    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.name, 'new-task-id.jsonl');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/claude/claude_persisted_native_id_test.dart`
Expected: FAIL — `detect` returns `'new-task-id'`/`null` instead of `'old-session-id'`, locate returns null / wrong name.

- [ ] **Step 3: Implement detect preference**

In `ai_history_capability.dart` replace `detectNativeId` (keep `_layoutSegments` as-is):

```dart
  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    // Duplicated sessions carry the source transcript under its original
    // pinned filename; prefer the persisted id over the taskId probe.
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) {
      final persistedExists = await pinnedTranscriptExists(
        fs: ctx.fs,
        toolRoots: ctx.transcriptRoots,
        sessionId: persisted,
        bucket: ctx.bucket,
        layoutSegments: _layoutSegments,
      );
      if (persistedExists) return persisted;
    }
    final id = ctx.taskId.trim();
    if (id.isEmpty) return null;
    final exists = await pinnedTranscriptExists(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: id,
      bucket: ctx.bucket,
      layoutSegments: _layoutSegments,
    );
    return exists ? id : null;
  }
```

- [ ] **Step 4: Implement locate preference**

In `ai_transcript.dart` add below the imports and rewrite the probe part of `locateClaudeTranscript`:

```dart
/// Probes the persisted id first (duplicated sessions), then [ctx.taskId].
/// `matchDirectories: false` in both probes: history parse needs the `.jsonl`
/// file itself; a `{sessionId}/` sidecar directory must not shadow it.
Future<PinnedTranscriptProbeResult> _locateProbe(
  SessionHistoryContext ctx,
) async {
  final persisted = ctx.persistedNativeId?.trim() ?? '';
  if (persisted.isNotEmpty) {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: persisted,
      bucket: ctx.bucket,
      layoutSegments: const ['projects'],
      matchDirectories: false,
    );
    if (probe.exists) return probe;
  }
  return probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['projects'],
    matchDirectories: false,
  );
}
```

In `locateClaudeTranscript` replace the existing `final probe = await probePinnedTranscript(...);` block (lines 15-24) with:

```dart
  final probe = await _locateProbe(ctx);
```

(Keep the doc comment updated: mention persisted-first order.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/services/cli/claude/claude_persisted_native_id_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 6: Run the wider claude history suite**

Run: `cd client && flutter test test/services/cli`
Expected: PASS — no regressions in existing resume/history tests.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/claude/capabilities/history/ai_history_capability.dart \
  client/lib/services/cli/claude/capabilities/history/ai_transcript.dart \
  client/test/services/cli/claude/claude_persisted_native_id_test.dart
git commit -m "feat(cli): claude history prefers persisted native id over taskId probe"
```

---

### Task 2: flashskyai clientPinned capability honors persisted native ids

**Files:**
- Modify: `client/lib/services/cli/flashskyai/capabilities/history/ai_history_capability.dart` (`detectNativeId`, lines 63-75)
- Modify: `client/lib/services/cli/flashskyai/capabilities/history/ai_transcript.dart` (`locateFlashskyaiTranscript`, lines 15-27)
- Test: `client/test/services/cli/flashskyai/flashskyai_persisted_native_id_test.dart` (new)

**Interfaces:**
- Consumes: same probe helpers as Task 1, with `_layoutSegments = ['projects', 'workspaces']`.
- Produces: same persisted-first semantics for flashskyai. Task 4 seeds `'flashskyai': <sourceSessionId>` relying on this.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/flashskyai/flashskyai_persisted_native_id_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late String toolRoot;
  const capability = FlashskyaiAiHistoryCapability();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('flashskyai_persisted_id_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    toolRoot = fs.pathContext.join(tmp.path, 'flashskyai-config');
  });

  Future<void> writeTranscript(String id, {String segment = 'projects'}) async {
    final dir = fs.pathContext.join(toolRoot, segment, 'b1');
    await fs.ensureDir(dir);
    await fs.writeString(
      fs.pathContext.join(dir, '$id.jsonl'),
      '{"type":"user","message":{"content":"hi"}}\n',
    );
  }

  ResumeContext resumeCtx({String? persisted}) => ResumeContext(
        fs: fs,
        toolValue: 'flashskyai',
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  SessionHistoryContext historyCtx({String? persisted}) =>
      SessionHistoryContext(
        fs: fs,
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  test('detect prefers a persisted id whose transcript exists', () async {
    await writeTranscript('old-session-id');
    final id = await capability.detectNativeId(
      resumeCtx(persisted: 'old-session-id'),
    );
    expect(id, 'old-session-id');
  });

  test('detect scans workspaces/ legacy segment too', () async {
    await writeTranscript('old-session-id', segment: 'workspaces');
    final id = await capability.detectNativeId(
      resumeCtx(persisted: 'old-session-id'),
    );
    expect(id, 'old-session-id');
  });

  test('detect falls back to taskId probe when persisted transcript misses',
      () async {
    await writeTranscript('new-task-id');
    final id = await capability.detectNativeId(resumeCtx(persisted: 'gone'));
    expect(id, 'new-task-id');
  });

  test('locate prefers the persisted transcript', () async {
    await writeTranscript('old-session-id');
    final bundle = await locateFlashskyaiTranscript(historyCtx(
      persisted: 'old-session-id',
    ));
    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.name, 'old-session-id.jsonl');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/flashskyai/flashskyai_persisted_native_id_test.dart`
Expected: FAIL for the persisted-first cases.

- [ ] **Step 3: Implement detect preference**

In `ai_history_capability.dart` replace `detectNativeId` (same shape as Task 1, flashskyai `_layoutSegments`):

```dart
  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    // Duplicated sessions carry the source transcript under its original
    // pinned filename; prefer the persisted id over the taskId probe.
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) {
      final persistedExists = await pinnedTranscriptExists(
        fs: ctx.fs,
        toolRoots: ctx.transcriptRoots,
        sessionId: persisted,
        bucket: ctx.bucket,
        layoutSegments: _layoutSegments,
      );
      if (persistedExists) return persisted;
    }
    final id = ctx.taskId.trim();
    if (id.isEmpty) return null;
    final exists = await pinnedTranscriptExists(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: id,
      bucket: ctx.bucket,
      layoutSegments: _layoutSegments,
    );
    return exists ? id : null;
  }
```

- [ ] **Step 4: Implement locate preference**

In `ai_transcript.dart` add a `_locateProbe` helper (identical structure to Task 1 Step 4 but with `layoutSegments: const ['projects', 'workspaces']`) and replace the inline `probePinnedTranscript(...)` call in `locateFlashskyaiTranscript` with `final probe = await _locateProbe(ctx);`.

Full helper for this file:

```dart
/// Probes the persisted id first (duplicated sessions), then [ctx.taskId].
Future<PinnedTranscriptProbeResult> _locateProbe(
  SessionHistoryContext ctx,
) async {
  final persisted = ctx.persistedNativeId?.trim() ?? '';
  if (persisted.isNotEmpty) {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: persisted,
      bucket: ctx.bucket,
      layoutSegments: const ['projects', 'workspaces'],
      matchDirectories: false,
    );
    if (probe.exists) return probe;
  }
  return probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['projects', 'workspaces'],
    matchDirectories: false,
  );
}
```

Update the doc comment on `locateFlashskyaiTranscript` to mention persisted-first order.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/services/cli/flashskyai/flashskyai_persisted_native_id_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/flashskyai/capabilities/history/ai_history_capability.dart \
  client/lib/services/cli/flashskyai/capabilities/history/ai_transcript.dart \
  client/test/services/cli/flashskyai/flashskyai_persisted_native_id_test.dart
git commit -m "feat(cli): flashskyai history prefers persisted native id over taskId probe"
```

---

### Task 3: CLI-state probe sweep — `hasCliState` recognizes forked state

The delete/diagnostics probe `_findCliState` only checks the taskId-named pinned transcript. A fork stores state under the seeded (source) id, so `hasCliState` must retry with the persisted id.

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart` (`hasCliState` lines 1180-1215, `_findCliState` lines 1545-1583)
- Test: `client/test/services/session/lifecycle_has_cli_state_fork_test.dart` (new)

**Interfaces:**
- Consumes: `probePinnedTranscript` (existing), `RuntimeLayout.workspaceBucketForPrimaryPath`, `RuntimeLayout.sessionRuntimeToolDir`.
- Produces: `hasCliState` returns true for a session whose only CLI state lives under `session.nativeSessionIds[cli]`. No signature changes.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/session/lifecycle_has_cli_state_fork_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late SessionLifecycleService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lifecycle_cli_state_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
    service = SessionLifecycleService(appDataBasePath: tmp.path);
  });

  Future<void> seedClaudeTranscript(String sessionId, String transcriptId) async {
    final toolDir = layout.sessionRuntimeToolDir('ws1', sessionId, 'claude');
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/tmp/proj');
    final dir = fs.pathContext.join(toolDir, 'projects', bucket);
    await fs.ensureDir(dir);
    await fs.writeString(fs.pathContext.join(dir, '$transcriptId.jsonl'), '{}\n');
  }

  AppSession sessionWith(Map<String, String> nativeIds) => AppSession(
        sessionId: 'fork-session-id',
        workspaceId: 'ws1',
        folders: [WorkspaceFolder(path: '/tmp/proj')],
        cli: CliTool.claude,
        nativeSessionIds: nativeIds,
        createdAt: 1,
      );

  Workspace workspaceFor(AppSession session) => Workspace(
        workspaceId: session.workspaceId,
        folders: session.folders,
        display: 'ws',
        createdAt: 1,
      );

  test('finds forked state via persisted native id', () async {
    await seedClaudeTranscript('fork-session-id', 'source-session-id');
    final session = sessionWith({'claude': 'source-session-id'});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isTrue);
  });

  test('still false when neither taskId nor persisted state exists', () async {
    final session = sessionWith({'claude': 'source-session-id'});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isFalse);
  });

  test('taskId probe still works without persisted ids', () async {
    await seedClaudeTranscript('fork-session-id', 'fork-session-id');
    final session = sessionWith(const {});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/session/lifecycle_has_cli_state_fork_test.dart`
Expected: first test FAILS (`has` is false — probe only looks for `fork-session-id.jsonl`).

- [ ] **Step 3: Implement the persisted-id fallback**

In `session_lifecycle_service.dart`, inside `hasCliState` after `resolvedCli` resolution (around line 1204), compute the persisted candidate and pass it down:

```dart
    final persistedId = resolvedCli == null
        ? ''
        : (memberBinding?.nativeSessionIds[resolvedCli.value] ??
                session.nativeSessionIds[resolvedCli.value] ??
                '')
            .trim();
```

and change the `_findCliState(...)` call to add one argument:

```dart
      fallbackSessionId: persistedId,
```

In `_findCliState` add the parameter and the retry:

```dart
  Future<_CliStateProbeResult> _findCliState({
    required RuntimeContext roots,
    required AppSession session,
    required String teamId,
    required String runtimeSessionId,
    required String cliSessionId,
    String? fallbackSessionId,
    CliTool? cli,
    String? workspaceId,
  }) async {
```

and after the first `_findCliStateInFilesystem(...)` result (replace the tail `return`):

```dart
    final probe = await _findCliStateInFilesystem(
      fs: roots.fs,
      toolRoots: toolRoots,
      sessionId: id,
      bucket: bucket,
    );
    if (probe.exists) return probe;
    final fallback = fallbackSessionId?.trim() ?? '';
    if (fallback.isNotEmpty && fallback != id) {
      return _findCliStateInFilesystem(
        fs: roots.fs,
        toolRoots: toolRoots,
        sessionId: fallback,
        bucket: bucket,
      );
    }
    return const _CliStateProbeResult(exists: false);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/session/lifecycle_has_cli_state_fork_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the lifecycle-adjacent suites**

Run: `cd client && flutter test test/services/session test/repositories`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/session_lifecycle_service.dart \
  client/test/services/session/lifecycle_has_cli_state_fork_test.dart
git commit -m "feat(session): hasCliState recognizes forked state via persisted native id"
```

---

### Task 4: `SessionRepository.duplicateSession`

Builds the fork record (same pattern as `_cloneSessionRecord` — direct construction, NOT `createSession`, because folders/memberTargets must be copied verbatim rather than recomputed), copies `runtime/{tool}/`, seeds the native id, rolls back on failure.

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` (add `duplicateSession` near `cloneWorkspace`, ~line 1211; add two imports)
- Test: `client/test/repositories/session_repository_duplicate_test.dart` (new)

**Interfaces:**
- Consumes: `CliToolRegistry.builtIn().capability<AiHistoryCapability>(cli)?.binding` (for clientPinned detection), `Filesystem.copyTree` (destination pre-cleaned by implementation), existing `_withSessionFile` / `_writeSession` / index-prepend block from `createSession` (lines 856-871).
- Produces: `Future<AppSession> duplicateSession(String sourceSessionId, {required String display})` — throws `StateError` for unknown ids and team sessions; seeds `nativeSessionIds[tool]` = persisted entry, else source sessionId for clientPinned CLIs. Task 5 consumes exactly this signature.

- [ ] **Step 1: Write the failing test**

Create `client/test/repositories/session_repository_duplicate_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late SessionRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_duplicate_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
    repo = SessionRepository(rootDir: tmp.path);
  });

  Future<AppSession> seedSimpleSession(CliTool cli) async {
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/tmp/my-workspace'),
    ]);
    final created =
        (await repo.createSession(workspace.workspaceId, cli: cli)).session;
    await repo.renameSession(created.sessionId, 'My chat');
    return created;
  }

  Future<String> writeClaudeTranscript(AppSession session, String id) async {
    final toolDir = layout.sessionRuntimeToolDir(
      session.workspaceId,
      session.sessionId,
      'claude',
    );
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/tmp/my-workspace');
    final dir = fs.pathContext.join(toolDir, 'projects', bucket);
    await fs.ensureDir(dir);
    final path = fs.pathContext.join(dir, '$id.jsonl');
    await fs.writeString(path, '{"type":"user","message":{"content":"hi"}}\n');
    return path;
  }

  test('duplicates a simple claude session with a history fork', () async {
    final source = await seedSimpleSession(CliTool.claude);
    final transcriptPath =
        await writeClaudeTranscript(source, source.sessionId);

    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'My chat (copy)',
    );

    expect(fork.isSimple, isTrue);
    expect(fork.sessionId, isNot(source.sessionId));
    expect(fork.display, 'My chat (copy)');
    expect(fork.cli, CliTool.claude);
    expect(fork.folders.length, source.folders.length);
    expect(fork.firstFolderPath, source.firstFolderPath);
    expect(fork.launchState, AppSessionLaunchState.created);
    // clientPinned: seed the source sessionId so resume finds the copied
    // transcript filename.
    expect(fork.nativeSessionIds, {'claude': source.sessionId});

    final copiedPath = fs.pathContext.join(
      layout.sessionRuntimeToolDir(source.workspaceId, fork.sessionId, 'claude'),
      'projects',
      RuntimeLayout.workspaceBucketForPrimaryPath('/tmp/my-workspace'),
      '${source.sessionId}.jsonl',
    );
    expect(await fs.readString(copiedPath), isNotNull);

    // Source untouched.
    final reloadedSource = await repo.findById(source.sessionId);
    expect(reloadedSource!.display, 'My chat');
    expect(await fs.readString(transcriptPath), isNotNull);

    // Fork is listed and indexed.
    final sessions = await repo.loadSessionsForWorkspace(source.workspaceId);
    expect(
      sessions.map((s) => s.sessionId),
      containsAll([source.sessionId, fork.sessionId]),
    );
  });

  test('carries persisted postCaptured native ids across the fork',
      () async {
    final source = await seedSimpleSession(CliTool.codex);
    await repo.recordNativeSessionId(
      source.sessionId,
      tool: 'codex',
      nativeId: 'codex-native-uuid-1',
    );
    final sourceSessions = layout.sessionRuntimeToolDir(
      source.workspaceId,
      source.sessionId,
      'codex',
    );
    final rolloutDir = fs.pathContext.join(
      sourceSessions,
      'sessions',
      '2026',
      '08',
      '26',
    );
    await fs.ensureDir(rolloutDir);
    await fs.writeString(
      fs.pathContext.join(
        rolloutDir,
        'rollout-2026-08-26-codex-native-uuid-1.jsonl',
      ),
      '{"session_meta":{}}\n',
    );

    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'Fork codex',
    );

    expect(fork.nativeSessionIds['codex'], 'codex-native-uuid-1');
    final copiedRollout = fs.pathContext.join(
      layout.sessionRuntimeToolDir(source.workspaceId, fork.sessionId, 'codex'),
      'sessions',
      '2026',
      '08',
      '26',
      'rollout-2026-08-26-codex-native-uuid-1.jsonl',
    );
    expect(await fs.readString(copiedRollout), isNotNull);
  });

  test('skips the copy silently when the CLI never launched', () async {
    final source = await seedSimpleSession(CliTool.claude);
    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'Fresh fork',
    );
    expect(fork.nativeSessionIds, {'claude': source.sessionId});
    final toolDir = layout.sessionRuntimeToolDir(
      source.workspaceId,
      fork.sessionId,
      'claude',
    );
    expect(await fs.stat(toolDir), isNot(isDirectory));
  });

  test('rejects team sessions', () async {
    final source = await seedSimpleSession(CliTool.claude);
    await repo.updateSessionTeam(source.sessionId, 'some-team');
    expect(
      () => repo.duplicateSession(source.sessionId, display: 'x'),
      throwsStateError,
    );
  });

  test('throws for unknown session ids', () async {
    expect(
      () => repo.duplicateSession('missing-id', display: 'x'),
      throwsStateError,
    );
  });
}
```

Note: `isNot(isDirectory)` needs `import 'package:flutter_test/flutter_test.dart'` matcher — if unavailable in the installed flutter_test version, assert instead:

```dart
    expect((await fs.stat(toolDir)).isDirectory, isFalse);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/repositories/session_repository_duplicate_test.dart`
Expected: compile error — `duplicateSession` undefined.

- [ ] **Step 3: Implement `duplicateSession`**

Add imports to `session_repository.dart` (alphabetical among the `../services/…` block):

```dart
import '../services/cli/registry/capabilities/ai_history_capability.dart';
import '../services/cli/registry/cli_tool_registry.dart';
```

Add the method right above `cloneWorkspace`:

```dart
  /// Duplicates a Simple session together with its CLI runtime state
  /// (conversation-history fork). See
  /// `docs/superpowers/specs/2026-08-26-duplicate-session-design.md`.
  ///
  /// Copies `runtime/{tool}/` verbatim and seeds the fork's
  /// [AppSession.nativeSessionIds] so resume/history resolve against the
  /// copied state: postCaptured CLIs reuse their persisted entry,
  /// clientPinned CLIs get the source sessionId (the pinned transcript
  /// filename). Team sessions are rejected. On a mid-copy failure the
  /// half-written target directory is removed before rethrowing.
  Future<AppSession> duplicateSession(
    String sourceSessionId, {
    required String display,
  }) {
    return _withSessionFile(sourceSessionId, () async {
      final fs = await _fs();
      final source = await _findSession(fs, sourceSessionId);
      if (source == null) {
        throw StateError('Unknown sessionId: $sourceSessionId');
      }
      if (!source.isSimple) {
        throw StateError(
          'duplicateSession supports Simple sessions only '
          '(source ${source.sessionId} is teamed)',
        );
      }
      final cli = source.cli ?? CliTool.claude;
      final tool = cli.value;
      final now = DateTime.now().millisecondsSinceEpoch;
      final newSessionId = const Uuid().v4();

      final persisted = source.nativeSessionIds[tool]?.trim() ?? '';
      final pinsOwnTranscript =
          CliToolRegistry.builtIn()
              .capability<AiHistoryCapability>(cli)
              ?.binding ==
          ResumeBinding.clientPinned;
      final seededNativeId = persisted.isNotEmpty
          ? persisted
          : pinsOwnTranscript
          ? source.sessionId
          : '';

      var fork = AppSession(
        sessionId: newSessionId,
        workspaceId: source.workspaceId,
        folders: List.of(source.folders),
        memberTargets: Map.of(source.memberTargets),
        display: display,
        cli: cli,
        provider: source.provider,
        model: source.model,
        effort: source.effort,
        presetId: source.presetId,
        nativeSessionIds: seededNativeId.isEmpty
            ? const {}
            : {tool: seededNativeId},
        launchState: AppSessionLaunchState.created,
        createdAt: now,
        updatedAt: now,
        expertKey: source.expertKey,
        continueOverrides: source.continueOverrides,
      );
      try {
        await fs.ensureSessionDir(source.workspaceId, newSessionId);
        final sourceToolDir = fs.layout.sessionRuntimeToolDir(
          source.workspaceId,
          sourceSessionId,
          tool,
        );
        if ((await fs.fs.stat(sourceToolDir)).isDirectory) {
          await fs.fs.copyTree(
            source: sourceToolDir,
            destination: fs.layout.sessionRuntimeToolDir(
              source.workspaceId,
              newSessionId,
              tool,
            ),
          );
        }
      } on Object {
        await fs.deleteSessionDir(source.workspaceId, newSessionId);
        rethrow;
      }
      await _writeSession(fs, fork);

      // Index mirror — same prepend semantics as createSession.
      final key = _workspacesIndexCacheKey();
      Workspace? cachedWorkspace;
      for (final w in _workspacesIndexByRoot[key] ?? const <Workspace>[]) {
        if (w.workspaceId == source.workspaceId) {
          cachedWorkspace = w;
          break;
        }
      }
      final manifest = await _readManifest(fs, source.workspaceId, indexOnly: true);
      final baseIds = cachedWorkspace?.sessionIds ?? manifest?.sessionIds ?? const <String>[];
      if (!baseIds.contains(newSessionId)) {
        await _rememberWorkspace(
          (cachedWorkspace ?? manifest)!.copyWith(
            sessionIds: [newSessionId, ...baseIds],
          ),
        );
      }
      appLogger.d(
        '[session-duplicate] duplicated $sourceSessionId -> $newSessionId '
        'tool=$tool',
      );
      return fork;
    });
  }
```

Notes for the implementer:
- `fs.layout` is the public `WorkspaceLayout` getter on `SessionRepositoryFs` (session_repository_fs.dart:30); `fs.fs` is the underlying `Filesystem` (line 27).
- `LocalFilesystem.copyTree` removes + recreates the destination first, and returns quietly when the source is gone — the `stat` guard avoids creating an empty tool dir for never-launched sessions.
- If `_readManifest(indexOnly: true)` has a different name/signature in the current file, mirror exactly what `createSession` uses at line 734.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/repositories/session_repository_duplicate_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full repository suite**

Run: `cd client && flutter test test/repositories`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/test/repositories/session_repository_duplicate_test.dart
git commit -m "feat(repo): duplicateSession forks a simple session with CLI history"
```

---

### Task 5: ChatCubit wrapper + immediate-open seam

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (add `duplicateSession` after `renameSession`, ~line 2034)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (`openWorkspaceSessionTab`, lines 82-128)

**Interfaces:**
- Consumes: `repo.duplicateSession(sourceSessionId, display:)` from Task 4; `ChatTab.isRunning` / `membersPendingConnect` (`chat/model/chat_tab.dart:101,121`); `_tabStore.openTabBySessionId`.
- Produces: `Future<AppSession> ChatCubit.duplicateSession(SessionRepository repo, String sourceSessionId, {required String newDisplayTitle})` — throws `StateError` when the source tab is live; appends the fork to cubit state. `openWorkspaceSessionTab(..., {bool? connectImmediatelyOverride})`. Task 6 consumes both.

- [ ] **Step 1: Implement the cubit wrapper**

Add after `renameSession` in `chat_cubit.dart`:

```dart
  /// Duplicates a Simple session (launch identity + CLI history fork).
  ///
  /// [newDisplayTitle] is resolved by the caller so l10n stays out of the
  /// cubit. Throws [StateError] while the source session still has a live
  /// terminal or pending connects — copying a live transcript risks torn
  /// JSONL appends and corrupt SQLite WAL snapshots.
  Future<AppSession> duplicateSession(
    SessionRepository repo,
    String sourceSessionId, {
    required String newDisplayTitle,
  }) async {
    final tab = _tabStore.openTabBySessionId(sourceSessionId);
    if (tab != null &&
        (tab.isRunning || tab.membersPendingConnect.isNotEmpty)) {
      throw StateError('Cannot duplicate a running session');
    }
    final created = await repo.duplicateSession(
      sourceSessionId,
      display: newDisplayTitle,
    );
    final sessions = [...state.sessions, created];
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions),
    );
    return created;
  }
```

(`_tabStore`, `_dataStore`, `_emitSnapshot` already exist — see `renameSession` at lines 2012-2034 for usage.)

- [ ] **Step 2: Add the connect-immediately override seam**

In `workspace_session_actions.dart`, change the signature and the preference read:

```dart
Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session, {
  String? tabScopeId,
  bool? connectImmediatelyOverride,
}) async {
```

and replace (lines 101-105):

```dart
  final connectImmediately = connectImmediatelyOverride ??
      context
          .read<SessionPreferencesCubit>()
          .state
          .preferences
          .openExistingSessionStartsTerminal;
```

Update the doc comment above the function: "`connectImmediatelyOverride` forces the choice (duplicate flow always connects immediately); null defers to the user preference."

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart
git commit -m "feat(chat): duplicateSession cubit entry + forced-connect open seam"
```

---

### Task 6: Sidebar「复制」menu item + l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (near `renameConversation`, ~line 953)
- Modify: `client/lib/widgets/sidebar_session_tile.dart`
- Test: extend `client/test/widgets/sidebar_session_tile_test.dart`

**Interfaces:**
- Consumes: `ChatCubit.duplicateSession` (Task 5), `openWorkspaceSessionTab(connectImmediatelyOverride:)` (Task 5), `session.isSimple`.
- Produces: context-menu + overflow-menu item `duplicate`; hidden for team sessions; disabled while the source tab is live.

- [ ] **Step 1: Add l10n keys**

In `app_en.arb` after `"unpinConversation"`:

```json
  "duplicateConversation": "Duplicate conversation",
  "sessionDuplicated": "Conversation duplicated",
  "sessionDuplicateFailed": "Failed to duplicate conversation",
  "sessionTitleCopySuffix": "(copy)",
```

In `app_zh.arb` at the matching position:

```json
  "duplicateConversation": "复制对话",
  "sessionDuplicated": "对话已复制",
  "sessionDuplicateFailed": "复制对话失败",
  "sessionTitleCopySuffix": "（副本）",
```

- [ ] **Step 2: Write the failing widget tests**

Append inside `main()` of `client/test/widgets/sidebar_session_tile_test.dart` (reuse its existing `_host`, `_RecordingChatCubit`, `_openContextMenu`, `_dismissContextMenu` helpers — read the file first and follow its patterns):

```dart
  testWidgets('context menu offers Duplicate for simple sessions',
      (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(_host(
      chatCubit: chatCubit,
      automationCubit: automationCubit,
      sessionRepository: SessionRepository(rootDir: '/nonexistent'),
      attentionCubit: attention,
    ));
    await _openContextMenu(tester);

    expect(find.text('Duplicate conversation'), findsOneWidget);
    final item = tester.widget<TpActionMenuPopupItem<String>>(
      find.byWidgetPredicate(
        (w) => w is TpActionMenuPopupItem<String> && w.value == 'duplicate',
      ),
    );
    expect(item.enabled, isTrue);
  });

  testWidgets('context menu hides Duplicate for team sessions',
      (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    const teamed = AppSession(
      sessionId: 'sess-team',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    await tester.pumpWidget(_host(
      chatCubit: chatCubit,
      automationCubit: automationCubit,
      sessionRepository: SessionRepository(rootDir: '/nonexistent'),
      attentionCubit: attention,
      child: SidebarSessionTile(session: teamed, onTap: () {}),
    ));
    await _openContextMenu(tester);

    expect(find.text('Duplicate conversation'), findsNothing);
  });

  testWidgets('tapping Duplicate calls the cubit and opens the fork',
      (tester) async {
    final recorded = <String>[];
    final chatCubit = _DuplicateRecordingChatCubit(recorded);
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(_host(
      chatCubit: chatCubit,
      automationCubit: automationCubit,
      sessionRepository: SessionRepository(rootDir: '/nonexistent'),
      attentionCubit: attention,
    ));
    await _openContextMenu(tester);
    await tester.tap(find.text('Duplicate conversation'));
    await tester.pumpAndSettle();

    expect(recorded.single, 'sess-1');
  });
```

Add the recording cubit next to `_RecordingChatCubit` at the top of the file:

```dart
class _DuplicateRecordingChatCubit extends _RecordingChatCubit {
  _DuplicateRecordingChatCubit(this.recordedCalls);

  final List<String> recordedCalls;

  @override
  Future<AppSession> duplicateSession(
    SessionRepository repo,
    String sourceSessionId, {
    required String newDisplayTitle,
  }) async {
    recordedCalls.add(sourceSessionId);
    return AppSession(
      sessionId: 'sess-1-fork',
      workspaceId: 'ws1',
      display: newDisplayTitle,
      createdAt: 1,
    );
  }
}
```

Add imports the file lacks: `package:collection/collection.dart` is NOT needed here; `TpActionMenuPopupItem` comes from `package:shared_ui/shared_ui.dart` (add if absent).

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/widgets/sidebar_session_tile_test.dart`
Expected: FAIL — no `Duplicate conversation` entry yet; `_DuplicateRecordingChatCubit` fails to compile until `duplicateSession` override matches (it exists since Task 5).

- [ ] **Step 4: Implement the menu items**

In `sidebar_session_tile.dart`:

a) Context menu — insert between the `rename` and `pin` entries in `_contextMenuItems` (lines 148-159):

```dart
    if (session.isSimple)
      TpActionMenuPopupItem(
        value: 'duplicate',
        icon: Icons.copy_rounded,
        label: l10n.duplicateConversation,
        enabled: _duplicateEnabled(session),
      ),
```

b) Overflow menu — insert a matching item between the rename and pin `TpActionMenuItem`s in `build` (lines 451-479):

```dart
                    if (session.isSimple)
                      TpActionMenuItem(
                        icon: Icons.copy_rounded,
                        label: l10n.duplicateConversation,
                        enabled: _duplicateEnabled(session),
                        menuController: controller,
                        onTap: () => unawaited(
                          _duplicateSession(context, session, l10n),
                        ),
                      ),
```

c) Handler + guard — add next to `_handleContextAction` and wire the switch case `case 'duplicate': await _duplicateSession(context, session, l10n);` between `rename` and `pin`:

```dart
  bool _duplicateEnabled(AppSession session) {
    final chat = _chatCubit;
    if (chat == null) return false;
    final tab = chat.tabStore.openTabBySessionId(session.sessionId);
    return tab == null ||
        !(tab.isRunning || tab.membersPendingConnect.isNotEmpty);
  }

  Future<void> _duplicateSession(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) async {
    final chatCubit = _chatCubit;
    final repo = _repo;
    if (chatCubit == null || repo == null) return;
    final baseTitle = session.display.isNotEmpty
        ? session.display
        : l10n.defaultNewChatSessionTitle;
    try {
      final fork = await chatCubit.duplicateSession(
        repo,
        session.sessionId,
        newDisplayTitle: '$baseTitle ${l10n.sessionTitleCopySuffix}',
      );
      if (!mounted) return;
      AppToast.show(context, message: l10n.sessionDuplicated);
      final workspace = context.read<ChatCubit>().state.workspaces.firstWhereOrNull(
            (w) => w.workspaceId == fork.workspaceId,
          );
      if (workspace != null) {
        await openWorkspaceSessionTab(
          context,
          workspace,
          fork,
          connectImmediatelyOverride: true,
        );
      }
    } on Object catch (error, stackTrace) {
      appLogger.e(
        'duplicateSession',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        AppToast.show(
          context,
          message: l10n.sessionDuplicateFailed,
          variant: TpToastVariant.error,
        );
      }
    }
  }
```

New imports at the top of the file:

```dart
import 'package:collection/collection.dart';

import '../pages/home_workspace/workspace/workspace_session_actions.dart';
import '../services/session/session_lifecycle_service.dart'; // only if appLogger not already reachable via an existing import
```

`appLogger` lives in `../utils/logging/logger.dart` — import that instead of the lifecycle line if not already present. Check existing imports first; do not duplicate.

- [ ] **Step 5: Run widget tests to verify they pass**

Run: `cd client && flutter test test/widgets/sidebar_session_tile_test.dart`
Expected: PASS including the three new tests.

- [ ] **Step 6: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze clean; full test suite passes.

- [ ] **Step 7: Manual smoke (desktop debug run)**

Launch the app, create a Simple claude conversation, send one message, stop the session, right-click the row → Duplicate conversation. Expect: toast confirmation, new tab opens, terminal shows the resumed history (`--resume` of the fork), original conversation unchanged. Also verify: team session row shows no Duplicate item; duplicating a never-launched session yields a fresh conversation.

- [ ] **Step 8: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/widgets/sidebar_session_tile.dart \
  client/test/widgets/sidebar_session_tile_test.dart
git commit -m "feat(ui): duplicate-conversation action for simple sessions"
```

---

## Self-Review Checklist (completed during planning)

- Spec coverage: capability preference (Tasks 1-2), equality sweep (Task 3), repository fork + seeding rules incl. rollback (Task 4), cubit guard + immediate open (Task 5), menu visibility/disabled rules + l10n + suffix title (Task 6). Repeated duplication suffix stacking accepted per spec.
- Known gaps (documented, not silent): running-state disabled rendering isn't widget-asserted (needs a live TerminalSession); covered by `_duplicateEnabled` + the cubit guard and the Task 6 Step 7 manual smoke. Mid-copy rollback isn't unit-tested (no fs injection seam on the repo); logic kept minimal and reviewed.
