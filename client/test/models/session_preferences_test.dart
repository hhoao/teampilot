import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      final prefs = SessionPreferences();
      expect(prefs.cliExecutablePathFor('flashskyai'), '');
      expect(prefs.defaultSshWorkingDirectory, '');
      expect(prefs.sshUseLoginShell, false);
      expect(prefs.autoLaunchAllMembersOnConnect, false);
      expect(prefs.scopeSessionsToSelectedTeam, true);
      expect(prefs.notifyOnSessionIdle, true);
      expect(prefs.openExistingSessionStartsTerminal, false);
      expect(prefs.simpleModeDefaultFullAccess, true);
    });

    test('toJson/fromJson round-trips', () {
      final prefs = SessionPreferences(
        cliExecutablePaths: const {
          'flashskyai': '/opt/bin/flashskyai',
          'claude': '/opt/bin/claude',
          'codex': '/opt/bin/codex',
        },
        defaultSshWorkingDirectory: '~/work',
        sshUseLoginShell: true,
        autoLaunchAllMembersOnConnect: true,
        scopeSessionsToSelectedTeam: true,
        notifyOnSessionIdle: false,
        openExistingSessionStartsTerminal: true,
        simpleModeDefaultFullAccess: false,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.cliExecutablePaths, {
        'flashskyai': '/opt/bin/flashskyai',
        'claude': '/opt/bin/claude',
        'codex': '/opt/bin/codex',
      });
      expect(restored.defaultSshWorkingDirectory, '~/work');
      expect(restored.sshUseLoginShell, true);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
      expect(restored.notifyOnSessionIdle, false);
      expect(restored.openExistingSessionStartsTerminal, true);
      expect(restored.simpleModeDefaultFullAccess, false);
    });

    test('toJson is free of legacy runtime knobs', () {
      final json = SessionPreferences().toJson();
      expect(json.containsKey('connectionMode'), isFalse);
      expect(json.containsKey('windowsStorageBackend'), isFalse);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePaths, isEmpty);
      expect(restored.defaultSshWorkingDirectory, '');
      expect(restored.sshUseLoginShell, false);
      expect(restored.autoLaunchAllMembersOnConnect, false);
      expect(restored.scopeSessionsToSelectedTeam, true);
      expect(restored.openExistingSessionStartsTerminal, false);
      expect(restored.simpleModeDefaultFullAccess, true);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(
        cliExecutablePaths: const {'flashskyai': '/a/b', 'claude': '/c/d'},
        openExistingSessionStartsTerminal: true,
        simpleModeDefaultFullAccess: false,
      );
      expect(next.cliExecutablePathFor('flashskyai'), '/a/b');
      expect(next.cliExecutablePaths, {'flashskyai': '/a/b', 'claude': '/c/d'});
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.autoLaunchAllMembersOnConnect, false);
      expect(next.scopeSessionsToSelectedTeam, true);
      expect(next.openExistingSessionStartsTerminal, true);
      expect(next.simpleModeDefaultFullAccess, false);
    });

    test('chatSubmitSwitchesToTerminal defaults false', () {
      expect(SessionPreferences().chatSubmitSwitchesToTerminal, isFalse);
    });

    test('simpleModeDefaultFullAccess defaults true', () {
      expect(SessionPreferences().simpleModeDefaultFullAccess, isTrue);
    });

    test('simpleModeDefaultFullAccess JSON round-trip', () {
      final prefs = SessionPreferences(simpleModeDefaultFullAccess: false);
      final again = SessionPreferences.fromJson(prefs.toJson());
      expect(again.simpleModeDefaultFullAccess, isFalse);
    });

    test('fromJson defaults simpleModeDefaultFullAccess when key missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.simpleModeDefaultFullAccess, isTrue);
    });

    test('chatSubmitSwitchesToTerminal JSON round-trip', () {
      final prefs = SessionPreferences(chatSubmitSwitchesToTerminal: true);
      final again = SessionPreferences.fromJson(prefs.toJson());
      expect(again.chatSubmitSwitchesToTerminal, isTrue);
    });

    test('absent chatSubmitSwitchesToTerminal key defaults false', () {
      expect(
        SessionPreferences.fromJson(const {}).chatSubmitSwitchesToTerminal,
        isFalse,
      );
    });

    test('fromJson ignores non-string cli executable path entries', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{
        'cliExecutablePaths': {
          'claude': '/opt/bin/claude',
          'codex': 42,
          '': '/bad',
          'flashskyai': '   ',
        },
      });

      expect(restored.cliExecutablePaths, {'claude': '/opt/bin/claude'});
    });
  });

  group('idle terminal reclaim', () {
    test('reclaim defaults: enabled, 3 minutes', () {
      final p = SessionPreferences();
      expect(p.reclaimIdleTerminals, isTrue);
      expect(p.reclaimIdleTerminalAfterSeconds, 180);
    });

    test('reclaim fields survive JSON round-trip', () {
      final p = SessionPreferences(
        reclaimIdleTerminals: false,
        reclaimIdleTerminalAfterSeconds: 7,
      );
      final back = SessionPreferences.fromJson(p.toJson());
      expect(back.reclaimIdleTerminals, isFalse);
      expect(back.reclaimIdleTerminalAfterSeconds, 7);
    });

    test('fromJson falls back to defaults for missing reclaim keys', () {
      final p = SessionPreferences.fromJson(const {});
      expect(p.reclaimIdleTerminals, isTrue);
      expect(p.reclaimIdleTerminalAfterSeconds, 180);
    });

    test('copyWith updates reclaim fields', () {
      final p = SessionPreferences();
      final q = p.copyWith(
        reclaimIdleTerminals: false,
        reclaimIdleTerminalAfterSeconds: 12,
      );
      expect(q.reclaimIdleTerminals, isFalse);
      expect(q.reclaimIdleTerminalAfterSeconds, 12);
    });
  });
}
