import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/chat/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/chat/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/chat/team_generation/team_generation_cleanup_service.dart';
import 'package:teampilot/services/chat/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/chat/team_generation/team_generation_session_port.dart';

import '../../support/in_memory_filesystem.dart';

class _FakePort implements TeamGenerationSessionPort {
  final deletedSessions = <String>[];
  final knownSessions = <String>{'builder'};
  var activityStreamOpened = false;

  @override
  Future<SessionPortOpenResult> createBuilder({
    required Workspace workspace,
    required SimpleLaunchIdentity identity,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String workflowId,
    required String fixedSessionId,
    required String expertKey,
    String emptyDisplayTitleFallback = 'Team Builder',
    bool preserveWorkbenchView = true,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> open(String sessionId) async =>
      const SessionPortOpenResult(status: 'opened');

  @override
  Future<void> select(String sessionId) async {}

  @override
  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt,
  ) async {}

  @override
  Future<AppSession?> sessionById(String sessionId) async =>
      knownSessions.contains(sessionId)
      ? AppSession(sessionId: sessionId, workspaceId: 'ws', createdAt: 1)
      : null;

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {}

  @override
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  }) async {}

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async => const PortDeliveryOutcome(result: 'submitted');

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async {
    deletedSessions.add(sessionId);
    knownSessions.remove(sessionId);
    return true;
  }

  final _controllers = <String, StreamController<PortActivity>>{};

  void emit(String sessionId, bool ready) {
    _controllers
        .putIfAbsent(sessionId, StreamController<PortActivity>.broadcast)
        .add(PortActivity(sessionId: sessionId, readyToChat: ready));
  }

  @override
  Stream<PortActivity> activityStream(String sessionId) {
    activityStreamOpened = true;
    return _controllers
        .putIfAbsent(sessionId, StreamController<PortActivity>.broadcast)
        .stream;
  }
}

void main() {
  late InMemoryFilesystem fs;
  late TeamGenerationJobStore store;
  late _FakePort port;
  final revoked = <String>[];

  TeamGenerationCleanupService service() => TeamGenerationCleanupService(
    jobStore: store,
    sessionPort: port,
    revokeToken: revoked.add,
  );

  Future<void> seedJob({
    required Map<String, TeamGenerationReceipt> receipts,
    TeamGenerationPhase phase = TeamGenerationPhase.delivered,
    String workflowId = 'wf',
    bool retainBuilderSession = false,
  }) async {
    final settings = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        teamMode: TeamMode.mixed,
        retainBuilderSession: retainBuilderSession,
      ),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    await store.create(
      workspaceId: 'ws',
      workflowId: workflowId,
      builderSessionId: 'builder',
      originalPrompt: 'task',
      generator: TeamGenerationJobGenerator.fromSettings(settings),
      settings: settings,
      launch: const TeamGenerationLaunchSnapshot(
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        folderIds: [],
        targetIds: ['local'],
        workspaceRevision: 'rev-1',
        capturedAt: 1000,
      ),
    );
    await store.mutate('ws', workflowId, (job) {
      return job.copyWith(
        phase: phase,
        destinationSessionId: 'dest',
        receipts: receipts,
      );
    });
  }

  setUp(() {
    fs = InMemoryFilesystem();
    store = TeamGenerationJobStore(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );
    port = _FakePort();
    revoked.clear();
  });

  test('does not delete before both handoff gates are durable', () async {
    final allReceipts = {
      'promptDeliveryDelivered': const TeamGenerationReceipt(
        state: TeamGenerationReceiptState.succeeded,
      ),
      'finalizeResponseFlushed': const TeamGenerationReceipt(
        state: TeamGenerationReceiptState.succeeded,
      ),
    };

    var n = 0;
    for (final missing in [
      'promptDeliveryDelivered',
      'finalizeResponseFlushed',
    ]) {
      n++;
      final receipts = <String, TeamGenerationReceipt>{...allReceipts}
        ..remove(missing);
      await seedJob(receipts: receipts, workflowId: 'wf-$n');
      final result = await service().cleanup(
        workspaceId: 'ws',
        workflowId: 'wf-$n',
      );
      expect(result, TeamGenerationCleanupResult.deferred);
      expect(port.deletedSessions, isEmpty);
    }
  });

  test('deletes builder, revokes token, and compacts job once gated', () async {
    await seedJob(
      receipts: {
        'promptDeliveryDelivered': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
        'finalizeResponseFlushed': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
      },
    );

    final result = await service().cleanup(workspaceId: 'ws', workflowId: 'wf');

    expect(result, TeamGenerationCleanupResult.cleaned);
    expect(port.deletedSessions, ['builder']);
    expect(revoked, ['wf']);
    final job = await store.read('ws', 'wf');
    expect(job!.phase, TeamGenerationPhase.complete);
    expect(job.originalPrompt, isEmpty);
    expect(job.stagedResources, isEmpty);
    expect(job.probeSnapshotJson, isNull);
  });

  test('retention mode keeps Builder without waiting for idle', () async {
    await seedJob(
      receipts: {
        'promptDeliveryDelivered': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
        'finalizeResponseFlushed': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
      },
      retainBuilderSession: true,
    );

    final result = await service().cleanup(workspaceId: 'ws', workflowId: 'wf');

    expect(result, TeamGenerationCleanupResult.cleaned);
    expect(port.deletedSessions, isEmpty);
    expect(port.activityStreamOpened, isFalse);
    expect(revoked, ['wf']);
    final job = await store.read('ws', 'wf');
    expect(job!.phase, TeamGenerationPhase.complete);
    expect(
      job.receipts['builderRetained']!.state,
      TeamGenerationReceiptState.succeeded,
    );
  });

  test('deletes immediately after durable handoff receipts', () async {
    await seedJob(
      receipts: {
        'promptDeliveryDelivered': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
        'finalizeResponseFlushed': const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
        ),
      },
    );

    final result = await service().cleanup(workspaceId: 'ws', workflowId: 'wf');

    expect(result, TeamGenerationCleanupResult.cleaned);
    expect(port.deletedSessions, ['builder']);
    expect(port.activityStreamOpened, isFalse);
    expect(revoked, ['wf']);
    final job = await store.read('ws', 'wf');
    expect(job!.phase, TeamGenerationPhase.complete);
  });
}
