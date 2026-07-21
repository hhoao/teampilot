import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';

/// Resolves the effective [CliTool] for a session member's terminal behavior.
///
/// Personal sessions (no team) use the pinned [AppSession.cli]. Team sessions
/// prefer [SessionMemberBinding.cli] when set, else [cliForMember] (live
/// profile — legacy sessions without a lock).
abstract final class SessionMemberCliResolver {
  SessionMemberCliResolver._();

  static CliTool resolve({
    required AppSession? persistedSession,
    required TeamProfile? team,
    required String memberId,
    required CliTool Function(
      TeamProfile team,
      String memberId, {
      List<CliPreset> globalPresets,
    })
    cliForMember,
    List<CliPreset> globalPresets = const [],
  }) {
    final isPersonal =
        persistedSession == null ||
        persistedSession.sessionTeam.trim().isEmpty;
    if (isPersonal) {
      return persistedSession?.cli ?? CliTool.claude;
    }
    if (team == null) return CliTool.claude;
    final locked = persistedSession!.bindingFor(memberId)?.cli;
    if (locked != null) return locked;
    return cliForMember(team, memberId, globalPresets: globalPresets);
  }
}
