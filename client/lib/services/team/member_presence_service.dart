import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../terminal/terminal_session.dart';
import 'claude_roster_activity_source.dart';

/// Aggregates terminal connection + per-CLI workload into [MemberPresence].
class MemberPresenceService {
  MemberPresenceService({Filesystem? fs, ClaudeRosterActivitySource? claudeRoster})
    : fs = fs ?? AppStorage.fs,
      _claudeRoster = claudeRoster ??
          ClaudeRosterActivitySource(fs: fs ?? AppStorage.fs);

  final Filesystem fs;
  final ClaudeRosterActivitySource _claudeRoster;

  Future<Map<String, MemberPresence>> compute({
    required TeamCli teamCli,
    required List<TeamMemberConfig> members,
    required String cliTeamName,
    required String? memberToolConfigDir,
    required Map<String, TerminalSession> memberShells,
  }) async {
    final valid = members.where((m) => m.isValid).toList();
    if (valid.isEmpty) return const {};

    var claudeWorking = const <String, bool>{};
    if (teamCli == TeamCli.claude &&
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
          teamCli: teamCli,
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
    required TeamCli teamCli,
    required String memberId,
    required TerminalSession shell,
    required Map<String, bool> claudeWorking,
  }) {
    return switch (teamCli) {
      TeamCli.claude => _claudeRoster.workloadForMember(
        memberId: memberId,
        workingByName: claudeWorking,
      ),
      TeamCli.flashskyai => shell.activityTracker.isWorking
          ? MemberWorkload.working
          : MemberWorkload.idle,
      TeamCli.codex => MemberWorkload.idle,
    };
  }
}
