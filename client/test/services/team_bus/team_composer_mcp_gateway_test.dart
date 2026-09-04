import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_handler.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_authorizer.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';

import '../../support/in_memory_filesystem.dart';

class _StaticSessionLookup implements TeamGenerationSessionLookup {
  @override
  Future<AppSession?> findById(String sessionId) async => AppSession(
        sessionId: sessionId,
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late InMemoryFilesystem fs;
  late TeamGenerationJobStore jobStore;
  late TeamGenerationAuthorizer authorizer;
  late TeammateBusMcpGateway gateway;
  late TeamComposerMcpHandler handler;
  late HttpClient client;
  late String token;
  final handlerCalls = <String>[];

  setUp(() async {
    fs = InMemoryFilesystem();
    jobStore = TeamGenerationJobStore(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
      clock: () => DateTime.utc(2026, 8, 31),
    );
    final settings = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    await jobStore.create(
      workspaceId: 'ws',
      workflowId: 'wf',
      builderSessionId: 'builder',
      originalPrompt: 'task',
      generator: TeamGenerationJobGenerator.fromSettings(settings),
      settings: settings,
      launch: const TeamGenerationLaunchSnapshot(
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        launchSecurityPolicyValue: 'fullAccess',
        folderIds: [],
        targetIds: ['local'],
        workspaceRevision: 'rev-1',
        capturedAt: 1000,
      ),
    );
    authorizer = TeamGenerationAuthorizer(
      sessionLookup: _StaticSessionLookup(),
      jobStore: jobStore,
      tokenFactory: () => 'token-1',
    );
    handlerCalls.clear();
    handler = TeamComposerMcpHandler(
      context: TeamComposerHandlerContext(
        jobStore: jobStore,
        executor: TeamGenerationWorkflowExecutor(),
        contextProvider: (job) async {
          handlerCalls.add('context');
          return {'originalPrompt': job.originalPrompt};
        },
        probeRunner: (job) async {
          handlerCalls.add('probe');
          return {'targets': const []};
        },
        planValidator: (job, plan) async {
          handlerCalls.add('validate');
          return const PlanValidationOutcome(
            valid: true,
            issues: [],
            normalizedPlan: {},
            revision: 'rev',
          );
        },
        finalizer: (job, key) async {
          handlerCalls.add('finalize-run');
        },
      ),
    );

    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachTeamComposerHandler(handler: handler, authorizer: authorizer);
    gateway.setTeamComposerPrincipalResolver(
      (sessionId) async => sessionId == 'builder'
          ? const ComposerPrincipal(
              sessionId: 'builder',
              workspaceId: 'ws',
              workflowId: 'wf',
            )
          : null,
    );
    token = await authorizer.issue(
      const TeamGenerationPrincipal(
        sessionId: 'builder',
        workspaceId: 'ws',
        workflowId: 'wf',
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.dispose();
    authorizer.revoke('wf');
  });

  Future<Map<String, Object?>> postJsonRpc({
    String? session,
    String? withToken,
    required String method,
    Map<String, Object?> params = const {},
    Object? id = 1,
  }) async {
    final request = await client.postUrl(gateway.teamComposerMcpEndpoint);
    if (session != null) {
      request.headers.set(TeamComposerMcpConstants.sessionHeader, session);
    }
    if (withToken != null) {
      request.headers.set(TeamComposerMcpConstants.tokenHeader, withToken);
    }
    request.add(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          if (id != null) 'id': id,
          'method': method,
          'params': params,
        }),
      ),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (body.isEmpty) return const {};
    return (jsonDecode(body) as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> callTool({
    String? session,
    String? withToken,
    required String tool,
    Map<String, Object?> arguments = const {},
  }) =>
      postJsonRpc(
        session: session,
        withToken: withToken,
        method: 'tools/call',
        params: {'name': tool, 'arguments': arguments},
      );

  test('initialize succeeds without workflow token', () async {
    final response = await postJsonRpc(
      method: 'initialize',
      params: {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'cursor', 'version': '1'},
      },
    );
    expect(response['error'], isNull);
    final result = response['result'] as Map?;
    expect(result?['serverInfo'], isA<Map>());
    expect((result?['serverInfo'] as Map?)?['name'], 'team-composer');
    expect(handlerCalls, isEmpty);
  });

  test('tools/list advertises four composer tools without token', () async {
    final response = await postJsonRpc(method: 'tools/list');
    expect(response['error'], isNull);
    final tools = (response['result'] as Map?)?['tools'] as List? ?? const [];
    expect(
      tools.map((t) => (t as Map)['name']).toSet(),
      TeamComposerToolName.all.toSet(),
    );
    final validate = tools.cast<Map>().firstWhere(
      (tool) => tool['name'] == TeamComposerToolName.validatePlan,
    );
    expect(validate['outputSchema'], isA<Map>());
    expect(validate['annotations'], isA<Map>());
    expect(
      ((validate['inputSchema'] as Map)['properties'] as Map)['plan'],
      isA<Map>(),
    );
  });

  test('gateway rejects absent token before handler dispatch', () async {
    final response = await callTool(
      session: 'builder',
      tool: 'get_generation_context',
    );
    final error = response['error'] as Map?;
    expect(error?['code'], TeamComposerRpcErrorCode.unauthorized);
    expect(handlerCalls, isEmpty);
  });

  test('authorized builder calls get_generation_context', () async {
    final response = await callTool(
      session: 'builder',
      withToken: token,
      tool: 'get_generation_context',
    );
    expect(response['error'], isNull);
    expect(handlerCalls, contains('context'));
  });

  test('wrong session is rejected', () async {
    final response = await callTool(
      session: 'normal',
      withToken: token,
      tool: 'get_generation_context',
    );
    final error = response['error'] as Map?;
    expect(error?['code'], TeamComposerRpcErrorCode.unauthorized);
    expect(handlerCalls, isEmpty);
  });

  test('schemas restrict to four composer tools', () {
    expect(
      handler.toolSchemas().keys.toSet(),
      TeamComposerToolName.all.toSet(),
    );
  });
}
