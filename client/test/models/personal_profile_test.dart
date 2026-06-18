import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/launch_profile_kind.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/workspace_agent_config.dart';

void main() {
  test('kind is always personal', () {
    expect(const PersonalProfile(id: 'x', display: 'X').kind,
        LaunchProfileKind.personal);
  });

  test('json round-trip preserves bundle, tiering and agent', () {
    const identity = PersonalProfile(
      id: 'coding',
      display: 'Coding',
      bundle: const ConfigBundle(skillIds: ['s1'], mcpServerIds: ['m1']),
      providerIdsByTool: {'claude': 'anthropic'},
      modelsByTool: {'claude': 'opus'},
      effortsByTool: {'claude': 'high'},
      agent: WorkspaceAgentConfig(prompt: 'hi'),
      activePresetId: 'preset-1',
    );
    final restored = PersonalProfile.fromJson(identity.toJson());
    expect(restored, identity);
  });
}
