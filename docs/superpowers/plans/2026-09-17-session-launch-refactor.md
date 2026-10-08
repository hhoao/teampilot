# Session Launch Refactor Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Collapse session-open and member-connect launch paths into one explicit scheduler/executor flow, remove duplicated asynchronous control logic, and delete the callback-heavy launch composition layers.

**Architecture:** ChatCubit remains the state owner and exposes thin launch entry methods. SessionLaunchService forwards intent to SessionLaunchCoordinator, which surfaces tabs and creates immutable SessionConnectJob values. One SessionConnectScheduler owns de-duplication and post-frame execution, while SessionConnectExecutor owns persist/readiness/runtime/shell connection and cleanup. SessionConnectOrchestrator remains runtime provisioning infrastructure.

**Tech Stack:** Dart, Flutter, flutter_bloc/Cubit, existing SessionLaunchHost ports, TerminalSession, SessionConnectOrchestrator, repository test wrapper, focused unit tests, and integration tests.

## Global Constraints

- Never invoke flutter test directly; use commands such as cd client && dart run tool/run_tests.dart test/services/launch/session_connect_job_test.dart.
- Before completion run cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart.
- Preserve injected HomeStorage and RuntimeContext; do not use Directory.current for workspace/app data.
- Use sessionRosterMembers(session, team) for session member placement; do not use raw team.members for session placement decisions.
- Keep CLI selection behind the existing CLI registry/capability and preset resolver patterns.
- Use AppLogger for diagnostics and l10n for user-facing messages; do not add print.
- Mock subprocesses and filesystems through constructor injection.
- Do not overwrite or clean unrelated existing worktree changes.
- No compatibility adapters are required; all in-repository callers may be updated to new APIs.

---

## File Map

### Create

- client/lib/services/launch/session/session_launch_coordinator.dart — intent-level create/open/member selection and job construction.
- client/lib/services/launch/connect/session_connect_job.dart — immutable connection job and launch reason.
- client/lib/services/launch/connect/session_connect_scheduler.dart — de-duplication, pending tokens, post-frame execution, and stale-job dropping.
- client/lib/services/launch/connect/session_connect_executor.dart — one persist/readiness/runtime/shell-connect workflow and cleanup boundary.
- Focused tests under client/test/services/launch/.

### Modify

- client/lib/cubits/chat/session_launch_service.dart — thin facade and application/state adapters.
- client/lib/cubits/chat_cubit.dart — thin forwarding methods and state ownership only.
- client/lib/cubits/chat/session_launch_host.dart — narrow typed ports needed by new components.
- client/lib/services/launch/launch_factory.dart — launch composition root.
- client/lib/services/launch/tab/session_tab_surface_coordinator.dart — tab surfacing only.
- client/lib/services/launch/connect/member_connect_stage.dart — member selection/materialization/job creation only.
- client/lib/services/launch/connect/session_shell_connector.dart — low-level attachment/provisioning only.
- client/lib/services/launch/connect/session_lifecycle_connect_coordinator.dart — lifecycle gate adapter.
- client/lib/services/launch/connect/session_ssh_profile_reconnect.dart — enqueue jobs through unified scheduler.
- client/lib/services/launch/session/session_default_materializer.dart — hand off unified jobs instead of the old pipeline callback.
- UI, automation, and integration callers identified by compiler/search.

### Delete after migration

- client/lib/services/launch/session_launch_bundle.dart
- client/lib/services/launch/session/session_launch_pipeline.dart
- client/lib/services/launch/tab/session_launch_connect_prep_runner.dart
- client/lib/services/launch/tab/session_tab_connect_prep.dart after its logic is absorbed.
- The old duplicate member scheduler implementation after its queue/guard behavior is moved.
- Callback typedefs and operation/outcome types with no remaining consumers.

The nested services/launch/{connect,contracts,session,staging,tab,workspace} files are the current source of truth. Do not restore older flat-path files.

---

### Task 1: Add the explicit connection job contract

**Files:**

- Create: client/lib/services/launch/connect/session_connect_job.dart
- Test: client/test/services/launch/session_connect_job_test.dart

**Interfaces:**

- Consumes ChatTab, AppSession, SessionOpenRequest, Workspace, TeamProfile, and TeamMemberConfig.
- Produces immutable SessionConnectJob, LaunchReason, sessionId, and memberId.

- [ ] Step 1: Write tests for job identity and intent fields

~~~dart
test('job identity uses session and selected member', () {
  final job = SessionConnectJob(
    tab: tab,
    session: session,
    request: request,
    generation: 3,
    workspace: workspace,
    team: team,
    member: member,
    reason: LaunchReason.openExisting,
  );

  expect(job.sessionId, session.sessionId);
  expect(job.memberId, member.id);
  expect(job.generation, 3);
  expect(job.reason, LaunchReason.openExisting);
});

test('personal job uses session id as member identity', () {
  final job = personalJob();
  expect(job.memberId, job.session.sessionId);
});
~~~

- [ ] Step 2: Run the focused test to verify it fails

Run: cd client && dart run tool/run_tests.dart test/services/launch/session_connect_job_test.dart

Expected: FAIL because the new type and constructor are absent.

- [ ] Step 3: Implement the immutable contract

~~~dart
enum LaunchReason {
  create,
  openExisting,
  memberSelected,
  restore,
  retry,
  sshReconnect,
}

final class SessionConnectJob {
  const SessionConnectJob({
    required this.tab,
    required this.session,
    required this.request,
    required this.generation,
    required this.workspace,
    this.team,
    this.member,
    required this.reason,
  });

  final ChatTab tab;
  final AppSession session;
  final SessionOpenRequest request;
  final int generation;
  final Workspace? workspace;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final LaunchReason reason;

  String get sessionId => session.sessionId;
  String get memberId => member?.id.trim().isNotEmpty == true
      ? member!.id.trim()
      : session.sessionId;
}
~~~

- [ ] Step 4: Run the focused test

Run: cd client && dart run tool/run_tests.dart test/services/launch/session_connect_job_test.dart

Expected: PASS.

- [ ] Step 5: Commit

~~~bash
git add client/lib/services/launch/connect/session_connect_job.dart client/test/services/launch/session_connect_job_test.dart
git commit -m "refactor(launch): add explicit session connect job"
~~~

### Task 2: Build the unified scheduler

**Files:**

- Create: client/lib/services/launch/connect/session_connect_scheduler.dart
- Test: client/test/services/launch/session_connect_scheduler_test.dart
- Consume: client/lib/services/launch/connect/session_connect_job.dart

**Interfaces:**

- Consumes SessionConnectJob and an injected SessionConnectExecutorPort.
- Produces Future<void> enqueue(SessionConnectJob job), bool isPending({required String sessionId, required String memberId}), and void cancelForTab(ChatTab tab).

- [ ] Step 1: Write tests for duplicate, stale, concurrency, and cleanup behavior

Use a fake executor and injected post-frame callback:

~~~dart
test('same session/member is executed once while pending', () async {
  final job = jobFor(sessionId: 'session-1', memberId: 'member-1');
  await scheduler.enqueue(job);
  await scheduler.enqueue(job);
  await flushPostFrameCallbacks();
  expect(executor.jobs.map((item) => item.sessionId + '|' + item.memberId),
      <String>['session-1|member-1']);
});

test('different sessions can execute concurrently', () async {
  await scheduler.enqueue(jobFor(sessionId: 'session-1', memberId: 'member-1'));
  await scheduler.enqueue(jobFor(sessionId: 'session-2', memberId: 'member-1'));
  await flushPostFrameCallbacks();
  expect(executor.jobs, hasLength(2));
});

test('closed tab or changed generation is dropped before execution', () async {
  final job = jobFor(sessionId: 'session-1', memberId: 'member-1', generation: 2);
  valid = false;
  await scheduler.enqueue(job);
  await flushPostFrameCallbacks();
  expect(executor.jobs, isEmpty);
});

test('executor failure clears pending identity', () async {
  executor.error = StateError('connect failed');
  final job = jobFor(sessionId: 'session-1', memberId: 'member-1');
  await scheduler.enqueue(job);
  await flushPostFrameCallbacks();
  expect(scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'), false);
});
~~~

Define the test fixtures explicitly: jobFor accepts sessionId, memberId, and optional generation; flushPostFrameCallbacks drains the injected PostFrameScheduler queue; RecordingExecutor exposes jobs and an optional error. The fake host records beginSessionConnect and finishSessionConnect calls.

- [ ] Step 2: Run the focused test to verify it fails

Run: cd client && dart run tool/run_tests.dart test/services/launch/session_connect_scheduler_test.dart

Expected: FAIL because the scheduler and executor seam are absent.

- [ ] Step 3: Implement one typed executor seam and scheduler

~~~dart
abstract interface class SessionConnectExecutorPort {
  Future<void> execute(SessionConnectJob job);
}

class SessionConnectScheduler {
  SessionConnectScheduler({
    required this.executor,
    required this.postFrame,
    required this.isJobValid,
    required this.onBegin,
    required this.onFinish,
  });

  final SessionConnectExecutorPort executor;
  final PostFrameScheduler postFrame;
  final bool Function(SessionConnectJob job) isJobValid;
  final void Function(String sessionId) onBegin;
  final void Function(String sessionId) onFinish;

  final Set<String> _pending = <String>{};

  String key(SessionConnectJob job) => job.sessionId + '|' + job.memberId;

  Future<void> enqueue(SessionConnectJob job) async {
    final id = key(job);
    if (!_pending.add(id)) return;
    onBegin(job.sessionId);
    postFrame(() {
      unawaited(_execute(job, id));
    });
  }

  Future<void> _execute(SessionConnectJob job, String id) async {
    try {
      if (isJobValid(job)) await executor.execute(job);
    } on Object catch (error, stackTrace) {
      appLogger.e('[session-launch] unexpected executor failure',
          error: error, stackTrace: stackTrace);
    } finally {
      _pending.remove(id);
      onFinish(job.sessionId);
    }
  }

  bool isPending({required String sessionId, required String memberId}) =>
      _pending.contains(sessionId + '|' + memberId);

  void cancelForTab(ChatTab tab) {
    _pending.removeWhere((id) => id.startsWith(tab.info.id + '|'));
  }
}
~~~

Use the existing host connect state machine; do not introduce a second boolean source of truth.

- [ ] Step 4: Run focused scheduler and existing parallel-connect tests

~~~bash
cd client
dart run tool/run_tests.dart test/services/launch/session_connect_scheduler_test.dart
dart run tool/run_tests.dart test/services/launch/session_launch_parallel_connect_test.dart
~~~

Expected: PASS.

- [ ] Step 5: Commit

~~~bash
git add client/lib/services/launch/connect/session_connect_scheduler.dart client/test/services/launch/session_connect_scheduler_test.dart
git commit -m "refactor(launch): centralize connection scheduling"
~~~

### Task 3: Move common preparation and cleanup into the executor

**Files:**

- Create: client/lib/services/launch/connect/session_connect_executor.dart
- Modify: client/lib/cubits/chat/session_launch_service.dart
- Modify: client/lib/cubits/chat/session_launch_host.dart
- Modify: client/lib/services/launch/connect/session_shell_connector.dart
- Test: client/test/services/launch/session_connect_executor_test.dart

**Interfaces:**

- Consumes SessionConnectJob, SessionLaunchHost, SessionPersistenceWriter, SessionShellConnector, lifecycle gate, and shell factory through typed constructor dependencies.
- Produces Future<void> execute(SessionConnectJob job) through SessionConnectExecutorPort.

- [ ] Step 1: Write tests for ordered preparation, stale cancellation, rollback, and cleanup

~~~dart
test('executor persists, readies, resolves, installs, then attaches', () async {
  await executor.execute(job);
  expect(events, <String>[
    'persist',
    'ensure-ready',
    'resolve-member',
    'install-team-runtime',
    'acquire-shell',
    'connect-shell',
  ]);
});

test('executor stops without attachment when the job becomes stale', () async {
  valid = false;
  await executor.execute(job);
  expect(events, isEmpty);
  expect(shellConnector.connectCalls, 0);
});

test('executor rolls back a staged launch when preparation fails', () async {
  persistError = StateError('persist failed');
  await executor.execute(job);
  expect(rollbackCalls, 1);
  expect(host.launchErrors, contains(job.sessionId));
});

test('executor clears temporary remote resources after connector failure', () async {
  connectorError = StateError('attach failed');
  await executor.execute(job);
  expect(remotePlaneClosed, true);
  expect(host.finishedSessionIds, contains(job.sessionId));
});
~~~

- [ ] Step 2: Run the focused test to verify it fails

Run: cd client && dart run tool/run_tests.dart test/services/launch/session_connect_executor_test.dart

Expected: FAIL because the executor does not exist.

- [ ] Step 3: Implement the executor and move shared methods behind typed ports

Define one preparation port instead of passing one callback per operation:

~~~dart
abstract interface class SessionConnectPreparationPort {
  Future<AppSession> persist(SessionConnectJob job);
  Future<AppSession?> ensureReady(SessionConnectJob job, AppSession session);
  Future<ResolvedLaunchMembers> resolveMember(
      SessionConnectJob job, AppSession session);
  Future<void> installTeamRuntime(
      SessionConnectJob job, AppSession session, TeamProfile? team);
  TerminalSession shellForLaunch(
      SessionConnectJob job, AppSession session, ResolvedLaunchMembers resolved);
  bool isValid(SessionConnectJob job);
  void rollback(SessionConnectJob job, AppSession session);
}

class SessionConnectExecutor implements SessionConnectExecutorPort {
  SessionConnectExecutor({
    required this.preparation,
    required this.shellConnector,
  });

  final SessionConnectPreparationPort preparation;
  final SessionShellConnector shellConnector;

  @override
  Future<void> execute(SessionConnectJob job) async {
    AppSession? activeSession;
    try {
      activeSession = await preparation.persist(job);
      if (!preparation.isValid(job)) return;
      activeSession =
          await preparation.ensureReady(job, activeSession) ?? activeSession;
      if (!preparation.isValid(job)) return;
      final resolved = await preparation.resolveMember(job, activeSession);
      if (!preparation.isValid(job)) return;
      await preparation.installTeamRuntime(job, activeSession, resolved.team);
      if (!preparation.isValid(job)) return;
      final shell = preparation.shellForLaunch(job, activeSession, resolved);
      await shellConnector.connect(
        tab: job.tab,
        session: activeSession,
        shell: shell,
        repo: job.request.repo,
        launched: activeSession.launchState == AppSessionLaunchState.started,
        team: resolved.team,
        member: resolved.member,
        workspace: job.workspace,
      );
    } on Object catch (error, stackTrace) {
      if (activeSession != null && preparation.isValid(job)) {
        preparation.rollback(job, activeSession);
      }
      appLogger.e('[session-launch] connect job failed',
          error: error, stackTrace: stackTrace);
    }
  }
}
~~~

Move the bodies of _persistSessionIfNeeded, _ensureTeamSessionReady, _resolveLaunchMembers, _installTeamRuntimeIfNeeded, _shellForLaunch, and _launchStillValid behind SessionConnectPreparationPort. Keep SessionConnectOrchestrator and SessionShellConnector.connect behavior unchanged. The executor owns the single failure/cleanup boundary; stale jobs are silent cancellations.

- [ ] Step 4: Run focused executor, connector, and persistence tests

~~~bash
cd client
dart run tool/run_tests.dart test/services/launch/session_connect_executor_test.dart
dart run tool/run_tests.dart test/services/launch/session_persistence_writer_test.dart
dart run tool/run_tests.dart test/services/launch/session_launch_connect_prep_runner_test.dart
~~~

Expected: the new executor tests PASS and the old prep test remains PASS until its caller is migrated.

- [ ] Step 5: Commit

~~~bash
git add client/lib/services/launch/connect/session_connect_executor.dart client/lib/cubits/chat/session_launch_service.dart client/lib/cubits/chat/session_launch_host.dart client/lib/services/launch/connect/session_shell_connector.dart client/test/services/launch/session_connect_executor_test.dart
git commit -m "refactor(launch): centralize connection execution"
~~~

### Task 4: Add the intent coordinator and migrate tab-open launches

**Files:**

- Create: client/lib/services/launch/session/session_launch_coordinator.dart
- Modify: client/lib/services/launch/tab/session_tab_surface_coordinator.dart
- Modify: client/lib/services/launch/session/session_default_materializer.dart
- Modify: client/lib/cubits/chat/session_launch_service.dart
- Test: client/test/services/launch/session_launch_coordinator_test.dart
- Update: existing session-open/materializer tests under client/test/services/launch/

**Interfaces:**

- Consumes create/open requests, team/member intent, tab surface, scheduler, workspace index, and snapshot ports.
- Produces Future<SessionOpenStatus> createAndOpen(SessionCreateRequest request), Future<SessionOpenStatus> open(SessionOpenRequest request), and Future<void> openMember(TeamProfile team, TeamMemberConfig member, {SessionRepository? repo, String? workspaceCwd}).

- [ ] Step 1: Write tests for provisional create, history-only open, immediate open, and tab reuse

~~~dart
test('create surfaces provisional tab before async connection', () async {
  final status = await coordinator.createAndOpen(createRequest);
  expect(status, SessionOpenStatus.opened);
  expect(surface.openedSessionIds, contains(createRequest.sessionId));
  expect(scheduler.jobs.single.reason, LaunchReason.create);
});

test('history-only open surfaces a tab without enqueueing a job', () async {
  final status = await coordinator.open(historyOnlyRequest);
  expect(status, SessionOpenStatus.opened);
  expect(surface.openedSessionIds, contains(historyOnlyRequest.session.sessionId));
  expect(scheduler.jobs, isEmpty);
});

test('immediate open enqueues exactly one job', () async {
  final status = await coordinator.open(immediateOpenRequest);
  expect(status, SessionOpenStatus.opened);
  expect(scheduler.jobs, hasLength(1));
  expect(scheduler.jobs.single.reason, LaunchReason.openExisting);
});

test('existing tab is reused with the expected generation', () async {
  final status = await coordinator.open(immediateOpenRequest);
  expect(status, SessionOpenStatus.opened);
  expect(surface.reusedSessionIds,
      contains(immediateOpenRequest.session.sessionId));
  expect(scheduler.jobs.single.tab.launchGeneration,
      surface.reusedTab.launchGeneration);
});
~~~

Assert tab/snapshot/workbench events and exact jobs sent to the fake scheduler.

- [ ] Step 2: Run the focused test to verify it fails

Run: cd client && dart run tool/run_tests.dart test/services/launch/session_launch_coordinator_test.dart

Expected: FAIL because the coordinator does not exist.

- [ ] Step 3: Implement intent-level coordination

Move _runCreate validation and provisional-session construction into SessionLaunchCoordinator. Preserve mixed placement validation and session roster binding rules. Change SessionTabSurfaceCoordinator to return a surfacing result containing tab, session, generation, and connect intent; it must not accept preparation callbacks. Change SessionDefaultMaterializer to call coordinator intent methods instead of closing over SessionLaunchPipeline.openSession.

- [ ] Step 4: Replace launch bundle construction in SessionLaunchService

The service constructs or receives coordinator, scheduler, and executor through the composition root. It exposes only the two facade methods used by ChatCubit:

~~~dart
Future<SessionOpenStatus> requestCreateAndOpenSession(SessionCreateRequest request);
Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request);
~~~

Do not add deprecated forwarding methods for removed pipeline operations.

- [ ] Step 5: Run focused tab/open tests

~~~bash
cd client
dart run tool/run_tests.dart test/services/launch/session_launch_coordinator_test.dart
dart run tool/run_tests.dart test/services/launch/session_tab_surface_coordinator_test.dart
dart run tool/run_tests.dart test/services/launch/session_default_materializer_test.dart
dart run tool/run_tests.dart test/services/launch/session_launch_open_validator_test.dart
~~~

Expected: PASS.

- [ ] Step 6: Commit

~~~bash
git add client/lib/services/launch/session/session_launch_coordinator.dart client/lib/services/launch/tab/session_tab_surface_coordinator.dart client/lib/services/launch/session/session_default_materializer.dart client/lib/cubits/chat/session_launch_service.dart client/test/services/launch/session_launch_coordinator_test.dart client/test/services/launch/session_tab_surface_coordinator_test.dart client/test/services/launch/session_default_materializer_test.dart
git commit -m "refactor(launch): route session opens through coordinator"
~~~

### Task 5: Migrate member connect, retry, and SSH reconnect

**Files:**

- Modify: client/lib/services/launch/connect/member_connect_stage.dart
- Replace/migrate: client/lib/services/launch/connect/session_member_connect_scheduler.dart
- Modify: client/lib/services/launch/connect/session_ssh_profile_reconnect.dart
- Modify: client/lib/services/launch/connect/session_lifecycle_connect_coordinator.dart
- Modify: client/lib/cubits/chat/session_launch_service.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Update: client/lib/cubits/chat/tab_member_materializer.dart
- Update tests: session_member_connect_scheduler_test.dart, session_lifecycle_connect_coordinator_test.dart, session_ssh_profile_reconnect_test.dart

**Interfaces:**

- Consumes team/member selection and existing session tabs.
- Produces SessionConnectJob values consumed by the unified scheduler. No member path may call SessionShellConnector.connect directly.

- [ ] Step 1: Add failing assertions for same-executor routing

~~~dart
test('openMemberTab enqueues a job consumed by the unified executor', () async {
  await memberStage.openMemberTab(team, member);
  await flushPostFrameCallbacks();
  expect(executor.jobs.single.memberId, member.id);
});
test('launchAllMembers enqueues one job per valid roster member', () async {
  await memberStage.launchAllMembers(team);
  await flushPostFrameCallbacks();
  expect(executor.jobs.map((job) => job.memberId), orderedEquals(validMemberIds));
});
test('lifecycle retry and SSH reconnect enqueue jobs instead of calling connector directly', () async {
  await runDeferredLifecycleGateScenario(lifecycleCoordinator);
  await sshReconnect.reconnect(profileId);
  expect(executor.jobs, hasLength(2));
  expect(shellConnector.directConnectCalls, 0);
});
~~~

- [ ] Step 2: Run affected tests before migration

~~~bash
cd client
dart run tool/run_tests.dart test/services/launch/session_member_connect_scheduler_test.dart
dart run tool/run_tests.dart test/services/launch/session_lifecycle_connect_coordinator_test.dart
dart run tool/run_tests.dart test/services/launch/session_ssh_profile_reconnect_test.dart
~~~

Expected: existing tests PASS; new same-executor assertions fail.

- [ ] Step 3: Reduce MemberConnectStage to target selection and job creation

For each operation, resolve the selected member, materialize a default session when needed, build a job with LaunchReason.memberSelected, retry, or restore, then enqueue it. All-member launch must use sessionRosterMembers(session, team) after a session exists and preserve the selected member while background jobs do not change selection.

- [ ] Step 4: Migrate lifecycle and SSH reconnect

Retries from lifecycle and SSH profile reconnect must enqueue jobs through the unified scheduler. They must not own post-frame callbacks, shell creation, pending markers, or connector error handling.

- [ ] Step 5: Remove the old scheduler

Move required queue and de-duplication behavior into SessionConnectScheduler, update MemberConnector, TabMemberMaterializer, and all callers, then delete SessionMemberConnectScheduler.

- [ ] Step 6: Run migrated focused tests

~~~bash
cd client
dart run tool/run_tests.dart test/services/launch/session_member_connect_scheduler_test.dart
dart run tool/run_tests.dart test/services/launch/session_lifecycle_connect_coordinator_test.dart
dart run tool/run_tests.dart test/services/launch/session_ssh_profile_reconnect_test.dart
dart run tool/run_tests.dart test/services/launch/session_launch_parallel_connect_test.dart
dart run tool/run_tests.dart test/services/launch/session_launch_pipeline_all_members_test.dart
~~~

Expected: PASS. Rename tests that still mention deleted pipeline/scheduler terminology when their subject is now the coordinator or unified scheduler.

- [ ] Step 7: Commit

~~~bash
git add client/lib/services/launch/connect/member_connect_stage.dart client/lib/services/launch/connect/session_connect_scheduler.dart client/lib/services/launch/connect/session_ssh_profile_reconnect.dart client/lib/services/launch/connect/session_lifecycle_connect_coordinator.dart client/lib/cubits/chat/session_launch_service.dart client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/tab_member_materializer.dart client/test/services/launch/session_connect_scheduler_test.dart client/test/services/launch/session_lifecycle_connect_coordinator_test.dart client/test/services/launch/session_ssh_profile_reconnect_test.dart client/test/services/launch/session_launch_parallel_connect_test.dart client/test/services/launch/session_launch_pipeline_all_members_test.dart
git commit -m "refactor(launch): unify member connection paths"
~~~

### Task 6: Remove old composition layers and simplify application wiring

**Files:**

- Delete: client/lib/services/launch/session_launch_bundle.dart
- Delete: client/lib/services/launch/session/session_launch_pipeline.dart
- Delete: client/lib/services/launch/tab/session_launch_connect_prep_runner.dart
- Delete: client/lib/services/launch/tab/session_tab_connect_prep.dart when no imports remain
- Modify: client/lib/services/launch/launch_factory.dart
- Modify: client/lib/cubits/chat/session_launch_service.dart
- Modify: client/lib/cubits/chat/session_launch_host.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Update all remaining imports found by search
- Update tests referencing removed pipeline symbols

- [ ] Step 1: Locate all old-symbol consumers

Run:

~~~bash
rg -n "SessionLaunchBundle|SessionLaunchPipeline|SessionLaunchConnectPrepRunner|runSessionTabConnectPrep|LaunchOperation|LaunchOutcome|SessionMemberConnectScheduler|SessionTabConnectPrepCallbacks" client/lib client/test
~~~

Expected: output is limited to migration code/tests and symbols scheduled for removal.

- [ ] Step 2: Move construction to the composition root

Make launch_factory.dart construct the coordinator, scheduler, executor, and runtime infrastructure. SessionLaunchService must not construct SessionLaunchBundleDeps or use a late final pipeline to close a dependency cycle. Production wiring continues injecting SessionConnectOrchestrator and HomeStorage.

- [ ] Step 3: Simplify ChatCubit and host ports

Keep state mutation methods on ChatCubit. Remove launch-specific orchestration and host members that existed only for deleted callback paths. Retain ports needed by teardown, runtime state, TeamBus, status, and persistence.

- [ ] Step 4: Delete obsolete files and compile-guided references

Delete the listed files, then run:

~~~bash
cd client
dart analyze
~~~

Fix every deleted-symbol import/reference by moving the caller to the coordinator, scheduler, or executor. Do not reintroduce a compatibility wrapper.

- [ ] Step 5: Run all launch tests

Run: cd client && dart run tool/run_tests.dart test/services/launch

Expected: PASS.

- [ ] Step 6: Commit

~~~bash
git add client/lib/app/app_shell.dart client/lib/services/launch/launch_factory.dart client/lib/services/launch/connect/session_connect_job.dart client/lib/services/launch/connect/session_connect_scheduler.dart client/lib/services/launch/connect/session_connect_executor.dart client/lib/services/launch/session/session_launch_coordinator.dart client/lib/services/launch/tab/session_tab_surface_coordinator.dart client/lib/services/launch/session/session_default_materializer.dart client/lib/services/launch/connect/member_connect_stage.dart client/lib/services/launch/connect/session_shell_connector.dart client/lib/cubits/chat/session_launch_service.dart client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/test/services/launch/session_connect_job_test.dart client/test/services/launch/session_connect_scheduler_test.dart client/test/services/launch/session_connect_executor_test.dart client/test/services/launch/session_launch_coordinator_test.dart client/test/services/launch/session_tab_surface_coordinator_test.dart client/test/services/launch/session_default_materializer_test.dart
git commit -m "refactor(launch): remove callback pipeline composition"
~~~

### Task 7: Update integration coverage and verify acceptance criteria

**Files:**

- Update launch-related tests and harnesses under client/test/integration/ and client/test/integration/support/.
- Update focused tests renamed from pipeline/scheduler terminology.
- Modify the approved spec only if final entry paths differ.

- [ ] Step 1: Verify direct connector and scheduler ownership

Run:

~~~bash
rg -n "\\.connect\\(|postFrameScheduler|membersPendingConnect|beginSessionConnect|finishSessionConnect|failSessionConnect" client/lib/services/launch client/lib/cubits/chat/session_launch_service.dart
rg -n "SessionShellConnector\\.connect|_shellConnector\\.connect|shellConnector\\.connect" client/lib/services/launch
~~~

Expected: only SessionConnectExecutor invokes the connector; only SessionConnectScheduler owns post-frame and pending-job scheduling.

- [ ] Step 2: Run focused integration scenarios

~~~bash
cd client
dart run tool/run_tests.dart test/integration/codex_config_materialize_launch_integration_test.dart
dart run tool/run_tests.dart test/integration/cli_message_matrix_claude_test.dart
dart run tool/run_tests.dart test/integration/mixed_team_claude_bus_integration_test.dart
dart run tool/run_tests.dart test/integration/mixed_team_claude_idle_busy_integration_test.dart
~~~

Expected: PASS.

- [ ] Step 3: Run analyzer and full suite

~~~bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
~~~

Expected: analyzer succeeds and the wrapper reports all tests passing.

- [ ] Step 4: Verify final source shape

~~~bash
rg -n "SessionLaunchBundle|SessionLaunchPipeline|SessionLaunchConnectPrepRunner|SessionMemberConnectScheduler|SessionTabConnectPrepCallbacks|runSessionTabConnectPrep" client/lib client/test
rg -n "SessionShellConnector\\.connect|_shellConnector\\.connect|shellConnector\\.connect" client/lib/services/launch
git diff --check
~~~

Expected: deleted symbols have no remaining references; only the executor invokes the connector; git diff --check is clean.

- [ ] Step 5: Commit final test/harness updates

~~~bash
git add client/test/integration/codex_config_materialize_launch_integration_test.dart client/test/integration/cli_message_matrix_claude_test.dart client/test/integration/mixed_team_claude_bus_integration_test.dart client/test/integration/mixed_team_claude_idle_busy_integration_test.dart client/test/integration/support/mixed_team_integration_harness.dart docs/superpowers/plans/2026-09-17-session-launch-refactor.md
git commit -m "test(launch): verify unified session connection flow"
~~~

## Final acceptance checklist

- [ ] ChatCubit has one documented launch facade path into SessionLaunchService and SessionLaunchCoordinator.
- [ ] New and existing session opens produce SessionConnectJob values when connection is requested.
- [ ] Member, retry, restore, all-member, and SSH reconnect flows use the same scheduler and executor.
- [ ] Only SessionConnectExecutor calls SessionShellConnector.connect().
- [ ] Only SessionConnectScheduler owns post-frame scheduling and pending de-duplication.
- [ ] Provisional rollback, stale cancellation, launch errors, remote-plane cleanup, and connect-token cleanup are covered by tests.
- [ ] SessionLaunchBundle and SessionLaunchPipeline are deleted.
- [ ] No compatibility adapters or deprecated aliases remain.
- [ ] Analyzer and the full repository test wrapper pass.
