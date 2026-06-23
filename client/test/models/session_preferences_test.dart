import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      final prefs = SessionPreferences();
      expect(prefs.cliExecutablePathFor('flashskyai'), '');
      expect(prefs.defaultSshWorkingDirectory, '');
      expect(prefs.sshUseLoginShell, false);
      expect(prefs.autoLaunchAllMembersOnConnect, true);
      expect(prefs.scopeSessionsToSelectedTeam, true);
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
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(
        cliExecutablePaths: const {'flashskyai': '/a/b', 'claude': '/c/d'},
      );
      expect(next.cliExecutablePathFor('flashskyai'), '/a/b');
      expect(next.cliExecutablePaths, {'flashskyai': '/a/b', 'claude': '/c/d'});
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.autoLaunchAllMembersOnConnect, true);
      expect(next.scopeSessionsToSelectedTeam, true);
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
}
