import '../../models/member_instance.dart';
import '../../models/team_config.dart';

/// Caches [runtimeRosterMembers] for a [TeamProfile] until the profile changes.
///
/// Presence polling calls this every second; without a cache each tick allocates
/// fresh [MemberInstance] / [TeamMemberConfig] pods even when the roster is
/// unchanged.
class RuntimeRosterCache {
  TeamProfile? _team;
  List<TeamMemberConfig>? _members;

  List<TeamMemberConfig> resolve(TeamProfile team) {
    final cached = _members;
    final prev = _team;
    if (cached != null && prev != null) {
      if (identical(prev, team)) return cached;
      if (prev == team) {
        _team = team;
        return cached;
      }
    }
    final members = runtimeRosterMembers(team);
    _team = team;
    _members = members;
    return members;
  }

  void clear() {
    _team = null;
    _members = null;
  }
}
