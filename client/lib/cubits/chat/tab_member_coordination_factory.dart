import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/team/session_working_resolver.dart';
import '../../services/terminal/terminal_session.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Resolves [MemberCoordination] for a connected tab member.
final class TabMemberCoordinationFactory {
  TabMemberCoordinationFactory({
    required ChatTabStore tabStore,
    required List<CliPreset> Function() globalPresets,
    required TeamProfile? Function() activeTeam,
    SessionWorkingResolver? sessionWorking,
  }) : _tabStore = tabStore,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _sessionWorking = sessionWorking ?? SessionWorkingResolver();

  final ChatTabStore _tabStore;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final SessionWorkingResolver _sessionWorking;

  SessionWorkingResolver get sessionWorking => _sessionWorking;

  MemberCoordination? forMember(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return null;
    final shell = tab.memberShells[memberId];
    if (shell == null || !shell.isConnected) return null;

    final isPersonal = _sessionWorking.isPersonalTab(tab);
    final team = _activeTeam();
    if (!isPersonal && team == null && !directToPty) return null;

    final member = _resolveMember(tab, memberId, team, isPersonal);
    if (!member.isValid && !isPersonal && !directToPty) return null;

    final resolvedTeam = team ?? _fallbackTeam(tab, isPersonal);
    return MemberCoordination.resolve(
      shell: shell,
      member: member.isValid
          ? member
          : TeamMemberConfig(id: memberId, name: memberId),
      team: resolvedTeam,
      teamMode: resolvedTeam.teamMode,
      globalPresets: _globalPresets(),
      bus: tab.teamBus,
      isPersonalSession: isPersonal,
    );
  }

  MemberCoordination forTabMember({
    required ChatTab tab,
    required String memberId,
    required TerminalSession shell,
    required bool isPersonal,
  }) {
    final team = _activeTeam();
    final resolvedTeam = team ?? _fallbackTeam(tab, isPersonal);
    return MemberCoordination.resolve(
      shell: shell,
      member: _resolveMember(tab, memberId, team, isPersonal),
      team: resolvedTeam,
      teamMode: resolvedTeam.teamMode,
      globalPresets: _globalPresets(),
      bus: tab.teamBus,
      isPersonalSession: isPersonal,
    );
  }

  TeamMemberConfig resolveMember(
    ChatTab tab,
    String memberId,
    TeamProfile? team,
    bool isPersonal,
  ) => _resolveMember(tab, memberId, team, isPersonal);

  TeamProfile fallbackTeam(ChatTab tab, bool isPersonal) =>
      _fallbackTeam(tab, isPersonal);

  TeamMemberConfig _resolveMember(
    ChatTab tab,
    String memberId,
    TeamProfile? team,
    bool isPersonal,
  ) {
    if (isPersonal) {
      return TeamMemberConfig(id: memberId, name: memberId);
    }
    return team?.members.firstWhere(
          (m) => m.id == memberId,
          orElse: () => const TeamMemberConfig(id: '', name: ''),
        ) ??
        const TeamMemberConfig(id: '', name: '');
  }

  TeamProfile _fallbackTeam(ChatTab tab, bool isPersonal) {
    final session = tab.persistedSession;
    if (isPersonal) {
      return TeamProfile(
        id: '',
        name: '',
        cli: session?.cli ?? CliTool.claude,
      );
    }
    return TeamProfile(
      id: session?.sessionTeam.trim() ?? '',
      name: '',
      cli: session?.cli ?? CliTool.claude,
      teamMode: tab.teamBus != null ? TeamMode.mixed : TeamMode.native,
    );
  }
}
