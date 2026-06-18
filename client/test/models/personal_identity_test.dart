import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/project_agent_config.dart';

void main() {
  test('kind is always personal', () {
    expect(const PersonalIdentity(id: 'x', display: 'X').kind,
        IdentityKind.personal);
  });

  test('json round-trip preserves bundle, tiering and agent', () {
    const identity = PersonalIdentity(
      id: 'coding',
      display: 'Coding',
      bundle: const ConfigBundle(skillIds: ['s1'], mcpServerIds: ['m1']),
      providerIdsByTool: {'claude': 'anthropic'},
      modelsByTool: {'claude': 'opus'},
      effortsByTool: {'claude': 'high'},
      agent: ProjectAgentConfig(prompt: 'hi'),
      activePresetId: 'preset-1',
    );
    final restored = PersonalIdentity.fromJson(identity.toJson());
    expect(restored, identity);
  });
}
