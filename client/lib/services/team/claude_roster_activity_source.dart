import 'dart:convert';

import '../../models/member_presence.dart';
import '../io/filesystem.dart';
import 'claude_team_roster_service.dart';

/// Reads Claude team roster `members[].isActive` from shared session config.
class ClaudeRosterActivitySource {
  ClaudeRosterActivitySource({required this.fs});

  final Filesystem fs;

  String? _cachePath;
  DateTime? _cacheMtime;
  Map<String, bool>? _cacheWorking;

  String rosterConfigPath({
    required String claudeConfigDir,
    required String cliTeamName,
  }) {
    final safe = ClaudeTeamRosterService.safeClaudePathSegment(cliTeamName);
    return fs.pathContext.join(claudeConfigDir, 'teams', safe, 'config.json');
  }

  /// `true` = working, `false` = idle. Missing member omitted (treat as idle).
  Future<Map<String, bool>> readMemberWorking({
    required String claudeConfigDir,
    required String cliTeamName,
  }) async {
    final path = rosterConfigPath(
      claudeConfigDir: claudeConfigDir,
      cliTeamName: cliTeamName,
    );
    final stat = await fs.stat(path);
    if (!stat.exists) {
      _clearCache();
      return const {};
    }

    final mtime = stat.mtime;
    if (_cachePath == path &&
        mtime != null &&
        mtime == _cacheMtime &&
        _cacheWorking != null) {
      return _cacheWorking!;
    }

    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      _clearCache();
      return const {};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      _clearCache();
      return const {};
    }

    final members = decoded['members'];
    if (members is! List) {
      _clearCache();
      return const {};
    }

    final out = <String, bool>{};
    for (final entry in members) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      // Claude sets isActive=true on turn start and false on Stop; omitted = idle.
      final isActive = entry['isActive'];
      out[name] = isActive == true;
    }
    _cachePath = path;
    _cacheMtime = mtime;
    _cacheWorking = out;
    return out;
  }

  void _clearCache() {
    _cachePath = null;
    _cacheMtime = null;
    _cacheWorking = null;
  }

  MemberWorkload workloadForMember({
    required String memberId,
    required Map<String, bool> workingByName,
  }) {
    if (!workingByName.containsKey(memberId)) {
      return MemberWorkload.idle;
    }
    return workingByName[memberId] == true
        ? MemberWorkload.working
        : MemberWorkload.idle;
  }
}
