import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/utils/team_member_naming.dart';

class _RecordingLifecycle implements CliSessionLifecycleCapability {
  var ensurePersistedCalls = 0;
  CliSessionPersistContext? lastPersistContext;

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async {
    ensurePersistedCalls++;
    lastPersistContext = ctx;
    return const CliSessionPersistResult();
  }

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async =>
      const CliSessionInitResult();

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) =>
      const CliSessionGateDecision(allowed: true);
}

class _ToolWithExtraCapability implements CliToolDefinition {
  const _ToolWithExtraCapability(this._inner, this._extra);

  final CliToolDefinition _inner;
  final CliCapability _extra;

  @override
  CliTool get id => _inner.id;

  @override
  bool get isLaunchSupported => _inner.isLaunchSupported;

  @override
  Iterable<CliCapability> get capabilities => [
    ..._inner.capabilities,
    _extra,
  ];
}

CliToolRegistry _registryWithLifecycle(
  CliTool cli,
  CliSessionLifecycleCapability lifecycle,
) {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  final inner = registry.tryGet(cli);
  expect(inner, isNotNull);
  registry.register(_ToolWithExtraCapability(inner!, lifecycle));
  return registry;
}

void main() {
  late Directory base;
  late _RecordingLifecycle recording;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_lifecycle_');
    recording = _RecordingLifecycle();
    final fs = LocalFilesystem();
    service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      hostEnvironment: HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      ),
      cliRegistry: _registryWithLifecycle(CliTool.cursor, recording),
    );
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
  });

  test('ensureSessionProfile invokes lifecycle ensurePersisted for cursor', () async {
    const workspaceId = 'workspace-1';
    const sessionId = 'session-1';
    const teamId = 'team-cursor';
    const memberId = 'team-lead';

    await service.ensureSessionProfile(
      workspaceId,
      sessionId,
      teamId,
      cli: CliTool.cursor,
      team: TeamProfile(
        id: teamId,
        name: 'Cursor Team',
        cli: CliTool.cursor,
        teamMode: TeamMode.mixed,
        members: const [
          TeamMemberConfig(
            id: TeamMemberNaming.teamLeadName,
            name: 'Team Lead',
          ),
        ],
      ),
      memberId: memberId,
    );

    expect(recording.ensurePersistedCalls, 1);
    expect(recording.lastPersistContext?.workspaceId, workspaceId);
    expect(recording.lastPersistContext?.sessionId, sessionId);
    expect(recording.lastPersistContext?.memberId, memberId);
    expect(recording.lastPersistContext?.tool, CliTool.cursor);
  });
}
