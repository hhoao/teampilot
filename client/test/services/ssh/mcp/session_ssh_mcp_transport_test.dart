import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/launch/session_shell_connector.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_transport.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';

class _FakeTeamBehavior implements TeamBehaviorCapability {
  const _FakeTeamBehavior({required this.supportsLocalStdioBridge});

  @override
  final bool supportsLocalStdioBridge;
  @override
  bool get supportsNativeTeam => false;
  @override
  bool get longBlockingWaitForMessage => true;
  @override
  Set<String> get doneEventNames => const {};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
  @override
  bool get defaultForceWaitBeforeStop => true;
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}

class _FakeTool implements CliToolDefinition {
  const _FakeTool(this.id, this.capabilities);

  @override
  final CliTool id;
  @override
  bool get isLaunchSupported => true;
  @override
  final Iterable<CliCapability> capabilities;
}

CliToolRegistry _registry({
  required bool supportsBridge,
  required CliTool cli,
}) {
  final registry = CliToolRegistry();
  registry.register(
    _FakeTool(cli, [
      _FakeTeamBehavior(supportsLocalStdioBridge: supportsBridge),
    ]),
  );
  return registry;
}

Workspace _workspace({
  List<WorkspaceFolder> folders = const [],
  bool injectSessionSshMcp = true,
}) => Workspace(
  workspaceId: 'ws',
  createdAt: 1,
  folders: folders,
  injectSessionSshMcp: injectSessionSshMcp,
);

Workspace _mixedLocalSsh({bool injectSessionSshMcp = true}) => _workspace(
  injectSessionSshMcp: injectSessionSshMcp,
  folders: const [
    WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
    WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
  ],
);

Workspace _remoteOnlySsh({bool injectSessionSshMcp = true}) => _workspace(
  injectSessionSshMcp: injectSessionSshMcp,
  folders: const [WorkspaceFolder(path: '/home', targetId: 'ssh:home')],
);

void main() {
  const sessionSshEndpoint = 'http://127.0.0.1:9/ssh/mcp';
  final sessionSshUri = Uri.parse(sessionSshEndpoint);

  Map<String, Object?> resolve({
    required bool supportsBridge,
    CliTool cli = CliTool.claude,
    String? Function()? bridgeLocator,
    bool isLocalNative = true,
    RemoteBusBinding? remoteBinding,
  }) => resolveSessionSshMcpTransportConfig(
    cliRegistry: _registry(supportsBridge: supportsBridge, cli: cli),
    sessionSshMcpEndpoint: sessionSshUri,
    sessionId: 'sess-1',
    memberId: 'member-1',
    cli: cli,
    isLocalNative: isLocalNative,
    bridgeLocator: bridgeLocator,
    remoteBinding: remoteBinding,
  );

  Map<String, Map<String, Object?>> compose({
    Workspace? workspace,
    Uri? sessionSshMcpEndpoint,
    RuntimeKind launchKind = RuntimeKind.local,
    RemoteBusBinding? mixedRemoteBinding,
    MemberAgentStatusEndpoint? agentStatus,
  }) => composeRuntimeExtraMcpServers(
    extra: const {},
    session: AppSession(sessionId: 'sess-1', workspaceId: 'ws', createdAt: 1),
    memberId: 'member-1',
    cli: CliTool.claude,
    launchKind: launchKind,
    cliRegistry: _registry(supportsBridge: false, cli: CliTool.claude),
    catalogEndpoint: Uri.parse('http://127.0.0.1:9/catalog/mcp'),
    composerEndpoint: Uri.parse('http://127.0.0.1:9/team-composer/mcp'),
    isLocalNative: true,
    teamGenerationTokenIssuer: null,
    mixedRemoteBinding: mixedRemoteBinding,
    agentStatus: agentStatus,
    workspace: workspace,
    sessionSshMcpEndpoint: sessionSshMcpEndpoint,
  );

  test(
    'shouldInject is true for mixed local + ssh:home with default toggle and local launch',
    () {
      expect(
        shouldInjectSessionSshMcp(
          workspace: _mixedLocalSsh(),
          launchKind: RuntimeKind.local,
        ),
        isTrue,
      );
    },
  );

  test('shouldInject is false for local-only workspace', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _workspace(
          folders: const [
            WorkspaceFolder(
              path: '/local',
              targetId: WorkspaceFolder.localTargetId,
            ),
          ],
        ),
        launchKind: RuntimeKind.local,
      ),
      isFalse,
    );
  });

  test('shouldInject is true for remote-only ssh folders', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _remoteOnlySsh(),
        launchKind: RuntimeKind.local,
      ),
      isTrue,
    );
  });

  test('shouldInject is false when SSH launch has no remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.ssh,
      ),
      isFalse,
    );
  });

  test('shouldInject is true when SSH launch has remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.ssh,
        remoteBinding: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: 18080,
        ),
      ),
      isTrue,
    );
  });

  test('shouldInject is true for termux launch with remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.termux,
        remoteBinding: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: 18080,
        ),
      ),
      isTrue,
    );
  });

  test('shouldInject is false when injectSessionSshMcp is false', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(injectSessionSshMcp: false),
        launchKind: RuntimeKind.local,
      ),
      isFalse,
    );
  });

  test('shouldInject is false for mixed local + wsl without ssh folder', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _workspace(
          folders: const [
            WorkspaceFolder(
              path: '/local',
              targetId: WorkspaceFolder.localTargetId,
            ),
            WorkspaceFolder(path: '/wsl', targetId: 'wsl:ubuntu'),
          ],
        ),
        launchKind: RuntimeKind.local,
      ),
      isFalse,
    );
  });

  test('shouldInject is true for mixed wsl + ssh with WSL launch', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _workspace(
          folders: const [
            WorkspaceFolder(path: '/wsl', targetId: 'wsl:ubuntu'),
            WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
          ],
        ),
        launchKind: RuntimeKind.wsl,
      ),
      isTrue,
    );
  });

  test('shouldInject is true for mixed local + ssh with WSL launch', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.wsl,
      ),
      isTrue,
    );
  });

  test('local HTTP fallback when bridge locator returns null', () {
    final cfg = resolve(supportsBridge: true, bridgeLocator: () => null);

    expect(cfg['type'], 'http');
    expect(cfg['url'], sessionSshEndpoint);
    expect(cfg['command'], isNull);
    final headers = cfg['headers'] as Map;
    expect(headers[teammateBusMcpSessionHeader], 'sess-1');
    expect(headers[teammateBusMcpMemberHeader], 'member-1');
    expect(headers.containsKey(teammateBusTokenHeader), isFalse);
  });

  test(
    'local stdio uses teammate_bus_bridge with --bus-url as full ssh MCP URL',
    () {
      const bridgePath = '/opt/teampilot/teammate_bus_bridge';
      final cfg = resolve(
        supportsBridge: true,
        bridgeLocator: () => bridgePath,
      );

      expect(
        cfg,
        teammateBusMcpServerConfigStdio(
          bridgePath: bridgePath,
          endpoint: sessionSshUri,
          memberId: 'member-1',
          sessionId: 'sess-1',
        ),
      );
      expect(cfg['args'], containsAllInOrder(['--bus-url', sessionSshEndpoint]));
    },
  );

  test(
    'non-native home plane stays HTTP even when locator returns a path',
    () {
      final cfg = resolve(
        supportsBridge: true,
        isLocalNative: false,
        bridgeLocator: () => '/opt/teampilot/teammate_bus_bridge',
      );

      expect(cfg['type'], 'http');
      expect(cfg['url'], sessionSshEndpoint);
      expect(cfg['command'], isNull);
    },
  );

  test(
    'remote uses idle HTTP port + /ssh/mcp + token, never stdio',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
        mcpRawTunnelPort: 19090,
        mcpRelayArgv: ['/usr/bin/teammate_bus_relay', '--port', '19090'],
      );
      final cfg = resolve(
        supportsBridge: true,
        remoteBinding: remote,
        bridgeLocator: () => '/opt/teampilot/teammate_bus_bridge',
      );

      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:18080$sessionSshMcpPath');
      expect(cfg['command'], isNull);
      expect(cfg['args'], isNull);
      final headers = cfg['headers'] as Map;
      expect(headers[teammateBusMcpSessionHeader], 'sess-1');
      expect(headers[teammateBusMcpMemberHeader], 'member-1');
      expect(headers[teammateBusTokenHeader], 'bus-tok');
    },
  );

  test('extraMcpServersWithSessionSsh adds key ssh', () {
    final extra = <String, Map<String, Object?>>{
      catalogMcpServerName: teammateBusMcpServerConfig(
        endpoint: Uri.parse('http://127.0.0.1:9/catalog/mcp'),
        memberId: 'member-1',
        sessionId: 'sess-1',
      ),
    };
    final config = resolve(supportsBridge: false, bridgeLocator: () => null);

    final merged = extraMcpServersWithSessionSsh(extra: extra, config: config);

    expect(merged.keys, containsAll([catalogMcpServerName, sessionSshMcpServerName]));
    expect(merged[sessionSshMcpServerName], config);
    expect(merged[catalogMcpServerName], extra[catalogMcpServerName]);
    expect(sessionSshMcpServerName, 'ssh');
  });

  test(
    'composeRuntimeExtraMcpServers injects ssh for mixed workspace and endpoint',
    () {
      final merged = compose(
        workspace: _mixedLocalSsh(),
        sessionSshMcpEndpoint: sessionSshUri,
      );

      expect(merged.keys, containsAll([catalogMcpServerName, sessionSshMcpServerName]));
      expect(merged[sessionSshMcpServerName]?['url'], sessionSshEndpoint);
    },
  );

  test(
    'composeRuntimeExtraMcpServers omits ssh without workspace',
    () {
      final merged = compose(sessionSshMcpEndpoint: sessionSshUri);

      expect(merged.containsKey(sessionSshMcpServerName), isFalse);
      expect(merged, contains(catalogMcpServerName));
    },
  );

  test(
    'composeRuntimeExtraMcpServers omits ssh when endpoint is null',
    () {
      final merged = compose(workspace: _mixedLocalSsh());

      expect(merged.containsKey(sessionSshMcpServerName), isFalse);
      expect(merged, contains(catalogMcpServerName));
    },
  );

  test(
    'composeRuntimeExtraMcpServers omits ssh when injectSessionSshMcp is false',
    () {
      final merged = compose(
        workspace: _mixedLocalSsh(injectSessionSshMcp: false),
        sessionSshMcpEndpoint: sessionSshUri,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isFalse);
      expect(merged, contains(catalogMcpServerName));
    },
  );

  test(
    'composeRuntimeExtraMcpServers omits ssh when launchKind is ssh',
    () {
      final merged = compose(
        workspace: _mixedLocalSsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isFalse);
    },
  );

  test(
    'compose injects ssh tunnel URL for SSH launch with remoteBinding',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
      );
      final merged = compose(
        workspace: _mixedLocalSsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
        mixedRemoteBinding: remote,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isTrue);
      expect(
        merged[sessionSshMcpServerName]?['url'],
        'http://127.0.0.1:18080$sessionSshMcpPath',
      );
      final headers = merged[sessionSshMcpServerName]?['headers'] as Map;
      expect(headers[teammateBusTokenHeader], 'bus-tok');
      expect(headers[teammateBusMcpSessionHeader], 'sess-1');
      expect(headers[teammateBusMcpMemberHeader], 'member-1');
    },
  );

  test(
    'compose injects ssh for remote-only workspace on local launch',
    () {
      final merged = compose(
        workspace: _remoteOnlySsh(),
        sessionSshMcpEndpoint: sessionSshUri,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isTrue);
      expect(merged[sessionSshMcpServerName]?['url'], sessionSshEndpoint);
    },
  );

  test(
    'compose injects ssh tunnel URL for remote-only workspace on SSH launch',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
      );
      final merged = compose(
        workspace: _remoteOnlySsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
        mixedRemoteBinding: remote,
      );

      expect(
        merged[sessionSshMcpServerName]?['url'],
        'http://127.0.0.1:18080$sessionSshMcpPath',
      );
    },
  );

  test(
    'compose injects ssh tunnel URL from agentStatus when mixedRemoteBinding is null',
    () {
      const agentStatus = MemberAgentStatusEndpoint(
        url: 'http://127.0.0.1:18080/agent-status',
        token: 'status-tok',
      );
      final merged = compose(
        workspace: _remoteOnlySsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
        agentStatus: agentStatus,
      );

      expect(
        merged[sessionSshMcpServerName]?['url'],
        'http://127.0.0.1:18080$sessionSshMcpPath',
      );
      final headers = merged[sessionSshMcpServerName]?['headers'] as Map;
      expect(headers[teammateBusTokenHeader], 'status-tok');
    },
  );

  test(
    'compose local launch ignores mixedRemoteBinding and keeps gateway URL',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
      );
      final merged = compose(
        workspace: _mixedLocalSsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.local,
        mixedRemoteBinding: remote,
      );

      expect(merged[sessionSshMcpServerName]?['url'], sessionSshEndpoint);
      final headers = merged[sessionSshMcpServerName]?['headers'] as Map?;
      expect(headers?[teammateBusTokenHeader], isNull);
    },
  );

  test('workspaceSessionSshMcpEnabled is true for remote-only ssh folders', () {
    expect(workspaceSessionSshMcpEnabled(_remoteOnlySsh()), isTrue);
  });

  test('workspaceHasSshMcpFolder is false for local-only', () {
    expect(
      workspaceHasSshMcpFolder(
        _workspace(
          folders: const [
            WorkspaceFolder(
              path: '/local',
              targetId: WorkspaceFolder.localTargetId,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
}
