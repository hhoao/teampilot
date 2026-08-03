import 'dart:convert';

import '../io/filesystem.dart';
import 'claude_team_roster_service.dart';

/// Reads Claude native-team inbox files (`teams/.../inboxes/*.json`).
class ClaudeRosterInboxSource {
  ClaudeRosterInboxSource({required this.fs});

  final Filesystem fs;

  String inboxPath({
    required String claudeConfigDir,
    required String cliTeamName,
    required String memberId,
  }) {
    final safeTeam = ClaudeTeamRosterService.safeClaudePathSegment(cliTeamName);
    final safeMember = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
    return fs.pathContext.join(
      claudeConfigDir,
      'teams',
      safeTeam,
      'inboxes',
      '$safeMember.json',
    );
  }

  /// Unread rows (`read == false`) in a member inbox file.
  Future<int> unreadCountForPath(String inboxPath) async {
    final stat = await fs.stat(inboxPath);
    if (!stat.exists) return 0;
    final raw = await fs.readString(inboxPath);
    if (raw == null || raw.trim().isEmpty) return 0;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return 0;
    var unread = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      if (item['read'] == false) unread++;
    }
    return unread;
  }
}
