import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/team_generation_graph.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/launch/session_shell_connector.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_handler.dart';
import 'package:teampilot/services/team_generation/providers/managed_team_builder_skill_provider.dart';
import 'package:teampilot/services/team_generation/team_generation_authorizer.dart';
import 'package:teampilot/services/team_generation/team_generation_coordinator.dart';
import 'package:teampilot/services/team_generation/team_generation_recovery_service.dart';
import 'package:teampilot/services/team_generation/catalog/catalog_generation_stager.dart';

import '../support/post_frame_test_harness.dart';

class _TargetRegistry extends Fake implements RuntimeTargetRegistry {}

class _RemoteCliReadiness extends Fake implements RemoteCliReadinessService {}

class _RecordingRecovery implements TeamGenerationRecoveryPort {
  _RecordingRecovery({this.error});

  final Object? error;
  final workspaceIds = <String>[];

  @override
  Future<void> recoverAll(Iterable<String> workspaceIds) async {
    this.workspaceIds.addAll(workspaceIds);
    if (error != null) throw error!;
  }

  @override
  Future<void> recoverWorkspace(String workspaceId) async {
    workspaceIds.add(workspaceId);
  }
}

class _RecordingBootstrapPort {
  int tokenIssuerAttachments = 0;
  int resourceResolverAttachments = 0;
  int composerHandlerAttachments = 0;
  int principalResolverAttachments = 0;
  int catalogStagerAttachments = 0;
  String? Function(AppSession session)? tokenIssuer;
  SessionResourceProviderResolver? resourceProviderResolver;
  TeamComposerMcpHandler? composerHandler;
  TeamGenerationAuthorizer? authorizer;
  TeamComposerPrincipalFactory? principalResolver;
  CatalogGenerationStager? catalogStager;

  TeamGenerationGraphBootstrapPort get port => TeamGenerationGraphBootstrapPort(
    setTokenIssuer: (issuer) {
      tokenIssuerAttachments++;
      tokenIssuer = issuer;
    },
    attachResourceProviderResolver: (resolver) {
      resourceResolverAttachments++;
      resourceProviderResolver = resolver;
    },
    attachComposerHandler: ({required handler, required authorizer}) {
      composerHandlerAttachments++;
      composerHandler = handler;
      this.authorizer = authorizer;
    },
    setComposerPrincipalResolver: (resolver) {
      principalResolverAttachments++;
      principalResolver = resolver;
    },
    attachCatalogGenerationStager: (stager) {
      catalogStagerAttachments++;
      catalogStager = stager;
    },
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'bootstrap exposes one graph-owned coordinator and attaches builder-only wiring once',
    () {
      final chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );
      final workbench = WorkbenchCubit();
      final sessionRepository = SessionRepository(rootDir: '/team-generation');
      final profileRepository = LaunchProfileRepository(
        rootDir: '/team-generation-profiles',
      );
      final teamCubit = LaunchProfileCubit(
        repository: profileRepository,
        sessionRepository: sessionRepository,
        executableResolver: () => 'true',
      );
      addTearDown(chat.close);
      addTearDown(workbench.close);
      addTearDown(teamCubit.close);

      final graph = buildTeamGenerationGraph(
        chatCubit: chat,
        workbenchCubit: workbench,
        teamCubit: teamCubit,
        sessionRepo: sessionRepository,
        identityRepository: profileRepository,
        cliToolRegistry: CliToolRegistry.builtIn(),
        targetRegistry: _TargetRegistry(),
        remoteCliReadiness: _RemoteCliReadiness(),
      );
      final recording = _RecordingBootstrapPort();
      final bootstrap = TeamGenerationGraphBootstrap(
        graph: graph,
        port: recording.port,
        principalResolver: (_) async => null,
      );

      bootstrap.attach();
      bootstrap.attach();

      expect(bootstrap.coordinator, same(graph.coordinator));
      expect(recording.tokenIssuerAttachments, 1);
      expect(recording.resourceResolverAttachments, 1);
      expect(recording.composerHandlerAttachments, 1);
      expect(recording.composerHandler, same(graph.composerHandler));
      expect(recording.authorizer, same(graph.authorizer));
      expect(recording.principalResolverAttachments, 1);
      expect(recording.catalogStagerAttachments, 1);
      expect(recording.catalogStager, same(graph.catalogStager));

      final builder = AppSession(
        sessionId: 'builder',
        workspaceId: 'workspace',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'workflow',
        createdAt: 1,
      );
      final simple = AppSession(
        sessionId: 'simple',
        workspaceId: 'workspace',
        createdAt: 1,
      );
      final team = AppSession(
        sessionId: 'team',
        workspaceId: 'workspace',
        sessionTeam: 'team-id',
        createdAt: 1,
      );
      final resolver = recording.resourceProviderResolver!;

      expect(
        resolver(builder, ResourceProviderSet.empty).skills.single.providerId,
        ManagedTeamBuilderSkillProvider.skillId,
      );
      expect(resolver(simple, ResourceProviderSet.empty).skills, isEmpty);
      expect(resolver(team, ResourceProviderSet.empty).skills, isEmpty);

      var builderTokenRequests = 0;
      final access = issueTeamGenerationMcpAccess(
        session: builder,
        tokenIssuer: (session) {
          builderTokenRequests++;
          return recording.tokenIssuer!(session);
        },
      );
      expect(builderTokenRequests, 1);
      expect(access!.catalogToken, access.composerToken);
      expect(access.catalogToken, isNotEmpty);
      expect(
        issueTeamGenerationMcpAccess(
          session: simple,
          tokenIssuer: recording.tokenIssuer!,
        ),
        isNull,
      );
      expect(
        issueTeamGenerationMcpAccess(
          session: team,
          tokenIssuer: recording.tokenIssuer!,
        ),
        isNull,
      );
    },
  );

  test('bootstrap recovery scans discovered workspaces once ready', () async {
    final recovery = _RecordingRecovery();
    final discovery = Completer<Iterable<String>>();

    final running = runTeamGenerationBootstrapRecovery(
      recovery: recovery,
      workspaceIdsAfterDiscovery: discovery.future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(recovery.workspaceIds, isEmpty);

    discovery.complete(const ['ws-a', 'ws-b']);
    await running;

    expect(recovery.workspaceIds, ['ws-a', 'ws-b']);
  });

  test(
    'bootstrap recovery reports failures through startup diagnostics',
    () async {
      final failure = StateError('recovery failed');
      Object? loggedError;
      StackTrace? loggedStackTrace;

      await runTeamGenerationBootstrapRecovery(
        recovery: _RecordingRecovery(error: failure),
        workspaceIdsAfterDiscovery: Future.value(const ['ws']),
        diagnosticLogger: (error, stackTrace) {
          loggedError = error;
          loggedStackTrace = stackTrace;
        },
      );

      expect(loggedError, same(failure));
      expect(loggedStackTrace, isNotNull);
    },
  );
}
