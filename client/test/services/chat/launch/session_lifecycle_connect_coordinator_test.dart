import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_provisioner.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/chat/launch/connect/session_lifecycle_connect_coordinator.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/connect/session_shell_connector.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_transport.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test(
    'ssh launch without binding does not leave Remote projects after overlay rematerialize',
    () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final capturing = _CapturingLifecycle();
      final registry = CliToolRegistry()
        ..register(_LifecycleTool(CliTool.cursor, capturing));
      const profile = SshProfile(
        id: 'home-server',
        name: 'Home',
        host: '192.168.1.8',
        username: 'alice',
      );
      final workspace = Workspace(
        workspaceId: 'ws',
        createdAt: 1,
        injectSessionSshMcp: true,
        folders: const [
          WorkspaceFolder(
            path: '/home/alice/proj',
            targetId: 'ssh:home-server',
          ),
        ],
      );
      expect(workspaceSessionSshMcpEnabled(workspace), isTrue);
      expect(
        shouldInjectSessionSshMcp(
          workspace: workspace,
          launchKind: RuntimeKind.ssh,
          remoteBinding: null,
        ),
        isFalse,
      );

      const member = TeamMemberConfig(id: 'm1', name: 'Member');
      const team = TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.cursor,
        members: [member],
      );
      final session = AppSession(
        sessionId: 'sess',
        workspaceId: workspace.workspaceId,
        sessionTeam: team.id,
        createdAt: 1,
      );
      final extra = composeRuntimeExtraMcpServers(
        extra: const {},
        session: session,
        memberId: member.id,
        cli: CliTool.cursor,
        launchKind: RuntimeKind.ssh,
        cliRegistry: registry,
        catalogEndpoint: Uri.parse('http://127.0.0.1:9/catalog/mcp'),
        composerEndpoint: Uri.parse('http://127.0.0.1:9/team-composer/mcp'),
        isLocalNative: true,
        teamGenerationTokenIssuer: null,
        workspace: workspace,
        sessionSshMcpEndpoint: Uri.parse('http://127.0.0.1:9/ssh/mcp'),
      );
      expect(extra.containsKey(sessionSshMcpServerName), isFalse);

      final host = _Host(
        lifecycle: SessionLifecycleService(
          storage: storage,
          cliToolRegistry: registry,
          sshProfileById: (id) => id == profile.id ? profile : null,
          configProfileService: ConfigProfileService(
            basePath: '/tp',
            home: '/home/test',
            storage: storage,
            fs: fs,
          ),
        ),
        cliRegistry: registry,
        teammateBusMcpGateway: TeammateBusMcpGateway(),
      );
      final coordinator = SessionLifecycleConnectCoordinator(
        host: host,
        launchContextFor: (s) => WorkspaceLaunchContext(
          session: s,
          workspace: workspace,
          usesPosixPaths: true,
        ),
        launchWorkTarget: (s, {String? memberId}) =>
            RuntimeTarget.ssh('home-server', label: 'Home'),
        scheduleMemberConnect:
            (_, _, _, {bool selectMember = false, LaunchReason? reason}) {},
        tabOpen: (_) => true,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
        cliTeamName: 'team',
      )..persistedSession = session;

      const memberHome = '/data/tp/members/m1/cursor/home';
      final layout = CursorHomeLayout(pathContext: fs.pathContext);
      final provisioner = CursorHomeProvisioner(fs: fs);
      const staleInjected = WorkspaceBaseInfoPromptInputs(
        sshMcpInjected: true,
        remoteFolders: [
          WorkspaceRemoteFolderInfo(
            profileId: 'home-server',
            name: 'Home',
            endpoint: 'alice@192.168.1.8:22',
            folderPaths: ['/home/alice/proj'],
          ),
        ],
      );
      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        workspaceBaseInfo: staleInjected,
      );
      expect(
        await fs.readString(layout.roleRule(memberHome)),
        contains('## Remote projects'),
      );

      await coordinator.gateBeforeAttach(
        team: team,
        member: member,
        session: session,
        tab: tab,
        extraMcpServers: extra,
      );

      final inputs = capturing.lastInit!.workspaceBaseInfo;
      expect(inputs.sshMcpInjected, isFalse);

      await provisioner.provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        additionalDirectories: const ['/repo/a'],
        workspaceBaseInfo: inputs,
      );

      final roleRule = await fs.readString(layout.roleRule(memberHome));
      expect(roleRule, contains('## Workspace directories'));
      expect(roleRule, contains('- /repo/a'));
      expect(roleRule, isNot(contains('## Remote projects')));
    },
  );
}

final class _CapturingLifecycle extends NoopCliSessionCapability {
  CliSessionInitContext? lastInit;

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async {
    lastInit = ctx;
    return const CliSessionInitResult();
  }
}

class _LifecycleTool implements CliToolDefinition {
  const _LifecycleTool(this.id, this._lifecycle);

  @override
  final CliTool id;
  final CliSessionCapability _lifecycle;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [_lifecycle];
}

class _Host implements SessionLaunchHost {
  _Host({
    required this.lifecycle,
    required this.cliRegistry,
    required this.teammateBusMcpGateway,
  });

  @override
  final SessionLifecycleService lifecycle;

  @override
  final CliToolRegistry cliRegistry;

  @override
  final TeammateBusMcpGateway teammateBusMcpGateway;

  @override
  bool get isClosed => false;

  @override
  void failSessionConnect(
    String sessionId,
    String rawMessage, {
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
