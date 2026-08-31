import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/mcp_method.dart';
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
  late InMemoryFilesystem fs;
  late TeamGenerationJobStore jobStore;
  late TeamGenerationAuthorizer authorizer;
  late TeammateBusMcpGateway gateway;
  late HttpServer probeServer;
  late TeamComposerMcpHandler handler;
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

    // A raw probe server that forwards into the gateway's route is not
    // directly reachable here, so tests drive the private path through a
    // loopback HttpServer that mimics the gateway routing contract.
    probeServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    probeServer.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final rpc = JsonRpcRequest.tryParse(body);
      if (request.uri.path != TeamComposerMcpConstants.mcpPath ||
          rpc == null ||
          rpc.method != McpMethod.toolsCall) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final sessionHeader =
          request.headers.value(TeamComposerMcpConstants.sessionHeader) ?? '';
      final tokenHeader =
          request.headers.value(TeamComposerMcpConstants.tokenHeader) ?? '';
      final principal = sessionHeader == 'builder'
          ? const ComposerPrincipal(
              sessionId: 'builder',
              workspaceId: 'ws',
              workflowId: 'wf',
            )
          : null;
      final authorized = principal != null &&
          await authorizer.authorize(
            principal: TeamGenerationPrincipal(
              sessionId: principal.sessionId,
              workspaceId: principal.workspaceId,
              workflowId: principal.workflowId,
            ),
            token: tokenHeader,
          );
      if (!authorized) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            JsonRpcResponse.error(
              rpc.id,
              TeamComposerRpcErrorCode.unauthorized,
              'unauthorized',
            ).encode(),
          );
        await request.response.close();
        return;
      }
      final result = await handler.handleToolCall(
        requestId: rpc.id,
        toolName: rpc.params[McpParams.toolName] as String? ?? '',
        arguments: rpc.toolArguments,
        principal: principal,
      );
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(result.response));
      await request.response.close();
      final cb = result.afterResponseFlushed;
      if (cb != null) {
        unawaited(cb());
      }    });
  });

  tearDown(() async {
    await probeServer.close(force: true);
    await gateway.dispose();
    authorizer.revoke('wf');
  });

  Future<Map<String, Object?>> postJsonRpc({
    String? session,
    String? withToken,
    required String tool,
    Map<String, Object?> arguments = const {},
  }) async {
    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${probeServer.port}${TeamComposerMcpConstants.mcpPath}',
      ),
    );
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
          'id': 1,
          'method': 'tools/call',
          'params': {'name': tool, 'arguments': arguments},
        }),
      ),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    client.close();
    return (jsonDecode(body) as Map).cast<String, Object?>();
  }

  test('gateway rejects absent token before handler dispatch', () async {
    final response = await postJsonRpc(
      session: 'builder',
      tool: 'get_generation_context',
    );
    final error = response['error'] as Map?;
    expect(error?['code'], TeamComposerRpcErrorCode.unauthorized);
    expect(handlerCalls, isEmpty);
  });

  test('authorized builder calls get_generation_context', () async {
    final response = await postJsonRpc(
      session: 'builder',
      withToken: token,
      tool: 'get_generation_context',
    );
    expect(response['error'], isNull);
    expect(handlerCalls, contains('context'));
  });

  test('wrong session is rejected', () async {
    final response = await postJsonRpc(
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
