import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_state.dart';

void main() {
  group('ExtensionState.effectiveEnabled', () {
    test('falls back to globalEnabled when no team override', () {
      const state = ExtensionState(globalEnabled: {'rtk'});
      expect(state.effectiveEnabled('team-a', 'rtk'), isTrue);
      expect(state.effectiveEnabled('team-a', 'codegraph'), isFalse);
    });

    test('team override wins over global', () {
      const state = ExtensionState(
        globalEnabled: {'rtk'},
        teamOverrides: {
          'team-a': {'rtk': false, 'codegraph': true},
        },
      );
      expect(state.effectiveEnabled('team-a', 'rtk'), isFalse);
      expect(state.effectiveEnabled('team-a', 'codegraph'), isTrue);
      expect(state.effectiveEnabled('team-b', 'rtk'), isTrue);
    });
  });

  group('ExtensionState JSON round-trip', () {
    test('preserves installed + enabled + overrides', () {
      const state = ExtensionState(
        installed: {
          'codegraph': InstalledExtension(
            id: 'codegraph',
            version: '1.4.0',
            installedAt: 5,
          ),
        },
        globalEnabled: {'rtk'},
        teamOverrides: {
          'team-a': {'codegraph': true},
        },
      );
      final restored = ExtensionState.fromJson(state.toJson());
      expect(restored.installed['codegraph']!.version, '1.4.0');
      expect(restored.installed['codegraph']!.installedAt, 5);
      expect(restored.globalEnabled, {'rtk'});
      expect(restored.teamOverrides['team-a'], {'codegraph': true});
    });

    test('empty state round-trips to empty', () {
      final restored = ExtensionState.fromJson(const ExtensionState().toJson());
      expect(restored.installed, isEmpty);
      expect(restored.globalEnabled, isEmpty);
      expect(restored.teamOverrides, isEmpty);
      expect(restored.migrations, isEmpty);
    });

    test('migrations round-trip and stay out of teamOverrides', () {
      final state =
          const ExtensionState().withMigration('rtk_flag_v1');
      expect(state.migrations, {'rtk_flag_v1'});
      expect(state.teamOverrides, isEmpty);
      final restored = ExtensionState.fromJson(state.toJson());
      expect(restored.migrations, {'rtk_flag_v1'});
      expect(restored.teamOverrides, isEmpty);
    });

    test('a team named like a migration key keeps independent overrides', () {
      final state = const ExtensionState()
          .withMigration('rtk_flag_v1')
          .withTeamOverride('rtk_flag_v1', 'codegraph', true);
      // The migration marker and the (oddly-named) team never share a namespace.
      expect(state.migrations, {'rtk_flag_v1'});
      expect(state.teamOverrides['rtk_flag_v1'], {'codegraph': true});
      expect(state.effectiveEnabled('rtk_flag_v1', 'codegraph'), isTrue);
    });
  });

  group('mutation helpers', () {
    test('withGlobalEnabled toggles membership', () {
      const state = ExtensionState();
      expect(state.withGlobalEnabled('rtk', true).globalEnabled, {'rtk'});
      expect(
        state.withGlobalEnabled('rtk', true).withGlobalEnabled('rtk', false).globalEnabled,
        isEmpty,
      );
    });

    test('withTeamOverride sets and clears', () {
      const state = ExtensionState();
      final set = state.withTeamOverride('team-a', 'rtk', false);
      expect(set.teamOverrides['team-a'], {'rtk': false});
      final cleared = set.withTeamOverride('team-a', 'rtk', null);
      expect(cleared.teamOverrides['team-a'] ?? const {}, isEmpty);
    });

    test('withInstalled / withUninstalled', () {
      const state = ExtensionState();
      final installed = state.withInstalled('codegraph', '1.0.0', 42);
      expect(installed.installed['codegraph']!.version, '1.0.0');
      expect(installed.withUninstalled('codegraph').installed, isEmpty);
    });
  });
}
