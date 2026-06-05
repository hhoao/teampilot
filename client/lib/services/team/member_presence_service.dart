import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/registry/built_in_cli_tools.dart';
import '../cli/registry/capabilities/presence_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../terminal/terminal_session.dart';
import 'claude_roster_activity_source.dart';

/// Aggregates terminal connection + per-CLI workload into [MemberPresence].
class MemberPresenceService {
  MemberPresenceService({
    Filesystem? fs,
    ClaudeRosterActivitySource? claudeRoster,
    CliToolRegistry? cliToolRegistry,
  }) : fs = fs ?? AppStorage.fs,
       _claudeRoster =
           claudeRoster ?? ClaudeRosterActivitySource(fs: fs ?? AppStorage.fs),
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry;

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  final Filesystem fs;
  final ClaudeRosterActivitySource _claudeRoster;
  final CliToolRegistry _cliToolRegistry;

  Future<Map<String, MemberPresence>> compute({
    required CliTool teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
  }) async {
    final valid = members.where((m) => m.isValid).toList();
    if (valid.isEmpty) return const {};

    final presenceCap =
        _cliToolRegistry.capability<PresenceCapability>(teamCli);
    var claudeWorking = const <String, bool>{};
    if ((presenceCap?.usesClaudeRoster ?? false) &&
        memberToolConfigDir != null &&
        memberToolConfigDir.trim().isNotEmpty &&
        cliTeamName.trim().isNotEmpty) {
      claudeWorking = await _claudeRoster.readMemberWorking(
        claudeConfigDir: memberToolConfigDir.trim(),
        cliTeamName: cliTeamName.trim(),
      );
    }

    final out = <String, MemberPresence>{};
    for (final member in valid) {
      final shell = memberShells[member.id];
      final connection = _connectionOf(shell);
      final workload = switch (connection) {
        MemberConnection.connected => _workloadFor(
          presenceCap: presenceCap,
          memberId: member.id,
          shell: shell!,
          claudeWorking: claudeWorking,
        ),
        _ => null,
      };
      out[member.id] = MemberPresence(
        connection: connection,
        workload: workload,
      );
    }
    return out;
  }

  static MemberConnection _connectionOf(TerminalSession? shell) {
    if (shell == null) return MemberConnection.offline;
    if (shell.isConnecting) return MemberConnection.connecting;
    if (shell.isConnected) return MemberConnection.connected;
    return MemberConnection.offline;
  }

  MemberWorkload _workloadFor({
    required PresenceCapability? presenceCap,
    required String memberId,
    required TerminalSession shell,
    required Map<String, bool> claudeWorking,
  }) {
    if (presenceCap?.usesClaudeRoster ?? false) {
      return _claudeRoster.workloadForMember(
        memberId: memberId,
        workingByName: claudeWorking,
      );
    }
    if (presenceCap?.usesShellActivity ?? false) {
      return shell.activityTracker.isWorking
          ? MemberWorkload.working
          : MemberWorkload.idle;
    }
    return MemberWorkload.idle;
  }
}
