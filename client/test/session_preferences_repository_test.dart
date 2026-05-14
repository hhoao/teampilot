import 'dart:convert';

import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns defaults when no stored value', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '');
    expect(loaded.autoLaunchAllMembersOnConnect, false);
    expect(loaded.scopeSessionsToSelectedTeam, false);
  });

  test('round-trips through SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    await repo.save(const SessionPreferences(
      cliExecutablePath: '/usr/local/bin/flashskyai',
      autoLaunchAllMembersOnConnect: true,
      scopeSessionsToSelectedTeam: true,
    ));

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '/usr/local/bin/flashskyai');
    expect(loaded.autoLaunchAllMembersOnConnect, true);
    expect(loaded.scopeSessionsToSelectedTeam, true);
  });

  test('falls back to defaults on malformed JSON', () async {
    SharedPreferences.setMockInitialValues({
      'flashskyai.session_preferences.v1': 'not-json',
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    final loaded = await repo.load();

    expect(loaded.cliExecutablePath, '');
    expect(loaded.autoLaunchAllMembersOnConnect, false);
    expect(loaded.scopeSessionsToSelectedTeam, false);
  });

  test('stores JSON under the documented key', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SessionPreferencesRepository(prefs);

    await repo.save(const SessionPreferences(cliExecutablePath: '/x'));

    final raw = prefs.getString('flashskyai.session_preferences.v1');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['cliExecutablePath'], '/x');
  });
}
