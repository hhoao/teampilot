import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/presence_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../team_bus/team_bus.dart';
import '../terminal/terminal_session.dart';
import '../cli/claude/roster_activity_source.dart';
import 'member_coordination.dart';

/// Session-scoped inputs for [MemberPresenceService.compute].
class PresenceSessionContext {
  const PresenceSessionContext({
    required this.team,
    this.appSession,
    this.teamBus,
    this.globalPresets = const [],
  });

  final TeamProfile team;

  /// Active tab session — when set, presence polls session pods (not a fresh
  /// expand of possibly-stale [TeamMemberConfig.replicas]).
  final AppSession? appSession;
  final TeamBus? teamBus;
  final List<CliPreset> globalPresets;
}

/// Aggregates terminal connection + agent availability into [MemberPresence].
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
    PresenceSessionContext? session,
  }) async {
    final presenceCap = _cliToolRegistry.capability<PresenceCapability>(
      teamCli,
    );
    final usesClaudeRoster = presenceCap?.usesClaudeRoster ?? false;
    final usesShellActivity = presenceCap?.usesShellActivity ?? false;

    var claudeWorking = const <String, bool>{};
    if (session?.team.teamMode != TeamMode.mixed &&
        usesClaudeRoster &&
        memberToolConfigDir != null &&
        memberToolConfigDir.trim().isNotEmpty &&
        cliTeamName.trim().isNotEmpty) {
      claudeWorking = await _claudeRoster.readMemberWorking(
        claudeConfigDir: memberToolConfigDir.trim(),
        cliTeamName: cliTeamName.trim(),
      );
    }

    final team = session?.team;
    final teamMode = team?.teamMode ?? TeamMode.native;
    final bus = session?.teamBus;
    final globalPresets = session?.globalPresets ?? const [];

    final out = <String, MemberPresence>{};
    for (final member in members) {
      if (!member.isValid) continue;
      final shell = memberShells[member.id];
      final connection = _connectionOf(shell);
      final availability = switch (connection) {
        MemberConnection.connected => MemberCoordination.resolve(
          shell: shell!,
          member: member,
          team: team ?? TeamProfile(id: '', name: '', cli: teamCli),
          teamMode: teamMode,
          globalPresets: globalPresets,
          bus: bus,
          session: session?.appSession,
          claudeRosterWorking: _claudeRoster.isMemberWorking(
            memberId: member.id,
            workingByName: claudeWorking,
          ),
          usesClaudeRoster: usesClaudeRoster,
          usesShellActivity: usesShellActivity,
        ).availability(),
        _ => null,
      };
      out[member.id] = MemberPresence(
        connection: connection,
        availability: availability,
      );
    }
    return out.isEmpty ? const {} : out;
  }

  static MemberConnection _connectionOf(TerminalSession? shell) {
    if (shell == null) return MemberConnection.offline;
    if (shell.isConnecting) return MemberConnection.connecting;
    if (shell.isConnected) return MemberConnection.connected;
    return MemberConnection.offline;
  }
}
