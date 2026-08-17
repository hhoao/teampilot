import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/session_selection_arg_provider.dart';

void main() {
  const provider = _FakeSessionSelectionArgProvider();

  test('encodes a resume session as the semantic selection', () {
    final context = _context(resumeSessionId: ' resume-id ');

    expect(provider.buildLaunchArgs(context).single.args, [
      'resume',
      'resume-id',
    ]);
  });

  test('resume selection takes precedence over a fixed session id', () {
    final context = _context(
      fixedSessionId: 'fixed-id',
      resumeSessionId: 'resume-id',
    );

    expect(provider.buildLaunchArgs(context).single.args, [
      'resume',
      'resume-id',
    ]);
  });

  test('encodes a fixed session when no resume id is present', () {
    final context = _context(fixedSessionId: ' fixed-id ');

    expect(provider.buildLaunchArgs(context).single.args, [
      'fixed',
      'fixed-id',
    ]);
  });

  test('emits no contribution when session selection is empty', () {
    expect(provider.buildLaunchArgs(_context()), isEmpty);
    expect(provider.buildLaunchArgs(_context(resumeSessionId: '  ')), isEmpty);
  });
}

CliLaunchContext _context({String? fixedSessionId, String? resumeSessionId}) {
  return CliLaunchContext(
    team: TeamProfile(id: 'team', name: 'Team'),
    member: TeamMemberConfig(id: 'member', name: 'Member'),
    fixedSessionId: fixedSessionId,
    resumeSessionId: resumeSessionId,
  );
}

final class _FakeSessionSelectionArgProvider
    extends SessionSelectionArgProvider {
  const _FakeSessionSelectionArgProvider();

  @override
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  ) {
    return [
      CliLaunchArgContribution(
        key: 'session-selection',
        phase: LaunchArgPhase.session,
        args: [selection.kind.name, selection.id],
      ),
    ];
  }
}
