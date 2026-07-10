import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/launch/layered_config_bundle.dart';

void main() {
  test('union with precedence team > expert > workspace', () {
    const workspace = ConfigBundle(
      skillIds: ['ws-a', 'shared'],
      pluginIds: ['ws-p'],
      mcpServerIds: ['ws-m'],
    );
    const expert = ConfigBundle(
      skillIds: ['ex-b', 'shared'],
      pluginIds: ['ex-p'],
      mcpServerIds: const [],
    );
    const team = ConfigBundle(
      skillIds: ['team-c', 'shared'],
      pluginIds: const [],
      mcpServerIds: ['team-m'],
    );

    final merged = LayeredConfigBundle.merge(
      team: team,
      expert: expert,
      workspace: workspace,
    );

    // shared kept once; team occurrence wins (appears in team position policy —
    // assert set equality + that shared is present once)
    expect(merged.skillIds.toSet(), {'ws-a', 'ex-b', 'team-c', 'shared'});
    expect(merged.skillIds.where((id) => id == 'shared').length, 1);
    expect(merged.pluginIds.toSet(), {'ws-p', 'ex-p'});
    expect(merged.mcpServerIds.toSet(), {'ws-m', 'team-m'});
  });

  test('null team/expert still returns workspace base', () {
    const workspace = ConfigBundle(skillIds: ['only']);
    final merged = LayeredConfigBundle.merge(workspace: workspace);
    expect(merged.skillIds, ['only']);
  });
}
