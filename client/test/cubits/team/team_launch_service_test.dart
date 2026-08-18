import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/team/launch_profile_cubit_host.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/cubits/team/team_launch_service.dart';
import 'package:teampilot/cubits/team/team_profile_provisioner.dart';
import 'package:teampilot/cubits/team/team_resource_sync_service.dart';
import 'package:teampilot/models/launch_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/mcp/profile_mcp_linker_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

void main() {
  test(
    'launchMember forwards additional directories to the launch environment',
    () async {
      const team = TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.opencode,
        teamMode: TeamMode.mixed,
        members: [TeamMemberConfig(id: 'member', name: 'Member')],
      );
      final host = _RecordingHost(
        LaunchProfileState(
          identities: const <LaunchProfile>[team],
          selectedTeamId: team.id,
          isLoading: false,
        ),
      );
      final lifecycle = _RecordingLifecycleService();
      final sync = TeamResourceSyncService(
        host: host,
        provisioner: TeamProfileProvisioner(),
        mcpLinker: ProfileMcpLinkerService(),
        pluginRepository: PluginRepository(),
        mcpRepository: McpRepository(),
        installedPluginsLoader: () async => const [],
        installedMcpLoader: () async => const [],
        extensionMcpContributor: (_) async => const [],
      );
      final service = TeamLaunchService(
        host: host,
        lifecycle: lifecycle,
        sync: sync,
        executableResolver: () => 'opencode',
        launcher: (_, _) async {},
      );

      await service.launchMember(
        team.members.single.id,
        workingDirectory: '/workspace/main',
        additionalDirectories: const [
          '/workspace/shared-a',
          '/workspace/shared-b',
        ],
      );

      expect(lifecycle.additionalDirectories, [
        '/workspace/shared-a',
        '/workspace/shared-b',
      ]);
    },
  );
}

final class _RecordingHost implements LaunchProfileCubitHost {
  _RecordingHost(this.state);

  @override
  LaunchProfileState state;

  @override
  bool get isClosed => false;

  @override
  void applyState(LaunchProfileState next) => state = next;

  @override
  Future<void> saveTeamProfiles(List<TeamProfile> teams) async {}
}

final class _RecordingLifecycleService extends SessionLifecycleService {
  List<String>? additionalDirectories;

  @override
  Future<TeamLaunchOutcome> prepareTeamLaunchEnvironment({
    required TeamProfile team,
    TeamMemberConfig? member,
    String workspaceId = '',
    String sessionId = '',
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
  }) async {
    this.additionalDirectories = List<String>.from(additionalDirectories);
    return const TeamLaunchOutcome(environment: {});
  }
}
