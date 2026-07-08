import '../../cubits/chat/model/chat_tab.dart';
import '../../models/cli_preset.dart';
import '../../models/member_instance.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'member_coordination.dart';

export 'member_coordination.dart' show MemberCoordination, MemberCoordinationScope;

/// Session-level working indicator — same rules as the members panel.
final class SessionWorkingResolver {
  SessionWorkingResolver({CliToolRegistry? cliToolRegistry})
    : _cliToolRegistry = cliToolRegistry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _cliToolRegistry;

  bool isPersonalTab(ChatTab tab) =>
      MemberCoordinationScope.isPersonalSession(tab: tab);

  bool usesPresenceSnapshotForTab({
    required ChatTab tab,
    required String? activeSessionId,
    required bool presenceNonEmpty,
  }) {
    if (!presenceNonEmpty || activeSessionId == null) return false;
    if (tab.info.id != activeSessionId) return false;
    if (isPersonalTab(tab)) return false;
    // Native Claude roster + mixed bus both publish via [MemberPresenceCubit].
    return true;
  }

  bool tabHasWorkingMember({
    required ChatTab tab,
    required TeamProfile? team,
    required List<CliPreset> globalPresets,
    Map<String, bool> claudeWorkingByMemberId = const {},
  }) {
    if (tab.memberShells.isEmpty) return false;

    final resolvedTeam = team ?? _fallbackTeam(tab);
    final teamMode = resolvedTeam.teamMode;
    final bus = tab.teamBus;
    final isPersonal = isPersonalTab(tab);

    final members = team != null
        ? runtimeRosterMembers(team).where((m) => m.isValid)
        : tab.memberShells.keys.map(
            (id) => TeamMemberConfig(id: id, name: id),
          );

    for (final member in members) {
      final shell = tab.memberShells[member.id];
      if (shell == null || !shell.isConnected) continue;

      final coordination = MemberCoordination.resolve(
        shell: shell,
        member: member,
        team: resolvedTeam,
        teamMode: teamMode,
        globalPresets: globalPresets,
        bus: bus,
        isPersonalSession: isPersonal,
        claudeRosterWorking: claudeWorkingByMemberId[member.id] ?? false,
        cliToolRegistry: _cliToolRegistry,
      );
      if (coordination.availability() == MemberAvailability.working) {
        return true;
      }
      if (coordination.countsAsSessionWorkingWhileBooting()) return true;
    }
    return false;
  }

  TeamProfile _fallbackTeam(ChatTab tab) {
    final session = tab.persistedSession;
    final hasBus = tab.teamBus != null;
    return TeamProfile(
      id: session?.sessionTeam.trim() ?? '',
      name: '',
      cli: session?.cli ?? CliTool.claude,
      teamMode: hasBus ? TeamMode.mixed : TeamMode.native,
    );
  }
}
