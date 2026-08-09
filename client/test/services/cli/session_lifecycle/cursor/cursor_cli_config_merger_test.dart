import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/cli_config_merger.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_cli_config_policy.dart';

void main() {
  group('extractWarmTier', () {
    test('copies serverConfigCache and network, strips bus allow entries', () {
      final userConfig = {
        'version': 1,
        'authInfo': {'userId': 'u1'},
        'serverConfigCache': {'feature': true},
        'network': {'proxy': 'http://127.0.0.1:7890'},
        'permissions': {
          'allow': [
            'Shell(ls)',
            CursorCliConfigPolicy.teamBusMcpAllowEntry,
          ],
          'deny': ['Shell(rm)'],
        },
      };

      final warm = CursorCliConfigMerger.extractWarmTier(userConfig);

      expect(warm['serverConfigCache'], {'feature': true});
      expect(warm['network'], {'proxy': 'http://127.0.0.1:7890'});
      expect(warm.containsKey('authInfo'), isFalse);

      final allow = (warm['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Shell(ls)'));
      expect(allow, isNot(contains(CursorCliConfigPolicy.teamBusMcpAllowEntry)));
      expect((warm['permissions']! as Map)['deny'], ['Shell(rm)']);
    });
  });

  group('mergeMemberConfig', () {
    test('combines base with teammate-bus Mcp allow without duplicating', () {
      const base = {
        'version': 1,
        'serverConfigCache': {'feature': true},
        'network': {'proxy': 'http://127.0.0.1:7890'},
        'permissions': {
          'allow': ['Shell(ls)'],
        },
      };

      final merged = CursorCliConfigMerger.mergeMemberConfig(
        base: base,
        memberOverrides: const {},
      );

      final allow = (merged['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Shell(ls)'));
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
      expect(
        allow
            .where((e) => e == CursorCliConfigPolicy.teamBusMcpAllowEntry)
            .length,
        1,
      );
      expect(merged['serverConfigCache'], base['serverConfigCache']);
      expect(merged['network'], base['network']);
    });

    test('empty base still yields valid versioned member config', () {
      final merged = CursorCliConfigMerger.mergeMemberConfig(
        base: const {},
        memberOverrides: const {},
      );

      expect(merged['version'], CursorCliConfigPolicy.defaultVersion);
      final allow = (merged['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
    });
  });
}
