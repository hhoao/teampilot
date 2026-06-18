import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_state.dart';

void main() {
  group('ExtensionState.effectiveEnabledForWorkspace', () {
    test('falls back to globalEnabled when no workspace override', () {
      const state = ExtensionState(globalEnabled: {'rtk'});
      expect(state.effectiveEnabledForWorkspace('proj-a', 'rtk'), isTrue);
      expect(state.effectiveEnabledForWorkspace('proj-a', 'codegraph'), isFalse);
    });

    test('workspace override wins over global', () {
      const state = ExtensionState(
        globalEnabled: {'rtk'},
        workspaceOverrides: {
          'proj-a': {'rtk': false, 'codegraph': true},
        },
      );
      expect(state.effectiveEnabledForWorkspace('proj-a', 'rtk'), isFalse);
      expect(state.effectiveEnabledForWorkspace('proj-a', 'codegraph'), isTrue);
      expect(state.effectiveEnabledForWorkspace('proj-b', 'rtk'), isTrue);
    });

    test('workspace overrides are independent of team overrides', () {
      const state = ExtensionState(
        globalEnabled: {'rtk'},
        teamOverrides: {
          'team-a': {'rtk': false},
        },
        workspaceOverrides: {
          'proj-a': {'rtk': true},
        },
      );
      expect(state.effectiveEnabled('team-a', 'rtk'), isFalse);
      expect(state.effectiveEnabledForWorkspace('proj-a', 'rtk'), isTrue);
    });
  });

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
        workspaceOverrides: {
          'proj-a': {'rtk': false},
        },
      );
      final restored = ExtensionState.fromJson(state.toJson());
      expect(restored.installed['codegraph']!.version, '1.4.0');
      expect(restored.installed['codegraph']!.installedAt, 5);
      expect(restored.globalEnabled, {'rtk'});
      expect(restored.teamOverrides['team-a'], {'codegraph': true});
      expect(restored.workspaceOverrides['proj-a'], {'rtk': false});
    });

    test('empty state round-trips to empty', () {
      final restored = ExtensionState.fromJson(const ExtensionState().toJson());
      expect(restored.installed, isEmpty);
      expect(restored.globalEnabled, isEmpty);
      expect(restored.teamOverrides, isEmpty);
      expect(restored.workspaceOverrides, isEmpty);
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

    test('withWorkspaceOverride sets and clears', () {
      const state = ExtensionState();
      final set = state.withWorkspaceOverride('proj-a', 'rtk', false);
      expect(set.workspaceOverrides['proj-a'], {'rtk': false});
      final cleared = set.withWorkspaceOverride('proj-a', 'rtk', null);
      expect(cleared.workspaceOverrides['proj-a'] ?? const {}, isEmpty);
    });

    test('withInstalled / withUninstalled', () {
      const state = ExtensionState();
      final installed = state.withInstalled('codegraph', '1.0.0', 42);
      expect(installed.installed['codegraph']!.version, '1.0.0');
      expect(installed.withUninstalled('codegraph').installed, isEmpty);
    });
  });
}
