import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

final class _RecordingLifecycle extends NoopCliSessionCapability {
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
}

class _ToolWithLifecycleOverride implements CliToolDefinition {
  const _ToolWithLifecycleOverride(this._inner, this._lifecycle);

  final CliToolDefinition _inner;
  final CliSessionCapability _lifecycle;

  @override
  CliTool get id => _inner.id;

  @override
  bool get isLaunchSupported => _inner.isLaunchSupported;

  @override
  Iterable<CliCapability> get capabilities => [
    for (final cap in _inner.capabilities)
      if (cap is! CliSessionCapability) cap,
    _lifecycle,
  ];
}

CliToolRegistry _registryWithLifecycle(
  CliTool cli,
  CliSessionCapability lifecycle,
) {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  final inner = registry.tryGet(cli);
  expect(inner, isNotNull);
  registry.register(_ToolWithLifecycleOverride(inner!, lifecycle));
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

  test(
    'ensureSessionProfile invokes lifecycle ensurePersisted for cursor',
    () async {
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
    },
  );

  test(
    'ensureSessionProfile forwards additionalDirectories to persist',
    () async {
      const extra = '/workspace/extra';
      await service.ensureSessionProfile(
        'workspace-1',
        'session-1',
        'team-cursor',
        cli: CliTool.cursor,
        team: TeamProfile(
          id: 'team-cursor',
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
        memberId: 'team-lead',
        workingDirectory: '/workspace/cwd',
        additionalDirectories: const [extra],
      );

      expect(recording.lastPersistContext?.workingDirectory, '/workspace/cwd');
      expect(recording.lastPersistContext?.additionalDirectories, [extra]);
    },
  );
}
