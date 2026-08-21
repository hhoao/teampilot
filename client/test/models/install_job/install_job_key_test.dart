import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';

void main() {
  test('activityId is stable for same key', () {
    const a = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeLocal(),
    );
    const b = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeLocal(),
    );
    expect(a, equals(b));
    expect(a.activityId, 'install-cliExecutable-claude-local');
  });

  test('ssh scope encodes profile id', () {
    const key = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeSsh('profile-42'),
    );
    expect(key.activityId, 'install-cliExecutable-claude-ssh-profile-42');
  });
}
