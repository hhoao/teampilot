import '../../cubits/chat/model/chat_tab.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../team_bus/team_bus.dart';
import '../terminal/terminal_session.dart';

/// Immutable inputs shared by every [MemberCoordination] implementation.
final class MemberCoordinationScope {
  const MemberCoordinationScope({
    required this.shell,
    required this.member,
    required this.team,
    required this.teamMode,
    required this.globalPresets,
    this.bus,
    this.session,
    this.claudeRosterWorking = false,
  });

  final TerminalSession shell;
  final TeamMemberConfig member;
  final TeamProfile team;
  final TeamMode teamMode;
  final List<CliPreset> globalPresets;
  final TeamBus? bus;
  final AppSession? session;
  final bool claudeRosterWorking;

  /// Personal sessions have no persisted team roster (`sessionTeam` empty) and
  /// no [TeamBus]. Tabs with a bus always use mixed coordination.
  static bool isPersonalSession({ChatTab? tab, AppSession? session}) {
    if (tab?.teamBus != null) return false;
    final persisted = session ?? tab?.persistedSession;
    if (persisted != null) return persisted.sessionTeam.trim().isEmpty;
    return true;
  }

  /// Legacy callers inferred personal mode from presence-cap flags.
  static bool inferPersonalFromLegacyFlags({
    required TeamMode teamMode,
    required TeamBus? bus,
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    if (teamMode == TeamMode.mixed && bus != null) return false;
    if (usesClaudeRoster) return false;
    return usesShellActivity && bus == null;
  }
}
