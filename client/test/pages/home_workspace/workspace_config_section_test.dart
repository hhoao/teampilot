import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_kind.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_config_section.dart';

void main() {
  test('personal shows full bundle surface without members', () {
    final s = WorkspaceConfigSection.forKind(LaunchProfileKind.personal);
    expect(s, isNot(contains(WorkspaceConfigSection.members)));
    expect(s, contains(WorkspaceConfigSection.skills));
    expect(s, contains(WorkspaceConfigSection.mcp));
  });

  test('team adds members', () {
    final s = WorkspaceConfigSection.forKind(LaunchProfileKind.team);
    expect(s, contains(WorkspaceConfigSection.members));
  });
}
