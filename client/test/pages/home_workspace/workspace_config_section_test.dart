import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_config_section.dart';

void main() {
  test('manage shows all project-scoped sections', () {
    expect(
      WorkspaceConfigSection.sections,
      [
        WorkspaceConfigSection.settings,
        WorkspaceConfigSection.skills,
        WorkspaceConfigSection.plugins,
        WorkspaceConfigSection.mcp,
        WorkspaceConfigSection.extensions,
        WorkspaceConfigSection.hooks,
      ],
    );
  });

  test('fromSegment resolves known segments only', () {
    expect(
      WorkspaceConfigSection.fromSegment('skills'),
      WorkspaceConfigSection.skills,
    );
    expect(
      WorkspaceConfigSection.fromSegment('hooks'),
      WorkspaceConfigSection.hooks,
    );
    expect(WorkspaceConfigSection.fromSegment('members'), isNull);
    expect(WorkspaceConfigSection.fromSegment('agent'), isNull);
  });
}
