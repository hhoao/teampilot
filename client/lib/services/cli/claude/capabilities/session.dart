import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../team_roster_service.dart';
import '../../registry/capabilities/cli_session_capability.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Claude session capability: noop lifecycle + standard CONFIG_DIR layout.
final class ClaudeCliSessionCapability extends NoopCliSessionCapability {
  const ClaudeCliSessionCapability();

  @override
  SessionHookMaterializationPaths hookMaterializationPaths({
    required p.Context pathContext,
    required String memberToolDir,
    String? memberHome,
    TeamMemberConfig? member,
  }) {
    if (member != null && member.isValid) {
      return (
        hooksDir: pathContext.join(memberToolDir, 'hooks'),
        configPath: pathContext.join(
          memberToolDir,
          'settings',
          '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
        ),
      );
    }
    return super.hookMaterializationPaths(
      pathContext: pathContext,
      memberToolDir: memberToolDir,
      memberHome: memberHome,
      member: member,
    );
  }
}
