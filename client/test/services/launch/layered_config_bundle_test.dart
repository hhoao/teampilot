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
      mcpServerIds: [],
    );
    const team = ConfigBundle(
      skillIds: ['team-c', 'shared'],
      pluginIds: [],
      mcpServerIds: ['team-m'],
    );

    final merged = LayeredConfigBundle.merge(
      team: team,
      expert: expert,
      workspace: workspace,
    );

    // team→expert→workspace first-seen: shared appears once at team position.
    expect(merged.skillIds, ['team-c', 'shared', 'ex-b', 'ws-a']);
    expect(merged.pluginIds, ['ex-p', 'ws-p']);
    expect(merged.mcpServerIds, ['team-m', 'ws-m']);
  });

  test('skips empty and whitespace-only ids', () {
    const workspace = ConfigBundle(skillIds: ['  ws-a  ', '', 'dup']);
    const expert = ConfigBundle(skillIds: ['dup', '  ']);
    const team = ConfigBundle(skillIds: ['team-c']);

    final merged = LayeredConfigBundle.merge(
      team: team,
      expert: expert,
      workspace: workspace,
    );

    expect(merged.skillIds, ['team-c', 'dup', 'ws-a']);
  });

  test('null team/expert still returns workspace base', () {
    const workspace = ConfigBundle(skillIds: ['only']);
    final merged = LayeredConfigBundle.merge(workspace: workspace);
    expect(merged.skillIds, ['only']);
  });
}
