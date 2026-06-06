import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  test('teamBusMcpAllowEntry uses teammate-bus server wildcard', () {
    expect(
      CursorCliConfigPolicy.teamBusMcpAllowEntry,
      'Mcp($teammateBusMcpServerName:*)',
    );
  });

  test('applyMixedTeamSessionPolicy adds Mcp allow without clobbering auth', () {
    const input = {
      'version': 1,
      'authInfo': {'userId': 'u1'},
      'permissions': {
        'allow': ['Shell(ls)'],
        'deny': [],
      },
    };
    final merged = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(input);
    final allow = (merged['permissions']! as Map)['allow'] as List;
    expect(allow, contains('Shell(ls)'));
    expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    expect(merged['authInfo'], isNotNull);
  });

  test('applyMixedTeamSessionPolicy is idempotent', () {
    final once = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(const {});
    final twice = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(once);
    final allow = (twice['permissions']! as Map)['allow'] as List;
    expect(
      allow.where((e) => e == CursorCliConfigPolicy.teamBusMcpAllowEntry).length,
      1,
    );
  });
}
