import 'package:uuid/uuid.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/session/launch_command_builder.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/storage/app_storage.dart';
import 'identity_cubit_host.dart';
import 'team_resource_sync_service.dart';

typedef TeamLauncher =
    Future<void> Function(TeamIdentity team, TeamMemberConfig member);
typedef CliExecutableResolver = String Function(CliTool cli);

/// Builds launch environments and previews, and drives single-member /
/// whole-team launches. Plugin state is re-synced before each launch.
class TeamLaunchService {
  TeamLaunchService({
    required IdentityCubitHost host,
    required SessionLifecycleService lifecycle,
    required TeamResourceSyncService sync,
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TeamLauncher? launcher,
  }) : _h = host,
       _lifecycle = lifecycle,
       _sync = sync,
       _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _launcher = launcher;

  final IdentityCubitHost _h;
  final SessionLifecycleService _lifecycle;
  final TeamResourceSyncService _sync;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final TeamLauncher? _launcher;

  String _resolveExecutableFor(CliTool cli) {
    return _cliExecutableResolver?.call(cli) ?? _executableResolver();
  }

  Future<Map<String, String>?> _buildLaunchEnvironment(
    TeamIdentity team, {
    TeamMemberConfig? member,
  }) async {
    final plan = await _lifecycle.prepareLaunch(
      session: AppSession(
        sessionId: const Uuid().v4(),
        projectId: '',
        primaryPath: AppStorage.cwd,
        sessionTeam: team.id,
        cliTeamName: team.id,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
      team: team,
      member: member,
    );
    return plan.env.isEmpty ? null : plan.env;
  }

  Future<void> _runLaunch(TeamIdentity team, TeamMemberConfig member) async {
    final env = await _buildLaunchEnvironment(team, member: member);
    final launch =
        _launcher ??
        (t, m) => LaunchCommandBuilder.launch(
          t,
          member: m,
          executable: _resolveExecutableFor(m.cliWithin(t)),
          extraEnvironment: env,
        );
    await launch(team, member);
  }

  String previewFor(TeamMemberConfig member) {
    final team = _h.state.selectedTeam;
    return team == null
        ? ''
        : LaunchCommandBuilder.preview(
            team,
            member,
            executable: _resolveExecutableFor(member.cliWithin(team)),
          );
  }

  String get selectedCommandPreview {
    final team = _h.state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(
      team,
      team.members.first,
      executable: _resolveExecutableFor(team.members.first.cliWithin(team)),
    );
  }

  Future<void> launchMember(String memberId) async {
    final team = _h.state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      _h.applyState(_h.state.copyWith(statusMessage: 'Team name is required.'));
      return;
    }
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) {
      _h.applyState(
        _h.state.copyWith(statusMessage: 'Member name is required.'),
      );
      return;
    }
    _h.applyState(
      _h.state.copyWith(
        isLaunching: true,
        statusMessage: 'Starting ${member.name}...',
      ),
    );
    try {
      await _sync.syncPluginsForSelected();
      await _runLaunch(team, member);
      _h.applyState(
        _h.state.copyWith(
          isLaunching: false,
          statusMessage:
              'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member, executable: _resolveExecutableFor(member.cliWithin(team)))}',
        ),
      );
    } on Object catch (error) {
      _h.applyState(
        _h.state.copyWith(
          isLaunching: false,
          statusMessage: 'Launch failed: $error',
        ),
      );
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = _h.state.selectedTeam;
    if (team == null || team.name.trim().isEmpty) {
      _h.applyState(_h.state.copyWith(statusMessage: 'Team name is required.'));
      return;
    }
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) {
      _h.applyState(
        _h.state.copyWith(
          statusMessage: 'At least one valid member is required.',
        ),
      );
      return;
    }
    _h.applyState(
      _h.state.copyWith(
        isLaunching: true,
        statusMessage: 'Starting ${validMembers.length} members...',
      ),
    );
    try {
      await _sync.syncPluginsForSelected();
      for (final member in validMembers) {
        await _runLaunch(team, member);
      }
      _h.applyState(
        _h.state.copyWith(
          isLaunching: false,
          statusMessage: 'Started ${validMembers.length} members.',
        ),
      );
    } on Object catch (error) {
      _h.applyState(
        _h.state.copyWith(
          isLaunching: false,
          statusMessage: 'Launch failed: $error',
        ),
      );
    }
  }
}
