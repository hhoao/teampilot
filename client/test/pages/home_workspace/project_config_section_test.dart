import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/pages/home_workspace/project/project_config_section.dart';

void main() {
  test('personal shows full bundle surface without members', () {
    final s = ProjectConfigSection.forKind(IdentityKind.personal);
    expect(s, isNot(contains(ProjectConfigSection.members)));
    expect(s, contains(ProjectConfigSection.skills));
    expect(s, contains(ProjectConfigSection.mcp));
  });

  test('team adds members', () {
    final s = ProjectConfigSection.forKind(IdentityKind.team);
    expect(s, contains(ProjectConfigSection.members));
  });
}
