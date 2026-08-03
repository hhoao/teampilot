import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';
import '../storage/app_storage.dart';
import '../terminal/terminal_session.dart';
import 'claude_roster_inbox_source.dart';

/// Nudges idle native Claude teammate PTYs when their inbox has unread mail.
///
/// TeamPilot launches one Claude process per pod; unlike in-process teammates,
/// external workers only see lead dispatch after inbox polling. When unread
/// mail sits in `inboxes/<pod>.json`, inject a short notice (same lifecycle as
/// mixed-mode bus doorbells).
class ClaudeNativeInboxDoorbell {
  ClaudeNativeInboxDoorbell({ClaudeRosterInboxSource? inboxSource})
    : _inboxSource = inboxSource ?? ClaudeRosterInboxSource(fs: AppStorage.fs);

  /// Integration tests may pause doorbell delivery while asserting inbox writes.
  static bool doorbellDisabledForTests = false;

  final ClaudeRosterInboxSource _inboxSource;

  static const doorbellNotice =
      '[teampilot] Unread teammate messages — check your inbox and handle them now.';

  static const doorbellRetryMs = 5000;

  final Map<String, int> _doorbelledAtMs = {};

  /// Poll inboxes for [session] pods and doorbell idle workers with unread mail.
  Future<void> reengageIdleWorkers({
    required AppSession session,
    required TeamProfile team,
    required String claudeConfigDir,
    required String cliTeamName,
    required Map<String, TerminalSession> memberShells,
    required void Function(String memberId, String notice) wakeMember,
    required bool Function(TerminalSession shell) isIdleAtPrompt,
  }) async {
    if (team.teamMode != TeamMode.native) return;
    final claudeDir = claudeConfigDir.trim();
    final teamName = cliTeamName.trim();
    if (claudeDir.isEmpty || teamName.isEmpty) return;

    final pods = sessionRosterMembers(session, team);
    for (final member in pods) {
      if (TeamMemberNaming.isTeamLead(member)) continue;
      final memberId = member.id.trim();
      if (memberId.isEmpty) continue;
      final shell = memberShells[memberId];
      if (shell == null || !shell.isConnected) continue;
      if (!isIdleAtPrompt(shell)) continue;

      final inboxPath = _inboxSource.inboxPath(
        claudeConfigDir: claudeDir,
        cliTeamName: teamName,
        memberId: memberId,
      );
      final unread = await _inboxSource.unreadCountForPath(inboxPath);
      if (unread <= 0) continue;

      final key = '${session.sessionId}:$memberId';
      final last = _doorbelledAtMs[key];
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last != null && now - last < doorbellRetryMs) continue;

      _doorbelledAtMs[key] = now;
      wakeMember(memberId, doorbellNotice);
    }
  }

  void clearSession(String sessionId) {
    _doorbelledAtMs.removeWhere((key, _) => key.startsWith('$sessionId:'));
  }
}
