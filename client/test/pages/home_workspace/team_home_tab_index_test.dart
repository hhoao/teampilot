import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_content.dart';
import 'package:teampilot/pages/team_config/team_config_section.dart';

void main() {
  test('team home tab list covers every team-config section exactly once', () {
    expect(
      teamHomeTabSections.toSet(),
      TeamConfigSection.values.toSet(),
    );
    expect(teamHomeTabSections.length, TeamConfigSection.values.length);
  });

  test('every team-config section deep-links to its own tab', () {
    for (final section in TeamConfigSection.values) {
      final index = teamHomeTabIndex(section);
      expect(
        index,
        greaterThanOrEqualTo(0),
        reason: '${section.name} has no tab',
      );
      expect(
        teamHomeTabSections[index],
        section,
        reason: '${section.name} resolves to another tab',
      );
    }
  });

  test('null deep link yields no tab index', () {
    expect(teamHomeTabIndex(null), -1);
  });
}
